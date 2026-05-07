import 'package:drift/drift.dart';
import 'package:drift/drift.dart' as drift;
import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:supermarket/core/services/accounting_service.dart';
import 'package:supermarket/core/services/audit_service.dart';
import 'package:supermarket/core/services/app_config_service.dart';
import 'package:uuid/uuid.dart';

class InventoryTransactionReport {
  final InventoryTransaction transaction;
  final Product product;
  final Warehouse? warehouse;

  InventoryTransactionReport({
    required this.transaction,
    required this.product,
    this.warehouse,
  });
}

class BatchReport {
  final ProductBatch batch;
  final Product product;
  final Warehouse? warehouse;

  BatchReport({required this.batch, required this.product, this.warehouse});
}

class InventoryService {
  final AppDatabase db;
  late final AuditService _auditService;
  late final AppConfigService _configService;

  InventoryService(this.db) {
    _auditService = AuditService(db);
    _configService = AppConfigService(db);
  }

  // ==================== REPORTING ====================

  /// Report: Inventory Transactions with product and warehouse details
  Stream<List<InventoryTransactionReport>> watchInventoryTransactions({
    String? productId,
    String? warehouseId,
    int limit = 100,
  }) {
    final query =
        db.select(db.inventoryTransactions).join([
            drift.innerJoin(
              db.products,
              db.products.id.equalsExp(db.inventoryTransactions.productId),
            ),
            drift.leftOuterJoin(
              db.warehouses,
              db.warehouses.id.equalsExp(db.inventoryTransactions.warehouseId),
            ),
          ])
          ..orderBy([
            drift.OrderingTerm(
              expression: db.inventoryTransactions.date,
              mode: drift.OrderingMode.desc,
            ),
          ])
          ..limit(limit);

    if (productId != null) {
      query.where(db.inventoryTransactions.productId.equals(productId));
    }
    if (warehouseId != null) {
      query.where(db.inventoryTransactions.warehouseId.equals(warehouseId));
    }

    return query.watch().map((rows) {
      return rows.map((row) {
        return InventoryTransactionReport(
          transaction: row.readTable(db.inventoryTransactions),
          product: row.readTable(db.products),
          warehouse: row.readTableOrNull(db.warehouses),
        );
      }).toList();
    });
  }

