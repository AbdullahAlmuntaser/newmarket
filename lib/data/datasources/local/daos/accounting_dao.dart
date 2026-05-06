import 'package:drift/drift.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:supermarket/data/datasources/local/app_database.dart';

part 'accounting_dao.g.dart';

class GLAccountConverter
    implements JsonConverter<GLAccount, Map<String, dynamic>> {
  const GLAccountConverter();

  @override
  GLAccount fromJson(Map<String, dynamic> json) => GLAccount.fromJson(json);

  @override
  Map<String, dynamic> toJson(GLAccount object) => object.toJson();
}

class AccountType {
  static const String asset = 'ASSET';
  static const String liability = 'LIABILITY';
  static const String equity = 'EQUITY';
  static const String revenue = 'REVENUE';
  static const String expense = 'EXPENSE';
}

@JsonSerializable(explicitToJson: true)
class TrialBalanceItem {
  @GLAccountConverter()
  final GLAccount account;
  final double totalDebit;
  final double totalCredit;

  double get netBalance {
    if (account.type == AccountType.asset ||
        account.type == AccountType.expense) {
      return totalDebit - totalCredit;
    } else {
      return totalCredit - totalDebit;
    }
  }

  TrialBalanceItem(this.account, this.totalDebit, this.totalCredit);

  factory TrialBalanceItem.fromJson(Map<String, dynamic> json) =>
      _$TrialBalanceItemFromJson(json);
  Map<String, dynamic> toJson() => _$TrialBalanceItemToJson(this);
}

class GLLineWithAccount {
  final GLLine line;
  final GLAccount account;
  GLLineWithAccount(this.line, this.account);
}

class IncomeStatement {
  final double totalRevenue;
  final double costOfGoodsSold;
  final double grossProfit;
  final double totalExpenses;
  final double netIncome;

  IncomeStatement({
    required this.totalRevenue,
    required this.costOfGoodsSold,
    required this.grossProfit,
    required this.totalExpenses,
    required this.netIncome,
  });
}

class BalanceSheet {
  final List<TrialBalanceItem> assets;
  final List<TrialBalanceItem> liabilities;
  final List<TrialBalanceItem> equity;
  final double totalAssets;
  final double totalLiabilities;
  final double totalEquity;

  BalanceSheet({
    required this.assets,
    required this.liabilities,
    required this.equity,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.totalEquity,
  });
}

