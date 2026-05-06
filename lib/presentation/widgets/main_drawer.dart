import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supermarket/core/auth/auth_provider.dart';
import 'package:supermarket/l10n/app_localizations.dart';

class MainDrawer extends StatelessWidget {
  const MainDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    const Color drawerBgColor = Color(0xFF1E1E26);
    const Color dividerColor = Color(0xFF3E3E4A);

    AuthProvider authProvider;
    AppLocalizations? l10n;

    try {
      authProvider = Provider.of<AuthProvider>(context, listen: false);
      l10n = AppLocalizations.of(context);
    } catch (e) {
      return const Drawer(
        backgroundColor: drawerBgColor,
        child: Center(
          child: Icon(Icons.error_outline, color: Colors.white24, size: 40),
        ),
      );
    }

    final role = authProvider.currentUser?.role.toLowerCase() ?? 'cashier';
    final isAdmin = role == 'admin';
    final isManager = role == 'manager' || isAdmin;
    final isCashier = role == 'cashier' || isManager;

    return Drawer(
      width: 280,
      backgroundColor: drawerBgColor,
      surfaceTintColor: Colors.transparent,
      child: Column(
        children: [
          _buildHeader(context, authProvider, drawerBgColor),
          const Divider(color: dividerColor, height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  context,
                  icon: Icons.grid_view_rounded,
                  title: l10n?.dashboard ?? 'لوحة التحكم',
                  onTap: () => context.go('/'),
                ),
                if (isAdmin)
                  _buildSubItem(context, 'لوحة تحكم المدير', '/admin-dashboard'),
                _buildDrawerItem(
                  context,
                  icon: Icons.point_of_sale_rounded,
                  title: l10n?.pos ?? 'نقطة البيع',
                  onTap: () => context.push('/pos'),
                ),
                if (isCashier) ...[
                  _buildExpansionGroup(
                    context,
                    icon: Icons.history_rounded,
                    title: l10n?.sales ?? 'المبيعات',
                    children: [
                      _buildSubItem(context, l10n?.sales ?? 'سجل المبيعات', '/sales'),
                      _buildSubItem(
                        context,
                        'فاتورة مبيعات جديدة',
                        '/sales/invoice',
                      ),
                    ],
                  ),
                  _buildExpansionGroup(
                    context,
                    icon: Icons.assignment_return_rounded,
                    title: l10n?.returns ?? 'المرتجعات',
                    children: [
                      _buildSubItem(
                        context,
                        l10n?.salesReturns ?? 'مرتجعات المبيعات',
                        '/sales/returns',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.purchaseReturns ?? 'مرتجعات المشتريات',
                        '/purchases/returns',
                      ),
                    ],
                  ),
                ],
                if (isManager) ...[
                  const _DrawerDivider(),
                  _buildExpansionGroup(
                    context,
                    icon: Icons.inventory_2_rounded,
                    title: l10n?.products ?? 'المنتجات',
                    children: [
                      _buildSubItem(context, 'قائمة المنتجات', '/products'),
                      _buildSubItem(
                        context,
                        l10n?.categories ?? 'الفئات',
                        '/categories',
                      ),
                      _buildSubItem(
                        context,
                        'إدارة التصنيع (BOM)',
                        '/manufacturing/bom',
                      ),
                      _buildSubItem(
                        context,
                        'المنتجات أوشكت على النفاد',
                        '/low-stock',
                      ),
                    ],
                  ),
                  _buildExpansionGroup(
                    context,
                    icon: Icons.shopping_cart_rounded,
                    title: l10n?.purchases ?? 'المشتريات',
                    children: [
                      _buildSubItem(context, 'قائمة المشتريات', '/purchases'),
                      _buildSubItem(
                        context,
                        l10n?.newPurchase ?? 'إضافة عملية شراء',
                        '/purchases/new',
                      ),
                      _buildSubItem(
                        context,
                        'أوامر الشراء',
                        '/purchases/orders',
                      ),
                      _buildSubItem(
                        context,
                        'دفعات الموردين',
                        '/suppliers/payments',
                      ),
                      _buildSubItem(
                        context,
                        'أداء الموردين',
                        '/purchases/performance',
                      ),
                      _buildSubItem(
                        context,
                        'مرتجعات المشتريات',
                        '/purchases/returns',
                      ),
                    ],
                  ),
                  _buildDrawerItem(
                    context,
                    icon: Icons.swap_horiz_rounded,
                    title: 'التحويل المخزني',
                    onTap: () => context.push('/inventory/transfer'),
                  ),
                ],

                const _DrawerDivider(),

                _buildExpansionGroup(
                  context,
                  icon: Icons.people_alt_rounded,
                  title: l10n?.customers ?? 'العملاء',
                  children: [
                    _buildSubItem(context, 'قائمة العملاء', '/customers'),
                  ],
                ),

                if (isManager) ...[
                  _buildExpansionGroup(
                    context,
                    icon: Icons.local_shipping_rounded,
                    title: l10n?.suppliers ?? 'الموردين',
                    children: [
                      _buildSubItem(context, 'قائمة الموردين', '/suppliers'),
                    ],
                  ),
                ],
                if (isManager) ...[
                  const _DrawerDivider(),
                  _buildExpansionGroup(
                    context,
                    icon: Icons.inventory_2_rounded,
                    title: 'إدارة المخزون',
                    children: [
                      _buildSubItem(
                        context,
                        l10n?.noWarehousesFound ?? 'المستودعات',
                        '/inventory/warehouses',
                      ),
                      _buildSubItem(
                        context,
                        'مدير المستودع',
                        '/inventory/warehouse-manager',
                      ),
                      _buildSubItem(
                        context,
                        'التحويل المخزني',
                        '/inventory/transfer',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.inventoryAudit ?? 'جرد المخزون',
                        '/inventory/stock-take',
                      ),
                      _buildSubItem(
                        context,
                        'تنبيهات المخزون',
                        '/inventory/low-stock-alert',
                      ),
                      _buildSubItem(
                        context,
                        'إدارة الورديات',
                        '/inventory/shifts',
                      ),
                    ],
                  ),
                  _buildExpansionGroup(
                    context,
                    icon: Icons.badge_rounded,
                    title: 'الموارد البشرية',
                    children: [
                      _buildSubItem(context, 'إدارة الموظفين', '/hr/employees'),
                      _buildSubItem(context, 'مسيرات الرواتب', '/hr/payroll'),
                    ],
                  ),
                  _buildExpansionGroup(
                    context,
                    icon: Icons.assessment_rounded,
                    title: l10n?.reports ?? 'التقارير',
                    children: [
                      _buildSubItem(
                        context,
                        'تقارير المبيعات',
                        '/reports/sales',
                      ),
                      _buildSubItem(
                        context,
                        'ربحية المنتجات',
                        '/reports/profitability',
                      ),
                      _buildSubItem(
                        context,
                        'إجمالي الربح',
                        '/reports/gross-profit',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.inventoryReports ?? 'تقارير المخزون',
                        '/reports/inventory',
                      ),
                      _buildSubItem(
                        context,
                        'جرد المستودعات',
                        '/reports/inventory-audit',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.vatReport ?? 'تقرير ضريبة القيمة المضافة',
                        '/reports/vat',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.agingReport ?? 'تقرير أعمار الديون',
                        '/reports/aging',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.cashFlowForecast ?? 'توقعات التدفق النقدي',
                        '/reports/cash-flow',
                      ),
                      _buildSubItem(context, l10n?.auditLog ?? 'سجل التدقيق', '/reports/audit'),
                    ],
                  ),
                ],
                if (isAdmin) ...[
                  const _DrawerDivider(),
                  _buildExpansionGroup(
                    context,
                    icon: Icons.account_balance_rounded,
                    title: l10n?.accounting ?? 'المحاسبة',
                    children: [
                      _buildSubItem(
                        context,
                        'الفترات المحاسبية',
                        '/accounting/periods',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.chartOfAccounts ?? 'شجرة الحسابات',
                        '/accounting/coa',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.generalLedger ?? 'دفتر الأستاذ',
                        '/accounting/general-ledger',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.balanceSheet ?? 'الميزانية العمومية',
                        '/accounting/balance-sheet',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.incomeStatement ?? 'قائمة الدخل',
                        '/accounting/income-statement',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.cashFlow ?? 'التدفقات النقدية',
                        '/accounting/cash-flow',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.trialBalance ?? 'ميزان المراجعة',
                        '/accounting/trial-balance',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.expenses ?? 'المصروفات',
                        '/accounting/expenses',
                      ),
                      _buildSubItem(
                        context,
                        'إدارة الشيكات',
                        '/accounting/checks',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.fixedAssets ?? 'الأصول الثابتة',
                        '/accounting/fixed-assets',
                      ),
                      _buildSubItem(
                        context,
                        'قيود يدوية',
                        '/accounting/manual-journal',
                      ),
                      _buildSubItem(
                        context,
                        'سندات القبض والصرف',
                        '/accounting/manual-voucher',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.reconciliation ?? 'التسويات',
                        '/accounting/reconciliation',
                      ),
                      _buildSubItem(
                        context,
                        'ورديات الكاشير',
                        '/accounting/shifts',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.costCenters ?? 'مراكز التكلفة',
                        '/accounting/cost-centers',
                      ),
                      _buildSubItem(
                        context,
                        'الميزانيات التقديرية',
                        '/accounting/budgets',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.apInvoices ?? 'فواتير الذمم الدائنة',
                        '/accounting/ap-invoices',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.supplierLedger ?? 'كشف حساب المورد',
                        '/accounting/supplier-ledger',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.arInvoices ?? 'فواتير الذمم المدينة',
                        '/accounting/ar-invoices',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.customerLedger ?? 'كشف حساب العميل',
                        '/accounting/customer-ledger',
                      ),
                      ],
                      ),                  _buildExpansionGroup(
                    context,
                    icon: Icons.settings_rounded,
                    title: 'الإعدادات',
                    children: [
                      _buildSubItem(context, l10n?.staffManagement ?? 'إدارة المستخدمين', '/users'),
                      _buildSubItem(
                        context,
                        'أسعار العملات',
                        '/settings/currency-rates',
                      ),
                      _buildSubItem(
                        context,
                        'الصلاحيات',
                        '/settings/permissions',
                      ),
                      _buildSubItem(
                        context,
                        l10n?.backupAndSync ?? 'النسخ الاحتياطي',
                        '/settings/backup',
                      ),
                      _buildSubItem(context, l10n?.cloudSync ?? 'المزامنة', '/sync'),
                      _buildSubItem(
                        context,
                        'إعدادات الطابعة',
                        '/settings/printer',
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 20),
                _buildDrawerItem(
                  context,
                  icon: Icons.logout_rounded,
                  title: l10n?.logout ?? 'تسجيل الخروج',
                  onTap: () {
                    authProvider.logout();
                    context.go('/login');
                  },
                  isDestructive: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AuthProvider authProvider,
    Color bgColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 50, bottom: 20, left: 20, right: 20),
      color: bgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 35,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.person_rounded,
              size: 45,
              color: Color(0xFF2196F3),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            authProvider.currentUser?.fullName ?? 'System Admin',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            authProvider.currentUser?.role ?? 'admin',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      leading: Icon(
        icon,
        color: isDestructive ? Colors.redAccent : Colors.white70,
        size: 24,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.redAccent : Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
      ),
      visualDensity: const VisualDensity(vertical: -1),
    );
  }

  Widget _buildExpansionGroup(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(icon, color: Colors.white70, size: 24),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
        iconColor: Colors.white,
        collapsedIconColor: Colors.white70,
        children: children,
      ),
    );
  }

  Widget _buildSubItem(BuildContext context, String title, String route) {
    return ListTile(
      contentPadding: const EdgeInsets.only(right: 55, left: 16),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white60, fontSize: 14),
      ),
      onTap: () {
        Navigator.pop(context);
        context.push(route);
      },
    );
  }
}

class _DrawerDivider extends StatelessWidget {
  const _DrawerDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      color: Color(0xFF3E3E4A),
      height: 20,
      thickness: 1,
      indent: 15,
      endIndent: 15,
    );
  }
}