  /// Report: Product Batches with product and warehouse details
  Stream<List<BatchReport>> watchProductBatches({
    String? productId,
    String? warehouseId,
  }) {
    final query = db.select(db.productBatches).join([
      drift.innerJoin(
        db.products,
        db.products.id.equalsExp(db.productBatches.productId),
      ),
      drift.leftOuterJoin(
        db.warehouses,
        db.warehouses.id.equalsExp(db.productBatches.warehouseId),
      ),
    ]);

    if (productId != null) {
      query.where(db.productBatches.productId.equals(productId));
    }
    if (warehouseId != null) {
      query.where(db.productBatches.warehouseId.equals(warehouseId));
    }

    query.orderBy([
      drift.OrderingTerm(
        expression: db.productBatches.createdAt,
        mode: drift.OrderingMode.desc,
      ),
    ]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return BatchReport(
          batch: row.readTable(db.productBatches),
          product: row.readTable(db.products),
          warehouse: row.readTableOrNull(db.warehouses),
        );
      }).toList();
    });
  }

  /// Convenience: Get total inventory value (delegates to DB)
  Future<double> getTotalInventoryValue() {
    return db.calculateTotalInventoryValue();
  }

  /// Convenience: Watch low stock products (delegates to DB)
  Stream<List<Product>> watchLowStockProducts() {
    return db.watchLowStockProducts();
  }

  /// Watch product batches that are expiring within the next [days]
  Stream<List<BatchReport>> watchExpiringSoonBatches({int days = 30}) {
    final now = DateTime.now();
    final threshold = now.add(Duration(days: days));

    final query = db.select(db.productBatches).join([
      drift.innerJoin(
        db.products,
        db.products.id.equalsExp(db.productBatches.productId),
      ),
      drift.leftOuterJoin(
        db.warehouses,
        db.warehouses.id.equalsExp(db.productBatches.warehouseId),
      ),
    ])..where(
      db.productBatches.expiryDate.isBiggerOrEqual(Variable(now)) &
      db.productBatches.expiryDate.isSmallerOrEqual(Variable(threshold)) &
      db.productBatches.quantity.isBiggerThan(const Variable(0))
    );

    return query.watch().map((rows) {
      return rows.map((row) {
        return BatchReport(
          batch: row.readTable(db.productBatches),
          product: row.readTable(db.products),
          warehouse: row.readTableOrNull(db.warehouses),
        );
      }).toList();
    });
  }

  /// تنفيذ عملية جرد وتسوية للمخزون
  /// [auditCompanion] رأس الجرد (التاريخ، الملاحظات)
  /// [items] قائمة بالأصناف المجردة (الكمية الفعلية، معرف المنتج)
  Future<void> performInventoryAudit({
    required InventoryAuditsCompanion auditCompanion,
    required List<InventoryAuditItemsCompanion> items,
    String? userId,
  }) async {
    await db.transaction(() async {
      // 1. تسجيل رأس الجرد
      final auditId = await db.into(db.inventoryAudits).insert(auditCompanion);

      double totalInventoryAdjustmentValue = 0.0;

      for (var item in items) {
        final productId = item.productId.value;
        final actualStock = item.actualStock.value;

        // 2. جلب المنتج الحالي لمعرفة المخزون المسجل
        final product = await (db.select(
          db.products,
        )..where((p) => p.id.equals(productId))).getSingle();
        final systemStock = product.stock;
        final difference = actualStock - systemStock;

        // 3. تحديث سجل الجرد بالتفاصيل المحسوبة
        await db
            .into(db.inventoryAuditItems)
            .insert(
              item.copyWith(
                auditId: drift.Value(auditId as String),
                systemStock: drift.Value(systemStock),
                difference: drift.Value(difference),
              ),
            );

        if (difference != 0) {
          // 4. تحديث كمية المنتج في جدول المنتجات
          await (db.update(db.products)..where((p) => p.id.equals(productId)))
              .write(ProductsCompanion(stock: drift.Value(actualStock)));

          // 5. تحديث الدفعات (Batches) - منطق التسوية
          if (difference < 0) {
            double remainingToDeduct = difference.abs();
            final batches =
                await (db.select(db.productBatches)
                      ..where(
                        (b) =>
                            b.productId.equals(productId) &
                            b.quantity.isBiggerThan(const Variable(0)),
                      )
                      ..orderBy([
                        (b) => drift.OrderingTerm(
                          expression: b.createdAt,
                          mode: drift.OrderingMode.asc,
                        ),
                      ]))
                    .get();

            for (var batch in batches) {
              if (remainingToDeduct <= 0) break;
              double deductFromThisBatch = batch.quantity >= remainingToDeduct
                  ? remainingToDeduct
                  : batch.quantity;

              await (db.update(
                db.productBatches,
              )..where((b) => b.id.equals(batch.id))).write(
                ProductBatchesCompanion(
                  quantity: drift.Value(batch.quantity - deductFromThisBatch),
                ),
              );
              remainingToDeduct -= deductFromThisBatch;
              totalInventoryAdjustmentValue -=
                  deductFromThisBatch * batch.costPrice;
            }
          } else {
            // فائض - إنشاء دفعة جديدة
            // الحصول على المستودع الافتراضي من الإعدادات
            final defaultWarehouseId = await _configService.getDefaultWarehouseId();
            const uuid = Uuid();
            final averageCost = product.buyPrice;
            await db.into(db.productBatches).insert(
              ProductBatchesCompanion(
                id: drift.Value(uuid.v4()),
                productId: drift.Value(productId),
                warehouseId: drift.Value(defaultWarehouseId),
                batchNumber: drift.Value('AUDIT-${auditId.toString().substring(0, 8)}'),
                expiryDate: const drift.Value(null),
                quantity: drift.Value(difference),
                initialQuantity: drift.Value(difference),
                costPrice: drift.Value(averageCost),
              ),
            );
            totalInventoryAdjustmentValue += difference * averageCost;
          }
        }
      }

      // 6. التسوية المحاسبية (Accounting Entry)
      if (totalInventoryAdjustmentValue != 0) {
        await _postInventoryAdjustment(
          totalInventoryAdjustmentValue,
          auditId as String,
        );
      }

      // 7. توثيق العملية
      await _auditService.log(
        action: 'INVENTORY_AUDIT',
        targetEntity: 'InventoryAudits',
        entityId: auditId as String,
        userId: userId,
        details:
            'Performed inventory audit with total value adjustment: $totalInventoryAdjustmentValue',
      );
    });
  }

  Future<void> _postInventoryAdjustment(
    double value,
    String referenceId,
  ) async {
    final dao = db.accountingDao;
    final entryId = const Uuid().v4();

    final inventoryAccount = await dao.getAccountByCode(
      AccountingService.codeInventory,
    );
    final adjustmentAccount = await dao.getAccountByCode(
      AccountingService.codeCashOverShort,
    );

    if (inventoryAccount == null || adjustmentAccount == null) {
      throw Exception('Missing GL accounts for inventory adjustment.');
    }

    final entry = GLEntriesCompanion.insert(
      id: drift.Value(entryId),
      description: 'Inventory Adjustment (Audit #$referenceId)',
      date: drift.Value(DateTime.now()),
      referenceType: const drift.Value('INVENTORY_ADJUST'),
      referenceId: drift.Value(referenceId),
    );

    List<GLLinesCompanion> lines = [];
    if (value > 0) {
      lines.add(
        GLLinesCompanion.insert(
          entryId: entryId,
          accountId: inventoryAccount.id,
          debit: drift.Value(value.abs()),
          credit: const drift.Value(0.0),
        ),
      );
      lines.add(
        GLLinesCompanion.insert(
          entryId: entryId,
          accountId: adjustmentAccount.id,
          debit: const drift.Value(0.0),
          credit: drift.Value(value.abs()),
        ),
      );
    } else {
      lines.add(
        GLLinesCompanion.insert(
          entryId: entryId,
          accountId: adjustmentAccount.id,
          debit: drift.Value(value.abs()),
          credit: const drift.Value(0.0),
        ),
      );
      lines.add(
        GLLinesCompanion.insert(
          entryId: entryId,
          accountId: inventoryAccount.id,
          debit: const drift.Value(0.0),
          credit: drift.Value(value.abs()),
        ),
      );
    }

    await dao.createEntry(entry, lines);
  }

  Future<void> deductStock({
    required String itemId,
    required double quantity,
    required String warehouseId,
    String? referenceId,
  }) async {
    await db.transaction(() async {
      final product = await (db.select(
        db.products,
      )..where((p) => p.id.equals(itemId))).getSingle();
      
      if (product.stock < quantity) throw Exception('Insufficient stock');

      await (db.update(db.products)..where((p) => p.id.equals(itemId))).write(
        ProductsCompanion(stock: drift.Value(product.stock - quantity)),
      );

      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              productId: itemId,
              quantity: -quantity,
              type: 'SALE',
              referenceId: drift.Value(referenceId),
            ),
          );
    });
  }

  /// تحويل مخزون بين مستودعين (أو فرعين)
  Future<void> transferStock({
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<StockTransferItemsCompanion> items,
    String? note,
    String? userId,
  }) async {
    await db.transaction(() async {
      final transferId = const Uuid().v4();

      // 1. تسجيل رأس التحويل
      await db.into(db.stockTransfers).insert(
            StockTransfersCompanion.insert(
              id: drift.Value(transferId),
              fromWarehouseId: fromWarehouseId,
              toWarehouseId: toWarehouseId,
              transferDate: drift.Value(DateTime.now()),
              note: drift.Value(note),
              status: const drift.Value('COMPLETED'),
            ),
          );

      for (var itemCompanion in items) {
        final productId = itemCompanion.productId.value;
        final batchId = itemCompanion.batchId.value;
        final qty = itemCompanion.quantity.value;

        // 2. تحديث الدفعة المصدر (Batch Out)
        final sourceBatch = await (db.select(db.productBatches)
              ..where((b) => b.id.equals(batchId)))
            .getSingle();

        if (sourceBatch.quantity < qty) {
          throw Exception('الكمية غير كافية في الدفعة المصدر لمستودع ${sourceBatch.warehouseId}');
        }

        await (db.update(db.productBatches)..where((b) => b.id.equals(batchId)))
            .write(ProductBatchesCompanion(quantity: drift.Value(sourceBatch.quantity - qty)));

        // 3. تحديث أو إنشاء الدفعة في المستودع الهدف (Batch In)
        // نحاول البحث عن دفعة بنفس رقم التشغيلة وتاريخ الانتهاء في المستودع الهدف
        final targetBatch = await (db.select(db.productBatches)
              ..where(
                (b) =>
                    b.productId.equals(productId) &
                    b.warehouseId.equals(toWarehouseId) &
                    b.batchNumber.equals(sourceBatch.batchNumber),
              ))
            .getSingleOrNull();

        if (targetBatch != null) {
          await (db.update(db.productBatches)..where((b) => b.id.equals(targetBatch.id)))
              .write(ProductBatchesCompanion(quantity: drift.Value(targetBatch.quantity + qty)));
        } else {
          // إنشاء دفعة جديدة في المستودع الهدف
          await db.into(db.productBatches).insert(
                ProductBatchesCompanion.insert(
                  productId: productId,
                  warehouseId: toWarehouseId,
                  batchNumber: sourceBatch.batchNumber,
                  expiryDate: drift.Value(sourceBatch.expiryDate),
                  quantity: drift.Value(qty),
                  initialQuantity: drift.Value(qty),
                  costPrice: drift.Value(sourceBatch.costPrice),
                ),
              );
        }

        // 4. تسجيل بنود التحويل
        await db.into(db.stockTransferItems).insert(
              itemCompanion.copyWith(transferId: drift.Value(transferId)),
            );

        // 5. تسجيل حركات المخزون (Inventory Transactions)
        await db.into(db.inventoryTransactions).insert(
              InventoryTransactionsCompanion.insert(
                productId: productId,
                warehouseId: fromWarehouseId,
                batchId: drift.Value(batchId),
                quantity: -qty,
                type: 'TRANSFER_OUT',
                referenceId: transferId,
              ),
            );

        await db.into(db.inventoryTransactions).insert(
              InventoryTransactionsCompanion.insert(
                productId: productId,
                warehouseId: toWarehouseId,
                batchId: drift.Value(batchId), // نستخدم نفس المعرف المرجعي أو نحدثه لاحقاً
                quantity: qty,
                type: 'TRANSFER_IN',
                referenceId: transferId,
              ),
            );
      }

      // 6. توثيق العملية
      await _auditService.log(
        action: 'STOCK_TRANSFER',
        targetEntity: 'StockTransfers',
        entityId: transferId,
        userId: userId,
        details: 'Transferred stock from $fromWarehouseId to $toWarehouseId',
      );
    });
  }
}
