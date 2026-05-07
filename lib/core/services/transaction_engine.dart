import 'package:drift/drift.dart';
import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:supermarket/core/events/app_events.dart';
import 'package:supermarket/core/services/event_bus_service.dart';
import 'package:supermarket/core/services/audit_service.dart';
import 'package:supermarket/core/services/inventory_costing_service.dart';
import 'package:supermarket/core/services/app_config_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:developer' as developer;

class TransactionEngine {
  final AppDatabase db;
  final EventBusService eventBus;
  late final AuditService _auditService;
  late final AppConfigService _configService;
  InventoryCostingService? _costingService;

  TransactionEngine(this.db, this.eventBus) {
    _auditService = AuditService(db);
    _configService = AppConfigService(db);
  }

  void setCostingService(InventoryCostingService costingService) {
    _costingService = costingService;
  }

  /// Checks if the current accounting period is open
  /// Throws an exception if no open period exists or if the current date is outside the open period
  Future<void> _checkAccountingPeriodOpen() async {
    final now = DateTime.now();
    final openPeriod =
        await (db.select(db.accountingPeriods)
              ..where((p) => p.isClosed.equals(false))
              ..where((p) => p.startDate.isSmallerOrEqual(Variable(now)))
              ..where((p) => p.endDate.isBiggerOrEqual(Variable(now))))
            .getSingleOrNull();

    if (openPeriod == null) {
      throw Exception(
        'لا توجد فترة محاسبية مفتوحة حالياً. يرجى فتح فترة محاسبية جديدة.',
      );
    }
  }

  /// Posts a purchase invoice (Draft -> Received)
  /// This updates inventory, creates batches, allocates landed costs, and triggers accounting.
  Future<void> postPurchase(String purchaseId, {String? userId}) async {
    if (purchaseId.isEmpty) {
      throw Exception('معرف الفاتورة غير صالح.');
    }
    
    // Check if accounting period is open before posting
    await _checkAccountingPeriodOpen();

    try {
      await db.transaction(() async {
        // 1. Get Purchase and Items
        final purchase = await (db.select(
          db.purchases,
        )..where((p) => p.id.equals(purchaseId))).getSingle();

        // Validate supplier if credit purchase
        if (purchase.isCredit && purchase.supplierId == null) {
          throw Exception('يجب اختيار مورد لفاتورة الشراء الآجل.');
        }

        if (purchase.status == 'RECEIVED') {
          throw Exception('هذه الفاتورة تم استلامها بالفعل.');
        }

        final items = await (db.select(
          db.purchaseItems,
        )..where((pi) => pi.purchaseId.equals(purchaseId))).get();

        if (items.isEmpty) {
          throw Exception('لا يمكن ترحيل فاتورة مشتريات بدون أصناف.');
        }

        // 2. Calculate Subtotal for Landed Cost Allocation
        double subtotal = 0;
        for (var item in items) {
          if (item.quantity <= 0) {
            throw Exception('كمية الشراء يجب أن تكون أكبر من الصفر.');
          }
          subtotal += item.quantity * item.price;
        }

        // 3. Process each item
        for (var item in items) {
          // Landed Cost Allocation (by value proportion)
          double itemValue = item.quantity * item.price;
          double proportion = subtotal > 0 ? itemValue / subtotal : 0;
          double allocatedLandedCost = purchase.landedCosts * proportion;
          double landedCostPerUnit = item.quantity > 0
              ? allocatedLandedCost / item.quantity
              : 0;
          double finalUnitCost = item.price + landedCostPerUnit;

          final product = await (db.select(
            db.products,
          )..where((p) => p.id.equals(item.productId))).getSingle();

          double qtyInBaseUnit = item.quantity * item.unitFactor;

          // A. Create Product Batch
          final batchId = const Uuid().v4();
          await db
              .into(db.productBatches)
              .insert(
                ProductBatchesCompanion.insert(
                  id: Value(batchId),
                  productId: item.productId,
                  warehouseId: purchase.warehouseId ?? '',
                  batchNumber:
                      item.batchNumber != null && item.batchNumber!.isNotEmpty
                      ? item.batchNumber!
                      : 'PUR-${purchase.id.substring(0, 8)}',
                  expiryDate: Value(item.expiryDate),
                  quantity: Value(qtyInBaseUnit),
                  initialQuantity: Value(qtyInBaseUnit),
                  costPrice: Value(
                    finalUnitCost / item.unitFactor,
                  ), // Cost per base unit
                  syncStatus: const Value(1),
                ),
              );

          // B. Update Purchase Item with Batch ID
          await (db.update(db.purchaseItems)
                ..where((pi) => pi.id.equals(item.id)))
              .write(PurchaseItemsCompanion(batchId: Value(batchId)));

          // C. Record Inventory Transaction
          await db
              .into(db.inventoryTransactions)
              .insert(
                InventoryTransactionsCompanion.insert(
                  productId: item.productId,
                  warehouseId: purchase.warehouseId ?? '',
                  batchId: Value(batchId),
                  quantity: qtyInBaseUnit,
                  type: 'PURCHASE',
                  referenceId: purchaseId,
                ),
              );

          // D. Update Product Total Stock & Buy Price
          await (db.update(
            db.products,
          )..where((p) => p.id.equals(item.productId))).write(
            ProductsCompanion(
              stock: Value(product.stock + qtyInBaseUnit),
              buyPrice: Value(finalUnitCost),
            ),
          );
        }

        // 4. Update Purchase Status
        await (db.update(db.purchases)..where((p) => p.id.equals(purchaseId)))
            .write(const PurchasesCompanion(status: Value('RECEIVED')));

        // 5. Update Supplier Balance if Credit
        if (purchase.isCredit && purchase.supplierId != null) {
          final supplier = await (db.select(
            db.suppliers,
          )..where((s) => s.id.equals(purchase.supplierId!))).getSingle();

          await (db.update(
            db.suppliers,
          )..where((s) => s.id.equals(supplier.id))).write(
            SuppliersCompanion(balance: Value(supplier.balance + purchase.total)),
          );
        }

        // 6. Trigger Accounting & Events
        eventBus.fire(PurchasePostedEvent(purchase, items, userId: userId));

        await _auditService.log(
          action: 'POST_PURCHASE',
          targetEntity: 'Purchases',
          entityId: purchaseId,
          userId: userId,
          details: 'Posted purchase invoice $purchaseId',
        );
      });
    } catch (e) {
      throw Exception('خطأ في العملية: $e');
    }
  }

