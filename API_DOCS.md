# 📚 SystemMarket ERP - توثيق الخدمات (API Documentation)

## فهرس الخدمات

### 1. خدمات الأعمال الأساسية

#### SalesService - خدمة المبيعات
```dart
// إنشاء عملية بيع جديدة
Future<Sale> createSale({
  required String id,
  required String customerId,
  required List<SaleItemData> items,
  required String paymentMethod,
  required String branchId,
  double? discount,
  double? taxRate,
});

// إرجاع بيع
Future<void> createSaleReturn({
  required String saleId,
  required List<SaleItemData> items,
  String? reason,
});

// الحصول على مبيعات حديثة
Future<List<Sale>> getRecentSales({
  int limit = 20,
  int offset = 0,
});
```

#### PurchaseService - خدمة المشتريات
```dart
// إنشاء أمر شراء
Future<PurchaseOrder> createPurchaseOrder({
  required String supplierId,
  required List<PurchaseItemData> items,
  DateTime? expectedDate,
});

// استلام بضاعة (GRN)
Future<void> receiveGoods({
  required String purchaseId,
  required List<GRNItemData> items,
});

// إرجاع شراء
Future<void> createPurchaseReturn({
  required String purchaseId,
  required List<PurchaseItemData> items,
});
```

#### InventoryService - خدمة المخزون
```dart
// إضافة مخزون
Future<void> addStock(
  String productId,
  int quantity,
  String reason, {
  String? batchId,
});

// خصم مخزون
Future<void> removeStock(
  String productId,
  int quantity,
  String reason,
);

// جرد مخزون
Future<void> performStockTake({
  required String warehouseId,
  required List<StockCountData> counts,
});

// نقل مخزون بين مستودعات
Future<void> transferStock({
  required String fromWarehouseId,
  required String toWarehouseId,
  required List<TransferItemData> items,
});
```

#### AccountingService - الخدمة المحاسبية
```dart
// قيد يومية
Future<GLEntry> createJournalEntry({
  required String description,
  required List<GLLineData> lines,
  String? referenceId,
  DateTime? date,
});

// تسجيل دفعة عميل
Future<void> recordCustomerPayment({
  required String customerId,
  required double amount,
  required String paymentMethod,
  String? invoiceId,
});

// تسجيل دفعة مورد
Future<void> recordSupplierPayment({
  required String supplierId,
  required double amount,
  required String paymentMethod,
  String? invoiceId,
});

// ترحيل بيع (ينشئ قيود تلقائية)
Future<void> postSale(Sale sale);

// ترحيل شراء (ينشئ قيود تلقائية)
Future<void> postPurchase(PurchaseOrder purchase);
```

### 2. خدمات التقارير

#### ReportEngineService - محرك التقارير
```dart
// الأصناف الأكثر مبيعاً
Future<List<Map<String, dynamic>>> getTopSellingProducts({
  DateTime? startDate,
  DateTime? endDate,
  int limit = 10,
});

// هامش الربح
Future<List<Map<String, dynamic>>> getProfitMarginReport({
  DateTime? startDate,
  DateTime? endDate,
});

// حركة صنف
Future<List<Map<String, dynamic>>> getProductMovementReport(
  String productId,
);

// المبيعات اليومية
Future<List<Map<String, dynamic>>> getDailySalesReport({
  required DateTime startDate,
  required DateTime endDate,
});

// قيمة المخزون
Future<Map<String, dynamic>> getInventoryValuationReport();

// تصدير JSON
String exportToJson(List<Map<String, dynamic>> data);

// تصدير CSV
String exportToCsv(List<Map<String, dynamic>> data);
```

### 3. خدمات النظام

#### AppConfigService - إعدادات النظام
```dart
// الحصول على نسبة الضريبة
Future<double> getTaxRate();

// الحصول على الفرع الافتراضي
Future<String> getDefaultBranchId();

// الحصول على المستودع الافتراضي
Future<String> getDefaultWarehouseId();

// تحديث إعداد
Future<void> updateSetting(String key, dynamic value);
```

