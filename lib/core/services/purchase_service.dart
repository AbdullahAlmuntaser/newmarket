import 'package:drift/drift.dart';
import 'package:supermarket/core/services/inventory_costing_service.dart';
import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:supermarket/core/services/posting_engine.dart';
import 'package:uuid/uuid.dart';

class PurchaseService {
  final AppDatabase db;
  final PostingEngine postingEngine;
  final InventoryCostingService inventoryCostingService;

  PurchaseService(this.db, this.postingEngine, this.inventoryCostingService);

  Future<Purchase> createPurchase({
    required String supplierId,
    required List<PurchaseItemsCompanion> items,
    required double total,
    String? warehouseId,
  }) async {
    final purchaseId = const Uuid().v4();
    final purchase = PurchasesCompanion.insert(
      id: Value(purchaseId),
      supplierId: Value(supplierId),
      date: Value(DateTime.now()),
      total: total,
      status: const Value('draft'),
      warehouseId: Value(warehouseId),
    );

    await db.into(db.purchases).insert(purchase);

    for (var item in items) {
      await db
          .into(db.purchaseItems)
          .insert(item.copyWith(purchaseId: Value(purchaseId)));
    }

    return await (db.select(
      db.purchases,
    )..where((p) => p.id.equals(purchaseId))).getSingle();
  }

  Future<void> postPurchase(String purchaseId) async {
    // 1. Verify that GRN exists for this purchase
    final grn = await (db.select(db.goodReceivedNotes)
          ..where((g) => g.purchaseId.equals(purchaseId))
          ..where((g) => g.status.equals('POSTED')))
        .getSingleOrNull();

    if (grn == null) {
      throw Exception('لا يمكن ترحيل الفاتورة قبل استلام البضاعة (GRN غير موجود أو غير مرحل).');
    }

    final purchase = await (db.select(db.purchases)
          ..where((p) => p.id.equals(purchaseId)))
        .getSingle();
    final items = await (db.select(db.purchaseItems)
          ..where((i) => i.purchaseId.equals(purchaseId)))
        .get();

    double subtotal = 0;
    for (var item in items) {
      subtotal += (item.quantity * item.unitFactor * item.unitPrice);
    }

    // حساب إجمالي المصاريف الإضافية
    double totalExpenses = (purchase.shippingCost + purchase.otherExpenses);

    double discount = purchase.discount;
    double tax = (subtotal - discount) * 0.15;

    await postingEngine.post(
      type: TransactionType.purchase,
      referenceId: purchaseId,
      context: {
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'expenses': totalExpenses,
        'total': subtotal - discount + tax + totalExpenses,
        'supplierId': purchase.supplierId,
        'description':
            'Purchase Invoice #${purchase.invoiceNumber ?? purchase.id.substring(0, 8)}',
      },
    );

    // Update Purchase status to COMPLETED
    await (db.update(db.purchases)..where((p) => p.id.equals(purchaseId))).write(
      const PurchasesCompanion(status: Value('COMPLETED')),
    );
  }
}