  /// Posts a sale (Draft -> Posted)
  /// This updates inventory batches (FEFO), records inventory transactions, and triggers accounting.
  Future<void> postSale(String saleId, {String? userId}) async {
    // Check if accounting period is open before posting
    await _checkAccountingPeriodOpen();
    
    // NEW: Check if there is an active shift for cash sales
    final saleHeader = await (db.select(db.sales)..where((s) => s.id.equals(saleId))).getSingle();
    if (saleHeader.paymentMethod == 'cash' && userId != null) {
      final activeShift = await (db.select(db.shifts)
            ..where((s) => s.userId.equals(userId) & s.isOpen.equals(true)))
          .getSingleOrNull();
      if (activeShift == null) {
        throw Exception('لا يمكن إجراء عملية بيع نقدي بدون فتح وردية عمل.');
      }
    }

    await db.transaction(() async {
      // 1. Get Sale and Items
      final sale = saleHeader; // Already fetched above
      
      if (sale.status == 'POSTED') {
        throw Exception('هذه الفاتورة تم ترحيلها بالفعل.');
      }

      final items = await (db.select(
        db.saleItems,
      )..where((si) => si.saleId.equals(saleId))).get();

      if (items.isEmpty) {
        throw Exception('لا يمكن ترحيل فاتورة مبيعات بدون أصناف.');
      }

      // 2. Process each item (Inventory Update - FEFO)
      double saleCogs = 0.0;
      for (var item in items) {
        if (item.quantity <= 0) {
          throw Exception('الكمية يجب أن تكون أكبر من الصفر.');
        }
        
        if (item.price < 0) {
          throw Exception('السعر يجب أن يكون أكبر من أو يساوي الصفر.');
        }

        double remainingToDeduct = item.quantity * item.unitFactor;

        // Stock Validation
        final product = await (db.select(
          db.products,
        )..where((p) => p.id.equals(item.productId))).getSingle();

        if (product.stock < remainingToDeduct) {
          throw Exception(
            'المخزون غير كافٍ للمنتج: ${product.name}. المتوفر: ${product.stock}',
          );
        }

        // استخدم InventoryCostingService إذا كان متاحاً
        if (_costingService != null) {
          final batches = await _costingService!.getBatchesForSale(
            item.productId,
            remainingToDeduct,
          );
          
          double totalDeducted = 0;
          for (var batchData in batches) {
            if (batchData.remainingQuantity <= 0) continue;
            
            // Update Batch Quantity
            await (db.update(
              db.productBatches,
            )..where((b) => b.id.equals(batchData.batch.id))).write(
              ProductBatchesCompanion(
                quantity: Value(batchData.batch.quantity - batchData.remainingQuantity),
              ),
            );

            // Record Inventory Transaction
            await db
                .into(db.inventoryTransactions)
                .insert(
                  InventoryTransactionsCompanion.insert(
                    productId: item.productId,
                    warehouseId: batchData.batch.warehouseId,
                    batchId: Value(batchData.batch.id),
                    quantity: -batchData.remainingQuantity,
                    type: 'SALE',
                    referenceId: saleId,
                  ),
                );

            totalDeducted += batchData.remainingQuantity;
            saleCogs += (batchData.remainingQuantity * batchData.costPerUnit);
          }

          // Update Product Total Stock
          await (db.update(
            db.products,
          )..where((p) => p.id.equals(item.productId))).write(
            ProductsCompanion(stock: Value(product.stock - totalDeducted)),
          );
        } else {
          // Fallback: استخدام المنطق الأصلي FEFO
          // Prioritize: expiryDate ASC (nulls last), then createdAt ASC
          final batches =
              await (db.select(db.productBatches)
                    ..where((b) => b.productId.equals(item.productId))
                    ..where((b) => b.quantity.isBiggerThan(const Variable(0)))
                    ..orderBy([
                      (b) => OrderingTerm(
                        expression: b.expiryDate.isNull(),
                        mode: OrderingMode.asc,
                      ),
                      (b) => OrderingTerm(
                        expression: b.expiryDate,
                        mode: OrderingMode.asc,
                      ),
                      (b) => OrderingTerm(
                        expression: b.createdAt,
                        mode: OrderingMode.asc,
                      ),
                    ]))
                  .get();

          double totalDeducted = 0;
          for (var batch in batches) {
            if (remainingToDeduct <= 0) break;

            double deductFromThisBatch = batch.quantity >= remainingToDeduct
                ? remainingToDeduct
                : batch.quantity;

            // Update Batch Quantity
            await (db.update(
              db.productBatches,
            )..where((b) => b.id.equals(batch.id))).write(
              ProductBatchesCompanion(
                quantity: Value(batch.quantity - deductFromThisBatch),
              ),
            );

            // Record Inventory Transaction
            await db
                .into(db.inventoryTransactions)
                .insert(
                  InventoryTransactionsCompanion.insert(
                    productId: item.productId,
                    warehouseId: batch.warehouseId,
                    batchId: Value(batch.id),
                    quantity: -deductFromThisBatch,
                    type: 'SALE',
                    referenceId: saleId,
                  ),
                );

            remainingToDeduct -= deductFromThisBatch;
            totalDeducted += deductFromThisBatch;
            saleCogs += (deductFromThisBatch * batch.costPrice);
          }

          // Update Product Total Stock
          await (db.update(
            db.products,
          )..where((p) => p.id.equals(item.productId))).write(
            ProductsCompanion(stock: Value(product.stock - totalDeducted)),
          );
        }
      }
      // 3. Update Sale Status
      await (db.update(db.sales)..where((s) => s.id.equals(saleId))).write(
        const SalesCompanion(status: Value('POSTED')),
      );

      // 4. Update Customer Balance if Credit
      if (sale.isCredit && sale.customerId != null) {
        final customer = await (db.select(
          db.customers,
        )..where((c) => c.id.equals(sale.customerId!))).getSingle();

        await (db.update(
          db.customers,
        )..where((c) => c.id.equals(customer.id))).write(
          CustomersCompanion(balance: Value(customer.balance + sale.total)),
        );
      }

      // 5. Trigger Accounting & Events
      eventBus.fire(
        SaleCreatedEvent(sale, items, cogs: saleCogs, userId: userId),
      );

      await _auditService.log(
        action: 'POST_SALE',
        targetEntity: 'Sales',
        entityId: saleId,
        userId: userId,
        details: 'Posted sale invoice $saleId',
      );
    });
  }

