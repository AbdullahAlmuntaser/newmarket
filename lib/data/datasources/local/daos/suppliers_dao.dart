import 'package:drift/drift.dart';
import 'package:supermarket/data/datasources/local/daos/accounting_dao.dart';
import 'package:supermarket/core/services/cache_service.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';

part 'suppliers_dao.g.dart';

class SupplierTransaction {
  final DateTime date;
  final String description;
  final double debit; // له (مشتريات)
  final double credit; // عليه (مدفوعات/مرتجعات)
  final String referenceId;
  final String type; // PURCHASE, PAYMENT, RETURN

  SupplierTransaction({
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
    Suppliers,
    SupplierPayments,
    Purchases,
    PurchaseReturns,
    GLAccounts,
    GLEntries,
    GLLines,
    APInvoices,
  ],
)
class SuppliersDao extends DatabaseAccessor<AppDatabase>
    with _$SuppliersDaoMixin {
  SuppliersDao(super.db);
  
  final _cache = CacheService();

  /// Get supplier by ID with caching
  Future<Supplier?> getSupplierById(String id) async {
    // Try cache first
    final cached = _cache.get<Supplier>(CacheKeys.supplier(id));
    if (cached != null) {
      return cached;
    }

    // Load from database
    final supplier = await (select(suppliers)..where((s) => s.id.equals(id))).getSingleOrNull();
    
    if (supplier != null) {
      _cache.set(CacheKeys.supplier(id), supplier, ttl: const Duration(minutes: 10));
    }
    
    return supplier;
  }

  /// Get supplier by phone with caching
  Future<Supplier?> getSupplierByPhone(String phone) async {
    final cached = _cache.get<Supplier>(CacheKeys.supplierByPhone(phone));
    if (cached != null) {
      return cached;
    }

    final supplier = await (select(suppliers)..where((s) => s.phone.equals(phone))).getSingleOrNull();
    
    if (supplier != null) {
      _cache.set(CacheKeys.supplierByPhone(phone), supplier, ttl: const Duration(minutes: 10));
    }
    
    return supplier;
  }

  /// Get all suppliers with optional filtering - optimized with indexes
  Future<List<Supplier>> getSuppliers({
    String? supplierType,
    bool? isActive,
  }) async {
    var query = select(suppliers);

    if (supplierType != null) {
      query = query..where((s) => s.supplierType.equals(supplierType));
    }
    
    if (isActive != null) {
      query = query..where((s) => s.isActive.equals(isActive));
    }

    return query.get();
  }

  /// Clear supplier cache when data changes
  void clearSupplierCache([String? supplierId]) {
    if (supplierId != null) {
      _cache.remove(CacheKeys.supplier(supplierId));
    } else {
      _cache.clearByPattern('supplier_*');
    }
  }

  Stream<List<Supplier>> watchAllSuppliers() =>
      (select(suppliers)..where((tbl) => tbl.isActive.equals(true))).watch();

  Future<Supplier?> getSupplierById(String id) {
    return (select(suppliers)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  // AP Invoices
  Stream<List<APInvoice>> watchAPInvoices(String supplierId) {
    return (select(aPInvoices)..where((t) => t.supplierId.equals(supplierId))).watch();
  }

  Stream<List<APInvoice>> watchAllAPInvoices() {
    return (select(aPInvoices)..orderBy([(t) => OrderingTerm(expression: t.invoiceDate, mode: OrderingMode.desc)])).watch();
  }

  Future<int> createAPInvoice(APInvoicesCompanion entry) {
    return into(aPInvoices).insert(entry);
  }

  Future<List<APInvoice>> getUnpaidAPInvoices(String supplierId) {
    return (select(aPInvoices)
          ..where((t) =>
              t.supplierId.equals(supplierId) &
              t.status.isIn(['POSTED', 'PARTIAL'])))
        .get();
  }

  Future<List<APInvoice>> getDueAPInvoices(DateTime endDate) {
    return (select(aPInvoices)
          ..where((t) =>
              t.status.isIn(['POSTED', 'PARTIAL']) &
              t.dueDate.isSmallerOrEqual(Variable(endDate))))
        .get();
  }

  /// إدراج مورد مع إنشاء حساب محاسبي له تلقائياً
  Future<String> insertSupplierWithAccount(SuppliersCompanion entry) async {
    return transaction(() async {
      // 1. البحث عن الحساب الرئيسي للموردين (مثلاً '2010')
      final parentAccount = await (select(
        gLAccounts,
      )..where((t) => t.code.equals('2010'))).getSingleOrNull();

      final accountId = const Uuid().v4();
      final supplierId = const Uuid().v4();

      // 2. إنشاء حساب في دفتر الأستاذ العام
      await into(gLAccounts).insert(
        GLAccountsCompanion.insert(
          id: Value(accountId),
          code: '2010-${supplierId.substring(0, 5)}',
          name: 'مورد: ${entry.name.value}',
          type: AccountType
              .liability, // Removed .name as AccountType.liability is already a String
          parentId: Value(parentAccount?.id),
          isHeader: const Value(false),
          balance: const Value(0.0),
        ),
      );

      // 3. إدراج المورد وربطه بالحساب
      final finalEntry = entry.copyWith(
        id: Value(supplierId),
        accountId: Value(accountId),
      );
      await into(suppliers).insert(finalEntry);

      return supplierId;
    });
  }

  Future<bool> updateSupplier(Supplier entry) {
    return update(suppliers).replace(entry);
  }

  Future<int> deleteSupplier(Supplier entry) {
    // تعطيل المورد بدلاً من حذفه
    return (update(suppliers)..where((t) => t.id.equals(entry.id))).write(
      const SuppliersCompanion(isActive: Value(false)),
    );
  }

  /// بحث متقدم عن الموردين
  Future<List<Supplier>> searchSuppliers(String query) {
    return (select(suppliers)
          ..where(
            (t) =>
                t.name.contains(query) |
                t.phone.contains(query) |
                t.taxNumber.contains(query),
          )
          ..where((t) => t.isActive.equals(true)))
        .get();
  }

  Future<List<SupplierTransaction>> getSupplierStatement(
    String supplierId,
  ) async {
    final List<SupplierTransaction> allTransactions = [];

    // 1. جلب المشتريات الآجلة
    final supplierPurchases =
        await (select(db.purchases)..where(
              (p) => p.supplierId.equals(supplierId) & p.isCredit.equals(true),
            ))
            .get();

    for (var purchase in supplierPurchases) {
      allTransactions.add(
        SupplierTransaction(
          date: purchase.date,
          description:
              'فاتورة مشتريات رقم ${purchase.invoiceNumber ?? purchase.id.substring(0, 8)}',
          debit: purchase.total, // له
          credit: 0,
          referenceId: purchase.id,
          type: 'PURCHASE',
        ),
      );
    }

    // 2. جلب فواتير الذمم الدائنة (AP Invoices)
    final apInvoicesList = await (select(aPInvoices)..where((t) => t.supplierId.equals(supplierId))).get();
    for (var inv in apInvoicesList) {
      allTransactions.add(
        SupplierTransaction(
          date: inv.invoiceDate,
          description: 'فاتورة AP رقم ${inv.invoiceNumber}',
          debit: inv.totalAmount, // له
          credit: 0,
          referenceId: inv.id,
          type: 'AP_INVOICE',
        ),
      );
    }

    // 3. جلب المدفوعات للمورد (سند صرف)
    final payments = await (select(
      db.supplierPayments,
    )..where((p) => p.supplierId.equals(supplierId))).get();

    for (var payment in payments) {
      allTransactions.add(
        SupplierTransaction(
          date: payment.paymentDate,
          description: 'سند صرف - ${payment.note ?? ""}',
          debit: 0,
          credit: payment.amount, // عليه
          referenceId: payment.id,
          type: 'PAYMENT',
        ),
      );
    }

    // 4. جلب المرتجعات للمورد
    final returnsQuery = select(db.purchaseReturns).join([
      innerJoin(
        db.purchases,
        db.purchases.id.equalsExp(db.purchaseReturns.purchaseId),
      ),
    ])..where(db.purchases.supplierId.equals(supplierId));

    final returnRows = await returnsQuery.get();
    for (var row in returnRows) {
      final ret = row.readTable(db.purchaseReturns);
      allTransactions.add(
        SupplierTransaction(
          date: ret.createdAt,
          description: 'مرتجع مشتريات فاتورة ${ret.purchaseId.substring(0, 8)}',
          debit: 0,
          credit: ret.amountReturned, // عليه
          referenceId: ret.id,
          type: 'RETURN',
        ),
      );
    }

    // ترتيب الحركات حسب التاريخ
    allTransactions.sort((a, b) => a.date.compareTo(b.date));

    return allTransactions;
  }
}
