import 'dart:convert';
import 'package:drift/drift.dart';
import '../../datasources/local/app_database.dart';

/// خدمة سجل التدقيقات - تسجل جميع العمليات الحساسة في النظام
class AuditLogService {
  final AppDatabase db;

  AuditLogService(this.db);

  /// تسجيل عملية INSERT
  Future<void> logInsert({
    required String tableName,
    required int recordId,
    required Map<String, dynamic> newValues,
    int? userId,
    String? ipAddress,
  }) async {
    await db.into(db.auditLogs).insert(
      AuditLogsCompanion.insert(
        tableName: tableName,
        recordId: recordId,
        action: 'INSERT',
        newValues: Value(jsonEncode(newValues)),
        userId: Value(userId),
        ipAddress: Value(ipAddress),
      ),
    );
  }

  /// تسجيل عملية UPDATE
  Future<void> logUpdate({
    required String tableName,
    required int recordId,
    required Map<String, dynamic> oldValues,
    required Map<String, dynamic> newValues,
    int? userId,
    String? ipAddress,
  }) async {
    // تحديد الحقول التي تغيرت فقط
    final changedFields = <String, dynamic>{};
    
    for (var key in newValues.keys) {
      if (!oldValues.containsKey(key) || oldValues[key] != newValues[key]) {
        changedFields[key] = {
          'old': oldValues[key],
          'new': newValues[key],
        };
      }
    }

    if (changedFields.isNotEmpty) {
      await db.into(db.auditLogs).insert(
        AuditLogsCompanion.insert(
          tableName: tableName,
          recordId: recordId,
          action: 'UPDATE',
          oldValues: Value(jsonEncode(oldValues)),
          newValues: Value(jsonEncode(changedFields)),
          userId: Value(userId),
          ipAddress: Value(ipAddress),
        ),
      );
    }
  }

  /// تسجيل عملية DELETE
  Future<void> logDelete({
    required String tableName,
    required int recordId,
    required Map<String, dynamic> oldValues,
    int? userId,
    String? ipAddress,
  }) async {
    await db.into(db.auditLogs).insert(
      AuditLogsCompanion.insert(
        tableName: tableName,
        recordId: recordId,
        action: 'DELETE',
        oldValues: Value(jsonEncode(oldValues)),
        userId: Value(userId),
        ipAddress: Value(ipAddress),
      ),
    );
  }

  /// الحصول على سجل التدقيقات لجدول معين
  Future<List<AuditLog>> getAuditLogForTable(String tableName, {int? recordId}) async {
    var query = db.select(db.auditLogs)
        .where((t) => t.tableName.equals(tableName));

    if (recordId != null) {
      query = query.where((t) => t.recordId.equals(recordId));
    }

    return query.orderBy([(t) => OrderingTerm.desc(t.timestamp)]).get();
  }

  /// الحصول على سجل التدقيقات لمستخدم معين
  Future<List<AuditLog>> getAuditLogForUser(int userId, {DateTime? fromDate, DateTime? toDate}) async {
    var query = db.select(db.auditLogs)
        .where((t) => t.userId.equals(userId));

    if (fromDate != null) {
      query = query.where((t) => t.timestamp.isBiggerOrEqualValue(fromDate));
    }

    if (toDate != null) {
      query = query.where((t) => t.timestamp.isSmallerOrEqualValue(toDate));
    }

    return query.orderBy([(t) => OrderingTerm.desc(t.timestamp)]).get();
  }

  /// الحصول على جميع حركات التدقيق خلال فترة معينة
  Future<List<AuditLog>> getAuditLogsByPeriod(DateTime from, DateTime to, {String? action}) async {
    var query = db.select(db.auditLogs)
        .where((t) => t.timestamp.isBetweenValues(from, to));

    if (action != null) {
      query = query.where((t) => t.action.equals(action));
    }

    return query.orderBy([(t) => OrderingTerm.desc(t.timestamp)]).get();
  }

  /// تقرير التغيرات في سجل معين
  Future<List<Map<String, dynamic>>> getRecordChangeHistory(String tableName, int recordId) async {
    final logs = await getAuditLogForTable(tableName, recordId: recordId);
    
    return logs.map((log) => {
      'timestamp': log.timestamp,
      'action': log.action,
      'userId': log.userId,
      'oldValues': log.oldValues != null ? jsonDecode(log.oldValues!) : null,
      'newValues': log.newValues != null ? jsonDecode(log.newValues!) : null,
      'ipAddress': log.ipAddress,
    }).toList();
  }

  /// تنظيف السجلات القديمة (أقدم من عدد معين من الأيام)
  Future<int> cleanupOldLogs(int daysToKeep) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
    
    return await db.delete(db.auditLogs)
        .where((t) => t.timestamp.isSmallerThanValue(cutoffDate))
        .go();
  }

  /// تصدير سجل التدقيقات إلى JSON
  Future<String> exportAuditLogToJson({
    DateTime? fromDate,
    DateTime? toDate,
    String? tableName,
  }) async {
    List<AuditLog> logs;

    if (tableName != null) {
      logs = await getAuditLogForTable(tableName);
    } else if (fromDate != null && toDate != null) {
      logs = await getAuditLogsByPeriod(fromDate, toDate);
    } else {
      logs = await db.select(db.auditLogs)
          .orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          .limit(1000)
          .get();
    }

    final exportData = logs.map((log) => {
      'id': log.id,
      'tableName': log.tableName,
      'recordId': log.recordId,
      'action': log.action,
      'oldValues': log.oldValues,
      'newValues': log.newValues,
      'userId': log.userId,
      'timestamp': log.timestamp.toIso8601String(),
      'ipAddress': log.ipAddress,
    }).toList();

    return jsonEncode({
      'exportedAt': DateTime.now().toIso8601String(),
      'recordCount': exportData.length,
      'data': exportData,
    });
  }
}