  /// Posts a sale return
  /// This updates inventory batches (re-adds stock), records inventory transactions, and triggers accounting.
  Future<void> postSaleReturn(String returnId, {String? userId}) async {
    // Check if accounting period is open before posting
    await _checkAccountingPeriodOpen();
    
    // Check if already processed by looking for existing inventory transactions
    final existingTransactions = await (db.select(db.inventoryTransactions)
          ..where((t) => t.referenceId.equals(returnId))
          ..where((t) => t.type.equals('RETURN')))
        .get();
    if (existingTransactions.isNotEmpty) {
      throw Exception('تم معالجة مردود المبيعات بالفعل');
    }
    
    await db.transaction(() async {
      // 1. Get Return and Items
      final saleReturn = await (db.select(
        db.salesReturns,
      )..where((r) => r.id.equals(returnId))).getSingle();

      final items = await (db.select(
        db.salesReturnItems,
      )..where((ri) => ri.salesReturnId.equals(returnId))).get();

      final sale = await (db.select(
        db.sales,
      )..where((s) => s.id.equals(saleReturn.saleId))).getSingle();

      // 2. Process each item (Inventory Update - Return to Batch)
      for (var item in items) {
        double returnQty = item.quantity;
        final defaultWarehouse = await _configService.getDefaultWarehouseId();
        
        // Get current product
        final product = await (db.select(db.products)
              ..where((p) => p.id.equals(item.productId))).getSingle();
        double qtyInBaseUnit = returnQty;
        
        // Return stock to the specific batch or create new batch if none
        final batchId = item.batchId;
        final batch = batchId != null
            ? await (db.select(db.productBatches)
                  ..where((b) => b.id.equals(batchId)))
                .getSingleOrNull()
            : null;

        if (batch != null) {
          // Update existing batch
          await (db.update(db.productBatches)
                ..where((b) => b.id.equals(batch.id)))
              .write(
            ProductBatchesCompanion(
              quantity: Value(batch.quantity + qtyInBaseUnit),
            ),
          );
        } else {
          // Find or create batch - use FEFO logic to find existing batch first (nulls last)
          final existingBatches = await (db.select(db.productBatches)
                ..where((b) => b.productId.equals(item.productId))
                ..where((b) => b.quantity.isBiggerThan(const Variable(0)))
                ..orderBy([
                  (b) => OrderingTerm(
                    expression: b.expiryDate.isNull(),
                    mode: OrderingMode.asc,
                  ),
                  (b) => OrderingTerm(
                    expression: b.expiryDate,
                    mode: OrderingMode.asc,
                  ),
                ]))
              .get();
          
          if (existingBatches.isNotEmpty) {
            // Add to oldest batch (FEFO)
            final targetBatch = existingBatches.first;
            await (db.update(db.productBatches)
                  ..where((b) => b.id.equals(targetBatch.id)))
                .write(
              ProductBatchesCompanion(
                quantity: Value(targetBatch.quantity + qtyInBaseUnit),
              ),
            );
          } else {
            // Create new batch for the return
            final newBatchId = const Uuid().v4();
            await db.into(db.productBatches).insert(
              ProductBatchesCompanion.insert(
                id: Value(newBatchId),
                productId: item.productId,
                warehouseId: defaultWarehouse,
                batchNumber: 'RETURN-${returnId.substring(0, 8)}',
                expiryDate: const Value(null),
                quantity: Value(qtyInBaseUnit),
                initialQuantity: Value(qtyInBaseUnit),
                costPrice: Value(product.buyPrice),
              ),
            );
          }
        }

        // Update Product Total Stock (Only once)
        await (db.update(db.products)
              ..where((p) => p.id.equals(item.productId)))
            .write(ProductsCompanion(stock: Value(product.stock + qtyInBaseUnit)));

        // Validate batch integrity: ensure product.stock == sum(batches)
        final batchesAfterReturn = await (db.select(db.productBatches)
              ..where((b) => b.productId.equals(item.productId)))
            .get();
        double batchSum = 0;
        for (var b in batchesAfterReturn) {
          batchSum += b.quantity;
        }
        final newStock = product.stock + qtyInBaseUnit;
        if ((batchSum - newStock).abs() > 0.01) {
          developer.log(
            'WARNING: Stock/Batch mismatch after return. Product stock: $newStock, Batch sum: $batchSum',
            name: 'transaction_engine',
          );
        }

        // Record Inventory Transaction
        await db.into(db.inventoryTransactions).insert(
              InventoryTransactionsCompanion.insert(
                productId: item.productId,
                warehouseId: batch?.warehouseId ?? defaultWarehouse,
                batchId: Value(batch?.id ?? ''),
                quantity: qtyInBaseUnit,
                type: 'RETURN',
                referenceId: returnId,
              ),
            );
      }

      // 3. Update Customer Balance if Credit
      if (sale.isCredit && sale.customerId != null) {
        final customer = await (db.select(db.customers)
              ..where((c) => c.id.equals(sale.customerId!))).getSingle();
        await (db.update(db.customers)
              ..where((c) => c.id.equals(customer.id)))
            .write(CustomersCompanion(
          balance: Value(customer.balance - saleReturn.amountReturned),
        ));
      }

      // 4. Trigger Accounting & Events
      eventBus.fire(SaleReturnCreatedEvent(saleReturn, items, userId: userId));
    });
  }

