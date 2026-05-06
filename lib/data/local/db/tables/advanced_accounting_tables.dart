import 'package:drift/drift.dart';

// جدول العملات
class Currencies extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(min: 3, max: 3)(); // USD, SAR, EUR
  TextColumn get name => text().withLength(min: 2, max: 50)();
  TextColumn get symbol => text().nullable()();
  BoolColumn get isBase => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// جدول أسعار الصرف
class ExchangeRates extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get fromCurrencyId => integer().references(Currencies, #id)();
  IntColumn get toCurrencyId => integer().references(Currencies, #id)();
  RealColumn get rate => real()();
  DateTimeColumn get effectiveDate => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// جدول مراكز التكلفة
class CostCenters extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 2, max: 100)();
  TextColumn get code => text().withLength(min: 2, max: 50)();
  IntColumn? get parentId => integer().nullable().references(CostCenters, #id)(); // هيكل شجري
  TextColumn get type => text().withDefault(const Constant('department'))(); // department, project, branch
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// جدول الميزانيات التقديرية
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 2, max: 100)();
  TextColumn get period => text()(); // "2024", "2024-Q1"
  IntColumn? get costCenterId => integer().nullable().references(CostCenters, #id)();
  IntColumn? get accountId => integer().nullable(); // ربط بحساب محدد من شجرة الحسابات
  RealColumn get budgetedAmount => real()();
  RealColumn get actualAmount => real().withDefault(const Constant(0.0))(); // يُحدث تلقائياً من القيود
  RealColumn get variance => real().asComputed(() => budgetedAmount - actualAmount)();
  TextColumn get status => text().withDefault(const Constant('active'))(); // active, closed
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// جدول كشف الحساب البنكي
class BankStatements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId => integer(); // ربط بحساب البنك في شجرة الحسابات
  TextColumn get statementReference => text().nullable()();
  DateTimeColumn get statementDate => dateTime()();
  RealColumn get openingBalance => real()();
  RealColumn get closingBalance => real()();
  TextColumn get currency => text().withDefault(const Constant('SAR'))();
  TextColumn get status => text().withDefault(const Constant('imported'))(); // imported, reconciled
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// جدول حركات كشف الحساب البنكي
class BankStatementLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get statementId => integer().references(BankStatements, #id)();
  DateTimeColumn get transactionDate => dateTime()();
  TextColumn get description => text()();
  RealColumn get debit => real().withDefault(const Constant(0.0))();
  RealColumn get credit => real().withDefault(const Constant(0.0))();
  RealColumn get balance => real().nullable()();
  TextColumn get reference => text().nullable()();
  IntColumn? get matchedJournalEntryId => integer().nullable(); // ربط بالقيد المطابق
  TextColumn get reconciliationStatus => text().withDefault(const Constant('unreconciled'))(); // unreconciled, matched, cleared
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// جدول سجل التدقيقات (Audit Log)
class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tableName => text()();
  IntColumn get recordId => integer()();
  TextColumn get action => text()(); // INSERT, UPDATE, DELETE
  TextColumn get oldValues => text().nullable()(); // JSON
  TextColumn get newValues => text().nullable()(); // JSON
  IntColumn get userId => integer().nullable(); // من قام بالعملية
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
  TextColumn get ipAddress => text().nullable()();
}
