import 'dart:io';
// ignore_for_file: deprecated_member_use
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:uuid/uuid.dart';
import 'daos/products_dao.dart';
import 'daos/sales_dao.dart';
import 'daos/customers_dao.dart';
import 'daos/accounting_dao.dart';
import 'daos/users_dao.dart';
import 'daos/suppliers_dao.dart';
import 'daos/purchases_dao.dart';
import 'daos/bom_dao.dart';
import 'daos/warehouses_dao.dart';
import 'daos/global_units_dao.dart';
import 'daos/product_units_dao.dart';
import 'daos/audit_dao.dart';
import 'daos/stock_movement_dao.dart';
import 'tables/app_config_table.dart';
import 'tables/fixed_assets_tables.dart';
import 'tables/payroll_tables.dart';
import 'tables/advanced_accounting_tables.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

part 'app_database.g.dart';

mixin SyncableTable on Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get deviceId => text().nullable()();
  IntColumn get syncStatus => integer().withDefault(const Constant(1))();
  TextColumn get branchId => text().nullable().references(Branches, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

class Branches extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get code => text().unique()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

class Users extends Table with SyncableTable {
  TextColumn get username => text().unique()();
  TextColumn get password => text()();
  TextColumn get role => text()();
  TextColumn get fullName => text()();
}

class Categories extends Table with SyncableTable {
  TextColumn get name => text().unique()();
  TextColumn get code => text().unique().nullable()();
}

class Products extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get sku => text().unique()();
  TextColumn get barcode => text().nullable()(); // Primary barcode
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get unit =>
      text().withDefault(const Constant('pcs'))(); // Base unit
  TextColumn get cartonUnit => text().withDefault(const Constant('carton'))();
  IntColumn get piecesPerCarton => integer().withDefault(const Constant(1))();
  TextColumn get kiloUnit => text().nullable()();
  TextColumn get boxUnit => text().nullable()();
  RealColumn get buyPrice => real().withDefault(const Constant(0.0))();
  RealColumn get sellPrice => real().withDefault(const Constant(0.0))();
  RealColumn get wholesalePrice => real().withDefault(const Constant(0.0))();
  RealColumn get stock => real().withDefault(const Constant(0.0))();
  RealColumn get maxStock => real().withDefault(const Constant(1000.0))();
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  TextColumn get valuationMethod => text().withDefault(const Constant('FIFO'))(); // FIFO, AVCO
  BoolColumn get allowFreeQty => boolean().withDefault(const Constant(false))();
  BoolColumn get isService => boolean().withDefault(const Constant(false))();
  RealColumn get alertLimit => real().withDefault(const Constant(10.0))();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  RealColumn get taxRate => real().withDefault(const Constant(0.0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  // Variant support
  TextColumn get parentProductId => text().nullable().references(
    Products,
    #id,
  )(); // Null for main items; points to parent for variants
  TextColumn get attributes =>
      text().nullable()(); // JSON: {"color":"Red","size":"XL"}
  RealColumn get additionalCost =>
      real().nullable()(); // Extra cost for variant over base product
}

class ProductUnits extends Table with SyncableTable {
  // Multi-unit support for products (and variants)
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get unitName => text()(); // e.g., carton, box, kilo
  TextColumn get barcode =>
      text().unique().nullable()(); // Barcode for this unit
  RealColumn get unitFactor =>
      real().withDefault(const Constant(1.0))(); // How many base units
  RealColumn get buyPrice => real().nullable()(); // Unit-specific buy price
  RealColumn get sellPrice => real().nullable()(); // Unit-specific sell price
  RealColumn get wholesalePrice =>
      real().nullable()(); // Wholesale price for this unit
  RealColumn get halfWholesalePrice =>
      real().nullable()(); // Half-wholesale price
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}

class Customers extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get normalizedName => text().nullable()(); // For smart search
  TextColumn get phone => text().nullable()();
  TextColumn get taxNumber => text().nullable()(); // New: Tax Number for ERP
  TextColumn get address => text().nullable()(); // New: Detailed Address
  TextColumn get email => text().nullable()(); // New: Email
  TextColumn get customerType => text().withDefault(
    const Constant('RETAIL'),
  )(); // New: RETAIL, WHOLESALE, VIP
  BoolColumn get isActive =>
      boolean().withDefault(const Constant(true))(); // New: Status
  RealColumn get creditLimit => real().withDefault(const Constant(0.0))();
  RealColumn get balance => real().withDefault(const Constant(0.0))();
  TextColumn get accountId =>
      text().nullable().references(GLAccounts, #id)(); // New: Linked to GL
  TextColumn get currencyId => text().nullable().references(Currencies, #id)();
  RealColumn get exchangeRate => real().withDefault(const Constant(1.0))();
  BoolColumn get isQuickCustomer =>
      boolean().withDefault(const Constant(false))(); // Quick customer flag
  BoolColumn get createdFromPOS =>
      boolean().withDefault(const Constant(false))(); // Created from POS
  RealColumn get discountRate => real().withDefault(const Constant(0.0))(); // Customer-specific discount
}

class Suppliers extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get contactPerson => text().nullable()();
  TextColumn get taxNumber => text().nullable()(); // New: Tax Number
  TextColumn get address => text().nullable()(); // New: Address
  TextColumn get email => text().nullable()(); // New: Email
  TextColumn get supplierType => text().withDefault(
    const Constant('LOCAL'),
  )(); // New: LOCAL, INTERNATIONAL
  BoolColumn get isActive =>
      boolean().withDefault(const Constant(true))(); // New: Status
  RealColumn get balance => real().withDefault(const Constant(0.0))();
  TextColumn get accountId =>
      text().nullable().references(GLAccounts, #id)(); // New: Linked to GL
}

class GlobalUnits extends Table with SyncableTable {
  TextColumn get name => text().unique()();
  TextColumn get symbol => text().nullable()();
  BoolColumn get isCustom => boolean().withDefault(const Constant(true))();
}

class Sales extends Table with SyncableTable {
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  RealColumn get total => real()();
  RealColumn get discount => real().withDefault(const Constant(0.0))();
  RealColumn get tax => real().withDefault(const Constant(0.0))();
  TextColumn get paymentMethod => text()();
  BoolColumn get isCredit => boolean().withDefault(const Constant(false))();
  TextColumn get status => text().withDefault(
    const Constant('POSTED'),
  )(); // DRAFT, POSTED, CANCELLED
  TextColumn get saleType =>
      text().withDefault(const Constant('retail'))(); // retail / wholesale
  TextColumn get currencyId => text().nullable()();
  RealColumn get exchangeRate => real().withDefault(const Constant(1.0))();
  // ZATCA Fields
  TextColumn get qrCode => text().nullable()();
  TextColumn get hash => text().nullable()();
  TextColumn get signature => text().nullable()();
}

class SaleItems extends Table with SyncableTable {
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get price => real()();
  TextColumn get unitId => text().nullable().references(GlobalUnits, #id)();
  TextColumn get unitName => text().withDefault(const Constant('حبة'))();
  RealColumn get unitFactor => real().withDefault(const Constant(1.0))();
  TextColumn get warehouseId => text().nullable().references(Warehouses, #id)();
  TextColumn get batchId => text().nullable().references(ProductBatches, #id)();
  TextColumn get costCenterId => text().nullable().references(CostCenters, #id)(); // الحقل المضاف
}

class StockMovements extends Table with SyncableTable {
  @ReferenceName('productStockMovements')
  TextColumn get productId => text().references(Products, #id)();
  @ReferenceName('fromWarehouseStockMovements')
  TextColumn get fromWarehouseId =>
      text().nullable().references(Warehouses, #id)();
  @ReferenceName('toWarehouseStockMovements')
  TextColumn get toWarehouseId =>
      text().nullable().references(Warehouses, #id)();
  RealColumn get quantity => real()();
  RealColumn get cost =>
      real().withDefault(const Constant(0.0))(); // ADDED COST
  TextColumn get batchId => text().nullable().references(ProductBatches, #id)();
  DateTimeColumn get movementDate =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get type =>
      text()(); // TRANSFER, ADJUSTMENT, INITIAL, SALE, PURCHASE
  TextColumn get transactionId => text().nullable()(); // ADDED transactionId
  TextColumn get date => text()
      .nullable()(); // ADDED date as string or something? Wait, StockMovements already has movementDate. I will use date if needed.
  TextColumn get referenceId => text().nullable()(); // SaleId, PurchaseId, etc.
}

class Purchases extends Table with SyncableTable {
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  RealColumn get total => real()();
  RealColumn get tax => real().withDefault(const Constant(0.0))();
  RealColumn get discount => real().withDefault(
    const Constant(0.0),
  )(); // New: Additional header discount
  RealColumn get landedCosts => real().withDefault(const Constant(0.0))();
  RealColumn get shippingCost =>
      real().withDefault(const Constant(0.0))(); // New
  RealColumn get otherExpenses =>
      real().withDefault(const Constant(0.0))(); // New
  TextColumn get invoiceNumber => text().nullable()();
  TextColumn get purchaseType =>
      text().withDefault(const Constant('cash'))(); // cash / credit
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get time => dateTime().nullable()(); // New: Time field
  BoolColumn get isCredit => boolean().withDefault(const Constant(false))();
  TextColumn get status => text().withDefault(
    const Constant('DRAFT'),
  )(); // DRAFT, POSTED, RECEIVED, CANCELLED
  TextColumn get warehouseId => text().nullable().references(Warehouses, #id)();
  TextColumn get currencyId => text().nullable()();
  RealColumn get exchangeRate => real().withDefault(const Constant(1.0))();
  TextColumn get notes => text().nullable()(); // New
  TextColumn get referenceDocument => text().nullable()(); // جديد
  TextColumn get attachmentPath =>
      text().nullable()(); // New: Invoice image path
}

class PurchaseItems extends Table with SyncableTable {
  TextColumn get purchaseId => text().references(Purchases, #id)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get unitId =>
      text().nullable()(); // New: Unit ID (e.g., carton, kilo)
  RealColumn get unitFactor =>
      real().withDefault(const Constant(1.0))(); // New: Conversion to base unit
  RealColumn get quantity => real()();
  RealColumn get quantityInBaseUnit =>
      real().nullable()(); // New: Calculated base quantity
  RealColumn get unitPrice => real()(); // New: Price per selected unit
  RealColumn get price => real()(); // Total price (kept for compatibility)
  RealColumn get discount =>
      real().withDefault(const Constant(0.0))(); // New: Item discount
  RealColumn get discountPercent =>
      real().withDefault(const Constant(0.0))(); // New: Discount percentage
  RealColumn get tax =>
      real().withDefault(const Constant(0.0))(); // New: Tax amount
  RealColumn get taxPercent =>
      real().withDefault(const Constant(0.0))(); // New: Tax percentage
  RealColumn get landedCostShare =>
      real().withDefault(const Constant(0.0))(); // New: Share of landed costs
  TextColumn get batchId => text().nullable().references(ProductBatches, #id)();
  TextColumn get batchNumber => text().nullable()(); // New
  DateTimeColumn get expiryDate => dateTime().nullable()(); // New
  TextColumn get warehouseId => text().nullable().references(
    Warehouses,
    #id,
  )(); // New: Override warehouse per item
  BoolColumn get isCarton => boolean().withDefault(const Constant(false))();
}

class Warehouses extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get location => text().nullable()();
  TextColumn get accountId => text().nullable().references(GLAccounts, #id)(); // ربط المستودع بالحساب المحاسبي
  @override
  TextColumn get branchId => text().nullable().references(Branches, #id)();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}

@DataClassName('ProductBatch')
class ProductBatches extends Table with SyncableTable {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get batchNumber => text()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  RealColumn get quantity => real().withDefault(const Constant(0.0))();
  RealColumn get initialQuantity => real().withDefault(const Constant(0.0))();
  RealColumn get costPrice => real().withDefault(const Constant(0.0))();
}

/// Item variants (e.g., color, size) for products with multiple attributes
class ItemVariants extends Table with SyncableTable {
  @override
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class SalesReturns extends Table with SyncableTable {
  TextColumn get saleId => text().references(Sales, #id)();
  RealColumn get amountReturned => real()();
  TextColumn get reason => text().nullable()();
}

class SalesReturnItems extends Table with SyncableTable {
  TextColumn get salesReturnId => text().references(SalesReturns, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get price => real()();
  TextColumn get batchId => text().nullable().references(ProductBatches, #id)();
}

class PurchaseReturns extends Table with SyncableTable {
  TextColumn get purchaseId => text().references(Purchases, #id)();
  RealColumn get amountReturned => real()();
  TextColumn get reason => text().nullable()();
}

class PurchaseReturnItems extends Table with SyncableTable {
  TextColumn get purchaseReturnId => text().references(PurchaseReturns, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get price => real()();
}

class CustomerPayments extends Table with SyncableTable {
  TextColumn get customerId => text().references(Customers, #id)();
  RealColumn get amount => real()();
  DateTimeColumn get paymentDate =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get note => text().nullable()();
}

class SupplierPayments extends Table with SyncableTable {
  TextColumn get supplierId => text().references(Suppliers, #id)();
  RealColumn get amount => real()();
  RealColumn get remainingAmount =>
      real().withDefault(const Constant(0.0))(); // Unapplied amount
  DateTimeColumn get paymentDate =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get note => text().nullable()();
  TextColumn get status => text().withDefault(
    const Constant('COMPLETED'),
  )(); // COMPLETED, PARTIAL, CANCELLED
}

class PurchasePaymentLinks extends Table with SyncableTable {
  // Links payments to purchases for partial payment tracking
  TextColumn get paymentId => text().references(SupplierPayments, #id)();
  TextColumn get purchaseId => text().references(Purchases, #id)();
  RealColumn get amount => real()(); // Amount applied to this purchase
}

class GLAccounts extends Table with SyncableTable {
  TextColumn get code => text().unique()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // ASSET, LIABILITY, EQUITY, REVENUE, EXPENSE
  TextColumn get analyticType => text().nullable()(); // جديد: صندوق، بنك، عميل، مورد، موظف، مركز تكلفة
  TextColumn get parentId => text().nullable().references(GLAccounts, #id)();
  BoolColumn get isHeader => boolean().withDefault(const Constant(false))();
  RealColumn get balance => real().withDefault(const Constant(0.0))();
}

class CostCenters extends Table with SyncableTable {
  TextColumn get code => text().unique()();
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

class GLEntries extends Table with SyncableTable {
  TextColumn get description => text()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get referenceType =>
      text().nullable()(); // Sale, Purchase, Manual, Expense
  TextColumn get referenceId => text().nullable()();
  TextColumn get status => text().withDefault(
    const Constant('DRAFT'),
  )(); // New: DRAFT, POSTED, CANCELLED
  DateTimeColumn get postedAt => dateTime().nullable()(); // New
  TextColumn get postedBy => text().nullable()(); // New
  TextColumn get currencyId => text().nullable()();
  RealColumn get exchangeRate => real().withDefault(const Constant(1.0))();
}

class GLLines extends Table with SyncableTable {
  TextColumn get entryId => text().references(GLEntries, #id)();
  TextColumn get accountId => text().references(GLAccounts, #id)();
  TextColumn get costCenterId =>
      text().nullable().references(CostCenters, #id)();
  RealColumn get debit => real().withDefault(const Constant(0.0))();
  RealColumn get credit => real().withDefault(const Constant(0.0))();
  TextColumn get currencyId => text().nullable().references(Currencies, #id)();
  RealColumn get exchangeRate => real().withDefault(const Constant(1.0))();
  TextColumn get memo => text().nullable()();
}

class AccountingPeriods extends Table with SyncableTable {
  TextColumn get name => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get closedBy => text().nullable()();
  TextColumn get closingType => text().nullable()(); // DAILY, MONTHLY, YEARLY
  TextColumn get status =>
      text().withDefault(const Constant('OPEN'))(); // OPEN, CLOSED
}

class FixedAssets extends Table with SyncableTable {
  TextColumn get name => text()();
  DateTimeColumn get purchaseDate => dateTime()();
  RealColumn get cost => real()();
  RealColumn get salvageValue => real().withDefault(const Constant(0.0))();
  IntColumn get usefulLifeYears => integer()();
  RealColumn get accumulatedDepreciation =>
      real().withDefault(const Constant(0.0))();
}

class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityTable => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get status => integer().withDefault(const Constant(0))();
  TextColumn get deviceId => text().nullable()();
}

class InventoryAudits extends Table with SyncableTable {
  DateTimeColumn get auditDate => dateTime().withDefault(currentDateAndTime)();
  TextColumn get note => text().nullable()();
  TextColumn get auditedBy => text().nullable()();
}

class InventoryAuditItems extends Table with SyncableTable {
  TextColumn get auditId => text().references(InventoryAudits, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get systemStock => real()();
  RealColumn get actualStock => real()();
  RealColumn get difference => real()();
}

class Shifts extends Table with SyncableTable {
  TextColumn get userId => text().references(Users, #id)();
  DateTimeColumn get startTime => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get endTime => dateTime().nullable()();
  RealColumn get openingCash => real().withDefault(const Constant(0.0))();
  RealColumn get closingCash => real().nullable()();
  RealColumn get expectedCash => real().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get isOpen => boolean().withDefault(const Constant(true))();
}

class Reconciliations extends Table with SyncableTable {
  TextColumn get accountId => text().references(GLAccounts, #id)();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  RealColumn get bookBalance => real()();
  RealColumn get actualBalance => real()();
  RealColumn get difference => real()();
  TextColumn get note => text().nullable()();
}

class AuditLogs extends Table with SyncableTable {
  TextColumn get userId => text().nullable()();
  TextColumn get action => text()(); // CREATE, UPDATE, DELETE
  TextColumn get targetEntity => text()(); // Products, Sales, etc.
  TextColumn get entityId => text()();
  TextColumn get details => text().nullable()();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}

class StockTransfers extends Table with SyncableTable {
  @ReferenceName('fromWarehouseStockTransfers')
  TextColumn get fromWarehouseId => text().references(Warehouses, #id)();
  @ReferenceName('toWarehouseStockTransfers')
  TextColumn get toWarehouseId => text().references(Warehouses, #id)();
  DateTimeColumn get transferDate =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get note => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('COMPLETED'))();
}

class StockTransferItems extends Table with SyncableTable {
  TextColumn get transferId => text().references(StockTransfers, #id)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get batchId => text().references(ProductBatches, #id)();
  RealColumn get quantity => real()();
}

class Employees extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get employeeCode => text().unique()();
  TextColumn get jobTitle => text().nullable()();
  TextColumn get role =>
      text().withDefault(const Constant('USER'))(); // ADMIN or USER
  RealColumn get basicSalary => real().withDefault(const Constant(0.0))();
  DateTimeColumn get hireDate => dateTime().nullable()();
  TextColumn get warehouseId => text().nullable().references(Warehouses, #id)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

class PayrollEntries extends Table with SyncableTable {
  IntColumn get month => integer()();
  IntColumn get year => integer()();
  DateTimeColumn get generationDate =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get status => text().withDefault(const Constant('DRAFT'))();
  TextColumn get note => text().nullable()();
}

class PayrollLines extends Table with SyncableTable {
  TextColumn get payrollEntryId => text().references(PayrollEntries, #id)();
  TextColumn get employeeId => text().references(Employees, #id)();
  RealColumn get basicSalary => real()();
  RealColumn get allowances => real().withDefault(const Constant(0.0))();
  RealColumn get deductions => real().withDefault(const Constant(0.0))();
  RealColumn get netSalary => real()();
}

class Permissions extends Table with SyncableTable {
  TextColumn get code => text().unique()();
  TextColumn get description => text().nullable()();
}

class RolePermissions extends Table with SyncableTable {
  TextColumn get role => text()();
  TextColumn get permissionCode => text().references(Permissions, #code)();
}

class CashboxTransactions extends Table with SyncableTable {
  RealColumn get amount => real()();
  TextColumn get type => text()();
  TextColumn get category => text()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get userId => text().references(Users, #id)();
}

class PriceLists extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get description => text().nullable()();
}

class PriceListItems extends Table with SyncableTable {
  TextColumn get priceListId => text().references(PriceLists, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get price => real()();
  RealColumn get minQuantity => real().withDefault(const Constant(0.0))();
}

class Promotions extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get type =>
      text()(); // PERCENTAGE_DISCOUNT, FIXED_DISCOUNT, BOGO (Buy One Get One)
  RealColumn get value => real()(); // Discount amount or percentage
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get productId => text().nullable().references(Products, #id)();
  RealColumn get minPurchaseAmount => real().withDefault(const Constant(0.0))();
}

class PriceHistory extends Table with SyncableTable {
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get oldPrice => real()();
  RealColumn get newPrice => real()();
  TextColumn get type => text()(); // PURCHASE / SALE
}

class Currencies extends Table with SyncableTable {
  TextColumn get code => text().unique()(); // e.g., USD, YER, SAR
  TextColumn get name => text()();
  TextColumn get fractionalUnit => text().nullable()(); // فكة العملة
  IntColumn get decimalPlaces => integer().withDefault(const Constant(2))(); // عدد الكسور
  RealColumn get exchangeRate => real().withDefault(const Constant(1.0))();
  BoolColumn get isBase => boolean().withDefault(const Constant(false))();
}

class UnitConversions extends Table with SyncableTable {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get unitName => text()();
  RealColumn get factor =>
      real()(); // How many of this unit equal the base unit
  BoolColumn get isBaseUnit => boolean().withDefault(const Constant(false))();
  RealColumn get buyPrice => real().nullable()(); // Unit-specific buy price
  RealColumn get sellPrice => real().nullable()(); // Unit-specific sell price
  TextColumn get barcode =>
      text().unique().nullable()(); // Barcode for this unit
}

class APInvoices extends Table with SyncableTable {
  TextColumn get supplierId => text().references(Suppliers, #id)();
  TextColumn get invoiceNumber => text()();
  DateTimeColumn get invoiceDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get dueDate => dateTime().nullable()();
  RealColumn get totalAmount => real()();
  RealColumn get taxAmount => real().withDefault(const Constant(0.0))();
  RealColumn get paidAmount => real().withDefault(const Constant(0.0))();
  TextColumn get status => text().withDefault(const Constant('DRAFT'))(); // DRAFT, POSTED, PAID, PARTIAL
  TextColumn get notes => text().nullable()();
  TextColumn get accountId => text().nullable().references(GLAccounts, #id)();
}

class ARInvoices extends Table with SyncableTable {
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get invoiceNumber => text()();
  DateTimeColumn get invoiceDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get dueDate => dateTime().nullable()();
  RealColumn get totalAmount => real()();
  RealColumn get taxAmount => real().withDefault(const Constant(0.0))();
  RealColumn get paidAmount => real().withDefault(const Constant(0.0))();
  TextColumn get status => text().withDefault(const Constant('DRAFT'))(); // DRAFT, POSTED, PAID, PARTIAL
  TextColumn get notes => text().nullable()();
  TextColumn get accountId => text().nullable().references(GLAccounts, #id)();
}

class InventoryTransactions extends Table with SyncableTable {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get batchId => text().nullable().references(ProductBatches, #id)();
  RealColumn get quantity => real()(); // Positive for in, negative for out
  TextColumn get type =>
      text()(); // PURCHASE, SALE, RETURN, TRANSFER, ADJUSTMENT
  TextColumn get referenceId => text()(); // PurchaseId, SaleId, etc.
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
}

class AccountTransactions extends Table with SyncableTable {
  TextColumn get accountId => text().references(GLAccounts, #id)();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get type => text()(); // INVOICE, PAYMENT, RETURN
  TextColumn get referenceId => text().nullable()();
  RealColumn get debit => real().withDefault(const Constant(0.0))();
  RealColumn get credit => real().withDefault(const Constant(0.0))();
  RealColumn get runningBalance => real().withDefault(const Constant(0.0))();
}

class StockTakes extends Table with SyncableTable {
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get status =>
      text().withDefault(const Constant('DRAFT'))(); // DRAFT, COMPLETED
  TextColumn get note => text().nullable()();
}

class StockTakeItems extends Table with SyncableTable {
  TextColumn get stockTakeId => text().references(StockTakes, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get expectedQty => real()();
  RealColumn get actualQty => real()();
  RealColumn get variance => real()();
}

class PostingProfiles extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get operationType =>
      text()(); // SALE, PURCHASE, RETURN, PAYMENT, EXPENSE, INVENTORY
  TextColumn get accountType =>
      text()(); // REVENUE, COGS, INVENTORY, RECEIVABLE, PAYABLE, TAX, CASH
  TextColumn get accountId => text().nullable().references(GLAccounts, #id)();
  TextColumn get description => text().nullable()();
  TextColumn get accountCode =>
      text().nullable()(); // Alternative: account code instead of FK
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sequence =>
      integer().withDefault(const Constant(0))(); // Order of posting lines
  TextColumn get side => text()(); // DEBIT or CREDIT
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get syncStatus => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class GoodReceivedNotes extends Table with SyncableTable {
  TextColumn get purchaseId => text().nullable().references(Purchases, #id)();
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get grnNumber => text().unique()();
  DateTimeColumn get receivedDate => dateTime().withDefault(currentDateAndTime)();
  TextColumn get receivedBy => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('DRAFT'))(); // DRAFT, POSTED
}

class GoodReceivedNoteItems extends Table with SyncableTable {
  TextColumn get grnId => text().references(GoodReceivedNotes, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get quantity => real()();
  TextColumn get batchNumber => text().nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
}

class DeliveryNotes extends Table with SyncableTable {
  TextColumn get saleOrderId => text().references(SalesOrders, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get deliveryNumber => text().unique()();
  DateTimeColumn get deliveryDate => dateTime().withDefault(currentDateAndTime)();
  TextColumn get deliveredBy => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('DRAFT'))(); // DRAFT, POSTED
}

class DeliveryNoteItems extends Table with SyncableTable {
  TextColumn get deliveryNoteId => text().references(DeliveryNotes, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get quantity => real()();
  TextColumn get batchId => text().nullable().references(ProductBatches, #id)();
}

class Checks extends Table with SyncableTable {
  TextColumn get checkNumber => text()();
  TextColumn get bankName => text()();
  DateTimeColumn get dueDate => dateTime()();
  RealColumn get amount => real()();
  TextColumn get type =>
      text()(); // RECEIVED (from customer), ISSUED (to supplier)
  TextColumn get status => text().withDefault(
    const Constant('PENDING'),
  )(); // PENDING, COLLECTED, BOUNCED
  TextColumn get partnerId => text().nullable()(); // Customer or Supplier ID
  TextColumn get paymentAccountId =>
      text().nullable().references(GLAccounts, #id)();
  TextColumn get note => text().nullable()();
  TextColumn get currencyId => text().nullable().references(Currencies, #id)();
  RealColumn get exchangeRate => real().withDefault(const Constant(1.0))();
}

class BillOfMaterials extends Table with SyncableTable {
  @ReferenceName('finishedProduct')
  TextColumn get finishedProductId => text().references(Products, #id)();
  @ReferenceName('componentProduct')
  TextColumn get componentProductId => text().references(Products, #id)();
  RealColumn get quantity =>
      real()(); // الكمية المطلوبة من المادة الخام لإنتاج وحدة واحدة
}

class PurchaseOrders extends Table with SyncableTable {
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  RealColumn get total => real()();
  TextColumn get orderNumber => text().nullable()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get status => text().withDefault(
    const Constant('QUOTATION'),
  )(); // QUOTATION, ORDER, DELIVERED, INVOICED, CANCELLED
  TextColumn get warehouseId => text().nullable().references(Warehouses, #id)();
  TextColumn get notes => text().nullable()();
}

class PurchaseOrderItems extends Table with SyncableTable {
  TextColumn get orderId => text().references(PurchaseOrders, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get price => real()();
  TextColumn get unitId => text().nullable()();
}

class SalesOrders extends Table with SyncableTable {
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  RealColumn get total => real()();
  TextColumn get orderNumber => text().nullable()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get status => text().withDefault(
    const Constant('QUOTATION'),
  )(); // QUOTATION, ORDER, DELIVERED, INVOICED, CANCELLED
  TextColumn get notes => text().nullable()();
}

class SalesOrderItems extends Table with SyncableTable {
  TextColumn get orderId => text().references(SalesOrders, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get price => real()();
  TextColumn get unitId => text().nullable()();
}

@DriftDatabase(
  tables: [
    Branches,
    Users,
    Categories,
    Products,
    Customers,
    Suppliers,
    Sales,
    SaleItems,
    Purchases,
    PurchaseItems,
    PurchaseOrders,
    PurchaseOrderItems,
    SalesOrders,
    SalesOrderItems,
    SalesReturns,
    SalesReturnItems,
    PurchaseReturns,
    PurchaseReturnItems,
    CustomerPayments,
    SupplierPayments,
    PurchasePaymentLinks,
    SyncQueue,
    GLAccounts,
    CostCenters,
    GLEntries,
    GLLines,
    AccountingPeriods,
    FixedAssets,
    InventoryAudits,
    InventoryAuditItems,
    Shifts,
    Reconciliations,
    AuditLogs,
    Warehouses,
    ProductBatches,
    ItemVariants,
    StockTransfers,
    StockTransferItems,
    Employees,
    PayrollEntries,
    PayrollLines,
    Permissions,
    RolePermissions,
    CashboxTransactions,
    PriceLists,
    PriceListItems,
    Promotions,
    Currencies,
    PriceHistory,
    UnitConversions,
    StockTakes,
    StockTakeItems,
    Checks,
    BillOfMaterials,
    InventoryTransactions,
    AccountTransactions,
    PostingProfiles,
    GlobalUnits,
    StockMovements,
    ProductUnits,
    APInvoices,
    ARInvoices,
    GoodReceivedNotes,
    GoodReceivedNoteItems,
    DeliveryNotes,
    DeliveryNoteItems,
    AppConfigTable,
    // Advanced Accounting Tables
    AssetCategories,
    AssetDepreciationLogs,
    AssetDisposals,
    PayrollRuns,
    PayrollDetails,
    AdditionalDeductions,
    ExchangeRates,
    Budgets,
    BankStatements,
    BankStatementLines,
  ],
  daos: [
    ProductsDao,
    SalesDao,
    CustomersDao,
    AccountingDao,
    UsersDao,
    SuppliersDao,
    PurchasesDao,
    BomDao,
    WarehousesDao,
    GlobalUnitsDao,
    ProductUnitsDao,
    AuditDao,
    StockMovementDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 35;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      // Seed data immediately after creation in the same transaction
      await seedData();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Direct migration instead of metadata-heavy reflection
      if (from < 32) {
        await m.createIndex(Index('products_sku_idx', 'CREATE INDEX products_sku_idx ON products (sku)'));
        await m.createIndex(Index('products_barcode_idx', 'CREATE INDEX products_barcode_idx ON products (barcode)'));
        await m.createIndex(Index('sale_items_sale_id_idx', 'CREATE INDEX sale_items_sale_id_idx ON sale_items (sale_id)'));
        await m.createIndex(Index('purchase_items_purchase_id_idx', 'CREATE INDEX purchase_items_purchase_id_idx ON purchase_items (purchase_id)'));
        await m.createIndex(Index('gl_lines_entry_id_idx', 'CREATE INDEX gl_lines_entry_id_idx ON gl_lines (entry_id)'));
        await m.createIndex(Index('gl_lines_account_id_idx', 'CREATE INDEX gl_lines_account_id_idx ON gl_lines (account_id)'));
        await m.createIndex(Index('stock_movements_product_id_idx', 'CREATE INDEX stock_movements_product_id_idx ON stock_movements (product_id)'));
      }
      if (from < 33) {
        try { await m.addColumn(products, products.valuationMethod); } catch (_) {}
        try { await m.addColumn(products, products.allowFreeQty); } catch (_) {}
        try { await m.addColumn(products, products.isService); } catch (_) {}
      }
      if (from < 34) {
        // Version 34: Update GRN table - add purchaseId and supplierId columns
        try { 
          await m.addColumn(goodReceivedNotes, goodReceivedNotes.purchaseId); 
        } catch (_) {}
        try { 
          await m.addColumn(goodReceivedNotes, goodReceivedNotes.supplierId); 
        } catch (_) {}
        // Note: purchaseOrderId will be kept for backward compatibility but deprecated
      }
      if (from < 35) {
        // Version 35: Add AppConfigTable for dynamic settings
        try { await m.createTable(appConfigTable); } catch (_) {}
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON;');
      await customStatement('PRAGMA journal_mode = WAL;');
      await customStatement('PRAGMA synchronous = NORMAL;');
    },
  );

  Future<int> getUnsyncedCount() async {
    final countExp = syncQueue.id.count();
    final query = selectOnly(syncQueue)..addColumns([countExp]);
    final result = await query.map((row) => row.read(countExp)).getSingle();
    return result ?? 0;
  }

  Future<double> calculateTotalInventoryValue() async {
    final query = selectOnly(productBatches)..addColumns([productBatches.quantity, productBatches.costPrice]);
    final rows = await query.get();
    double total = 0.0;
    for (final row in rows) {
      final qty = row.read(productBatches.quantity) ?? 0.0;
      final cost = row.read(productBatches.costPrice) ?? 0.0;
      total += qty * cost;
    }
    return total;
  }

  Stream<List<Product>> watchLowStockProducts() {
    return (select(products)..where((p) => p.stock.isSmallerOrEqual(p.alertLimit))).watch();
  }

  Future<void> seedData() async {
    await transaction(() async {
      // 1. Branches
      final branchesCount = await (selectOnly(branches)..addColumns([branches.id.count()])).map((row) => row.read(branches.id.count())).getSingle();
      if ((branchesCount ?? 0) == 0) {
        await into(branches).insert(
          BranchesCompanion.insert(
            name: 'الفرع الرئيسي',
            code: 'MAIN',
            isActive: const Value(true),
          ),
        );
      }

      // 2. Currencies
      final currenciesCount = await (selectOnly(currencies)..addColumns([currencies.id.count()])).map((row) => row.read(currencies.id.count())).getSingle();
      if ((currenciesCount ?? 0) == 0) {
        await batch((b) {
          b.insert(currencies, CurrenciesCompanion.insert(
            code: 'SAR',
            name: 'ريال سعودي',
            isBase: const Value(true),
            exchangeRate: const Value(1.0),
          ));
          b.insert(currencies, CurrenciesCompanion.insert(
            code: 'USD',
            name: 'دولار أمريكي',
            isBase: const Value(false),
            exchangeRate: const Value(3.75),
          ));
        });
      }

      // 3. Warehouses
      final warehousesCount = await (selectOnly(warehouses)..addColumns([warehouses.id.count()])).map((row) => row.read(warehouses.id.count())).getSingle();
      if ((warehousesCount ?? 0) == 0) {
        await into(warehouses).insert(
          WarehousesCompanion.insert(
            name: 'المستودع الرئيسي',
            isDefault: const Value(true),
          ),
        );
      }

      // 4. Categories
      final categoriesCount = await (selectOnly(categories)..addColumns([categories.id.count()])).map((row) => row.read(categories.id.count())).getSingle();
      if ((categoriesCount ?? 0) == 0) {
        await batch((b) {
          b.insert(categories, CategoriesCompanion.insert(name: 'مواد غذائية', code: const Value('FOOD')));
          b.insert(categories, CategoriesCompanion.insert(name: 'منظفات', code: const Value('CLEAN')));
        });
      }

      // 5. Suppliers
      final suppliersCount = await (selectOnly(suppliers)..addColumns([suppliers.id.count()])).map((row) => row.read(suppliers.id.count())).getSingle();
      if ((suppliersCount ?? 0) == 0) {
        await into(suppliers).insert(
          SuppliersCompanion.insert(name: 'مورد عام', isActive: const Value(true)),
        );
      }

      // 6. Customers
      final customersCount = await (selectOnly(customers)..addColumns([customers.id.count()])).map((row) => row.read(customers.id.count())).getSingle();
      if ((customersCount ?? 0) == 0) {
        await into(customers).insert(
          CustomersCompanion.insert(
            name: 'عميل نقدي',
            isQuickCustomer: const Value(true),
            isActive: const Value(true),
          ),
        );
      }

      // 8. GL Accounts
      await _seedGLAccounts();

      // 9. Posting Profiles
      await _seedPostingProfiles();

      // 10. Accounting Periods
      final periodsCount = await (selectOnly(accountingPeriods)..addColumns([accountingPeriods.id.count()])).map((row) => row.read(accountingPeriods.id.count())).getSingle();
      if ((periodsCount ?? 0) == 0) {
        await into(accountingPeriods).insert(
          AccountingPeriodsCompanion.insert(
            name: 'مايو 2026',
            startDate: DateTime(2026, 5, 1),
            endDate: DateTime(2026, 5, 31),
            status: const Value('OPEN'),
          ),
        );
      }
    });
  }

  Future<void> _seedGLAccounts() async {
    final countExp = gLAccounts.id.count();
    final countQuery = selectOnly(gLAccounts)..addColumns([countExp]);
    final accountsCount = await countQuery.map((row) => row.read(countExp)).getSingle();
    if ((accountsCount ?? 0) > 0) return;

    final accounts = [
      GLAccountsCompanion.insert(code: '1000', name: 'الأصول المتداولة', type: 'ASSET', isHeader: const Value(true)),
      GLAccountsCompanion.insert(code: '1010', name: 'الصندوق', type: 'ASSET'),
      GLAccountsCompanion.insert(code: '1020', name: 'البنك', type: 'ASSET'),
      GLAccountsCompanion.insert(code: '1030', name: 'العملاء', type: 'ASSET', analyticType: const Value('CLIENT')),
      GLAccountsCompanion.insert(code: '1200', name: 'مخزون البضاعة', type: 'ASSET', isHeader: const Value(true)),
      GLAccountsCompanion.insert(code: '1210', name: 'مخزون البضاعة', type: 'ASSET'),
      GLAccountsCompanion.insert(code: '2000', name: 'الخصوم المتداولة', type: 'LIABILITY', isHeader: const Value(true)),
      GLAccountsCompanion.insert(code: '2010', name: 'الموردون', type: 'LIABILITY', analyticType: const Value('SUPPLIER')),
      GLAccountsCompanion.insert(code: '2020', name: 'ضريبة القيمة المضافة', type: 'LIABILITY'),
      GLAccountsCompanion.insert(code: '3000', name: 'حقوق الملكية', type: 'EQUITY', isHeader: const Value(true)),
      GLAccountsCompanion.insert(code: '3010', name: 'رأس المال', type: 'EQUITY'),
      GLAccountsCompanion.insert(code: '3020', name: 'الأرباح المحتجزة', type: 'EQUITY'),
      GLAccountsCompanion.insert(code: '4000', name: 'الإيرادات', type: 'REVENUE', isHeader: const Value(true)),
      GLAccountsCompanion.insert(code: '4010', name: 'مبيعات البضاعة', type: 'REVENUE'),
      GLAccountsCompanion.insert(code: '4020', name: 'مردودات المبيعات', type: 'REVENUE'),
      GLAccountsCompanion.insert(code: '5000', name: 'تكلفة البضاعة المباعة', type: 'EXPENSE', isHeader: const Value(true)),
      GLAccountsCompanion.insert(code: '5010', name: 'تكلفة البضاعة المباعة', type: 'EXPENSE'),
      GLAccountsCompanion.insert(code: '5020', name: 'فرق صندوق', type: 'EXPENSE'),
      GLAccountsCompanion.insert(code: '6000', name: 'المصروفات', type: 'EXPENSE', isHeader: const Value(true)),
      GLAccountsCompanion.insert(code: '6010', name: 'مصروفات التشغيل', type: 'EXPENSE'),
    ];

    await batch((b) {
      for (var acc in accounts) {
        b.insert(gLAccounts, acc);
      }
    });
  }

  Future<void> _seedPostingProfiles() async {
    final countExp = postingProfiles.id.count();
    final countQuery = selectOnly(postingProfiles)..addColumns([countExp]);
    final profilesCount = await countQuery.map((row) => row.read(countExp)).getSingle();
    if ((profilesCount ?? 0) > 0) return;

    final gLAccountsList = await select(gLAccounts).get();
    Map<String, String> accountIdByCode = {for (var acc in gLAccountsList) acc.code: acc.id};

    if (accountIdByCode['1010'] == null || accountIdByCode['4010'] == null || accountIdByCode['5010'] == null) {
      return;
    }

    final profiles = [
      PostingProfilesCompanion.insert(
        operationType: 'SALE',
        accountType: 'CASH',
        accountId: Value(accountIdByCode['1010']),
        isActive: const Value(true),
        sequence: const Value(1),
        side: 'DEBIT',
      ),
      PostingProfilesCompanion.insert(
        operationType: 'SALE',
        accountType: 'REVENUE',
        accountId: Value(accountIdByCode['4010']),
        isActive: const Value(true),
        sequence: const Value(2),
        side: 'CREDIT',
      ),
      PostingProfilesCompanion.insert(
        operationType: 'SALE',
        accountType: 'COGS',
        accountId: Value(accountIdByCode['5010']),
        isActive: const Value(true),
        sequence: const Value(3),
        side: 'DEBIT',
      ),
      PostingProfilesCompanion.insert(
        operationType: 'SALE',
        accountType: 'INVENTORY',
        accountId: Value(accountIdByCode['1210']),
        isActive: const Value(true),
        sequence: const Value(4),
        side: 'CREDIT',
      ),
      PostingProfilesCompanion.insert(
        operationType: 'PURCHASE',
        accountType: 'INVENTORY',
        accountId: Value(accountIdByCode['1210']),
        isActive: const Value(true),
        sequence: const Value(1),
        side: 'DEBIT',
      ),
      PostingProfilesCompanion.insert(
        operationType: 'PURCHASE',
        accountType: 'CASH',
        accountId: Value(accountIdByCode['1010']),
        isActive: const Value(true),
        sequence: const Value(2),
        side: 'CREDIT',
      ),
      PostingProfilesCompanion.insert(
        operationType: 'PURCHASE',
        accountType: 'PAYABLE',
        accountId: Value(accountIdByCode['2010']),
        isActive: const Value(true),
        sequence: const Value(3),
        side: 'CREDIT',
      ),
    ];

    await batch((b) {
      for (var profile in profiles) {
        b.insert(postingProfiles, profile);
      }
    });
  }

  Future<void> ensureInitialized() async {
    // Just trigger a simple query to ensure connection and migrations are run
    selectOnly(branches)..limit(1)..get();
  }

  // DAO getters
  @override
  AccountingDao get accountingDao => AccountingDao(this);
  @override
  CustomersDao get customersDao => CustomersDao(this);
  @override
  ProductsDao get productsDao => ProductsDao(this);
  @override
  SalesDao get salesDao => SalesDao(this);
  @override
  PurchasesDao get purchasesDao => PurchasesDao(this);
  @override
  SuppliersDao get suppliersDao => SuppliersDao(this);
  @override
  UsersDao get usersDao => UsersDao(this);
  @override
  WarehousesDao get warehousesDao => WarehousesDao(this);
  @override
  GlobalUnitsDao get globalUnitsDao => GlobalUnitsDao(this);
  @override
  ProductUnitsDao get productUnitsDao => ProductUnitsDao(this);
  @override
  BomDao get bomDao => BomDao(this);
  @override
  AuditDao get auditDao => AuditDao(this);
  @override
  StockMovementDao get stockMovementDao => StockMovementDao(this);
}

LazyDatabase _openConnection() {
  debugPrint("DB: _openConnection started");
  return LazyDatabase(() async {
    try {
      debugPrint("DB: Getting application documents directory...");
      final dbFolder = await getApplicationDocumentsDirectory();
      debugPrint("DB: Documents directory: ${dbFolder.path}");
      
      final file = File(p.join(dbFolder.path, 'app_db.sqlite'));
      debugPrint("DB: Database file path: ${file.path}");

      debugPrint("DB: Applying SQLite workaround...");
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();

      final cachebase = (await getTemporaryDirectory()).path;
      sqlite.sqlite3.tempDirectory = cachebase;

      debugPrint("DB: Creating NativeDatabase...");
      final db = NativeDatabase.createInBackground(file);
      debugPrint("DB: NativeDatabase created successfully");
      return db;
    } catch (e, stack) {
      debugPrint("DB ERROR in _openConnection: $e");
      debugPrintStack(stackTrace: stack);
      rethrow;
    }
  });
}