#### PermissionService - الصلاحيات
```dart
// التحقق من صلاحية
Future<bool> hasPermission(String permission);

// تنفيذ دالة إذا كان لديه صلاحية
Future<T?> executeIfAllowed<T>({
  required String permission,
  required Future<T> Function() action,
  String? errorMessage,
});

// إضافة صلاحية لمستخدم
Future<void> grantPermission(String userId, String permission);

// سحب صلاحية
Future<void> revokePermission(String userId, String permission);
```

#### AuditService - سجلات التدقيق
```dart
// تسجيل حدث
Future<void> logEvent({
  required String entityType,
  required String entityId,
  required String action,
  Map<String, dynamic>? oldData,
  Map<String, dynamic>? newData,
});

// الحصول على سجلات كيان
Future<List<AuditLog>> getEntityLogs(String entityType, String entityId);

// البحث في السجلات
Future<List<AuditLog>> searchLogs({
  DateTime? startDate,
  DateTime? endDate,
  String? userId,
  String? action,
});
```

#### BackupService - النسخ الاحتياطي
```dart
// إنشاء نسخة احتياطية
Future<BackupFile> createBackup();

// استعادة نسخة
Future<void> restoreBackup(BackupFile backup);

// جدولة نسخ تلقائي
Future<void> scheduleAutomaticBackup(Duration interval);

// تنظيف النسخ القديمة
Future<void> cleanupOldBackups(int keepCount);
```

### 4. نماذج البيانات

#### SaleItemData
```dart
class SaleItemData {
  final String productId;
  final int quantity;
  final double price;
  final double? discount;
  
  SaleItemData({
    required this.productId,
    required this.quantity,
    required this.price,
    this.discount,
  });
}
```

#### GLLineData
```dart
class GLLineData {
  final String accountId;
  final double debit;
  final double credit;
  final String? description;
  
  GLLineData({
    required this.accountId,
    this.debit = 0,
    this.credit = 0,
    this.description,
  });
}
```

## أمثلة استخدام

### مثال 1: إنشاء عملية بيع كاملة
```dart
final sale = await salesService.createSale(
  id: uuid.v4(),
  customerId: customerId,
  items: [
    SaleItemData(productId: 'P001', quantity: 2, price: 100.0),
    SaleItemData(productId: 'P002', quantity: 1, price: 50.0),
  ],
  paymentMethod: 'cash',
  branchId: await configService.getDefaultBranchId(),
  discount: 10.0,
);

await accountingService.postSale(sale);
```

### مثال 2: تقرير الأصناف الأكثر مبيعاً
```dart
final report = await reportEngine.getTopSellingProducts(
  startDate: DateTime.now().subtract(Duration(days: 30)),
  endDate: DateTime.now(),
  limit: 10,
);

final csv = reportEngine.exportToCsv(report);
```

### مثال 3: التحقق من الصلاحيات
```dart
final canDelete = await permissionService.hasPermission('DELETE_INVOICE');

if (canDelete) {
  await invoiceService.deleteInvoice(invoiceId);
} else {
  throw Exception('غير مصرح لك بحذف الفواتير');
}
```

## الأخطاء الشائعة

### StaleElementReferenceException
```dart
// ❌ خطأ: استخدام مرجع قديم
final product = await db.select(db.products).getSingle();
await Future.delayed(Duration(seconds: 1));
await db.update(db.products).write(product); // قد يفشل

// ✅ صحيح: جلب أحدث بيانات
final product = await db.select(db.products).getSingle();
// ... معالجة فورية ...
await db.update(db.products).write(product);
```

### Negative Stock
```dart
// ❌ خطأ: عدم التحقق من المخزون
await inventoryService.removeStock(productId, 100, 'بيع');

// ✅ صحيح: التحقق أولاً
final product = await getProduct(productId);
if (product.stockQuantity >= 100) {
  await inventoryService.removeStock(productId, 100, 'بيع');
} else {
  throw Exception('المخزون غير كافٍ');
}
```

---

**الإصدار:** 2.0  
**آخر تحديث:** 2024
