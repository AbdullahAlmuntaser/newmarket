import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supermarket/injection_container.dart' as di;
import 'package:supermarket/core/auth/auth_provider.dart';
import 'package:supermarket/presentation/features/home/home_page.dart';
import 'package:supermarket/presentation/features/auth/login_page.dart';
import 'package:supermarket/presentation/features/dashboard/dashboard_page.dart';
import 'package:supermarket/presentation/features/dashboard/admin_dashboard_page.dart';
import 'package:supermarket/presentation/features/pos/pos_page.dart';
import 'package:supermarket/presentation/features/sales/sales_history_page.dart';
import 'package:supermarket/presentation/features/sales/sales_invoice_page.dart';
import 'package:supermarket/presentation/features/sales/sales_return_page.dart';
import 'package:supermarket/presentation/features/sales/add_sales_return_page.dart';
import 'package:supermarket/presentation/features/returns/returns_page.dart';
import 'package:supermarket/presentation/features/returns/create_return_page.dart';
import 'package:supermarket/presentation/features/products/products_page.dart';
import 'package:supermarket/presentation/features/products/categories_page.dart';
import 'package:supermarket/presentation/features/products/unit_conversion_page.dart';
import 'package:supermarket/presentation/features/inventory/stock_transfer_page.dart';
import 'package:supermarket/presentation/features/inventory/warehouse_management_page.dart';
import 'package:supermarket/presentation/features/inventory/stock_take_page.dart';
import 'package:supermarket/presentation/features/inventory/low_stock_alert_page.dart';
import 'package:supermarket/presentation/features/inventory/warehouse_manager_page.dart';
import 'package:supermarket/presentation/features/manufacturing/bom_management_page.dart';
import 'package:supermarket/presentation/features/hr/employees_page.dart';
import 'package:supermarket/presentation/features/hr/payroll_page.dart';
import 'package:supermarket/presentation/features/customers/customers_page.dart';
import 'package:supermarket/presentation/features/customers/customer_statement_page.dart';
import 'package:supermarket/presentation/features/suppliers/suppliers_page.dart';
import 'package:supermarket/presentation/features/suppliers/supplier_statement_page.dart';
import 'package:supermarket/presentation/features/suppliers/add_supplier_payment_page.dart';
import 'package:supermarket/presentation/features/suppliers/supplier_payments_page.dart';
import 'package:supermarket/presentation/features/purchases/purchases_page.dart';
import 'package:supermarket/presentation/features/purchases/add_purchase_page.dart';
import 'package:supermarket/presentation/features/purchases/purchase_orders_page.dart';
import 'package:supermarket/presentation/features/purchases/purchase_details_page.dart';
import 'package:supermarket/presentation/features/purchases/purchase_return_page.dart';
import 'package:supermarket/presentation/features/purchases/add_purchase_return_page.dart';
import 'package:supermarket/presentation/features/accounting/chart_of_accounts_page.dart';
import 'package:supermarket/presentation/features/accounting/general_ledger_page.dart';
import 'package:supermarket/presentation/features/accounting/balance_sheet_page.dart';
import 'package:supermarket/presentation/features/accounting/income_statement_page.dart';
import 'package:supermarket/presentation/features/accounting/cash_flow_page.dart';
import 'package:supermarket/presentation/features/accounting/trial_balance_page.dart';
import 'package:supermarket/presentation/features/accounting/expenses_page.dart';
import 'package:supermarket/presentation/features/accounting/fixed_assets_page.dart';
import 'package:supermarket/presentation/features/accounting/manual_journal_entry_page.dart';
import 'package:supermarket/presentation/features/accounting/manual_voucher_page.dart';
import 'package:supermarket/presentation/features/accounting/reconciliation_page.dart';
import 'package:supermarket/presentation/features/accounting/cost_centers_page.dart';
import 'package:supermarket/presentation/features/accounting/budgets_page.dart';
import 'package:supermarket/presentation/features/accounting/ap_invoices_page.dart';
import 'package:supermarket/presentation/features/accounting/supplier_ledger_page.dart';
import 'package:supermarket/presentation/features/accounting/ar_invoices_page.dart';
import 'package:supermarket/presentation/features/accounting/customer_ledger_page.dart';
import 'package:supermarket/presentation/features/accounting/accounting_periods_page.dart';
import 'package:supermarket/presentation/features/accounting/shifts_page.dart';
import 'package:supermarket/presentation/features/accounting/checks_page.dart';
import 'package:supermarket/presentation/features/accounting/cost_centers_page.dart';
import 'package:supermarket/presentation/features/accounting/ap_invoices_page.dart';
import 'package:supermarket/presentation/features/accounting/supplier_ledger_page.dart';
import 'package:supermarket/presentation/features/accounting/ar_invoices_page.dart';
import 'package:supermarket/presentation/features/accounting/customer_ledger_page.dart';
import 'package:supermarket/presentation/features/reports/sales_reports_page.dart';
import 'package:supermarket/presentation/features/reports/product_profitability_page.dart';
import 'package:supermarket/presentation/features/reports/profitability_report_page.dart';
import 'package:supermarket/presentation/features/reports/inventory_reports_screen.dart';
import 'package:supermarket/presentation/features/reports/inventory_audit_page.dart';
import 'package:supermarket/presentation/features/reports/vat_report_page.dart';
import 'package:supermarket/presentation/features/reports/audit_log_page.dart';
import 'package:supermarket/presentation/features/reports/aging_report_page.dart';
import 'package:supermarket/presentation/features/reports/cash_flow_forecast_page.dart';
import 'package:supermarket/presentation/features/auth/staff_management_page.dart';
import 'package:supermarket/presentation/features/settings/backup_page.dart';
import 'package:supermarket/presentation/features/settings/permissions_management_page.dart';
import 'package:supermarket/presentation/features/settings/currency_rates_page.dart';
import 'package:supermarket/presentation/features/settings/sync_page.dart';
import 'package:supermarket/presentation/features/reports/printer_settings_page.dart';
import 'package:supermarket/presentation/features/home/low_stock_products_page.dart';
import 'package:supermarket/presentation/features/purchases/supplier_performance_page.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: di.sl<AuthProvider>(),
  redirect: (context, state) {
    try {
      final authProvider = di.sl<AuthProvider>();
      
      final isAuthenticated = authProvider.isAuthenticated;
      final isLoggingIn = state.matchedLocation == '/login';

      if (!isAuthenticated && !isLoggingIn) return '/login';
      if (isAuthenticated && isLoggingIn) return '/';

      if (isAuthenticated && authProvider.currentUser != null) {
        final userId = authProvider.currentUser!.id;
        final location = state.matchedLocation;
        
        if (location.startsWith('/reports') && userId.isNotEmpty) {
          return '/';
        }
        
        if ((location == '/users' || location == '/settings/permissions' || location == '/sync') && userId.isNotEmpty) {
          return '/';
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('Router redirect error: $e');
      return '/login';
    }
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomePage()),
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
    GoRoute(path: '/dashboard', builder: (context, state) => const DashboardPage(currentUserId: 'admin')),
    GoRoute(path: '/admin-dashboard', builder: (context, state) => const AdminDashboardPage()),
    GoRoute(path: '/pos', builder: (context, state) => const PosPage()),
    GoRoute(path: '/sales', builder: (context, state) => const SalesHistoryPage()),
    GoRoute(path: '/sales/invoice', builder: (context, state) => const SalesInvoicePage()),
    GoRoute(path: '/sales/returns', builder: (context, state) => const SalesReturnPage()),
    GoRoute(path: '/sales/returns/new', builder: (context, state) => AddSalesReturnPage(saleId: state.extra as String?)),
    GoRoute(path: '/returns', builder: (context, state) => const ReturnsPage()),
    GoRoute(path: '/returns/new', builder: (context, state) => const CreateReturnPage(type: ReturnType.sale)),
    GoRoute(path: '/products', builder: (context, state) => const ProductsPage()),
    GoRoute(path: '/products/unit-conversion/:id', builder: (context, state) => UnitConversionPage(productId: state.pathParameters['id']!, productName: state.extra as String? ?? 'Product')),
    GoRoute(path: '/categories', builder: (context, state) => const CategoriesPage()),
    GoRoute(path: '/low-stock', builder: (context, state) => const LowStockProductsPage()),
    GoRoute(path: '/inventory/transfer', builder: (context, state) => const StockTransferPage()),
    GoRoute(path: '/inventory/warehouses', builder: (context, state) => const WarehouseManagementPage()),
    GoRoute(path: '/inventory/stock-take', builder: (context, state) => const StockTakePage()),
    GoRoute(path: '/inventory/low-stock-alert', builder: (context, state) => const LowStockAlertPage()),
    GoRoute(path: '/inventory/warehouse-manager', builder: (context, state) => const WarehouseManagerPage()),
    GoRoute(path: '/inventory/shifts', builder: (context, state) => const ShiftsPage()),
    GoRoute(path: '/manufacturing/bom', builder: (context, state) => const BomManagementPage()),
    GoRoute(path: '/hr/employees', builder: (context, state) => const EmployeesPage()),
    GoRoute(path: '/hr/payroll', builder: (context, state) => const PayrollPage()),
    GoRoute(path: '/customers', builder: (context, state) => const CustomersPage()),
    GoRoute(path: '/customers/statement/:id', builder: (context, state) => CustomerStatementPage(customerId: state.pathParameters['id']!)),
    GoRoute(path: '/suppliers', builder: (context, state) => const SuppliersPage()),
    GoRoute(path: '/suppliers/statement/:id', builder: (context, state) => SupplierStatementPage(supplier: state.extra as Supplier)),
    GoRoute(path: '/suppliers/payments', builder: (context, state) => const SupplierPaymentsPage()),
    GoRoute(path: '/suppliers/payment', builder: (context, state) => AddSupplierPaymentPage(supplier: state.extra as Supplier)),
    GoRoute(path: '/purchases', builder: (context, state) => const PurchasesPage()),
    GoRoute(path: '/purchases/new', builder: (context, state) => const AddPurchasePage()),
    GoRoute(path: '/purchases/orders', builder: (context, state) => const PurchaseOrdersPage()),
    GoRoute(path: '/purchases/performance', builder: (context, state) => const SupplierPerformancePage()),
    GoRoute(path: '/purchases/details/:id', builder: (context, state) => PurchaseDetailsPage(purchaseId: state.pathParameters['id']!)),
    GoRoute(path: '/purchases/returns', builder: (context, state) => const PurchaseReturnPage()),
    GoRoute(path: '/purchases/returns/new', builder: (context, state) => const AddPurchaseReturnPage()),
    GoRoute(path: '/accounting/coa', builder: (context, state) => const ChartOfAccountsPage()),
    GoRoute(path: '/accounting/general-ledger', builder: (context, state) => const GeneralLedgerPage()),
    GoRoute(path: '/accounting/balance-sheet', builder: (context, state) => const BalanceSheetPage()),
    GoRoute(path: '/accounting/income-statement', builder: (context, state) => const IncomeStatementPage()),
    GoRoute(path: '/accounting/cash-flow', builder: (context, state) => const CashFlowPage()),
    GoRoute(path: '/accounting/trial-balance', builder: (context, state) => const TrialBalancePage()),
    GoRoute(path: '/accounting/expenses', builder: (context, state) => const ExpensesPage()),
    GoRoute(path: '/accounting/fixed-assets', builder: (context, state) => const FixedAssetsPage()),
    GoRoute(path: '/accounting/manual-journal', builder: (context, state) => const ManualJournalEntryPage()),
    GoRoute(path: '/accounting/manual-voucher', builder: (context, state) => ManualVoucherPage(isReceipt: state.uri.queryParameters['receipt'] != 'false')),
    GoRoute(path: '/accounting/reconciliation', builder: (context, state) => const ReconciliationPage()),
    GoRoute(path: '/accounting/periods', builder: (context, state) => const AccountingPeriodsPage()),
    GoRoute(path: '/accounting/shifts', builder: (context, state) => const ShiftsPage()),
    GoRoute(path: '/accounting/checks', builder: (context, state) => const ChecksPage()),
    GoRoute(path: '/accounting/cost-centers', builder: (context, state) => const CostCentersPage()),
    GoRoute(path: '/accounting/budgets', builder: (context, state) => const BudgetsPage()),
    GoRoute(path: '/accounting/ap-invoices', builder: (context, state) => const APInvoicesPage()),
    GoRoute(path: '/accounting/supplier-ledger', builder: (context, state) => const SupplierLedgerPage()),
    GoRoute(path: '/accounting/ar-invoices', builder: (context, state) => const ARInvoicesPage()),
    GoRoute(path: '/accounting/customer-ledger', builder: (context, state) => const CustomerLedgerPage()),
    GoRoute(path: '/reports/sales', builder: (context, state) => const SalesReportsPage()),
    GoRoute(path: '/reports/profitability', builder: (context, state) => const ProductProfitabilityPage()),
    GoRoute(path: '/reports/gross-profit', builder: (context, state) => const ProfitabilityReportPage()),
    GoRoute(path: '/reports/inventory', builder: (context, state) => const InventoryReportsScreen()),
    GoRoute(path: '/reports/inventory-audit', builder: (context, state) => const InventoryAuditPage()),
    GoRoute(path: '/reports/vat', builder: (context, state) => const VatReportPage()),
    GoRoute(path: '/reports/aging', builder: (context, state) => const AgingReportPage()),
    GoRoute(path: '/reports/cash-flow', builder: (context, state) => const CashFlowForecastPage()),
    GoRoute(path: '/reports/audit', builder: (context, state) => const AuditLogPage()),
    GoRoute(path: '/users', builder: (context, state) => const StaffManagementPage()),
    GoRoute(path: '/sync', builder: (context, state) => const SyncPage()),
    GoRoute(path: '/settings/backup', builder: (context, state) => const BackupPage()),
    GoRoute(path: '/settings/permissions', builder: (context, state) => const PermissionsManagementPage()),
    GoRoute(path: '/settings/currency-rates', builder: (context, state) => const CurrencyRatesPage()),
    GoRoute(path: '/settings/printer', builder: (context, state) => const PrinterSettingsPage()),
  ],
);
