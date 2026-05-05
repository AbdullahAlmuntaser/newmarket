import 'package:drift/drift.dart';
import '../../data/datasources/local/app_database.dart';

/// خدمة إدارة إعدادات التطبيق الديناميكية
/// تستبدل القيم المزروعة (Hardcoded) بقيم قابلة للتغيير من واجهة المستخدم
class AppConfigService {
  final AppDatabase _db;

  AppConfigService(this._db);

  // مفاتيح الإعدادات الثابتة
  static const String keyDefaultWarehouse = 'default_warehouse_id';
  static const String keyDefaultBranch = 'default_branch_id';
  static const String keyTaxRate = 'tax_rate';
  static const String keyCompanyPhone = 'company_phone';
  static const String keyInvoiceMessage = 'invoice_message';
  static const String keyLowStockThreshold = 'low_stock_threshold';

  /// الحصول على قيمة إعداد معينة
  Future<String?> getString(String key) async {
    final result = await (_db.select(_db.appConfigTable)..where((t) => t.key.equals(key))).getSingleOrNull();
    return result?.value;
  }

  /// الحصول على قيمة رقمية
  Future<double> getDouble(String key, {double defaultValue = 0.0}) async {
    final val = await getString(key);
    return val != null ? double.tryParse(val) ?? defaultValue : defaultValue;
  }

  /// الحصول على قيمة صحيحة
  Future<int> getInt(String key, {int defaultValue = 0}) async {
    final val = await getString(key);
    return val != null ? int.tryParse(val) ?? defaultValue : defaultValue;
  }

  /// حفظ إعداد نصي
  Future<void> setString(String key, String value) async {
    await _db.into(_db.appConfigTable).insert(
      AppConfigTableCompanion(
        key: Value(key),
        value: Value(value),
        updatedAt: Value(DateTime.now()),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  /// حفظ إعداد رقمي
  Future<void> setDouble(String key, double value) async {
    await setString(key, value.toString());
  }

  /// حفظ إعداد صحيح
  Future<void> setInt(String key, int value) async {
    await setString(key, value.toString());
  }

  // --- دوال مساعدة للإعدادات الشائعة ---

  /// الحصول على معرف المستودع الافتراضي
  Future<String> getDefaultWarehouseId() async {
    return await getString(keyDefaultWarehouse) ?? 'MAIN_WAREHOUSE'; // قيمة افتراضية آمنة
  }

  /// الحصول على معرف الفرع الافتراضي
  Future<String> getDefaultBranchId() async {
    return await getString(keyDefaultBranch) ?? 'BR001';
  }

  /// الحصول على نسبة الضريبة
  Future<double> getTaxRate() async {
    return await getDouble(keyTaxRate, defaultValue: 0.15); // 15% افتراضي
  }

  /// الحصول على رسالة الفاتورة الافتراضية للواتساب
  Future<String> getInvoiceMessage() async {
    return await getString(keyInvoiceMessage) ?? 
      'شكراً لتعاملكم معنا.\nتفاصيل الفاتورة مرفقة.';
  }

  /// تحديد حد التنبيه للمخزون المنخفض
  Future<int> getLowStockThreshold() async {
    return await getInt(keyLowStockThreshold, defaultValue: 10);
  }

  /// تهيئة الإعدادات الافتراضية عند أول تشغيل
  Future<void> initializeDefaults() async {
    final hasConfig = await (_db.select(_db.appConfigTable)..limit(1)).get().then((v) => v.isNotEmpty);
    if (!hasConfig) {
      await setString(keyDefaultWarehouse, 'MAIN_WAREHOUSE');
      await setString(keyDefaultBranch, 'BR001');
      await setDouble(keyTaxRate, 0.15);
      await setInt(keyLowStockThreshold, 10);
      await setString(keyInvoiceMessage, 'شكراً لتعاملكم معنا. نقدر ثقتكم بنا.');
    }
  }
}
