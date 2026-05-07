import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:supermarket/data/datasources/local/daos/accounting_dao.dart';
import 'package:drift/drift.dart' hide JsonKey;
import 'package:uuid/uuid.dart';
import 'audit_service.dart';
import 'package:supermarket/core/events/app_events.dart';
import 'event_bus_service.dart';
import 'package:json_annotation/json_annotation.dart';
import 'dart:developer' as developer;
import 'app_config_service.dart';

part 'accounting_service.g.dart';

@JsonSerializable(explicitToJson: true)
class AccountingDashboardData {
  final double totalRevenue;
  final double totalExpenses;
  final double netIncome;
  final double totalAssets;
  final double totalLiabilities;
  final List<TrialBalanceItem> topExpenses;
  @GLEntryConverter()
  final List<GLEntry> recentTransactions;
  final List<DailyValue> dailyRevenue;
  final List<DailyValue> dailyExpenses;
  final List<DashboardTopProduct> topSellingProducts;
  final int expiringBatchesCount;
  final FinancialRatiosData ratios;

  AccountingDashboardData({
    required this.totalRevenue,
    required this.totalExpenses,
    required this.netIncome,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.topExpenses,
    required this.recentTransactions,
    required this.dailyRevenue,
    required this.dailyExpenses,
    required this.topSellingProducts,
    this.expiringBatchesCount = 0,
    required this.ratios,
  });

  factory AccountingDashboardData.fromJson(Map<String, dynamic> json) =>
      _$AccountingDashboardDataFromJson(json);
  Map<String, dynamic> toJson() => _$AccountingDashboardDataToJson(this);
}

@JsonSerializable()
class DashboardTopProduct {
  final String productName;
  final double quantity;
  DashboardTopProduct(this.productName, this.quantity);

  factory DashboardTopProduct.fromJson(Map<String, dynamic> json) =>
      _$DashboardTopProductFromJson(json);
  Map<String, dynamic> toJson() => _$DashboardTopProductToJson(this);
}

@JsonSerializable()
class DailyValue {
  final DateTime date;
  final double value;
  DailyValue(this.date, this.value);

  factory DailyValue.fromJson(Map<String, dynamic> json) =>
      _$DailyValueFromJson(json);
  Map<String, dynamic> toJson() => _$DailyValueToJson(this);
}

@JsonSerializable()
class CashFlowData {
  final double operatingActivities;
  final double investingActivities;
  final double financingActivities;
  final double netCashFlow;
  final double beginningCashBalance;
  final double endingCashBalance;
  final DateTime? startDate;
  final DateTime endDate;

  CashFlowData({
    required this.operatingActivities,
    required this.investingActivities,
    required this.financingActivities,
    required this.netCashFlow,
    required this.beginningCashBalance,
    required this.endingCashBalance,
    this.startDate,
    required this.endDate,
  });

  factory CashFlowData.fromJson(Map<String, dynamic> json) =>
      _$CashFlowDataFromJson(json);
  Map<String, dynamic> toJson() => _$CashFlowDataToJson(this);
}

@JsonSerializable()
class FinancialRatiosData {
  final double grossProfitMargin;
  final double netProfitMargin;
  final double currentRatio;

  FinancialRatiosData({
    required this.grossProfitMargin,
    required this.netProfitMargin,
    required this.currentRatio,
  });

  factory FinancialRatiosData.fromJson(Map<String, dynamic> json) =>
      _$FinancialRatiosDataFromJson(json);
  Map<String, dynamic> toJson() => _$FinancialRatiosDataToJson(this);
}

@JsonSerializable()
class VatReportData {
  final double totalOutputVat;
  final double totalInputVat;
  final double netVatPayable;
  final DateTime startDate;
  final DateTime endDate;

  VatReportData({
    required this.totalOutputVat,
    required this.totalInputVat,
    required this.netVatPayable,
    required this.startDate,
    required this.endDate,
  });

  factory VatReportData.fromJson(Map<String, dynamic> json) =>
      _$VatReportDataFromJson(json);
  Map<String, dynamic> toJson() => _$VatReportDataToJson(this);
}

@JsonSerializable(explicitToJson: true)
class IncomeStatementData {
  final List<TrialBalanceItem> revenues;
  final List<TrialBalanceItem> expenses;
  final double totalRevenue;
  final double totalExpense;
  final double netIncome;
  final DateTime? startDate;
  final DateTime endDate;

  IncomeStatementData({
    required this.revenues,
    required this.expenses,
    required this.totalRevenue,
    required this.totalExpense,
    required this.netIncome,
    this.startDate,
    required this.endDate,
  });

  factory IncomeStatementData.fromJson(Map<String, dynamic> json) =>
      _$IncomeStatementDataFromJson(json);
  Map<String, dynamic> toJson() => _$IncomeStatementDataToJson(this);
}

@JsonSerializable(explicitToJson: true)
class BalanceSheetData {
  final List<BalanceSheetItem> assets;
  final List<BalanceSheetItem> liabilities;
  final List<BalanceSheetItem> equity;
  final double totalAssets;
  final double totalLiabilities;
  final double totalEquity;
  final double netIncome;
  final DateTime date;

  BalanceSheetData({
    required this.assets,
    required this.liabilities,
    required this.equity,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.totalEquity,
    required this.netIncome,
    required this.date,
  });

  factory BalanceSheetData.fromJson(Map<String, dynamic> json) =>
      _$BalanceSheetDataFromJson(json);
  Map<String, dynamic> toJson() => _$BalanceSheetDataToJson(this);
}

@JsonSerializable(explicitToJson: true)
class BalanceSheetItem {
  @GLAccountConverter()
  final GLAccount account;
  final double balance;

  BalanceSheetItem(this.account, this.balance);

  factory BalanceSheetItem.fromJson(Map<String, dynamic> json) =>
      _$BalanceSheetItemFromJson(json);
  Map<String, dynamic> toJson() => _$BalanceSheetItemToJson(this);
}

class GLAccountConverter
    implements JsonConverter<GLAccount, Map<String, dynamic>> {
  const GLAccountConverter();

  @override
  GLAccount fromJson(Map<String, dynamic> json) => GLAccount.fromJson(json);

  @override
  Map<String, dynamic> toJson(GLAccount object) => object.toJson();
}

class GLEntryConverter implements JsonConverter<GLEntry, Map<String, dynamic>> {
  const GLEntryConverter();

  @override
  GLEntry fromJson(Map<String, dynamic> json) => GLEntry.fromJson(json);

  @override
  Map<String, dynamic> toJson(GLEntry object) => object.toJson();
}

class AccountingService {
  final AppDatabase db;
  final EventBusService eventBus;
  late final AuditService _auditService;
  late final AppConfigService _configService;

  AccountingService(this.db, this.eventBus) {
    _auditService = AuditService(db);
    _configService = AppConfigService(db);
    _listenToEvents();
  }

  void _listenToEvents() {
    eventBus.stream.listen((event) {
      developer.log('AccountingService: Received event ${event.runtimeType}', name: 'accounting.service');
      if (event is SaleCreatedEvent) {
        postSale(event.sale, event.items, cogs: event.cogs);
      } else if (event is PurchasePostedEvent) {
        postPurchase(event.purchase, event.items);
      } else if (event is SaleReturnCreatedEvent) {
        postSaleReturn(event.saleReturn, event.items);
      } else if (event is PurchaseReturnCreatedEvent) {
        postPurchaseReturn(event.purchaseReturn, event.items);
      } else if (event is CustomerPaymentEvent) {
        _handleCustomerPayment(event);
      } else if (event is SupplierPaymentEvent) {
        _handleSupplierPayment(event);
      }
    });
  }

  /// New: Generic journal entry creation from events
  Future<void> createJournalEntry(AppEvent event) async {
    if (event is SaleCreatedEvent) {
      await postSale(event.sale, event.items, cogs: event.cogs);
    }
  }

