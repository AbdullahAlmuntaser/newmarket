import 'package:drift/drift.dart';
import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:supermarket/data/datasources/local/daos/accounting_dao.dart';
import 'package:supermarket/core/utils/name_normalizer.dart';
import 'package:supermarket/core/services/cache_service.dart';
import 'package:uuid/uuid.dart';

part 'customers_dao.g.dart';

class CustomerSearchResult {
  final Customer customer;
  final double similarity; // 0.0 to 1.0
  final bool isExactMatch;

  CustomerSearchResult({
    required this.customer,
    required this.similarity,
    required this.isExactMatch,
  });
}

class CustomerTransaction {
  final DateTime date;
  final String description;
  final double debit; // عليه (مبيعات)
  final double credit; // له (مدفوعات/مرتجعات)
  final String referenceId;
  final String type; // SALE, PAYMENT, RETURN

  CustomerTransaction({
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    required this.referenceId,
    required this.type,
  });
}

@DriftAccessor(
  tables: [
    Customers,
    CustomerPayments,
    Sales,
    SalesReturns,
    GLAccounts,
    GLEntries,
    GLLines,
    ARInvoices,
  ],
)
class CustomersDao extends DatabaseAccessor<AppDatabase>
    with _$CustomersDaoMixin {
  CustomersDao(super.db);
  
  final _cache = CacheService();

  /// Get customer by ID with caching
  Future<Customer?> getCustomerById(String id) async {
    // Try cache first
    final cached = _cache.get<Customer>(CacheKeys.customer(id));
    if (cached != null) {
      return cached;
    }

    // Load from database
    final customer = await (select(customers)..where((c) => c.id.equals(id))).getSingleOrNull();
    
    if (customer != null) {
      _cache.set(CacheKeys.customer(id), customer, ttl: const Duration(minutes: 10));
    }
    
    return customer;
  }

  /// Get customer by phone with caching
  Future<Customer?> getCustomerByPhone(String phone) async {
    final cached = _cache.get<Customer>(CacheKeys.customerByPhone(phone));
    if (cached != null) {
      return cached;
    }

    final customer = await (select(customers)..where((c) => c.phone.equals(phone))).getSingleOrNull();
    
    if (customer != null) {
      _cache.set(CacheKeys.customerByPhone(phone), customer, ttl: const Duration(minutes: 10));
    }
    
    return customer;
  }

  /// Get all customers with optional filtering - optimized with indexes
  Future<List<Customer>> getCustomers({
    String? customerType,
    bool? isActive,
    bool lowBalanceOnly = false,
  }) async {
    var query = select(customers);

    if (customerType != null) {
      query = query..where((c) => c.customerType.equals(customerType));
    }
    
    if (isActive != null) {
      query = query..where((c) => c.isActive.equals(isActive));
    }
    
    if (lowBalanceOnly) {
      query = query..where((c) => c.balance.isBiggerThan(const Variable(0)));
    }

    return query.get();
  }

  /// Clear customer cache when data changes
  void clearCustomerCache([String? customerId]) {
    if (customerId != null) {
      _cache.remove(CacheKeys.customer(customerId));
    } else {
      _cache.clearByPattern('customer_*');
    }
  }

  Stream<List<Customer>> watchAllCustomers() {
    return (select(
      customers,
    )..where((tbl) => tbl.isActive.equals(true))).watch();
  }

  Stream<int> watchTotalCustomers() {
    return select(customers).watch().map((rows) => rows.length);
  }

  // AR Invoices
  Stream<List<ARInvoice>> watchARInvoices(String customerId) {
    return (select(aRInvoices)..where((t) => t.customerId.equals(customerId))).watch();
  }

  Stream<List<ARInvoice>> watchAllARInvoices() {
    return (select(aRInvoices)..orderBy([(t) => OrderingTerm(expression: t.invoiceDate, mode: OrderingMode.desc)])).watch();
  }

  Future<int> createARInvoice(ARInvoicesCompanion entry) {
    return into(aRInvoices).insert(entry);
  }

  Future<List<ARInvoice>> getUnpaidARInvoices(String customerId) {
    return (select(aRInvoices)
          ..where((t) =>
              t.customerId.equals(customerId) &
              t.status.isIn(['POSTED', 'PARTIAL'])))
        .get();
  }

  Future<List<ARInvoice>> getDueARInvoices(DateTime endDate) {
    return (select(aRInvoices)
          ..where((t) =>
              t.status.isIn(['POSTED', 'PARTIAL']) &
              t.dueDate.isSmallerOrEqual(Variable(endDate))))
        .get();
  }

  /// إدراج عميل مع إنشاء حساب محاسبي له تلقائياً
  Future<String> insertCustomerWithAccount(CustomersCompanion entry) async {
    return transaction(() async {
      // 1. البحث عن الحساب الرئيسي للعملاء (مثلاً '1201')
      // إذا لم يوجد، نستخدم حساب الأصول المتداولة الرئيسي
      final parentAccount = await (select(
        gLAccounts,
      )..where((t) => t.code.equals('1201'))).getSingleOrNull();

      final accountId = const Uuid().v4();
      final customerId = const Uuid().v4();

      // 2. إنشاء حساب في دفتر الأستاذ العام
      await into(gLAccounts).insert(
        GLAccountsCompanion.insert(
          id: Value(accountId),
          code: '1201-${customerId.substring(0, 5)}',
          name: 'عميل: ${entry.name.value}',
          type:
              AccountType.asset, // Corrected to use the static String constant
          parentId: parentAccount?.id != null
              ? Value(parentAccount!.id)
              : const Value.absent(),
          isHeader: const Value(false),
          balance: const Value(0.0),
        ),
      );

      // 3. إدراج العميل وربطه بالحساب
      final finalEntry = entry.copyWith(
        id: Value(customerId),
        accountId: Value(accountId),
      );
      await into(customers).insert(finalEntry);

      return customerId;
    });
  }

  Future<bool> updateCustomer(Customer entry) async {
    final result = await update(customers).replace(entry);
    // Clear cache for this specific customer
    clearCustomerCache(entry.id);
    return result;
  }

  Future<int> deleteCustomer(Customer entry) async {
    // نفضل التغيير إلى غير نشط بدلاً من الحذف الفعلي للحفاظ على السجلات المالية
    final result = await (update(customers)..where((t) => t.id.equals(entry.id))).write(
      const CustomersCompanion(isActive: Value(false)),
    );
    // Clear cache for deleted customer
    clearCustomerCache(entry.id);
    return result;
  }

  /// بحث متقدم عن العملاء
  Future<List<Customer>> searchCustomers(String query) {
    return (select(customers)
          ..where(
            (t) =>
                t.name.contains(query) |
                t.phone.contains(query) |
                t.taxNumber.contains(query),
          )
          ..where((t) => t.isActive.equals(true)))
        .get();
  }

  Future<List<CustomerPayment>> getPaymentsForCustomer(String customerId) {
    return (select(
      customerPayments,
    )..where((p) => p.customerId.equals(customerId))).get();
  }

  /// جلب كشف حساب تفصيلي للعميل مع الرصيد التراكمي
  Future<List<CustomerTransaction>> getCustomerStatement(
    String customerId,
  ) async {
    final List<CustomerTransaction> allTransactions = [];

    // 1. جلب المبيعات الآجلة
    final customerSales =
        await (select(db.sales)..where(
              (s) => s.customerId.equals(customerId) & s.isCredit.equals(true),
            ))
            .get();

    for (var sale in customerSales) {
      allTransactions.add(
        CustomerTransaction(
          date: sale.createdAt,
          description: 'فاتورة مبيعات آجل رقم ${sale.id.substring(0, 8)}',
          debit: sale.total,
          credit: 0,
          referenceId: sale.id,
          type: 'SALE',
        ),
      );
    }

    // 2. جلب فواتير الذمم المدينة (AR Invoices)
    final arInvoicesList = await (select(aRInvoices)..where((t) => t.customerId.equals(customerId))).get();
    for (var inv in arInvoicesList) {
      allTransactions.add(
        CustomerTransaction(
          date: inv.invoiceDate,
          description: 'فاتورة AR رقم ${inv.invoiceNumber}',
          debit: inv.totalAmount,
          credit: 0,
          referenceId: inv.id,
          type: 'AR_INVOICE',
        ),
      );
    }

    // 3. جلب المدفوعات
    final payments = await (select(
      db.customerPayments,
    )..where((p) => p.customerId.equals(customerId))).get();

    for (var payment in payments) {
      allTransactions.add(
        CustomerTransaction(
          date: payment.paymentDate,
          description: 'سند قبض - ${payment.note ?? ""}',
          debit: 0,
          credit: payment.amount,
          referenceId: payment.id,
          type: 'PAYMENT',
        ),
      );
    }

    // 4. جلب المرتجعات
    final returnsQuery = select(db.salesReturns).join([
      innerJoin(db.sales, db.sales.id.equalsExp(db.salesReturns.saleId)),
    ])..where(db.sales.customerId.equals(customerId));

    final returnRows = await returnsQuery.get();
    for (var row in returnRows) {
      final ret = row.readTable(db.salesReturns);
      allTransactions.add(
        CustomerTransaction(
          date: ret.createdAt,
          description: 'مرتجع مبيعات فاتورة ${ret.saleId.substring(0, 8)}',
          debit: 0,
          credit: ret.amountReturned,
          referenceId: ret.id,
          type: 'RETURN',
        ),
      );
    }

    // ترتيب الحركات حسب التاريخ
    allTransactions.sort((a, b) => a.date.compareTo(b.date));

    return allTransactions;
  }

  // ============================================
  // Quick Customer Smart Search Methods
  // ============================================

  /// Smart search for customers by name
  /// Returns list of search results with similarity scores
  Future<List<CustomerSearchResult>> smartSearchCustomers(String query) async {
    if (query.isEmpty) return [];

    final normalizedQuery = NameNormalizer.normalize(query);

    // Get all active customers
    final allCustomers = await (select(
      customers,
    )..where((c) => c.isActive.equals(true))).get();

    final results = <CustomerSearchResult>[];

    for (final customer in allCustomers) {
      // Use normalizedName if available, otherwise normalize on-the-fly
      final customerNormalized =
          customer.normalizedName ?? NameNormalizer.normalize(customer.name);

      // Exact match
      if (customerNormalized == normalizedQuery) {
        results.add(
          CustomerSearchResult(
            customer: customer,
            similarity: 1.0,
            isExactMatch: true,
          ),
        );
      }
      // Fuzzy match
      else {
        final similarity = NameNormalizer.calculateSimilarity(
          customerNormalized,
          normalizedQuery,
        );

        // Include if similarity >= 0.6 (60%)
        if (similarity >= 0.6) {
          results.add(
            CustomerSearchResult(
              customer: customer,
              similarity: similarity,
              isExactMatch: false,
            ),
          );
        }
      }
    }

    // Sort by similarity (highest first), then exact matches first
    results.sort((a, b) {
      if (a.isExactMatch && !b.isExactMatch) return -1;
      if (!a.isExactMatch && b.isExactMatch) return 1;
      return b.similarity.compareTo(a.similarity);
    });

    return results;
  }

  /// Find exact match by normalized name
  Future<Customer?> findByNormalizedName(String name) async {
    final normalized = NameNormalizer.normalize(name);
    return (select(customers)
          ..where((c) => c.normalizedName.equals(normalized))
          ..where((c) => c.isActive.equals(true)))
        .getSingleOrNull();
  }

  /// Create a quick customer from POS
  Future<String> createQuickCustomer(String name, {String? phone}) async {
    final normalized = NameNormalizer.normalize(name);

    return transaction(() async {
      final customerId = const Uuid().v4();

      // 1. Create customer with normalized name
      await into(customers).insert(
        CustomersCompanion.insert(
          id: Value(customerId),
          name: name,
          normalizedName: Value(normalized),
          phone: Value(phone),
          isQuickCustomer: const Value(true),
          createdFromPOS: const Value(true),
          creditLimit: const Value(0.0),
          balance: const Value(0.0),
          isActive: const Value(true),
        ),
      );

      return customerId;
    });
  }

  /// Get all quick customers (created from POS)
  Future<List<Customer>> getQuickCustomers() async {
    final result = await (select(customers)
          ..where((c) => c.isQuickCustomer.equals(true))
          ..where((c) => c.isActive.equals(true)))
        .get();
    // Cache quick customers list
    _cache.set(CacheKeys.quickCustomers, result, ttl: const Duration(minutes: 5));
    return result;
  }

  /// Watch only regular (non-quick) customers for credit sales
  Stream<List<Customer>> watchRegularCustomers() {
    return (select(customers)
          ..where((c) => c.isActive.equals(true))
          ..where((c) => c.isQuickCustomer.equals(false)))
        .watch();
  }
  
  /// Get all customers cached
  Future<List<Customer>> getAllCustomersCached() async {
    return _cache.getOrLoad(
      CacheKeys.customersAll,
      () async => (select(customers)..where((c) => c.isActive.equals(true))).get(),
      ttl: const Duration(minutes: 5),
    );
  }
}
