import 'package:drift/drift.dart';
import '../../datasources/local/app_database.dart';
import '../../datasources/local/daos/accounting_dao.dart';

/// خدمة إدارة الرواتب وحسابها
class PayrollService {
  final AppDatabase db;

  PayrollService(this.db);

  /// حساب رواتب شهر معين
  Future<Map<String, dynamic>> calculatePayroll(String period) async {
    final employees = await db.select(db.employees)
        .where((t) => t.status.equals('active'))
        .get();

    double totalSalaries = 0;
    double totalAllowances = 0;
    double totalDeductions = 0;
    double netPayable = 0;

    final payrollDetails = <PayrollDetailsCompanion>[];

    for (var emp in employees) {
      // حساب إجمالي البدلات
      final allowances = emp.housingAllowance + 
                        emp.transportAllowance + 
                        emp.otherAllowances;
      
      // حساب إجمالي الراتب قبل الخصومات
      final grossSalary = emp.basicSalary + allowances;
      
      // الحصول على الخصومات الإضافية لهذا الشهر
      final additionalDeductions = await _getAdditionalDeductionsForMonth(emp.id, period);
      
      // صافي الخصومات
      final totalEmpDeductions = emp.totalDeductions + additionalDeductions;
      
      // صافي الراتب
      final netSalary = grossSalary - totalEmpDeductions;

      payrollDetails.add(PayrollDetailsCompanion.insert(
        employeeId: emp.id,
        basicSalary: emp.basicSalary,
        housingAllowance: emp.housingAllowance,
        transportAllowance: emp.transportAllowance,
        otherAllowances: emp.otherAllowances,
        grossSalary: grossSalary,
        deductions: totalEmpDeductions,
        netSalary: netSalary,
      ));

      totalSalaries += emp.basicSalary;
      totalAllowances += allowances;
      totalDeductions += totalEmpDeductions;
      netPayable += netSalary;
    }

    // إنشاء سجل الرواتب الشهري
    final payrollRunId = await db.into(db.payrollRuns).insert(
      PayrollRunsCompanion.insert(
        period: period,
        totalSalaries: totalSalaries,
        totalAllowances: totalAllowances,
        totalDeductions: totalDeductions,
        netPayable: netPayable,
        status: 'draft',
      ),
    );

    // إضافة تفاصيل الرواتب
    for (var detail in payrollDetails) {
      await db.into(db.payrollDetails).insert(
        detail.copyWith(payrollRunId: Value(payrollRunId)),
      );
    }

    return {
      'payrollRunId': payrollRunId,
      'period': period,
      'totalSalaries': totalSalaries,
      'totalAllowances': totalAllowances,
      'totalDeductions': totalDeductions,
      'netPayable': netPayable,
      'employeeCount': employees.length,
    };
  }

  /// الحصول على الخصومات الإضافية لشهر معين
  Future<double> _getAdditionalDeductionsForMonth(int employeeId, String period) async {
    final year = int.parse(period.substring(0, 4));
    final month = int.parse(period.substring(5));
    
    final deductions = await db.select(db.additionalDeductions)
        .where((t) => t.employeeId.equals(employeeId))
        .get();

    double total = 0;
    for (var ded in deductions) {
      if (ded.deductionDate.year == year && ded.deductionDate.month == month) {
        total += ded.amount;
        
        // إذا كانت خصومة متكررة، إنقاص عدد الأقساط
        if (ded.isRecurring && ded.remainingInstallments > 0) {
          await db.update(db.additionalDeductions).replace(
            ded.copyWith(remainingInstallments: ded.remainingInstallments - 1),
          );
          
          // إذا انتهت الأقساط، حذف الخصم
          if (ded.remainingInstallments - 1 <= 0) {
            await db.delete(db.additionalDeductions)
                .where((t) => t.id.equals(ded.id))
                .go();
          }
        }
      }
    }

    return total;
  }

