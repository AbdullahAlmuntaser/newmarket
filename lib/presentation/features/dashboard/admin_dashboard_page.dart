import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart' as intl;
import 'package:supermarket/core/auth/auth_provider.dart';
import 'package:supermarket/core/services/accounting_service.dart';
import 'package:supermarket/core/services/event_bus_service.dart';
import 'package:supermarket/core/utils/export_service.dart';
import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:supermarket/presentation/features/accounting/accounting_provider.dart';
import 'package:supermarket/l10n/app_localizations.dart';
import 'dart:async';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  StreamSubscription? _eventSubscription;
  AccountingDashboardData? _cachedData;

  @override
  void initState() {
    super.initState();
    _setupEventListeners();
  }

  void _setupEventListeners() {
    final eventBus = context.read<EventBusService>();
    _eventSubscription = eventBus.stream.listen((event) {
      // Refresh dashboard on relevant events
      setState(() {
        _cachedData = null; // Clear cache to force refresh
      });
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.read<AuthProvider>();
    final accountingProvider = context.watch<AccountingProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminDashboard),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'تصدير التقرير',
            onPressed: () => _exportDashboard(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => accountingProvider.refresh(),
          ),
        ],
      ),
      body: FutureBuilder<AccountingDashboardData>(
        future: accountingProvider.getDashboardData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final data = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeCard(context, auth, l10n),
                if (data.expiringBatchesCount > 0) ...[
                  const SizedBox(height: 16),
                  _buildExpiryAlert(context, data.expiringBatchesCount),
                ],
                const SizedBox(height: 24),
                _buildSummaryKPIs(context, data, l10n),
                const SizedBox(height: 24),
                _buildFinancialRatios(context, data.ratios),
                const SizedBox(height: 24),
                _buildProfitLineChart(context, data, l10n),
                const SizedBox(height: 24),
                _buildChartsRow(context, data, l10n),
                const SizedBox(height: 24),
                _buildTopProductsChart(context, data, l10n),
                const SizedBox(height: 24),
                Text(
                  l10n.quickActions,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildActionsGrid(context, l10n),
                const SizedBox(height: 24),
                _buildRecentTransactions(context, data, l10n),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFinancialRatios(
    BuildContext context,
    FinancialRatiosData ratios,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المؤشرات المالية الذكية',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildRatioIndicator(
                  context,
                  'هامش الربح الإجمالي',
                  ratios.grossProfitMargin,
                  isPercentage: true,
                  color: ratios.grossProfitMargin > 0.2
                      ? Colors.green
                      : Colors.orange,
                ),
                _buildRatioIndicator(
                  context,
                  'هامش الربح الصافي',
                  ratios.netProfitMargin,
                  isPercentage: true,
                  color: ratios.netProfitMargin > 0.1
                      ? Colors.blue
                      : Colors.redAccent,
                ),
                _buildRatioIndicator(
                  context,
                  'نسبة السيولة',
                  ratios.currentRatio,
                  isPercentage: false,
                  color: ratios.currentRatio >= 1.5
                      ? Colors.teal
                      : Colors.deepOrange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatioIndicator(
    BuildContext context,
    String label,
    double value, {
    required bool isPercentage,
    required Color color,
  }) {
    final displayValue = isPercentage
        ? '${(value * 100).toStringAsFixed(1)}%'
        : value.toStringAsFixed(2);
    final progress = isPercentage
        ? value.clamp(0.0, 1.0)
        : (value / 3.0).clamp(0.0, 1.0);

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 70,
              height: 70,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 8,
                backgroundColor: color.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Text(
              displayValue,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 80,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildExpiryAlert(BuildContext context, int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'تنبيه: يوجد $count شحنات/دفعات ستنتهي صلاحيتها خلال 30 يوماً.',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => context.push('/products'),
            child: const Text('عرض'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportDashboard(BuildContext context) async {
    final db = context.read<AppDatabase>();
    final exportService = ExportService(db);
    
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Export products to CSV
      final filePath = await exportService.exportProducts();
      
      // Close loading dialog
      if (context.mounted) Navigator.pop(context);
      
      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير التقرير بنجاح: $filePath'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if still open
      if (context.mounted) Navigator.pop(context);
      
      // Show error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل التصدير: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildWelcomeCard(
    BuildContext context,
    AuthProvider auth,
    AppLocalizations l10n,
  ) {
    return Card(
      elevation: 0,
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(
                Icons.admin_panel_settings,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.welcomeAdmin}, ${auth.currentUser?.fullName ?? 'Admin'}!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.adminDashboardDescription,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimaryContainer.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryKPIs(
    BuildContext context,
    AccountingDashboardData data,
    AppLocalizations l10n,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900 ? 4 : 2;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          childAspectRatio: constraints.maxWidth > 900 ? 2.5 : 2.0,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _buildKPICard(
              context,
              'مبيعات اليوم',
              data.dailyRevenue.isNotEmpty ? data.dailyRevenue.last.value : 0.0,
              Icons.trending_up,
              Colors.green,
            ),
            _buildKPICard(
              context,
              'مشتريات اليوم',
              data.dailyExpenses.isNotEmpty ? data.dailyExpenses.last.value : 0.0,
              Icons.shopping_cart,
              Colors.blue,
            ),
            _buildKPICard(
              context,
              l10n.netIncome,
              data.netIncome,
              Icons.account_balance_wallet,
              Colors.blue,
            ),
            _buildKPICard(
              context,
              l10n.totalAssets,
              data.totalAssets,
              Icons.pie_chart,
              Colors.orange,
            ),
          ],
        );
      },
    );
  }

  Widget _buildKPICard(
    BuildContext context,
    String label,
    double value,
    IconData icon,
    Color color,
  ) {
    final currency = intl.NumberFormat.currency(symbol: '');
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      currency.format(value),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfitLineChart(
    BuildContext context,
    AccountingDashboardData data,
    AppLocalizations l10n,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تحليل صافي الربح (7 أيام)',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(
                    show: true,
                    drawVerticalLine: false,
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < 0 ||
                              value.toInt() >= data.dailyRevenue.length) {
                            return const SizedBox();
                          }
                          return Text(
                            intl.DateFormat(
                              'E',
                            ).format(data.dailyRevenue[value.toInt()].date),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(data.dailyRevenue.length, (i) {
                        final profit =
                            data.dailyRevenue[i].value -
                            data.dailyExpenses[i].value;
                        return FlSpot(i.toDouble(), profit);
                      }),
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartsRow(
    BuildContext context,
    AccountingDashboardData data,
    AppLocalizations l10n,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _buildRevenueBarChart(context, data, l10n),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: _buildExpensePieChart(context, data, l10n),
              ),
            ],
          );
        } else {
          return Column(
            children: [
              _buildRevenueBarChart(context, data, l10n),
              const SizedBox(height: 16),
              _buildExpensePieChart(context, data, l10n),
            ],
          );
        }
      },
    );
  }

  Widget _buildRevenueBarChart(
    BuildContext context,
    AccountingDashboardData data,
    AppLocalizations l10n,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.revenue} vs ${l10n.expenses}',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _getMaxDailyValue(data) * 1.2,
                  barGroups: _generateBarGroups(data),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < 0 ||
                              value.toInt() >= data.dailyRevenue.length) {
                            return const SizedBox();
                          }
                          return Text(
                            intl.DateFormat(
                              'E',
                            ).format(data.dailyRevenue[value.toInt()].date),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getMaxDailyValue(AccountingDashboardData data) {
    double max = 100;
    for (var d in data.dailyRevenue) {
      if (d.value > max) max = d.value;
    }
    for (var d in data.dailyExpenses) {
      if (d.value > max) max = d.value;
    }
    return max;
  }

  List<BarChartGroupData> _generateBarGroups(AccountingDashboardData data) {
    return List.generate(data.dailyRevenue.length, (i) {
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: data.dailyRevenue[i].value,
            color: Colors.green,
            width: 8,
          ),
          BarChartRodData(
            toY: data.dailyExpenses[i].value,
            color: Colors.red,
            width: 8,
          ),
        ],
      );
    });
  }

  Widget _buildExpensePieChart(
    BuildContext context,
    AccountingDashboardData data,
    AppLocalizations l10n,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.operatingExpenses,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: _generatePieSections(data),
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PieChartSectionData> _generatePieSections(AccountingDashboardData data) {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.deepOrange,
      Colors.brown,
    ];
    return List.generate(data.topExpenses.length, (i) {
      final item = data.topExpenses[i];
      return PieChartSectionData(
        color: colors[i % colors.length],
        value: item.totalDebit,
        title:
            '${(item.totalDebit / (data.totalExpenses == 0 ? 1 : data.totalExpenses) * 100).toStringAsFixed(0)}%',
        radius: 50,
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    });
  }

  Widget _buildTopProductsChart(
    BuildContext context,
    AccountingDashboardData data,
    AppLocalizations l10n,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'أكثر المنتجات مبيعاً',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            if (data.topSellingProducts.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('لا توجد بيانات مبيعات حالياً'),
                ),
              )
            else
              SizedBox(
                height: 250,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY:
                        data.topSellingProducts
                            .map((e) => e.quantity)
                            .reduce((a, b) => a > b ? a : b) *
                        1.2,
                    barGroups: List.generate(data.topSellingProducts.length, (
                      i,
                    ) {
                      final item = data.topSellingProducts[i];
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: item.quantity,
                            color: Theme.of(context).colorScheme.primary,
                            width: 20,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ],
                      );
                    }),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            if (value.toInt() < 0 ||
                                value.toInt() >=
                                    data.topSellingProducts.length) {
                              return const SizedBox();
                            }
                            final name = data
                                .topSellingProducts[value.toInt()]
                                .productName;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Transform.rotate(
                                angle: -0.5,
                                child: SizedBox(
                                  width: 60,
                                  child: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 9),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            );
                          },
                          reservedSize: 40,
                        ),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                        ),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    gridData: const FlGridData(
                      show: true,
                      drawVerticalLine: false,
                    ),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsGrid(BuildContext context, AppLocalizations l10n) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildActionCard(
          context,
          l10n.pos,
          Icons.point_of_sale,
          Colors.green,
          () => context.go('/pos'),
        ),
        _buildActionCard(
          context,
          l10n.accounting,
          Icons.account_balance,
          Colors.brown,
          () => context.go('/accounting/coa'),
        ),
        _buildActionCard(
          context,
          l10n.viewReports,
          Icons.analytics,
          Colors.indigo,
          () => context.go('/reports'),
        ),
        _buildActionCard(
          context,
          'الموظفين',
          Icons.badge,
          Colors.deepPurple,
          () => context.push('/hr/employees'),
        ),
        _buildActionCard(
          context,
          l10n.expenses,
          Icons.money_off,
          Colors.redAccent,
          () => context.push('/accounting/expenses'),
        ),
        _buildActionCard(
          context,
          'المخزون',
          Icons.inventory,
          Colors.blueGrey,
          () => context.push('/inventory/transfer'),
        ),
      ],
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: 110,
      height: 100,
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentTransactions(
    BuildContext context,
    AccountingDashboardData data,
    AppLocalizations l10n,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              l10n.generalLedger,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: data.recentTransactions.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = data.recentTransactions[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getEntryColor(
                    entry.referenceType,
                  ).withOpacity(0.1),
                  child: Icon(
                    _getEntryIcon(entry.referenceType),
                    color: _getEntryColor(entry.referenceType),
                    size: 20,
                  ),
                ),
                title: Text(
                  entry.description,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  intl.DateFormat.yMMMd().format(entry.date),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => context.go('/accounting/general-ledger'),
              );
            },
          ),
          if (data.recentTransactions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: Text('لا توجد معاملات مؤخراً')),
            ),
        ],
      ),
    );
  }

  IconData _getEntryIcon(String? type) {
    switch (type) {
      case 'SALE':
        return Icons.shopping_cart;
      case 'PURCHASE':
        return Icons.inventory;
      case 'EXPENSE':
        return Icons.money_off;
      default:
        return Icons.article;
    }
  }

  Color _getEntryColor(String? type) {
    switch (type) {
      case 'SALE':
        return Colors.green;
      case 'PURCHASE':
        return Colors.blue;
      case 'EXPENSE':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
