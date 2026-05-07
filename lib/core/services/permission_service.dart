import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:drift/drift.dart';

/// أكواد الصلاحيات المستخدمة في النظام
class PermissionCode {
  static const String POST_SALE = 'POST_SALE';
  static const String POST_PURCHASE = 'POST_PURCHASE';
  static const String POST_SALE_RETURN = 'POST_SALE_RETURN';
  static const String POST_PURCHASE_RETURN = 'POST_PURCHASE_RETURN';
  static const String DELETE_INVOICE = 'DELETE_INVOICE';
  static const String VOID_TRANSACTION = 'VOID_TRANSACTION';
  static const String MANAGE_USERS = 'MANAGE_USERS';
  static const String VIEW_REPORTS = 'VIEW_REPORTS';
  static const String MANAGE_SETTINGS = 'MANAGE_SETTINGS';
  static const String MANAGE_INVENTORY = 'MANAGE_INVENTORY';
  static const String APPROVE_DISCOUNT = 'APPROVE_DISCOUNT';
}

class PermissionService {
  final AppDatabase db;

  PermissionService(this.db);

  /// التحقق من أن المستخدم لديه الصلاحية المطلوبة
  Future<bool> hasPermission(String userId, String permissionCode) async {
    try {
      final user = db.select(db.users)..where((u) => u.id.equals(userId));
      final userData = await user.getSingleOrNull();
      if (userData == null) return false;

      // الحصول على صلاحيات الدور
      final query = db.select(db.rolePermissions)
          ..where((rp) => rp.role.equals(userData.role) & rp.permissionCode.equals(permissionCode));
      
      final permission = await query.getSingleOrNull();
      return permission != null;
    } catch (e) {
      return false;
    }
  }

  /// التحقق من الصلاحية باستخدام كود الصلاحية (للتوافق مع الكود القديم)
  Future<bool> check(String permissionCode) async {
    // ملاحظة: هذه الدالة تتطلب معرفة userId من السياق
    // يجب تمرير userId في التطبيقات الحقيقية
    return true; // افتراضي للسماح - يجب تحسينه
  }

  /// تنفيذ عملية فقط إذا كان المستخدم يملك الصلاحية
  Future<T?> executeIfAllowed<T>(
    String userId,
    String permissionCode,
    Future<T> Function() action,
  ) async {
    if (await hasPermission(userId, permissionCode)) {
      return await action();
    } else {
      throw Exception('غير مصرح لك بتنفيذ هذه العملية ($permissionCode)');
    }
  }
}