  /// Posts a purchase return
  Future<void> postPurchaseReturn(String returnId, {String? userId}) async {
    // Check if accounting period is open before posting
    await _checkAccountingPeriodOpen();
    
    // Check if already processed by looking for existing inventory transactions
    final existingTransactions = await (db.select(db.inventoryTransactions)
          ..where((t) => t.referenceId.equals(returnId))
          ..where((t) => t.type.equals('PURCHASE_RETURN')))
        .get();
    if (existingTransactions.isNotEmpty) {
      throw Exception('تم معالجة مردود المشتريات بالفعل');
    }
    
    await db.transaction(() async {
      // 1. Get Return and Items
      final purchaseReturn = await (db.select(
        db.purchaseReturns,
      )..where((r) => r.id.equals(returnId))).getSingle();

      final items = await (db.select(
        db.purchaseReturnItems,
      )..where((ri) => ri.purchaseReturnId.equals(returnId))).get();

      final purchase = await (db.select(
        db.purchases,
      )..where((p) => p.id.equals(purchaseReturn.purchaseId))).getSingle();

      // 2. Process each item (Inventory Update - Remove from Batch)
      for (var item in items) {
        double remainingToDeduct = item.quantity;

        // FEFO Logic for purchase return - nulls last
        final batches =
            await (db.select(db.productBatches)
                  ..where((b) => b.productId.equals(item.productId))
                  ..where((b) => b.quantity.isBiggerThan(const Variable(0)))
                  ..orderBy([
                    (b) => OrderingTerm(
                      expression: b.expiryDate.isNull(),
                      mode: OrderingMode.asc,
                    ),
                    (b) => OrderingTerm(
                      expression: b.expiryDate,
                      mode: OrderingMode.asc,
                    ),
                  ]))
                .get();

        for (var batch in batches) {
          if (remainingToDeduct <= 0) break;

          double deduct = batch.quantity >= remainingToDeduct
              ? remainingToDeduct
              : batch.quantity;

          await (db.update(
            db.productBatches,
          )..where((b) => b.id.equals(batch.id))).write(
            ProductBatchesCompanion(quantity: Value(batch.quantity - deduct)),
          );

          // Record Inventory Transaction
          await db
              .into(db.inventoryTransactions)
              .insert(
                InventoryTransactionsCompanion.insert(
                  productId: item.productId,
                  warehouseId: batch.warehouseId,
                  batchId: Value(batch.id),
                  quantity: -deduct,
                  type: 'PURCHASE_RETURN',
                  referenceId: returnId,
                ),
              );

          remainingToDeduct -= deduct;
        }

        // Update Product Total Stock
        final product = await (db.select(
          db.products,
        )..where((p) => p.id.equals(item.productId))).getSingle();

        await (db.update(
          db.products,
        )..where((p) => p.id.equals(item.productId))).write(
          ProductsCompanion(stock: Value(product.stock - item.quantity)),
        );
      }

      // 3. Update Supplier Balance if Credit
      if (purchase.isCredit && purchase.supplierId != null) {
        final supplier = await (db.select(
          db.suppliers,
        )..where((s) => s.id.equals(purchase.supplierId!))).getSingle();

        await (db.update(
          db.suppliers,
        )..where((s) => s.id.equals(supplier.id))).write(
          SuppliersCompanion(
            balance: Value(supplier.balance - purchaseReturn.amountReturned),
          ),
        );
      }

      // 4. Trigger Accounting & Events
      eventBus.fire(
        PurchaseReturnCreatedEvent(purchaseReturn, items, userId: userId),
      );
    });
  }

