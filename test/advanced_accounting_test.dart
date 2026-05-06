import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import '../lib/data/datasources/local/app_database.dart';
import '../lib/core/services/fixed_assets_service.dart';
import '../lib/core/services/payroll_service.dart';
import '../lib/core/services/audit_log_service.dart';

void main() {
  late AppDatabase db;
  late FixedAssetsService fixedAssetsService;
  late PayrollService payrollService;
  late AuditLogService auditLogService;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection.inMemory());
    fixedAssetsService = FixedAssetsService(db);
    payrollService = PayrollService(db);
    auditLogService = AuditLogService(db);

    // إعداد بيانات أولية للاختبار
    await _setupInitialData();
  });

  tearDown(() async {
    await db.close();
  });

  group('اختبارات الأصول الثابتة', () {
    test('حساب الإهلاك الشهري بطريقة القسط الثابت', () async {
      // إنشاء أصل تجريبي
      final categoryId = await db.into(db.assetCategories).insert(
        AssetCategoriesCompanion.insert(
          name: 'مركبات',
          code: 'VEH',
          defaultDepreciationRate: 0.2,
        ),
      );

      final assetId = await db.into(db.fixedAssets).insert(
        FixedAssetsCompanion.insert(
          name: 'سيارة نقل',
          categoryId: categoryId,
          purchaseCost: 120000,
          purchaseDate: DateTime(2024, 1, 1),
          acquisitionDate: DateTime(2024, 1, 1),
          salvageValue: 0,
          usefulLifeMonths: 60, // 5 سنوات
          depreciationMethod: 'straight_line',
        ),
      );

      final monthlyDepreciation = await fixedAssetsService.calculateMonthlyDepreciation(assetId);
      
      // الإهلاك الشهري المتوقع: 120000 / 60 = 2000
      expect(monthlyDepreciation, equals(2000.0));
    });

    test('تشغيل الإهلاك الشهري وإنشاء القيد المحاسبي', () async {
      // إعداد الأصل
      final categoryId = await db.into(db.assetCategories).insert(
        AssetCategoriesCompanion.insert(name: 'أثاث', code: 'FUR'),
      );

      final assetId = await db.into(db.fixedAssets).insert(
        FixedAssetsCompanion.insert(
          name: 'مكتب',
          categoryId: categoryId,
          purchaseCost: 6000,
          purchaseDate: DateTime(2024, 1, 1),
          acquisitionDate: DateTime(2024, 1, 1),
          salvageValue: 0,
          usefulLifeMonths: 12,
          depreciationMethod: 'straight_line',
        ),
      );

      final results = await fixedAssetsService.runMonthlyDepreciation(DateTime(2024, 1, 31));
      
      expect(results.length, greaterThan(0));
      expect(results.first['assetId'], equals(assetId));
      expect(results.first['depreciationAmount'], equals(500.0)); // 6000 / 12
      
      // التحقق من تحديث الأصل
      final updatedAsset = await db.select(db.fixedAssets)
          .where((t) => t.id.equals(assetId))
          .getSingle();
      
      expect(updatedAsset.accumulatedDepreciation, equals(500));
      expect(updatedAsset.lastDepreciationDate, isNotNull);
    });
  });

  group('اختبارات الرواتب', () {
    test('حساب رواتب الموظفين', () async {
      // إضافة موظف تجريبي
      await db.into(db.employees).insert(
        EmployeesCompanion.insert(
          name: 'أحمد محمد',
          code: 'EMP001',
          hireDate: DateTime(2024, 1, 1),
          basicSalary: 5000,
          housingAllowance: 1500,
          transportAllowance: 500,
          otherAllowances: 0,
          totalDeductions: 200,
        ),
      );

      final result = await payrollService.calculatePayroll('2024-01');
      
      expect(result['employeeCount'], equals(1));
      expect(result['totalSalaries'], equals(5000));
      expect(result['totalAllowances'], equals(2000)); // 1500 + 500
      expect(result['totalDeductions'], equals(200));
      expect(result['netPayable'], equals(6800)); // 5000 + 2000 - 200
    });

    test('خصم الخصومات الإضافية المتكررة', () async {
      final empId = await db.into(db.employees).insert(
        EmployeesCompanion.insert(
          name: 'خالد علي',
          code: 'EMP002',
          hireDate: DateTime(2024, 1, 1),
          basicSalary: 4000,
          housingAllowance: 1000,
          totalDeductions: 0,
        ),
      );

      // إضافة قرض بقسط شهري
      await db.into(db.additionalDeductions).insert(
        AdditionalDeductionsCompanion.insert(
          employeeId: empId,
          type: 'loan',
          amount: 500,
          deductionDate: DateTime(2024, 1, 15),
          isRecurring: true,
          remainingInstallments: 3,
        ),
      );

      final result = await payrollService.calculatePayroll('2024-01');
      
      // يجب أن يشمل الخصم الإضافي
      expect(result['totalDeductions'], equals(500));
      expect(result['netPayable'], equals(4500)); // 4000 + 1000 - 500
    });
  });

  group('اختبارات سجل التدقيقات', () {
    test('تسجيل عملية INSERT', () async {
      await auditLogService.logInsert(
        tableName: 'test_table',
        recordId: 1,
        newValues: {'name': 'Test', 'value': 100},
        userId: 1,
      );

      final logs = await auditLogService.getAuditLogForTable('test_table');
      
      expect(logs.length, equals(1));
      expect(logs.first.action, equals('INSERT'));
      expect(logs.first.recordId, equals(1));
    });

    test('تسجيل عملية UPDATE مع تحديد الحقول المتغيرة', () async {
      final oldValues = {'name': 'Old', 'value': 100};
      final newValues = {'name': 'New', 'value': 100}; // value لم يتغير

      await auditLogService.logUpdate(
        tableName: 'test_table',
        recordId: 2,
        oldValues: oldValues,
        newValues: newValues,
        userId: 1,
      );

      final logs = await auditLogService.getAuditLogForTable('test_table', recordId: 2);
      
      expect(logs.length, equals(1));
      expect(logs.first.action, equals('UPDATE'));
      
      // التحقق من أن فقط الحقل المتغير تم تسجيله
      final changes = logs.first.newValues;
      expect(changes, contains('name'));
    });

    test('الحصول على تاريخ التغيرات لسجل معين', () async {
      final recordId = 3;

      // تسجيل عدة عمليات
      await auditLogService.logInsert(
        tableName: 'products',
        recordId: recordId,
        newValues: {'name': 'Product'},
      );

      await auditLogService.logUpdate(
        tableName: 'products',
        recordId: recordId,
        oldValues: {'name': 'Product'},
        newValues: {'name': 'Updated Product'},
      );

      final history = await auditLogService.getRecordChangeHistory('products', recordId);
      
      expect(history.length, equals(2));
      expect(history.first['action'], equals('UPDATE'));
      expect(history.last['action'], equals('INSERT'));
    });
  });

  group('اختبارات التكامل', () {
    test('دورة حياة الأصل الكاملة (شراء -> إهلاك -> بيع)', () async {
      // 1. إنشاء فئة أصول
      final categoryId = await db.into(db.assetCategories).insert(
        AssetCategoriesCompanion.insert(name: 'أجهزة كمبيوتر', code: 'IT'),
      );

      // 2. شراء أصل
      final assetId = await db.into(db.fixedAssets).insert(
        FixedAssetsCompanion.insert(
          name: 'لابتوب',
          categoryId: categoryId,
          purchaseCost: 5000,
          purchaseDate: DateTime(2024, 1, 1),
          acquisitionDate: DateTime(2024, 1, 1),
          usefulLifeMonths: 24,
          depreciationMethod: 'straight_line',
        ),
      );

      // 3. تشغيل الإهلاك لمدة 6 أشهر
      for (var month = 1; month <= 6; month++) {
        await fixedAssetsService.runMonthlyDepreciation(DateTime(2024, month, 28));
      }

      final asset = await db.select(db.fixedAssets)
          .where((t) => t.id.equals(assetId))
          .getSingle();

      // الإهلاك المتراكم بعد 6 أشهر: (5000/24) * 6 = 1250
      expect(asset.accumulatedDepreciation, closeTo(1250, 1));

      // 4. بيع الأصل
      final disposalResult = await fixedAssetsService.disposeAsset(
        assetId: assetId,
        disposalDate: DateTime(2024, 7, 1),
        disposalType: 'sold',
        salePrice: 4000,
      );

      // الربح = سعر البيع - القيمة الدفترية
      // القيمة الدفترية = 5000 - 1250 = 3750
      // الربح = 4000 - 3750 = 250
      expect(disposalResult['gainOrLoss'], closeTo(250, 1));

      // التحقق من تحديث حالة الأصل
      final disposedAsset = await db.select(db.fixedAssets)
          .where((t) => t.id.equals(assetId))
          .getSingle();
      
      expect(disposedAsset.status, equals('sold'));
    });
  });
}

Future<void> _setupInitialData() async {
  // إضافة حسابات محاسبية أساسية للاختبار
  await db.into(db.glAccounts).insertAll([
    GLAccountsCompanion.insert(
      accountCode: '1010',
      accountName: 'النقدية',
      accountType: 'asset',
    ),
    GLAccountsCompanion.insert(
      accountCode: '1510',
      accountName: 'الأصول الثابتة',
      accountType: 'asset',
    ),
    GLAccountsCompanion.insert(
      accountCode: '1610',
      accountName: 'مجمع إهلاك الأصول الثابتة',
      accountType: 'contra_asset',
    ),
    GLAccountsCompanion.insert(
      accountCode: '6010',
      accountName: 'مصروف الرواتب',
      accountType: 'expense',
    ),
    GLAccountsCompanion.insert(
      accountCode: '6020',
      accountName: 'مصروف الإهلاك',
      accountType: 'expense',
    ),
  ]);
}