@DriftAccessor(
  tables: [GLAccounts, CostCenters, GLEntries, GLLines, Reconciliations, AccountingPeriods],
)
class AccountingDao extends DatabaseAccessor<AppDatabase>
    with _$AccountingDaoMixin {
  AccountingDao(super.db);

  // New: Check if a date is within a closed accounting period
  Future<bool> isDateInClosedPeriod(DateTime date) async {
    final query = select(db.accountingPeriods)
      ..where((p) =>
          p.isClosed.equals(true) &
          p.startDate.isSmallerOrEqual(Variable(date)) &
          p.endDate.isBiggerOrEqual(Variable(date)));
    final closedPeriod = await query.getSingleOrNull();
    return closedPeriod != null;
  }

  Future<void> closeAccountingPeriod(String periodId, {String? userId}) async {
    await (update(db.accountingPeriods)..where((t) => t.id.equals(periodId))).write(
      AccountingPeriodsCompanion(
        isClosed: const Value(true),
        closedAt: Value(DateTime.now()),
        closedBy: Value(userId),
        status: const Value('CLOSED'),
      ),
    );
  }

  // --- GL Accounts ---
  Future<List<GLAccount>> getAllAccounts() => (select(
    gLAccounts,
  )..orderBy([(t) => OrderingTerm(expression: t.code)])).get();

  Stream<List<GLAccount>> watchAccounts() => (select(
    gLAccounts,
  )..orderBy([(t) => OrderingTerm(expression: t.code)])).watch();

  Future<GLAccount?> getAccountByCode(String code) =>
      (select(gLAccounts)..where((t) => t.code.equals(code))).getSingleOrNull();

  Future<GLAccount?> getAccountById(String id) =>
      (select(gLAccounts)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> createAccount(GLAccountsCompanion account) =>
      into(gLAccounts).insert(account);

  Future<bool> updateAccount(GLAccount account) =>
      update(gLAccounts).replace(account);

  // New: Get accounts by type
  Future<List<GLAccount>> getAccountsByType(String type) =>
      (select(gLAccounts)..where((tbl) => tbl.type.equals(type))).get();

  // --- Cost Centers ---
  Future<List<CostCenter>> getAllCostCenters() => (select(costCenters)).get();
  Stream<List<CostCenter>> watchCostCenters() => (select(costCenters)).watch();
  Future<int> createCostCenter(CostCentersCompanion cc) =>
      into(costCenters).insert(cc);
  Future<bool> updateCostCenter(CostCenter cc) =>
      update(costCenters).replace(cc);

  // --- GL Entries ---
  Future<void> createEntry(
    GLEntriesCompanion entry,
    List<GLLinesCompanion> lines,
  ) {
    return transaction(() async {
      // Validate accounting balance: Sum of Debits == Sum of Credits
      double totalDebit = 0.0;
      double totalCredit = 0.0;
      for (var line in lines) {
        totalDebit += line.debit.value;
        totalCredit += line.credit.value;
      }
      if ((totalDebit - totalCredit).abs() > 0.001) {
        throw Exception(
          'القيد المحاسبي غير متوازن! (المدين: $totalDebit، الدائن: $totalCredit)',
        );
      }

      final entryRow = await into(gLEntries).insertReturning(entry);
      for (var line in lines) {
        // Propagate branchId from entry if not present in line
        final lineToInsert = line.copyWith(
          entryId: Value(entryRow.id),
          branchId: line.branchId.present ? line.branchId : Value(entryRow.branchId),
        );
        
        final lineRow = await into(gLLines).insertReturning(lineToInsert);

        // Update AccountTransactions for running balance
        await _updateAccountRunningBalance(lineRow, entryRow);
      }
    });
  }

  Future<void> _updateAccountRunningBalance(GLLine line, GLEntry entry) async {
    // Get last running balance for this account
    final lastTrans =
        await (select(db.accountTransactions)
              ..where((t) => t.accountId.equals(line.accountId))
              ..orderBy([
                (t) =>
                    OrderingTerm(expression: t.date, mode: OrderingMode.desc),
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();

    double lastBalance = lastTrans?.runningBalance ?? 0;

    final account = await (select(
      gLAccounts,
    )..where((a) => a.id.equals(line.accountId))).getSingle();

    double newBalance;
    // ASSET and EXPENSE accounts increase with Debit, decrease with Credit.
    // LIABILITY, EQUITY, and REVENUE accounts increase with Credit, decrease with Debit.
    if ([AccountType.asset, AccountType.expense].contains(account.type)) {
      newBalance = lastBalance + line.debit - line.credit;
    } else {
      newBalance = lastBalance + line.credit - line.debit;
    }

    await into(db.accountTransactions).insert(
      AccountTransactionsCompanion.insert(
        accountId: line.accountId,
        type: entry.referenceType ?? 'MANUAL',
        referenceId: Value(entry.referenceId),
        debit: Value(line.debit),
        credit: Value(line.credit),
        runningBalance: Value(newBalance),
        date: Value(entry.date),
        branchId: Value(entry.branchId),
      ),
    );
  }

  Stream<List<GLEntry>> watchRecentEntries({int limit = 50}) {
    return (select(gLEntries)
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .watch();
  }

  Future<List<GLLineWithAccount>> getLinesForEntry(String entryId) async {
    final query = select(gLLines).join([
      innerJoin(gLAccounts, gLAccounts.id.equalsExp(gLLines.accountId)),
    ])..where(gLLines.entryId.equals(entryId));

    final rows = await query.get();
    return rows.map((row) {
      return GLLineWithAccount(
        row.readTable(gLLines),
        row.readTable(gLAccounts),
      );
    }).toList();
  }

  // New: Get GL entries within a date range
  Future<List<GLEntry>> getGLEntriesInDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    return (select(
      gLEntries,
    )..where((tbl) => tbl.date.isBetween(Variable(startDate), Variable(endDate)))).get();
  }

  // --- Reconciliations ---
  Future<int> createReconciliation(ReconciliationsCompanion rec) =>
      into(reconciliations).insert(rec);

  Stream<List<Reconciliation>> watchReconciliations() =>
      (select(reconciliations)..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ]))
          .watch();

  // --- Reports ---
  Future<List<TrialBalanceItem>> getTrialBalance({String? branchId}) async {
    final accounts = await getAllAccounts();
    final items = <TrialBalanceItem>[];
    for (final account in accounts) {
      if (account.isHeader) continue;

      final debitSum = gLLines.debit.sum();
      final creditSum = gLLines.credit.sum();
      
      final query = selectOnly(gLLines)
        ..addColumns([debitSum, creditSum]);
      
      if (branchId != null) {
        query.where(gLLines.accountId.equals(account.id) & gLLines.branchId.equals(branchId));
      } else {
        query.where(gLLines.accountId.equals(account.id));
      }

      final result = await query.getSingle();
      final debit = result.read(debitSum) ?? 0.0;
      final credit = result.read(creditSum) ?? 0.0;

      items.add(TrialBalanceItem(account, debit, credit));
    }
    return items;
  }

  Future<double> getAccountBalance(String accountId, {String? branchId}) async {
    final account = await getAccountById(accountId);
    if (account == null) return 0.0;

    final debitSum = gLLines.debit.sum();
    final creditSum = gLLines.credit.sum();

    final query = selectOnly(gLLines)
      ..addColumns([debitSum, creditSum]);
    
    if (branchId != null) {
      query.where(gLLines.accountId.equals(accountId) & gLLines.branchId.equals(branchId));
    } else {
      query.where(gLLines.accountId.equals(accountId));
    }

    final result = await query.getSingleOrNull();

    if (result == null) {
      return 0.0;
    }

    final debit = result.read(debitSum) ?? 0.0;
    final credit = result.read(creditSum) ?? 0.0;

    if (account.type == AccountType.asset ||
        account.type == AccountType.expense) {
      return debit - credit;
    } else {
      return credit - debit;
    }
  }

  // New: Get account balance up to a specific date
  Future<double> getAccountBalanceAsOfDate(
    String accountId,
    DateTime asOfDate, {
    String? branchId,
  }) async {
    final account = await getAccountById(accountId);
    if (account == null) return 0.0;

    final debitSum = gLLines.debit.sum();
    final creditSum = gLLines.credit.sum();

    final query =
        selectOnly(gLLines).join([
            innerJoin(gLEntries, gLEntries.id.equalsExp(db.gLLines.entryId)),
          ])
          ..addColumns([debitSum, creditSum]);
    
    var predicate = gLLines.accountId.equals(accountId) &
                gLEntries.date.isSmallerOrEqual(Variable(asOfDate));
    
    if (branchId != null) {
      predicate = predicate & gLLines.branchId.equals(branchId);
    }
    
    query.where(predicate);

    final result = await query.getSingleOrNull();

    if (result == null) {
      return 0.0;
    }

    final debit = result.read(debitSum) ?? 0.0;
    final credit = result.read(creditSum) ?? 0.0;

    if (account.type == AccountType.asset ||
        account.type == AccountType.expense) {
      return debit - credit;
    } else {
      return credit - debit;
    }
  }

  // New: Get account balance movement in a specific date range
  Future<double> getAccountBalanceInRange(
    String accountId,
    DateTime startDate,
    DateTime endDate, {
    String? branchId,
  }) async {
    final account = await getAccountById(accountId);
    if (account == null) return 0.0;

    final debitSum = gLLines.debit.sum();
    final creditSum = gLLines.credit.sum();

    final query =
        selectOnly(gLLines).join([
            innerJoin(gLEntries, gLEntries.id.equalsExp(db.gLLines.entryId)),
          ])
          ..addColumns([debitSum, creditSum]);
    
    var predicate = gLLines.accountId.equals(accountId) &
                gLEntries.date.isBetween(Variable(startDate), Variable(endDate));
    
    if (branchId != null) {
      predicate = predicate & gLLines.branchId.equals(branchId);
    }
    
    query.where(predicate);

    final result = await query.getSingleOrNull();

    if (result == null) {
      return 0.0;
    }

    final debit = result.read(debitSum) ?? 0.0;
    final credit = result.read(creditSum) ?? 0.0;

    if (account.type == AccountType.asset ||
        account.type == AccountType.expense) {
      return debit - credit;
    } else {
      return credit - debit;
    }
  }

  // New: Get all account balances as of a specific date efficiently
  Future<List<TrialBalanceItem>> getAllAccountBalancesAsOfDate(
    DateTime asOfDate, {
    String? branchId,
  }) async {
    final allAccounts = await getAllAccounts();
    final debitSum = gLLines.debit.sum();
    final creditSum = gLLines.credit.sum();

    final query = selectOnly(gLLines).join([
      innerJoin(gLEntries, gLEntries.id.equalsExp(db.gLLines.entryId)),
    ])
      ..addColumns([gLLines.accountId, debitSum, creditSum]);
    
    var predicate = gLEntries.date.isSmallerOrEqual(Variable(asOfDate));
    if (branchId != null) {
      predicate = predicate & gLLines.branchId.equals(branchId);
    }
    
    query.where(predicate);
    query.groupBy([gLLines.accountId]);

    final rows = await query.get();
    final Map<String, ({double debit, double credit})> balanceMap = {
      for (final row in rows)
        row.read(gLLines.accountId)!: (
          debit: row.read(debitSum) ?? 0.0,
          credit: row.read(creditSum) ?? 0.0,
        ),
    };

    return allAccounts.map((account) {
      final balance = balanceMap[account.id] ?? (debit: 0.0, credit: 0.0);
      return TrialBalanceItem(account, balance.debit, balance.credit);
    }).toList();
  }

  // New: Get all GL lines for a specific account within a date range
  Future<List<GLLine>> getGLLinesForAccountInDateRange(
    String accountId,
    DateTime startDate,
    DateTime endDate, {
    String? branchId,
  }) {
    var predicate = gLLines.accountId.equals(accountId) &
              gLEntries.date.isBetween(Variable(startDate), Variable(endDate));
    
    if (branchId != null) {
      predicate = predicate & gLLines.branchId.equals(branchId);
    }

    return (select(gLLines).join([
          innerJoin(gLEntries, gLEntries.id.equalsExp(db.gLLines.entryId)),
        ])..where(predicate))
        .map((row) => row.readTable(gLLines))
        .get();
  }

  // New: Get all GLLines with their associated GLEntries within a date range
  Future<List<GLLineWithAccount>> getGLLinesWithEntriesInDateRange(
    DateTime startDate,
    DateTime endDate, {
    String? branchId,
  }) async {
    var predicate = gLEntries.date.isBetween(Variable(startDate), Variable(endDate));
    
    if (branchId != null) {
      predicate = predicate & gLLines.branchId.equals(branchId);
    }

    final query = select(gLLines).join([
      innerJoin(gLEntries, gLEntries.id.equalsExp(db.gLLines.entryId)),
      innerJoin(gLAccounts, gLAccounts.id.equalsExp(db.gLLines.accountId)),
    ])..where(predicate);

    final rows = await query.get();
    return rows.map((row) {
      return GLLineWithAccount(
        row.readTable(gLLines),
        row.readTable(gLAccounts),
      );
    }).toList();
  }

  Future<IncomeStatement> getIncomeStatement({
    required DateTime startDate,
    required DateTime endDate,
    String? branchId,
  }) async {
    final revenueAccounts = await getAccountsByType(AccountType.revenue);
    final expenseAccounts = await getAccountsByType(AccountType.expense);

    double totalRevenue = 0;
    for (final account in revenueAccounts) {
      totalRevenue +=
          await getAccountBalanceInRange(account.id, startDate, endDate, branchId: branchId);
    }

    double totalExpenses = 0;
    for (final account in expenseAccounts) {
      totalExpenses +=
          await getAccountBalanceInRange(account.id, startDate, endDate, branchId: branchId);
    }

    // In this model, COGS is typically part of expenses
    return IncomeStatement(
      totalRevenue: totalRevenue,
      costOfGoodsSold: 0, // Simplified
      grossProfit: totalRevenue,
      totalExpenses: totalExpenses,
      netIncome: totalRevenue - totalExpenses,
    );
  }

  Future<BalanceSheet> getBalanceSheet({DateTime? asOfDate, String? branchId}) async {
    final date = asOfDate ?? DateTime.now();
    final trialBalance = await getAllAccountBalancesAsOfDate(date, branchId: branchId);

    final assets = trialBalance.where((item) => item.account.type == AccountType.asset).toList();
    final liabilities = trialBalance.where((item) => item.account.type == AccountType.liability).toList();
    final equity = trialBalance.where((item) => item.account.type == AccountType.equity).toList();

    double totalAssets = assets.fold(0.0, (sum, item) => sum + item.netBalance);
    double totalLiabilities = liabilities.fold(0.0, (sum, item) => sum + item.netBalance);
    double totalEquity = equity.fold(0.0, (sum, item) => sum + item.netBalance);

    // Note: In a real system, Current Period Net Income should be added to Equity
    return BalanceSheet(
      assets: assets,
      liabilities: liabilities,
      equity: equity,
      totalAssets: totalAssets,
      totalLiabilities: totalLiabilities,
      totalEquity: totalEquity,
    );
  }

  // Budget Management Methods
  Future<List<Budget>> getAllBudgets() async {
    return (select(budgets)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<Budget?> getBudgetById(int id) async {
    return (select(budgets)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<List<Budget>> getBudgetsByPeriod(String period) async {
    return (select(budgets)..where((t) => t.period.equals(period)))
        .get();
  }

  Future<int> createBudget(BudgetsCompanion companion) async {
    return into(budgets).insert(companion);
  }

  Future<bool> updateBudget(int id, BudgetsCompanion companion) async {
    return (update(budgets)..where((t) => t.id.equals(id))).write(companion);
  }

  Future<bool> deleteBudget(int id) async {
    return (delete(budgets)..where((t) => t.id.equals(id))).go() > 0;
  }

  Future<void> updateActualAmount(int budgetId, double actualAmount) async {
    await (update(budgets)..where((t) => t.id.equals(budgetId)))
        .write(BudgetsCompanion(actualAmount: Value(actualAmount)));
  }

  // Cost Center Methods
  Future<List<CostCenter>> getAllCostCenters() async {
    return (select(costCenters)..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<int> createCostCenter(CostCentersCompanion companion) async {
    return into(costCenters).insert(companion);
  }

  // Currency Methods
  Future<List<Currency>> getAllCurrencies() async {
    return (select(currencies)..orderBy([(t) => OrderingTerm.asc(t.code)])).get();
  }

  Future<Currency?> getBaseCurrency() async {
    return (select(currencies)..where((t) => t.isBase.equals(true))).getSingleOrNull();
  }

  Future<int> createCurrency(CurrenciesCompanion companion) async {
    return into(currencies).insert(companion);
  }

  // Exchange Rate Methods
  Future<double?> getExchangeRate({
    required int fromCurrencyId,
    required int toCurrencyId,
    DateTime? date,
  }) async {
    final queryDate = date ?? DateTime.now();
    final result = await (select(exchangeRates)
          ..where((t) =>
              t.fromCurrencyId.equals(fromCurrencyId) &
              t.toCurrencyId.equals(toCurrencyId) &
              t.effectiveDate.isSmallerOrEqualValue(queryDate))
          ..orderBy([(t) => OrderingTerm.desc(t.effectiveDate)])
          ..limit(1))
        .getSingleOrNull();
    return result?.rate;
  }

  // Bank Statement Methods
  Future<List<BankStatement>> getAllBankStatements() async {
    return (select(bankStatements)..orderBy([(t) => OrderingTerm.desc(t.statementDate)]))
        .get();
  }

  Future<int> createBankStatement(BankStatementsCompanion companion) async {
    return into(bankStatements).insert(companion);
  }

  Future<List<BankStatementLine>> getBankStatementLines(int statementId) async {
    return (select(bankStatementLines)
          ..where((t) => t.statementId.equals(statementId))
          ..orderBy([(t) => OrderingTerm.asc(t.transactionDate)]))
        .get();
  }

  Future<int> createBankStatementLine(BankStatementLinesCompanion companion) async {
    return into(bankStatementLines).insert(companion);
  }

  Future<bool> matchBankLineWithJournal({
    required int lineId,
    required int journalEntryId,
  }) async {
    return (update(bankStatementLines)..where((t) => t.id.equals(lineId)))
        .write(BankStatementLinesCompanion(
          matchedJournalEntryId: Value(journalEntryId),
          reconciliationStatus: Value('matched'),
        ));
  }

  // Audit Log Methods
  Future<List<AuditLog>> getAuditLogs({
    String? tableName,
    int? recordId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var query = select(auditLogs);
    
    if (tableName != null) {
      query = query..where((t) => t.tableName.equals(tableName));
    }
    if (recordId != null) {
      query = query..where((t) => t.recordId.equals(recordId));
    }
    if (startDate != null && endDate != null) {
      query = query..where((t) => t.timestamp.isBetween(Variable(startDate), Variable(endDate)));
    }
    
    return (query..orderBy([(t) => OrderingTerm.desc(t.timestamp)])).get();
  }

  Future<int> createAuditLog(AuditLogsCompanion companion) async {
    return into(auditLogs).insert(companion);
  }
}
