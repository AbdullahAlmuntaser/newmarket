import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:supermarket/core/services/sales_service.dart';
import 'package:supermarket/core/services/inventory_service.dart';
import 'package:supermarket/core/services/accounting_service.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase db;
  late SalesService salesService;
  late InventoryService inventoryService;
  late AccountingService accountingService;

  setUp(() {
    db = AppDatabase.connect(NativeDatabase.memory());
    // تهيئة الخدمات ستتم في كل اختبار
  });

  tearDown(() async {
    await db.close();
  });

  test('دورة بيع كاملة: إنشاء بيع -> تحديث مخزون -> قيد محاسبي', () async {
    // إعداد الخدمات
    salesService = SalesService(db);
    inventoryService = InventoryService(db);
    accountingService = AccountingService(db);

    // 1. إنشاء منتج تجريبي
    final productId = const Uuid().v4();
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: productId,
      name: 'منتج اختبار',
      costPrice: 50.0,
      sellingPrice: 100.0,
      stockQuantity: 100,
      categoryId: Value.absent(),
    ));

    // 2. إنشاء عميل تجريبي
    final customerId = const Uuid().v4();
    await db.into(db.partners).insert(PartnersCompanion.insert(
      id: customerId,
      name: 'عميل اختبار',
      type: PartnerType.customer,
      phone: Value('123456789'),
    ));

    // 3. إنشاء عملية بيع
    final saleId = const Uuid().v4();
    final sale = await salesService.createSale(
      id: saleId,
      customerId: customerId,
      items: [
        SaleItemData(productId: productId, quantity: 5, price: 100.0),
      ],
      paymentMethod: 'cash',
      branchId: 'BR001',
    );

    // التحقق من إنشاء البيع
    expect(sale, isNotNull);
    expect(sale.totalAmount, closeTo(500.0, 0.01));

    // 4. التحقق من تحديث المخزون
    final product = await db.select(db.products).where((p) => p.id.equals(productId)).getSingle();
    expect(product.stockQuantity, equals(95)); // 100 - 5

    // 5. التحقق من القيد المحاسبي
    final entries = await db.select(db.glEntries).where((e) => e.referenceId.equals(saleId)).get();
    expect(entries.isNotEmpty, isTrue);
    
    // التحقق من أن القيد متوازن
    double totalDebit = 0;
    double totalCredit = 0;
    for (final entry in entries) {
      final lines = await db.select(db.glLines).where((l) => l.entryId.equals(entry.id)).get();
      for (final line in lines) {
        if (line.debit > 0) totalDebit += line.debit;
        if (line.credit > 0) totalCredit += line.credit;
      }
    }
    expect(totalDebit, closeTo(totalCredit, 0.01));
  });

  test('حماية المخزون السلبي: يجب فشل البيع إذا كان المخزون غير كافٍ', () async {
    salesService = SalesService(db);

    // إنشاء منتج بمخزون قليل
    final productId = const Uuid().v4();
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: productId,
      name: 'منتج محدود',
      costPrice: 50.0,
      sellingPrice: 100.0,
      stockQuantity: 3,
      categoryId: Value.absent(),
    ));

    final customerId = const Uuid().v4();
    await db.into(db.partners).insert(PartnersCompanion.insert(
      id: customerId,
      name: 'عميل',
      type: PartnerType.customer,
    ));

    // محاولة بيع كمية أكبر من المخزون
    expect(
      () => salesService.createSale(
        id: const Uuid().v4(),
        customerId: customerId,
        items: [
          SaleItemData(productId: productId, quantity: 10, price: 100.0),
        ],
        paymentMethod: 'cash',
        branchId: 'BR001',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('تسلسل حركات المخزون: شراء -> بيع -> مرتجع', () async {
    inventoryService = InventoryService(db);
    salesService = SalesService(db);

    final productId = const Uuid().v4();
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: productId,
      name: 'منتج متحرك',
      costPrice: 50.0,
      sellingPrice: 100.0,
      stockQuantity: 0,
      categoryId: Value.absent(),
    ));

    // 1. شراء
    await inventoryService.addStock(productId, 20, 'شراء ابتدائي');
    
    // 2. بيع
    final customerId = const Uuid().v4();
    await db.into(db.partners).insert(PartnersCompanion.insert(
      id: customerId,
      name: 'عميل',
      type: PartnerType.customer,
    ));
    
    await salesService.createSale(
      id: const Uuid().v4(),
      customerId: customerId,
      items: [SaleItemData(productId: productId, quantity: 15, price: 100.0)],
      paymentMethod: 'cash',
      branchId: 'BR001',
    );

    // 3. مرتجع جزئي
    await inventoryService.addStock(productId, 5, 'مرتجع مبيعات');

    final product = await db.select(db.products).where((p) => p.id.equals(productId)).getSingle();
    expect(product.stockQuantity, equals(10)); // 0 + 20 - 15 + 5
  });
}