  Future<void> _recordAccountTransaction({
    required String accountId,
    required String type,
    String? referenceId,
    double debit = 0,
    double credit = 0,
    DateTime? date,
    String? branchId,
  }) async {
    await db.transaction(() async {
      final lastTransaction =
          await (db.select(db.accountTransactions)
                ..where((t) => t.accountId.equals(accountId))
                ..orderBy([
                  (t) =>
                      OrderingTerm(expression: t.date, mode: OrderingMode.desc),
                ])
                ..limit(1))
              .getSingleOrNull();

      double currentBalance = lastTransaction?.runningBalance ?? 0.0;
      double newBalance = currentBalance + (debit - credit);

      // الحصول على معرف الفرع الافتراضي من الإعدادات
      final effectiveBranchId = branchId ?? await _configService.getDefaultBranchId();

      await db.into(db.accountTransactions).insert(
            AccountTransactionsCompanion.insert(
              accountId: accountId,
              date: Value(date ?? DateTime.now()),
              type: type,
              referenceId: Value(referenceId),
              debit: Value(debit),
              credit: Value(credit),
              runningBalance: Value(newBalance),
              branchId: Value(effectiveBranchId),
            ),
          );
    });
  }

  Future<void> _handleCustomerPayment(CustomerPaymentEvent event) async {
    final dao = db.accountingDao;
    final entryId = const Uuid().v4();

    // Accounts
    final arAccount = await dao.getAccountByCode(codeAccountsReceivable);
    final cashAccount = await dao.getAccountByCode(codeCash);

    if (arAccount == null || cashAccount == null) return;

    final customer = await db.customersDao.getCustomerById(event.customerId);
    final customerAccountId = customer?.accountId ?? arAccount.id;

    // الحصول على معرف الفرع الافتراضي من الإعدادات
    final defaultBranchId = await _configService.getDefaultBranchId();

    final entry = GLEntriesCompanion.insert(
      id: Value(entryId),
      description: 'سند قبض: ${customer?.name ?? "عميل"} - ${event.note ?? ""}',
      date: Value(DateTime.now()),
      referenceType: const Value('RECEIPT'),
      referenceId: Value(event.paymentId),
      status: const Value('POSTED'),
      postedAt: Value(DateTime.now()),
      branchId: Value(defaultBranchId),
    );

    final lines = [
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: cashAccount.id,
        debit: Value(event.amount),
        credit: const Value(0.0),
        branchId: Value(defaultBranchId),
      ),
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: customerAccountId,
        debit: const Value(0.0),
        credit: Value(event.amount),
        branchId: Value(defaultBranchId),
      ),
    ];

    await dao.createEntry(entry, lines);

    // Record in AccountTransactions for fast statements
    await _recordAccountTransaction(
      accountId: customerAccountId,
      type: 'PAYMENT',
      referenceId: event.paymentId,
      credit: event.amount,
      branchId: defaultBranchId,
    );
  }

  Future<void> _handleSupplierPayment(SupplierPaymentEvent event) async {
    final dao = db.accountingDao;
    final entryId = const Uuid().v4();

    // Accounts
    final apAccount = await dao.getAccountByCode(codeAccountsPayable);
    final cashAccount = await dao.getAccountByCode(codeCash);

    if (apAccount == null || cashAccount == null) return;

    final supplier = await db.suppliersDao.getSupplierById(event.supplierId);
    final supplierAccountId = supplier?.accountId ?? apAccount.id;

    // الحصول على معرف الفرع الافتراضي من الإعدادات
    final defaultBranchId = await _configService.getDefaultBranchId();

    final entry = GLEntriesCompanion.insert(
      id: Value(entryId),
      description: 'سند صرف: ${supplier?.name ?? "مورد"} - ${event.note ?? ""}',
      date: Value(DateTime.now()),
      referenceType: const Value('PAYMENT'),
      referenceId: Value(event.paymentId),
      status: const Value('POSTED'),
      postedAt: Value(DateTime.now()),
      branchId: Value(defaultBranchId),
    );

    final lines = [
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: supplierAccountId,
        debit: Value(event.amount),
        credit: const Value(0.0),
        branchId: Value(defaultBranchId),
      ),
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: cashAccount.id,
        debit: const Value(0.0),
        credit: Value(event.amount),
        branchId: Value(defaultBranchId),
      ),
    ];

    await dao.createEntry(entry, lines);

    // Record in AccountTransactions for fast statements
    await _recordAccountTransaction(
      accountId: supplierAccountId,
      type: 'PAYMENT',
      referenceId: event.paymentId,
      debit: event.amount,
      branchId: defaultBranchId,
    );
  }

  // Standard Account Codes
  static const String codeCash = '1010';
  static const String codeBank = '1020';
  static const String codeAccountsReceivable = '1030';
  static const String codeInventory = '1040';
  static const String codeInputVAT = '1050';
  static const String codeFixedAssets = '1200';
  static const String codeAccumulatedDepreciation = '1201';
  static const String codeAccountsPayable = '2010';
  static const String codeOutputVAT = '2020';
  static const String codeLoansPayable = '2500';
  static const String codeCapital = '3000';
  static const String codeRetainedEarnings = '3010';
  static const String codeSalesRevenue = '4010';
  static const String codeSalesReturns = '4020';
  static const String codeCOGS = '5010';
  static const String codePurchaseReturns = '5011';
  static const String codeCashOverShort = '5020';
  static const String codeOperatingExpenses = '6000';
  static const String codeDepreciationExpense = '6001';

  Future<void> seedDefaultAccounts({String? branchId}) async {
    final dao = db.accountingDao;
    // الحصول على معرف الفرع الافتراضي من الإعدادات إذا لم يتم تحديده
    final effectiveBranchId = branchId ?? await _configService.getDefaultBranchId();
    
    final accounts = {
      codeCash: GLAccountsCompanion.insert(
        code: codeCash,
        name: 'الصندوق',
        type: 'ASSET',
        branchId: Value(effectiveBranchId),
      ),
      codeBank: GLAccountsCompanion.insert(
        code: codeBank,
        name: 'البنك',
        type: 'ASSET',
        branchId: Value(effectiveBranchId),
      ),
      codeAccountsReceivable: GLAccountsCompanion.insert(
        code: codeAccountsReceivable,
        name: 'الذمم المدينة',
        type: 'ASSET',
        branchId: Value(effectiveBranchId),
      ),
      codeInventory: GLAccountsCompanion.insert(
        code: codeInventory,
        name: 'المخزون',
        type: 'ASSET',
        branchId: Value(effectiveBranchId),
      ),
      codeInputVAT: GLAccountsCompanion.insert(
        code: codeInputVAT,
        name: 'ضريبة المدخلات (المشتريات)',
        type: 'ASSET',
        branchId: Value(effectiveBranchId),
      ),
      codeFixedAssets: GLAccountsCompanion.insert(
        code: codeFixedAssets,
        name: 'الأصول الثابتة',
        type: 'ASSET',
        isHeader: const Value(true),
        branchId: Value(effectiveBranchId),
      ),
      codeAccumulatedDepreciation: GLAccountsCompanion.insert(
        code: codeAccumulatedDepreciation,
        name: 'مجمع الإهلاك',
        type: 'ASSET',
        branchId: Value(effectiveBranchId),
      ),
      codeAccountsPayable: GLAccountsCompanion.insert(
        code: codeAccountsPayable,
        name: 'الذمم الدائنة',
        type: 'LIABILITY',
        branchId: Value(effectiveBranchId),
      ),
      codeOutputVAT: GLAccountsCompanion.insert(
        code: codeOutputVAT,
        name: 'ضريبة المخرجات (المبيعات)',
        type: 'LIABILITY',
        branchId: Value(effectiveBranchId),
      ),
      codeLoansPayable: GLAccountsCompanion.insert(
        code: codeLoansPayable,
        name: 'القروض',
        type: 'LIABILITY',
        branchId: Value(effectiveBranchId),
      ),
      codeCapital: GLAccountsCompanion.insert(
        code: codeCapital,
        name: 'رأس المال',
        type: 'EQUITY',
        branchId: Value(effectiveBranchId),
      ),
      codeRetainedEarnings: GLAccountsCompanion.insert(
        code: codeRetainedEarnings,
        name: 'الأرباح المحتجزة',
        type: 'EQUITY',
        branchId: Value(effectiveBranchId),
      ),
      codeSalesRevenue: GLAccountsCompanion.insert(
        code: codeSalesRevenue,
        name: 'إيرادات المبيعات',
        type: 'REVENUE',
        branchId: Value(effectiveBranchId),
      ),
      codeSalesReturns: GLAccountsCompanion.insert(
        code: codeSalesReturns,
        name: 'مردودات المبيعات',
        type: 'REVENUE',
        branchId: Value(effectiveBranchId),
      ),
      codeCOGS: GLAccountsCompanion.insert(
        code: codeCOGS,
        name: 'تكلفة البضاعة المباعة',
        type: 'EXPENSE',
        branchId: Value(effectiveBranchId),
      ),
      codePurchaseReturns: GLAccountsCompanion.insert(
        code: codePurchaseReturns,
        name: 'مردودات المشتريات',
        type: 'EXPENSE',
        branchId: Value(effectiveBranchId),
      ),
      codeCashOverShort: GLAccountsCompanion.insert(
        code: codeCashOverShort,
        name: 'العجز والزيادة في الصندوق',
        type: 'EXPENSE',
        branchId: Value(effectiveBranchId),
      ),
      codeOperatingExpenses: GLAccountsCompanion.insert(
        code: codeOperatingExpenses,
        name: 'المصروفات التشغيلية',
        type: 'EXPENSE',
        isHeader: const Value(true),
        branchId: Value(effectiveBranchId),
      ),
      codeDepreciationExpense: GLAccountsCompanion.insert(
        code: codeDepreciationExpense,
        name: 'مصروف الإهلاك',
        type: 'EXPENSE',
        branchId: Value(effectiveBranchId),
      ),
    };

    for (var acc in accounts.values) {
      final existing = await dao.getAccountByCode(acc.code.value);
      if (existing == null) {
        await dao.createAccount(acc);
      } else if (existing.branchId == null && branchId != null) {
        await dao.updateAccount(existing.copyWith(branchId: Value(branchId)));
      }
    }
  }

  Future<FinancialRatiosData> getFinancialRatios() async {
    final incomeStatement = await getIncomeStatement();
    final dao = db.accountingDao;
    final asOfDate = DateTime.now();

    final cogsAccount = await dao.getAccountByCode(codeCOGS);
    final cogsBalance = cogsAccount != null
        ? await dao.getAccountBalanceAsOfDate(cogsAccount.id, asOfDate)
        : 0.0;
    final grossProfit = incomeStatement.totalRevenue - cogsBalance;
    final grossProfitMargin = incomeStatement.totalRevenue > 0
        ? (grossProfit / incomeStatement.totalRevenue)
        : 0.0;

    final netProfitMargin = incomeStatement.totalRevenue > 0
        ? (incomeStatement.netIncome / incomeStatement.totalRevenue)
        : 0.0;

    final currentAssetCodes = [
      codeCash,
      codeBank,
      codeAccountsReceivable,
      codeInventory,
    ];
    final currentLiabilityCodes = [codeAccountsPayable, codeOutputVAT];

    double totalCurrentAssets = 0.0;
    for (var code in currentAssetCodes) {
      final account = await dao.getAccountByCode(code);
      if (account != null) {
        totalCurrentAssets += await dao.getAccountBalanceAsOfDate(
          account.id,
          asOfDate,
        );
      }
    }

    double totalCurrentLiabilities = 0.0;
    for (var code in currentLiabilityCodes) {
      final account = await dao.getAccountByCode(code);
      if (account != null) {
        totalCurrentLiabilities += await dao.getAccountBalanceAsOfDate(
          account.id,
          asOfDate,
        );
      }
    }

    final currentRatio = totalCurrentLiabilities > 0
        ? (totalCurrentAssets / totalCurrentLiabilities)
        : 0.0;

    return FinancialRatiosData(
      grossProfitMargin: grossProfitMargin,
      netProfitMargin: netProfitMargin,
      currentRatio: currentRatio,
    );
  }

  Future<AccountingDashboardData> getDashboardData() async {
    final incomeStatement = await getIncomeStatement();
    final balanceSheet = await getBalanceSheet();
    final ratios = await getFinancialRatios();

    final topExpensesFull = List<TrialBalanceItem>.from(
      incomeStatement.expenses,
    );
    topExpensesFull.sort((a, b) => b.totalDebit.compareTo(a.totalDebit));
    final top5Expenses = topExpensesFull.take(5).toList();

    final recentEntries = await db.accountingDao
        .watchRecentEntries(limit: 5)
        .first;

    final now = DateTime.now();
    final last7Days = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));

    List<DailyValue> dailyRev = [];
    List<DailyValue> dailyExp = [];

    for (int i = 0; i < 7; i++) {
      final date = last7Days.add(Duration(days: i));
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
      final dayIncomeStatement = await getIncomeStatement(
        startDate: date,
        endDate: endOfDay,
      );
      dailyRev.add(DailyValue(date, dayIncomeStatement.totalRevenue));
      dailyExp.add(DailyValue(date, dayIncomeStatement.totalExpense));
    }

    final topProductsFromDao = await db.salesDao.getTopSellingProducts(
      limit: 5,
    );
    final topSellingProducts = topProductsFromDao
        .map((p) => DashboardTopProduct(p.product.name, p.totalQuantity))
        .toList();

    final expiringBatches = await db.productsDao.getExpiringBatches(
      daysThreshold: 30,
    );

    return AccountingDashboardData(
      totalRevenue: incomeStatement.totalRevenue,
      totalExpenses: incomeStatement.totalExpense,
      netIncome: incomeStatement.netIncome,
      totalAssets: balanceSheet.totalAssets,
      totalLiabilities: balanceSheet.totalLiabilities,
      topExpenses: top5Expenses,
      recentTransactions: recentEntries,
      dailyRevenue: dailyRev,
      dailyExpenses: dailyExp,
      topSellingProducts: topSellingProducts,
      expiringBatchesCount: expiringBatches.length,
      ratios: ratios,
    );
  }

  Future<String> createCustomerAccount(String customerName) async {
    final dao = db.accountingDao;
    final parent = await dao.getAccountByCode(codeAccountsReceivable);
    if (parent == null) {
      throw Exception('Accounts Receivable header account not found');
    }

    final existingSubAccounts = await (db.select(
      db.gLAccounts,
    )..where((a) => a.parentId.equals(parent.id))).get();
    final nextNumber = (existingSubAccounts.length + 1).toString().padLeft(
      4,
      '0',
    );
    final newCode = '${parent.code}.$nextNumber';

    final id = const Uuid().v4();
    final defaultBranchId = await _configService.getDefaultBranchId();
    await dao.createAccount(
      GLAccountsCompanion.insert(
        id: Value(id),
        code: newCode,
        name: 'حساب عميل: $customerName',
        type: 'ASSET',
        parentId: Value(parent.id),
        branchId: Value(defaultBranchId),
      ),
    );
    return id;
  }

  Future<String> createSupplierAccount(String supplierName) async {
    final dao = db.accountingDao;
    final parent = await dao.getAccountByCode(codeAccountsPayable);
    if (parent == null) {
      throw Exception('Accounts Payable header account not found');
    }

    final existingSubAccounts = await (db.select(
      db.gLAccounts,
    )..where((a) => a.parentId.equals(parent.id))).get();
    final nextNumber = (existingSubAccounts.length + 1).toString().padLeft(
      4,
      '0',
    );
    final newCode = '${parent.code}.$nextNumber';

    final id = const Uuid().v4();
    final defaultBranchId = await _configService.getDefaultBranchId();
    await dao.createAccount(
      GLAccountsCompanion.insert(
        id: Value(id),
        code: newCode,
        name: 'حساب مورد: $supplierName',
        type: 'LIABILITY',
        parentId: Value(parent.id),
        branchId: Value(defaultBranchId),
      ),
    );
    return id;
  }

  Future<void> postSale(Sale sale, List<SaleItem> items, {double? cogs}) async {
    if (await db.accountingDao.isDateInClosedPeriod(sale.createdAt)) {
      throw Exception('Cannot post sale in a closed accounting period.');
    }
    await db.transaction(() async {
      final dao = db.accountingDao;
      final entryId = const Uuid().v4();

      String debitAccountId;
      if (sale.isCredit) {
        if (sale.customerId == null) {
          throw Exception('Credit sale must have a customer.');
        }
        final customer = await db.customersDao.getCustomerById(sale.customerId!);
        if (customer?.accountId == null) {
          debitAccountId = (await dao.getAccountByCode(
            codeAccountsReceivable,
          ))!.id;
        } else {
          debitAccountId = customer!.accountId!;
        }
      } else {
        debitAccountId = (await dao.getAccountByCode(codeCash))!.id;
      }

      final revenueAccount = await dao.getAccountByCode(codeSalesRevenue);
      final taxAccount = await dao.getAccountByCode(codeOutputVAT);

      if (revenueAccount == null || taxAccount == null) {
        throw Exception('Missing one or more required GL accounts for sale.');
      }

      final entry = GLEntriesCompanion.insert(
        id: Value(entryId),
        description: 'Sale #${sale.id.substring(0, 8)}',
        date: Value(sale.createdAt),
        referenceType: const Value('SALE'),
        referenceId: Value(sale.id),
        status: const Value('POSTED'),
        postedAt: Value(DateTime.now()),
        currencyId: Value(sale.currencyId),
        exchangeRate: Value(sale.exchangeRate),
        branchId: Value(sale.branchId ?? await _configService.getDefaultBranchId()),
      );

      final lines = [
        GLLinesCompanion.insert(
          entryId: entryId,
          accountId: debitAccountId,
          debit: Value(sale.total),
          credit: const Value(0.0),
          currencyId: Value(sale.currencyId),
          exchangeRate: Value(sale.exchangeRate),
          branchId: Value(sale.branchId ?? await _configService.getDefaultBranchId()),
        ),
        GLLinesCompanion.insert(
          entryId: entryId,
          accountId: revenueAccount.id,
          debit: const Value(0.0),
          credit: Value(sale.total - sale.tax),
          currencyId: Value(sale.currencyId),
          exchangeRate: Value(sale.exchangeRate),
          branchId: Value(sale.branchId ?? await _configService.getDefaultBranchId()),
        ),
        if (sale.tax > 0)
          GLLinesCompanion.insert(
            entryId: entryId,
            accountId: taxAccount.id,
            debit: const Value(0.0),
            credit: Value(sale.tax),
            currencyId: Value(sale.currencyId),
            exchangeRate: Value(sale.exchangeRate),
            branchId: Value(sale.branchId ?? await _configService.getDefaultBranchId()),
          ),
      ];

      await dao.createEntry(entry, lines);

      // Record in AccountTransactions if credit
      if (sale.isCredit) {
        await _recordAccountTransaction(
          accountId: debitAccountId,
          type: 'INVOICE',
          referenceId: sale.id,
          debit: sale.total,
          date: sale.createdAt,
          branchId: sale.branchId ?? await _configService.getDefaultBranchId(),
        );
      }

      await _auditService.logCreate(
        'GLEntry',
        entryId,
        details: 'Revenue entry for Sale #${sale.id.substring(0, 8)}',
      );

      // Use actual COGS from event (calculated from batches) or calculate from batch costs
      final double totalCost = cogs ?? 0.0;
      double calculatedCost = 0.0;
      if (totalCost == 0.0) {
        for (var item in items) {
          final batches = await (db.select(db.productBatches)
                ..where((b) => b.productId.equals(item.productId))
                ..where((b) => b.quantity.isBiggerThan(const Variable(0)))
                ..orderBy([
                  (b) => OrderingTerm(
                    expression: b.expiryDate.isNull(),
                    mode: OrderingMode.asc,
                  ),
                  (b) => OrderingTerm(
                    expression: b.expiryDate,
                    mode: OrderingMode.asc,
                  ),
                  (b) => OrderingTerm(
                    expression: b.createdAt,
                    mode: OrderingMode.asc,
                  ),
                ]))
              .get();
          double remainingQty = item.quantity * item.unitFactor;
          for (var batch in batches) {
            if (remainingQty <= 0) break;
            double deductFromBatch = batch.quantity >= remainingQty
                ? remainingQty
                : batch.quantity;
            calculatedCost += deductFromBatch * batch.costPrice;
            remainingQty -= deductFromBatch;
          }
        }
      }

      final double finalCost = totalCost > 0 ? totalCost : calculatedCost;

      if (finalCost > 0) {
        final cogsEntryId = const Uuid().v4();
        final cogsAccount = await dao.getAccountByCode(codeCOGS);
        final inventoryAccount = await dao.getAccountByCode(codeInventory);

        if (cogsAccount != null && inventoryAccount != null) {
          final cogsEntry = GLEntriesCompanion.insert(
            id: Value(cogsEntryId),
            description: 'COGS for Sale #${sale.id.substring(0, 8)}',
            date: Value(sale.createdAt),
            referenceType: const Value('COGS'),
            referenceId: Value(sale.id),
            status: const Value('POSTED'),
            postedAt: Value(DateTime.now()),
            branchId: Value(sale.branchId ?? await _configService.getDefaultBranchId()),
          );

          final cogsLines = [
            GLLinesCompanion.insert(
              entryId: cogsEntryId,
              accountId: cogsAccount.id,
              debit: Value(finalCost),
              credit: const Value(0.0),
              branchId: Value(sale.branchId ?? await _configService.getDefaultBranchId()),
            ),
            GLLinesCompanion.insert(
              entryId: cogsEntryId,
              accountId: inventoryAccount.id,
              debit: const Value(0.0),
              credit: Value(finalCost),
              branchId: Value(sale.branchId ?? await _configService.getDefaultBranchId()),
            ),
          ];
          await dao.createEntry(cogsEntry, cogsLines);
        }
      }
    });
  }
  Future<void> postPurchase(Purchase purchase, List<PurchaseItem> items) async {
    if (await db.accountingDao.isDateInClosedPeriod(purchase.date)) {
      throw Exception('Cannot post purchase in a closed accounting period.');
    }
    await db.transaction(() async {
      final dao = db.accountingDao;
      final entryId = const Uuid().v4();

      final inventoryAccount = await dao.getAccountByCode(codeInventory);
      final taxAccount = await dao.getAccountByCode(codeInputVAT);

      String creditAccountId;
      if (purchase.isCredit) {
        if (purchase.supplierId == null) {
          throw Exception('Credit purchase must have a supplier.');
        }
        final supplier = await db.suppliersDao.getSupplierById(
          purchase.supplierId!,
        );
        creditAccountId =
            supplier?.accountId ??
            (await dao.getAccountByCode(codeAccountsPayable))!.id;
      } else {
        creditAccountId = (await dao.getAccountByCode(codeCash))!.id;
      }

      if (inventoryAccount == null || taxAccount == null) {
        throw Exception('Missing GL accounts for purchase.');
      }

      final inventoryValue = purchase.total - purchase.tax;

      final entry = GLEntriesCompanion.insert(
        id: Value(entryId),
        description: 'إثبات فاتورة مشتريات #${purchase.id.substring(0, 8)}',
        date: Value(purchase.date),
        referenceType: const Value('PURCHASE'),
        referenceId: Value(purchase.id),
        status: const Value('POSTED'),
        postedAt: Value(DateTime.now()),
        currencyId: Value(purchase.currencyId),
        exchangeRate: Value(purchase.exchangeRate),
        branchId: Value(purchase.branchId ?? await _configService.getDefaultBranchId()),
      );

      final lines = [
        GLLinesCompanion.insert(
          entryId: entryId,
          accountId: inventoryAccount.id,
          debit: Value(inventoryValue),
          credit: const Value(0.0),
          currencyId: Value(purchase.currencyId),
          exchangeRate: Value(purchase.exchangeRate),
          branchId: Value(purchase.branchId ?? await _configService.getDefaultBranchId()),
        ),
        if (purchase.tax > 0)
          GLLinesCompanion.insert(
            entryId: entryId,
            accountId: taxAccount.id,
            debit: Value(purchase.tax),
            credit: const Value(0.0),
            currencyId: Value(purchase.currencyId),
            exchangeRate: Value(purchase.exchangeRate),
            branchId: Value(purchase.branchId ?? await _configService.getDefaultBranchId()),
          ),
        GLLinesCompanion.insert(
          entryId: entryId,
          accountId: creditAccountId,
          debit: const Value(0.0),
          credit: Value(purchase.total),
          currencyId: Value(purchase.currencyId),
          exchangeRate: Value(purchase.exchangeRate),
          branchId: Value(purchase.branchId ?? await _configService.getDefaultBranchId()),
        ),
      ];

      await dao.createEntry(entry, lines);

      if (purchase.isCredit) {
        await _recordAccountTransaction(
          accountId: creditAccountId,
          type: 'INVOICE',
          referenceId: purchase.id,
          credit: purchase.total,
          date: purchase.date,
          branchId: purchase.branchId ?? await _configService.getDefaultBranchId(),
        );
      }

      await _auditService.logCreate(
        'GLEntry',
        entryId,
        details: 'Purchase entry for Purchase #${purchase.id.substring(0, 8)}',
      );
    });
  }
  Future<void> recordCustomerPayment({
    required String customerId,
    required double amount,
    required String paymentAccountCode,
    required String currencyId,
    required double exchangeRate,
  }) async {
    final dao = db.accountingDao;
    final entryId = const Uuid().v4();

    final arAccount = await dao.getAccountByCode(codeAccountsReceivable);
    final paymentAccount = await dao.getAccountByCode(paymentAccountCode);

    if (arAccount == null || paymentAccount == null) {
      throw Exception('AR or Payment account not found.');
    }

    final customer = await db.customersDao.getCustomerById(customerId);

    final defaultBranchId = await _configService.getDefaultBranchId();

    final entry = GLEntriesCompanion.insert(
      id: Value(entryId),
      description: 'Payment from ${customer?.name ?? "Customer"}',
      date: Value(DateTime.now()),
      referenceType: const Value('CUSTOMER_PAYMENT'),
      referenceId: Value(customerId),
      currencyId: Value(currencyId),
      exchangeRate: Value(exchangeRate),
      branchId: Value(defaultBranchId),
    );

    final lines = [
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: paymentAccount.id,
        debit: Value(amount),
        credit: const Value(0.0),
        currencyId: Value(currencyId),
        exchangeRate: Value(exchangeRate),
        branchId: Value(defaultBranchId),
      ),
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: arAccount.id,
        debit: const Value(0.0),
        credit: Value(amount),
        currencyId: Value(currencyId),
        exchangeRate: Value(exchangeRate),
        branchId: Value(defaultBranchId),
      ),
    ];

    await dao.createEntry(entry, lines);
  }

  Future<void> recordPaymentToSupplier({
    required String supplierId,
    required double amount,
    required String paymentAccountCode,
    required String currencyId,
    required double exchangeRate,
  }) async {
    final dao = db.accountingDao;
    final entryId = const Uuid().v4();

    final apAccount = await dao.getAccountByCode(codeAccountsPayable);
    final paymentAccount = await dao.getAccountByCode(paymentAccountCode);

    if (apAccount == null || paymentAccount == null) {
      throw Exception('AP or Payment account not found.');
    }

    final defaultBranchId = await _configService.getDefaultBranchId();

    final entry = GLEntriesCompanion.insert(
      id: Value(entryId),
      description: 'Payment to Supplier',
      date: Value(DateTime.now()),
      referenceType: const Value('SUPPLIER_PAYMENT'),
      referenceId: Value(supplierId),
      currencyId: Value(currencyId),
      exchangeRate: Value(exchangeRate),
      branchId: Value(defaultBranchId),
    );

    final lines = [
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: apAccount.id,
        debit: Value(amount),
        credit: const Value(0.0),
        currencyId: Value(currencyId),
        exchangeRate: Value(exchangeRate),
        branchId: Value(defaultBranchId),
      ),
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: paymentAccount.id,
        debit: const Value(0.0),
        credit: Value(amount),
        currencyId: Value(currencyId),
        exchangeRate: Value(exchangeRate),
        branchId: Value(defaultBranchId),
      ),
    ];

    await dao.createEntry(entry, lines);
  }

  Future<void> recordCheckCollected(Check check) async {
    final dao = db.accountingDao;
    final entryId = const Uuid().v4();

    GLAccount? primaryAccount;
    GLAccount? secondaryAccount;
    double amount = check.amount;
    String description;

    if (check.type == 'RECEIVED') {
      primaryAccount = await dao.getAccountByCode(codeAccountsReceivable);
      secondaryAccount = await dao.getAccountByCode(
        check.paymentAccountId ?? 'UNKNOWN',
      );
      description = 'Collection of Check #${check.checkNumber}';
    } else {
      primaryAccount = await dao.getAccountByCode(codeAccountsPayable);
      secondaryAccount = await dao.getAccountByCode(
        check.paymentAccountId ?? 'UNKNOWN',
      );
      description = 'Payment via Check #${check.checkNumber}';
    }

    if (primaryAccount == null || secondaryAccount == null) {
      throw Exception('Required GL accounts not found.');
    }

    final entry = GLEntriesCompanion.insert(
      id: Value(entryId),
      description: description,
      date: Value(DateTime.now()),
      referenceType: const Value('CHECK_COLLECTED'),
      referenceId: Value(check.id),
      currencyId: Value(check.currencyId),
      exchangeRate: Value(check.exchangeRate),
      branchId: Value(await _configService.getDefaultBranchId()),
    );

    final lines = [
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: primaryAccount.id,
        debit: Value(amount),
        credit: const Value(0.0),
        currencyId: Value(check.currencyId),
        exchangeRate: Value(check.exchangeRate),
        branchId: Value(await _configService.getDefaultBranchId()),
      ),
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: secondaryAccount.id,
        debit: const Value(0.0),
        credit: Value(amount),
        currencyId: Value(check.currencyId),
        exchangeRate: Value(check.exchangeRate),
        branchId: Value(await _configService.getDefaultBranchId()),
      ),
    ];
    await dao.createEntry(entry, lines);
  }

  Future<void> recordCheckBounced(Check check) async {
    final dao = db.accountingDao;
    final entryId = const Uuid().v4();

    GLAccount? primaryAccount;
    GLAccount? secondaryAccount;
    double amount = check.amount;
    String description;

    if (check.type == 'RECEIVED') {
      primaryAccount = await dao.getAccountByCode(codeAccountsReceivable);
      secondaryAccount = await dao.getAccountByCode(
        check.paymentAccountId ?? 'UNKNOWN',
      );
      description = 'Bounced Check #${check.checkNumber}';
    } else {
      primaryAccount = await dao.getAccountByCode(codeAccountsPayable);
      secondaryAccount = await dao.getAccountByCode(
        check.paymentAccountId ?? 'UNKNOWN',
      );
      description = 'Bounced Check #${check.checkNumber}';
    }

    if (primaryAccount == null || secondaryAccount == null) {
      throw Exception('Required GL accounts not found.');
    }

    final entry = GLEntriesCompanion.insert(
      id: Value(entryId),
      description: description,
      date: Value(DateTime.now()),
      referenceType: const Value('CHECK_BOUNCED'),
      referenceId: Value(check.id),
      currencyId: Value(check.currencyId),
      exchangeRate: Value(check.exchangeRate),
      branchId: Value(await _configService.getDefaultBranchId()),
    );

    final lines = [
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: primaryAccount.id,
        debit: Value(amount),
        credit: const Value(0.0),
        currencyId: Value(check.currencyId),
        exchangeRate: Value(check.exchangeRate),
        branchId: Value(await _configService.getDefaultBranchId()),
      ),
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: secondaryAccount.id,
        debit: const Value(0.0),
        credit: Value(amount),
        currencyId: Value(check.currencyId),
        exchangeRate: Value(check.exchangeRate),
        branchId: Value(await _configService.getDefaultBranchId()),
      ),
    ];
    await dao.createEntry(entry, lines);
  }

  Future<void> postSaleReturn(
    SalesReturn saleReturn,
    List<SalesReturnItem> items,
  ) async {
    final dao = db.accountingDao;
    final originalSale = await db.salesDao.getSaleById(saleReturn.saleId);
    if (originalSale == null) throw Exception('Original sale not found.');

    final entryId = const Uuid().v4();
    final salesReturnAccount = await dao.getAccountByCode(codeSalesReturns);
    final taxAccount = await dao.getAccountByCode(codeOutputVAT);
    final arAccount = await dao.getAccountByCode(codeAccountsReceivable);
    final cashAccount = await dao.getAccountByCode(codeCash);

    if (salesReturnAccount == null ||
        taxAccount == null ||
        arAccount == null ||
        cashAccount == null) {
      throw Exception('Missing accounts for sale return.');
    }

    final totalReturned = saleReturn.amountReturned;
    final taxPortion = originalSale.tax > 0
        ? (totalReturned / originalSale.total) * originalSale.tax
        : 0.0;
    final revenuePortion = totalReturned - taxPortion;
    final creditAccount = originalSale.isCredit ? arAccount : cashAccount;

    final entry = GLEntriesCompanion.insert(
      id: Value(entryId),
      description: 'Sale Return for Sale #${originalSale.id.substring(0, 8)}',
      date: Value(saleReturn.createdAt),
      referenceType: const Value('SALE_RETURN'),
      referenceId: Value(saleReturn.id),
      branchId: Value(originalSale.branchId ?? await _configService.getDefaultBranchId()),
    );

    final lines = [
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: salesReturnAccount.id,
        debit: Value(revenuePortion),
        credit: const Value(0.0),
        branchId: Value(originalSale.branchId ?? await _configService.getDefaultBranchId()),
      ),
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: taxAccount.id,
        debit: Value(taxPortion),
        credit: const Value(0.0),
        branchId: Value(originalSale.branchId ?? await _configService.getDefaultBranchId()),
      ),
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: creditAccount.id,
        debit: const Value(0.0),
        credit: Value(totalReturned),
        branchId: Value(originalSale.branchId ?? await _configService.getDefaultBranchId()),
      ),
    ];

    await dao.createEntry(entry, lines);

    // Record in AccountTransactions if credit
    if (originalSale.isCredit) {
      await _recordAccountTransaction(
        accountId: creditAccount.id,
        type: 'RETURN',
        referenceId: saleReturn.id,
        credit: totalReturned,
        date: saleReturn.createdAt,
        branchId: originalSale.branchId ?? await _configService.getDefaultBranchId(),
      );
    }

    double totalCostReversed = 0;
    for (var item in items) {
      final batches = await (db.select(db.productBatches)
            ..where((b) => b.productId.equals(item.productId))
            ..where((b) => b.quantity.isBiggerThan(const Variable(0)))
            ..orderBy([
              (b) => OrderingTerm(
                expression: b.expiryDate.isNull(),
                mode: OrderingMode.asc,
              ),
              (b) => OrderingTerm(
                expression: b.expiryDate,
                mode: OrderingMode.asc,
              ),
              (b) => OrderingTerm(
                expression: b.createdAt,
                mode: OrderingMode.asc,
              ),
            ]))
          .get();
      
      double remainingQty = item.quantity;
      for (var batch in batches) {
        if (remainingQty <= 0) break;
        double deductFromBatch = batch.quantity >= remainingQty
            ? remainingQty
            : batch.quantity;
        totalCostReversed += deductFromBatch * batch.costPrice;
        remainingQty -= deductFromBatch;
      }
    }

    if (totalCostReversed > 0) {
      final cogsEntryId = const Uuid().v4();
      final cogsAccount = await dao.getAccountByCode(codeCOGS);
      final inventoryAccount = await dao.getAccountByCode(codeInventory);
      if (cogsAccount != null && inventoryAccount != null) {
        final cogsEntry = GLEntriesCompanion.insert(
          id: Value(cogsEntryId),
          description:
              'COGS Reversal for Sale Return #${saleReturn.id.substring(0, 8)}',
          date: Value(saleReturn.createdAt),
          referenceType: const Value('COGS_REVERSAL'),
          referenceId: Value(saleReturn.id),
          branchId: Value(originalSale.branchId ?? await _configService.getDefaultBranchId()),
        );
        final cogsLines = [
          GLLinesCompanion.insert(
            entryId: cogsEntryId,
            accountId: inventoryAccount.id,
            debit: Value(totalCostReversed),
            credit: const Value(0.0),
            branchId: Value(originalSale.branchId ?? await _configService.getDefaultBranchId()),
          ),
          GLLinesCompanion.insert(
            entryId: cogsEntryId,
            accountId: cogsAccount.id,
            debit: const Value(0.0),
            credit: Value(totalCostReversed),
            branchId: Value(originalSale.branchId ?? await _configService.getDefaultBranchId()),
          ),
        ];
        await dao.createEntry(cogsEntry, cogsLines);
      }
    }
  }

  Future<void> postPurchaseReturn(
    PurchaseReturn purchaseReturn,
    List<PurchaseReturnItem> items,
  ) async {
    final dao = db.accountingDao;
    final originalPurchase = await db.purchasesDao.getPurchaseById(
      purchaseReturn.purchaseId,
    );
    if (originalPurchase == null) {
      throw Exception('Original purchase not found.');
    }

    final entryId = const Uuid().v4();
    final purchaseReturnAccount = await dao.getAccountByCode(
      codePurchaseReturns,
    );
    final taxAccount = await dao.getAccountByCode(codeInputVAT);
    final apAccount = await dao.getAccountByCode(codeAccountsPayable);
    final cashAccount = await dao.getAccountByCode(codeCash);

    if (purchaseReturnAccount == null ||
        taxAccount == null ||
        apAccount == null ||
        cashAccount == null) {
      throw Exception('Missing accounts for purchase return.');
    }

    final totalReturned = purchaseReturn.amountReturned;
    final taxPortion = originalPurchase.tax > 0
        ? (totalReturned / originalPurchase.total) * originalPurchase.tax
        : 0.0;
    final purchasePortion = totalReturned - taxPortion;
    final debitAccount = originalPurchase.isCredit ? apAccount : cashAccount;

    final entry = GLEntriesCompanion.insert(
      id: Value(entryId),
      description:
          'Purchase Return for Purchase #${originalPurchase.id.substring(0, 8)}',
      date: Value(purchaseReturn.createdAt),
      referenceType: const Value('PURCHASE_RETURN'),
      referenceId: Value(purchaseReturn.id),
      branchId: Value(originalPurchase.branchId ?? await _configService.getDefaultBranchId()),
    );

    final lines = [
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: debitAccount.id,
        debit: Value(totalReturned),
        credit: const Value(0.0),
        branchId: Value(originalPurchase.branchId ?? await _configService.getDefaultBranchId()),
      ),
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: purchaseReturnAccount.id,
        debit: const Value(0.0),
        credit: Value(purchasePortion),
        branchId: Value(originalPurchase.branchId ?? await _configService.getDefaultBranchId()),
      ),
      if (taxPortion > 0)
        GLLinesCompanion.insert(
          entryId: entryId,
          accountId: taxAccount.id,
          debit: const Value(0.0),
          credit: Value(taxPortion),
          branchId: Value(originalPurchase.branchId ?? await _configService.getDefaultBranchId()),
        ),
    ];

    await dao.createEntry(entry, lines);

    // Record in AccountTransactions if credit
    if (originalPurchase.isCredit) {
      final supplier = await db.suppliersDao.getSupplierById(
        originalPurchase.supplierId!,
      );
      final supplierAccountId = supplier?.accountId ?? apAccount.id;

      await _recordAccountTransaction(
        accountId: supplierAccountId,
        type: 'RETURN',
        referenceId: purchaseReturn.id,
        debit: totalReturned,
        date: purchaseReturn.createdAt,
        branchId: originalPurchase.branchId ?? await _configService.getDefaultBranchId(),
      );
    }
  }

  Future<void> runAutomaticDepreciation(DateTime asOfDate) async {
    final dao = db.accountingDao;
    final assets = await db.select(db.fixedAssets).get();
    final depreciationAccount = await dao.getAccountByCode(
      codeDepreciationExpense,
    );
    final accumulatedDepAccount = await dao.getAccountByCode(
      codeAccumulatedDepreciation,
    );

    if (depreciationAccount == null || accumulatedDepAccount == null) return;

    for (var asset in assets) {
      double monthlyDepreciation =
          (asset.cost - asset.salvageValue) / (asset.usefulLifeYears * 12);

      int totalMonths = asset.usefulLifeYears * 12;
      double alreadyDepreciatedMonths =
          asset.accumulatedDepreciation / monthlyDepreciation;

      final elapsedDuration = asOfDate.difference(asset.purchaseDate);
      int elapsedMonths = (elapsedDuration.inDays / 30).floor();

      int monthsToDepreciate = elapsedMonths - alreadyDepreciatedMonths.floor();
      if (monthsToDepreciate <= 0) continue;

      if (alreadyDepreciatedMonths + monthsToDepreciate > totalMonths) {
        monthsToDepreciate = (totalMonths - alreadyDepreciatedMonths).floor();
      }

      if (monthsToDepreciate <= 0) continue;

      double depreciationAmount = monthsToDepreciate * monthlyDepreciation;
      final entryId = const Uuid().v4();

      final entry = GLEntriesCompanion.insert(
        id: Value(entryId),
        description:
            'إهلاك تلقائي للأصل: ${asset.name} لمدة $monthsToDepreciate شهر',
        date: Value(asOfDate),
        referenceType: const Value('DEPRECIATION'),
        referenceId: Value(asset.id),
        status: const Value('POSTED'),
        postedAt: Value(DateTime.now()),
        branchId: Value(await _configService.getDefaultBranchId()),
      );

      final lines = [
        GLLinesCompanion.insert(
          entryId: entryId,
          accountId: depreciationAccount.id,
          debit: Value(depreciationAmount),
          branchId: Value(await _configService.getDefaultBranchId()),
        ),
        GLLinesCompanion.insert(
          entryId: entryId,
          accountId: accumulatedDepAccount.id,
          credit: Value(depreciationAmount),
          branchId: Value(await _configService.getDefaultBranchId()),
        ),
      ];

      await dao.createEntry(entry, lines);

      await (db.update(
        db.fixedAssets,
      )..where((a) => a.id.equals(asset.id))).write(
        FixedAssetsCompanion(
          accumulatedDepreciation: Value(
            asset.accumulatedDepreciation + depreciationAmount,
          ),
        ),
      );
    }
  }

  Future<VatReportData> getVatReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final dao = db.accountingDao;
    final reportStartDate = startDate ?? DateTime(2000);
    final reportEndDate = endDate ?? DateTime.now();
    final outputVatAccount = await dao.getAccountByCode(codeOutputVAT);
    final inputVatAccount = await dao.getAccountByCode(codeInputVAT);

    if (outputVatAccount == null || inputVatAccount == null) {
      throw Exception('Output VAT or Input VAT accounts not found.');
    }

    final outputVatLines =
        await (db.select(db.gLLines).join([
              innerJoin(
                db.gLEntries,
                db.gLEntries.id.equalsExp(db.gLLines.entryId),
              ),
            ])..where(
              db.gLLines.accountId.equals(outputVatAccount.id) &
                  db.gLEntries.date.isBetweenValues(
                    reportStartDate,
                    reportEndDate,
                  ),
            ))
            .get();

    double totalOutputVat = 0.0;
    for (final line in outputVatLines) {
      totalOutputVat +=
          (line.read(db.gLLines.credit) ?? 0) -
          (line.read(db.gLLines.debit) ?? 0);
    }

    final inputVatLines =
        await (db.select(db.gLLines).join([
              innerJoin(
                db.gLEntries,
                db.gLEntries.id.equalsExp(db.gLLines.entryId),
              ),
            ])..where(
              db.gLLines.accountId.equals(inputVatAccount.id) &
                  db.gLEntries.date.isBetweenValues(
                    reportStartDate,
                    reportEndDate,
                  ),
            ))
            .get();

    double totalInputVat = 0.0;
    for (final line in inputVatLines) {
      totalInputVat +=
          (line.read(db.gLLines.debit) ?? 0) -
          (line.read(db.gLLines.credit) ?? 0);
    }

    return VatReportData(
      totalOutputVat: totalOutputVat,
      totalInputVat: totalInputVat,
      netVatPayable: totalOutputVat - totalInputVat,
      startDate: reportStartDate,
      endDate: reportEndDate,
    );
  }

  Future<void> closeFinancialYear(DateTime endDate) async {
    final incomeStatement = await getIncomeStatement(endDate: endDate);
    final dao = db.accountingDao;
    final entryId = const Uuid().v4();
    final retainedEarningsAcc = await dao.getAccountByCode(
      codeRetainedEarnings,
    );
    if (retainedEarningsAcc == null) return;

    final entry = GLEntriesCompanion.insert(
      id: Value(entryId),
      description:
          'إغلاق السنة المالية حتى ${endDate.toIso8601String().split('T')[0]}',
      date: Value(endDate),
      referenceType: const Value('YEAR_END'),
      branchId: Value(await _configService.getDefaultBranchId()),
    );

    List<GLLinesCompanion> lines = [];
    for (var rev in incomeStatement.revenues) {
      double balance = rev.totalCredit - rev.totalDebit;
      if (balance != 0) {
        lines.add(
          GLLinesCompanion.insert(
            entryId: entryId,
            accountId: rev.account.id,
            debit: Value(balance),
            credit: const Value(0.0),
            memo: const Value('Year End Closing'),
            branchId: Value(await _configService.getDefaultBranchId()),
          ),
        );
      }
    }
    for (var exp in incomeStatement.expenses) {
      double balance = exp.totalDebit - exp.totalCredit;
      if (balance != 0) {
        lines.add(
          GLLinesCompanion.insert(
            entryId: entryId,
            accountId: exp.account.id,
            debit: const Value(0.0),
            credit: Value(balance),
            memo: const Value('Year End Closing'),
            branchId: Value(await _configService.getDefaultBranchId()),
          ),
        );
      }
    }
    if (incomeStatement.netIncome != 0) {
      lines.add(
        GLLinesCompanion.insert(
          entryId: entryId,
          accountId: retainedEarningsAcc.id,
          debit: Value(
            incomeStatement.netIncome < 0
                ? incomeStatement.netIncome.abs()
                : 0.0,
          ),
          credit: Value(
            incomeStatement.netIncome > 0 ? incomeStatement.netIncome : 0.0,
          ),
          memo: const Value('Net Income Transfer'),
          branchId: Value(await _configService.getDefaultBranchId()),
        ),
      );
    }

    if (lines.isNotEmpty) {
      await dao.createEntry(entry, lines);
    }
  }

  Future<IncomeStatementData> getIncomeStatement({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final dao = db.accountingDao;
    final allAccounts = await dao.getAllAccounts();
    final revenueAccounts = allAccounts.where((acc) => acc.type == 'REVENUE');
    final expenseAccounts = allAccounts.where((acc) => acc.type == 'EXPENSE');

    final List<TrialBalanceItem> revenues = [];
    for (var account in revenueAccounts) {
      final balance = await dao.getAccountBalanceAsOfDate(
        account.id,
        endDate ?? DateTime.now(),
      );
      revenues.add(TrialBalanceItem(account, 0.0, balance));
    }

    final List<TrialBalanceItem> expenses = [];
    for (var account in expenseAccounts) {
      final balance = await dao.getAccountBalanceAsOfDate(
        account.id,
        endDate ?? DateTime.now(),
      );
      expenses.add(TrialBalanceItem(account, balance, 0.0));
    }

    double totalRevenue = revenues.fold(
      0,
      (sum, item) => sum + item.totalCredit,
    );
    double totalExpense = expenses.fold(
      0,
      (sum, item) => sum + item.totalDebit,
    );

    return IncomeStatementData(
      revenues: revenues,
      expenses: expenses,
      totalRevenue: totalRevenue,
      totalExpense: totalExpense,
      netIncome: totalRevenue - totalExpense,
      startDate: startDate,
      endDate: endDate ?? DateTime.now(),
    );
  }

  Future<BalanceSheetData> getBalanceSheet({DateTime? date}) async {
    final dao = db.accountingDao;
    final asOfDate = date ?? DateTime.now();
    final allAccounts = await dao.getAllAccounts();

    final List<BalanceSheetItem> assets = [];
    for (var account in allAccounts.where((acc) => acc.type == 'ASSET')) {
      if (!account.isHeader) {
        final balance = await dao.getAccountBalanceAsOfDate(
          account.id,
          asOfDate,
        );
        assets.add(BalanceSheetItem(account, balance));
      }
    }

    final List<BalanceSheetItem> liabilities = [];
    for (var account in allAccounts.where((acc) => acc.type == 'LIABILITY')) {
      if (!account.isHeader) {
        final balance = await dao.getAccountBalanceAsOfDate(
          account.id,
          asOfDate,
        );
        liabilities.add(BalanceSheetItem(account, balance));
      }
    }

    final List<BalanceSheetItem> equity = [];
    for (var account in allAccounts.where((acc) => acc.type == 'EQUITY')) {
      if (!account.isHeader) {
        final balance = await dao.getAccountBalanceAsOfDate(
          account.id,
          asOfDate,
        );
        equity.add(BalanceSheetItem(account, balance));
      }
    }

    double totalAssets = assets.fold(0, (sum, item) => sum + item.balance);
    double totalLiabilities = liabilities.fold(
      0,
      (sum, item) => sum + item.balance,
    );
    double totalEquity = equity.fold(0, (sum, item) => sum + item.balance);

    final incomeStatement = await getIncomeStatement(endDate: asOfDate);
    totalEquity += incomeStatement.netIncome;

    return BalanceSheetData(
      assets: assets,
      liabilities: liabilities,
      equity: equity,
      totalAssets: totalAssets,
      totalLiabilities: totalLiabilities,
      totalEquity: totalEquity,
      netIncome: incomeStatement.netIncome,
      date: asOfDate,
    );
  }

  Future<void> createRevaluationEntry(dynamic invoice, String reason) async {
    // Implement revaluation logic based on the existing database structure
    // This is a placeholder for the actual revaluation implementation required by the business logic
    final entryId = const Uuid().v4();
    // Add logic here to create ledger lines based on invoice details and revaluation amount
    // await dao.createEntry(entry, lines);
    await _auditService.logCreate('GLEntry', entryId, details: reason);
  }

  Future<void> recordAssemblyEntry({
    required double producedQuantity,
    required double totalCost,
  }) async {
    final dao = db.accountingDao;
    final entryId = const Uuid().v4();

    final inventoryAccount = await dao.getAccountByCode(codeInventory);
    if (inventoryAccount == null) return;

    final entry = GLEntriesCompanion.insert(
      id: Value(entryId),
      description: 'قيد تجميع إنتاج تام: $producedQuantity وحدة',
      date: Value(DateTime.now()),
      referenceType: const Value('ASSEMBLY'),
      referenceId: Value(entryId),
      branchId: Value(await _configService.getDefaultBranchId()),
    );

    final lines = [
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: inventoryAccount.id,
        debit: Value(totalCost),
        branchId: Value(await _configService.getDefaultBranchId()),
      ),
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: inventoryAccount.id,
        credit: Value(totalCost),
        branchId: Value(await _configService.getDefaultBranchId()),
      ),
    ];

    await dao.createEntry(entry, lines);
  }

  Future<void> recordExpense({
    required String description,
    required double amount,
    required DateTime date,
    required String expenseAccountId,
    required String paymentAccountId,
  }) async {
    final dao = db.accountingDao;
    final entryId = const Uuid().v4();
    final entry = GLEntriesCompanion.insert(
      id: Value(entryId),
      description: description,
      date: Value(date),
      referenceType: const Value('EXPENSE'),
      branchId: Value(await _configService.getDefaultBranchId()),
    );
    final lines = [
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: expenseAccountId,
        debit: Value(amount),
        branchId: Value(await _configService.getDefaultBranchId()),
      ),
      GLLinesCompanion.insert(
        entryId: entryId,
        accountId: paymentAccountId,
        credit: Value(amount),
        branchId: Value(await _configService.getDefaultBranchId()),
      ),
    ];
    await dao.createEntry(entry, lines);
  }

  Future<CashFlowData> getCashFlowStatement({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final dao = db.accountingDao;
    final reportStartDate = startDate ?? DateTime(2000);
    final reportEndDate = endDate ?? DateTime.now();
    final glLinesWithAccounts = await dao.getGLLinesWithEntriesInDateRange(
      reportStartDate,
      reportEndDate,
    );

    double operatingActivities = 0.0;
    double investingActivities = 0.0;
    double financingActivities = 0.0;

    final cashAccounts = await dao.getAccountsByType('ASSET');
    final cashAccountIds = cashAccounts
        .where((acc) => acc.code == codeCash || acc.code == codeBank)
        .map((acc) => acc.id)
        .toSet();

    double beginningCashBalance = 0.0;
    if (reportStartDate != DateTime(2000)) {
      for (var cashAccountId in cashAccountIds) {
        beginningCashBalance += await dao.getAccountBalanceAsOfDate(
          cashAccountId,
          reportStartDate.subtract(const Duration(milliseconds: 1)),
        );
      }
    }

    final entriesMap = <String, List<GLLineWithAccount>>{};
    for (var lineWithAcc in glLinesWithAccounts) {
      entriesMap
          .putIfAbsent(lineWithAcc.line.entryId, () => [])
          .add(lineWithAcc);
    }

    for (var lines in entriesMap.values) {
      double cashMovement = 0.0;
      bool involvesCash = false;
      for (var line in lines) {
        if (cashAccountIds.contains(line.account.id)) {
          cashMovement += (line.line.debit - line.line.credit);
          involvesCash = true;
        }
      }
      if (!involvesCash || cashMovement == 0.0) continue;

      bool categorized = false;
      for (var line in lines) {
        if (!cashAccountIds.contains(line.account.id)) {
          if (line.account.type == 'REVENUE' ||
              line.account.type == 'EXPENSE' ||
              [
                codeAccountsReceivable,
                codeAccountsPayable,
                codeInputVAT,
                codeOutputVAT,
              ].contains(line.account.code)) {
            operatingActivities += cashMovement;
            categorized = true;
            break;
          } else if (line.account.code == codeFixedAssets) {
            investingActivities += cashMovement;
            categorized = true;
            break;
          } else if ([
            codeLoansPayable,
            codeCapital,
          ].contains(line.account.code)) {
            financingActivities += cashMovement;
            categorized = true;
            break;
          }
        }
      }
      if (!categorized) operatingActivities += cashMovement;
    }

    final netCashFlow =
        operatingActivities + investingActivities + financingActivities;
    return CashFlowData(
      operatingActivities: operatingActivities,
      investingActivities: investingActivities,
      financingActivities: financingActivities,
      netCashFlow: netCashFlow,
      beginningCashBalance: beginningCashBalance,
      endingCashBalance: beginningCashBalance + netCashFlow,
      startDate: reportStartDate,
      endDate: reportEndDate,
    );
  }
}