  /// Posts a customer payment (Receipt)
  Future<void> postCustomerPayment({
    required String customerId,
    required double amount,
    required String paymentMethod, // cash, bank, check
    String? note,
    String? userId,
  }) async {
    await db.transaction(() async {
      // 1. Create Payment Record
      final paymentId = const Uuid().v4();

      await db
          .into(db.customerPayments)
          .insert(
            CustomerPaymentsCompanion.insert(
              id: Value(paymentId),
              customerId: customerId,
              amount: amount,
              paymentDate: Value(DateTime.now()),
              note: Value(note),
              syncStatus: const Value(1),
            ),
          );

      // 2. Update Customer Balance
      final customer = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(customerId))).getSingle();

      await (db.update(db.customers)..where((c) => c.id.equals(customerId)))
          .write(CustomersCompanion(balance: Value(customer.balance - amount)));

      // 3. Trigger Accounting
      eventBus.fire(
        CustomerPaymentEvent(
          customerId: customerId,
          amount: amount,
          paymentMethod: paymentMethod,
          note: note,
          paymentId: paymentId,
          userId: userId,
        ),
      );
    });
  }

  /// Posts a supplier payment (Payment)
  Future<void> postSupplierPayment({
    required String supplierId,
    required double amount,
    required String paymentMethod,
    String? note,
    String? userId,
  }) async {
    await db.transaction(() async {
      // 1. Create Payment Record
      final paymentId = const Uuid().v4();

      await db
          .into(db.supplierPayments)
          .insert(
            SupplierPaymentsCompanion.insert(
              id: Value(paymentId),
              supplierId: supplierId,
              amount: amount,
              paymentDate: Value(DateTime.now()),
              note: Value(note),
              syncStatus: const Value(1),
            ),
          );

      // 2. Update Supplier Balance
      final supplier = await (db.select(
        db.suppliers,
      )..where((s) => s.id.equals(supplierId))).getSingle();

      await (db.update(db.suppliers)..where((s) => s.id.equals(supplierId)))
          .write(SuppliersCompanion(balance: Value(supplier.balance - amount)));

      // 3. Trigger Accounting
      eventBus.fire(
        SupplierPaymentEvent(
          supplierId: supplierId,
          amount: amount,
          paymentMethod: paymentMethod,
          note: note,
          paymentId: paymentId,
          userId: userId,
        ),
      );
    });
  }
}
