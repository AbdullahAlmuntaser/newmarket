import 'package:drift/drift.dart';
import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:supermarket/core/services/audit_service.dart';
import 'package:supermarket/core/services/inventory_costing_service.dart';
import 'package:uuid/uuid.dart';

class GrnService {
  final AppDatabase db;
  final InventoryCostingService? costingService;
  late final AuditService _auditService;

  GrnService(this.db, {this.costingService}) : _auditService = AuditService(db);

  Future<String> createGrnFromPurchase({
    required String purchaseId,
    required String warehouseId,
    String? receivedBy,
    String? notes,
    String? userId,
  }) async {
    return await db.transaction(() async {
      final purchase = await (db.select(db.purchases)
            ..where((p) => p.id.equals(purchaseId)))
          .getSingle();

      final purchaseItems = await (db.select(db.purchaseItems)
            ..where((pi) => pi.purchaseId.equals(purchaseId)))
          .get();

      String grnId = const Uuid().v4();
      String grnNumber = 'GRN-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';

      await db.into(db.goodReceivedNotes).insert(
        GoodReceivedNotesCompanion.insert(
          id: Value(grnId),
          purchaseId: Value(purchaseId),
          supplierId: Value(purchase.supplierId),
          warehouseId: warehouseId,
          grnNumber: grnNumber,
          receivedBy: Value(receivedBy),
          notes: Value(notes ?? 'From Purchase: ${purchase.invoiceNumber}'),
          status: const Value('POSTED'),
          receivedDate: Value(DateTime.now()),
        ),
      );

      final landedCosts = purchase.landedCosts + purchase.shippingCost + purchase.otherExpenses;
      double itemsSubtotal = 0;
      for (var item in purchaseItems) {
        itemsSubtotal += item.quantity * item.price;
      }

      for (var item in purchaseItems) {
        final String productId = item.productId;
        final double qty = item.quantity;
        final double unitFactor = item.unitFactor;
        final double qtyInBaseUnit = qty * unitFactor;

        double landedCostPerUnit = 0;
        if (landedCosts > 0 && itemsSubtotal > 0) {
          final double itemValue = qty * item.price;
          final double proportion = itemValue / itemsSubtotal;
          landedCostPerUnit = (landedCosts * proportion) / qty;
        }

        final double unitCost = item.price + landedCostPerUnit;

        final String batchId = const Uuid().v4();
        await db.into(db.productBatches).insert(
          ProductBatchesCompanion.insert(
            id: Value(batchId),
            productId: productId,
            warehouseId: warehouseId,
            batchNumber: item.batchNumber ?? 'BATCH-$grnNumber',
            quantity: Value(qtyInBaseUnit),
            initialQuantity: Value(qtyInBaseUnit),
            costPrice: Value(unitCost),
            expiryDate: Value(item.expiryDate),
          ),
        );

        final product = await (db.select(db.products)
              ..where((p) => p.id.equals(productId)))
            .getSingle();

        await (db.update(db.products)..where((p) => p.id.equals(productId)))
            .write(
          ProductsCompanion(
            stock: Value(product.stock + qtyInBaseUnit),
            buyPrice: Value(unitCost),
          ),
        );

        await db.into(db.inventoryTransactions).insert(
          InventoryTransactionsCompanion.insert(
            productId: productId,
            warehouseId: warehouseId,
            batchId: Value(batchId),
            quantity: qtyInBaseUnit,
            type: 'PURCHASE',
            referenceId: grnId,
          ),
        );

        await db.into(db.goodReceivedNoteItems).insert(
          GoodReceivedNoteItemsCompanion.insert(
            grnId: grnId,
            productId: productId,
            quantity: qty,
            batchNumber: Value(item.batchNumber),
            expiryDate: Value(item.expiryDate),
          ),
        );

        await (db.update(db.purchaseItems)
              ..where((pi) => pi.id.equals(item.id)))
            .write(PurchaseItemsCompanion(batchId: Value(batchId)));
      }

      await (db.update(db.purchases)..where((p) => p.id.equals(purchaseId)))
          .write(const PurchasesCompanion(status: Value('RECEIVED')));

      await _auditService.log(
        action: 'CREATE_GRN_FROM_PURCHASE',
        targetEntity: 'GoodReceivedNotes',
        entityId: grnId,
        userId: userId,
        details: 'Created GRN $grnNumber from Purchase $purchaseId',
      );

      return grnId;
    });
  }

