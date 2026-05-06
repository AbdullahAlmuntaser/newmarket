import 'package:drift/drift.dart';

// جدول الموظفين
class Employees extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 2, max: 150)();
  TextColumn get code => text().withLength(min: 2, max: 50)();
  TextColumn get position => text().nullable()();
  TextColumn get department => text().nullable()();
  DateTimeColumn get hireDate => dateTime()();
  RealColumn get basicSalary => real()();
  RealColumn get housingAllowance => real().withDefault(const Constant(0.0))();
  RealColumn get transportAllowance => real().withDefault(const Constant(0.0))();
  RealColumn get otherAllowances => real().withDefault(const Constant(0.0))();
  RealColumn get totalDeductions => real().withDefault(const Constant(0.0))(); // خصومات ثابتة
  TextColumn get bankAccountNumber => text().nullable()();
  TextColumn get bankName => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))(); // active, terminated
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// جدول الرواتب الشهرية
class PayrollRuns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get period => text()(); // مثال: "2024-01"
  DateTimeColumn runDate => dateTime().withDefault(currentDateAndTime)();
  RealColumn get totalSalaries => real().withDefault(const Constant(0.0))();
  RealColumn get totalAllowances => real().withDefault(const Constant(0.0))();
  RealColumn get totalDeductions => real().withDefault(const Constant(0.0))();
  RealColumn get netPayable => real().withDefault(const Constant(0.0))();
  IntColumn get journalEntryId => integer().nullable(); // ربط بالقيد المحاسبي
  TextColumn get status => text().withDefault(const Constant('draft'))(); // draft, posted, paid
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// جدول تفاصيل الرواتب لكل موظف
class PayrollDetails extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get payrollRunId => integer().references(PayrollRuns, #id)();
  IntColumn get employeeId => integer().references(Employees, #id)();
  RealColumn get basicSalary => real()();
  RealColumn get housingAllowance => real().withDefault(const Constant(0.0))();
  RealColumn get transportAllowance => real().withDefault(const Constant(0.0))();
  RealColumn get otherAllowances => real().withDefault(const Constant(0.0))();
  RealColumn get grossSalary => real()(); // إجمالي الراتب قبل الخصومات
  RealColumn get deductions => real().withDefault(const Constant(0.0))(); // صافي الخصومات لهذا الشهر
  RealColumn get netSalary => real()(); // صافي الراتب
  IntColumn? get paymentJournalEntryId => integer().nullable(); // قيد السداد الفردي (اختياري)
  TextColumn get paymentStatus => text().withDefault(const Constant('pending'))(); // pending, paid
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// جدول أنواع الخصومات الإضافية (سلف، غياب، إلخ)
class AdditionalDeductions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id)();
  TextColumn get type => text()(); // loan, absence, advance
  RealColumn get amount => real()();
  DateTimeColumn get deductionDate => dateTime()();
  TextColumn get description => text().nullable()();
  BoolColumn get isRecurring => boolean().withDefault(const Constant(false))();
  IntColumn get remainingInstallments => integer().withDefault(const Constant(0))(); // للأقساط
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