  /// ترحيل قيد الرواتب
  Future<int> postPayrollJournalEntry(int payrollRunId) async {
    final payrollRun = await db.select(db.payrollRuns)
        .where((t) => t.id.equals(payrollRunId))
        .getSingle();

    if (payrollRun.status != 'draft') {
      throw Exception('سجل الرواتب هذا قد تم ترحيله بالفعل');
    }

    // إنشاء القيد المحاسبي
    final entryId = await db.into(db.glEntries).insert(
      GLEntriesCompanion.insert(
        date: DateTime.now(),
        description: Value('قيد رواتب فترة ${payrollRun.period}'),
        reference: Value('PAY-${payrollRun.period}'),
        isPosted: Value(false),
      ),
    );

    final lines = <GLLinesCompanion>[];

    // قيد مصروف الرواتب (إجمالي الرواتب والبدلات)
    final salaryExpenseAccountId = await _getSalaryExpenseAccount();
    lines.add(GLLinesCompanion.insert(
      entryId: entryId,
      accountId: salaryExpenseAccountId,
      debit: payrollRun.totalSalaries + payrollRun.totalAllowances,
      credit: 0,
      description: Value('مصروف الرواتب والبدلات'),
    ));

    // قيد الخصومات المستحقة
    final deductionsLiabilityAccountId = await _getDeductionsLiabilityAccount();
    lines.add(GLLinesCompanion.insert(
      entryId: entryId,
      accountId: deductionsLiabilityAccountId,
      debit: 0,
      credit: payrollRun.totalDeductions,
      description: Value('الخصومات المستحقة'),
    ));

    // قيد صافي الرواتب المستحقة الدفع
    final salariesPayableAccountId = await _getSalariesPayableAccount();
    lines.add(GLLinesCompanion.insert(
      entryId: entryId,
      accountId: salariesPayableAccountId,
      debit: 0,
      credit: payrollRun.netPayable,
      description: Value('رواتب مستحقة الدفع'),
    ));

    await db.into(db.glLines).insertAll(lines);

    // ترحيل القيد
    await db.accountingDao.postJournalEntry(entryId);

    // تحديث حالة سجل الرواتب
    await db.update(db.payrollRuns).replace(
      payrollRun.copyWith(status: 'posted', journalEntryId: entryId),
    );

    return entryId;
  }

  /// سداد الرواتب
  Future<void> paySalaries(int payrollRunId) async {
    final payrollRun = await db.select(db.payrollRuns)
        .where((t) => t.id.equals(payrollRunId))
        .getSingle();

    if (payrollRun.status != 'posted') {
      throw Exception('يجب ترحيل قيد الرواتب أولاً');
    }

    // إنشاء قيد السداد
    final paymentEntryId = await db.into(db.glEntries).insert(
      GLEntriesCompanion.insert(
        date: DateTime.now(),
        description: Value('سداد رواتب فترة ${payrollRun.period}'),
        reference: Value('PAY-PMT-${payrollRun.period}'),
        isPosted: Value(false),
      ),
    );

    final salariesPayableAccountId = await _getSalariesPayableAccount();
    final bankAccountId = await _getBankAccount();

    await db.into(db.glLines).insertAll([
      GLLinesCompanion.insert(
        entryId: paymentEntryId,
        accountId: salariesPayableAccountId,
        debit: payrollRun.netPayable,
        credit: 0,
        description: Value('سداد الرواتب المستحقة'),
      ),
      GLLinesCompanion.insert(
        entryId: paymentEntryId,
        accountId: bankAccountId,
        debit: 0,
        credit: payrollRun.netPayable,
        description: Value('خروج من البنك'),
      ),
    ]);

    await db.accountingDao.postJournalEntry(paymentEntryId);

    // تحديث حالة سجل الرواتب
    await db.update(db.payrollRuns).replace(
      payrollRun.copyWith(status: 'paid'),
    );

    // تحديث حالة تفاصيل الرواتب
    final details = await db.select(db.payrollDetails)
        .where((t) => t.payrollRunId.equals(payrollRunId))
        .get();

    for (var detail in details) {
      await db.update(db.payrollDetails).replace(
        detail.copyWith(paymentStatus: 'paid'),
      );
    }
  }

  Future<int> _getSalaryExpenseAccount() async {
    final accounts = await db.select(db.glAccounts)
        .where((t) => t.accountCode.like('60%')) // مصروفات الرواتب
        .get();
    return accounts.isNotEmpty ? accounts.first.id : 1;
  }

  Future<int> _getDeductionsLiabilityAccount() async {
    final accounts = await db.select(db.glAccounts)
        .where((t) => t.accountCode.like('2%')) // خصوم
        .get();
    return accounts.isNotEmpty ? accounts.first.id : 1;
  }

  Future<int> _getSalariesPayableAccount() async {
    final accounts = await db.select(db.glAccounts)
        .where((t) => t.accountCode.like('21%')) // مستحقات
        .get();
    return accounts.isNotEmpty ? accounts.first.id : 1;
  }

  Future<int> _getBankAccount() async {
    final accounts = await db.select(db.glAccounts)
        .where((t) => t.accountCode.like('10%')) // بنوك
        .get();
    return accounts.isNotEmpty ? accounts.first.id : 1;
  }
}