  Future<List<GrnReportItem>> generateGrnReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final query = db.select(db.goodReceivedNotes).join([
      innerJoin(
        db.warehouses,
        db.warehouses.id.equalsExp(db.goodReceivedNotes.warehouseId),
      ),
    ]);

    if (startDate != null) {
      query.where(db.goodReceivedNotes.receivedDate.isBiggerOrEqual(Variable(startDate)));
    }
    if (endDate != null) {
      query.where(db.goodReceivedNotes.receivedDate.isSmallerOrEqual(Variable(endDate)));
    }

    query.orderBy([OrderingTerm(
      expression: db.goodReceivedNotes.receivedDate,
      mode: OrderingMode.desc,
    )]);

    final rows = await query.get();
    final result = <GrnReportItem>[];

    for (var row in rows) {
      final grn = row.readTable(db.goodReceivedNotes);
      final warehouse = row.readTableOrNull(db.warehouses);

      final items = await (db.select(db.goodReceivedNoteItems)
            ..where((i) => i.grnId.equals(grn.id)))
          .get();

      double totalQty = 0;
      for (var item in items) {
        totalQty += item.quantity;
      }

      result.add(GrnReportItem(
        grnId: grn.id,
        grnNumber: grn.grnNumber,
        warehouseName: warehouse?.name ?? 'Unknown',
        receivedDate: grn.receivedDate,
        totalQuantity: totalQty,
        status: grn.status,
        notes: grn.notes,
      ));
    }

    return result;
  }

  Future<List<ExpiringBatchReport>> getExpiringBatchesReport({int daysThreshold = 30}) async {
    final now = DateTime.now();
    final threshold = now.add(Duration(days: daysThreshold));

    final batches = await (db.select(db.productBatches).join([
      innerJoin(
        db.products,
        db.products.id.equalsExp(db.productBatches.productId),
      ),
      innerJoin(
        db.warehouses,
        db.warehouses.id.equalsExp(db.productBatches.warehouseId),
      ),
    ]))
        .get();

    final result = <ExpiringBatchReport>[];
    for (var row in batches) {
      final batch = row.readTable(db.productBatches);
      final product = row.readTable(db.products);
      final warehouse = row.readTableOrNull(db.warehouses);

      if (batch.expiryDate != null &&
          batch.expiryDate!.isAfter(now) &&
          batch.expiryDate!.isBefore(threshold) &&
          batch.quantity > 0) {
        final daysUntilExpiry = batch.expiryDate!.difference(now).inDays;
        result.add(ExpiringBatchReport(
          batchNumber: batch.batchNumber,
          productName: product.name,
          warehouseName: warehouse?.name ?? 'Unknown',
          quantity: batch.quantity,
          expiryDate: batch.expiryDate!,
          daysUntilExpiry: daysUntilExpiry,
          costValue: batch.quantity * batch.costPrice,
        ));
      }
    }

    result.sort((a, b) => a.daysUntilExpiry.compareTo(b.daysUntilExpiry));
    return result;
  }
}

class GrnReportItem {
  final String grnId;
  final String grnNumber;
  final String warehouseName;
  final DateTime receivedDate;
  final double totalQuantity;
  final String status;
  final String? notes;

  GrnReportItem({
    required this.grnId,
    required this.grnNumber,
    required this.warehouseName,
    required this.receivedDate,
    required this.totalQuantity,
    required this.status,
    this.notes,
  });
}

class ExpiringBatchReport {
  final String batchNumber;
  final String productName;
  final String warehouseName;
  final double quantity;
  final DateTime expiryDate;
  final int daysUntilExpiry;
  final double costValue;

  ExpiringBatchReport({
    required this.batchNumber,
    required this.productName,
    required this.warehouseName,
    required this.quantity,
    required this.expiryDate,
    required this.daysUntilExpiry,
    required this.costValue,
  });
}