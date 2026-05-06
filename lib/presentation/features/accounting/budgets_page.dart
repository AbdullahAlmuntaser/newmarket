import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supermarket/data/local/db/app_database.dart';
import 'package:supermarket/data/datasources/local/daos/accounting_dao.dart';

class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  List<Budget> _budgets = [];
  bool _isLoading = true;
  final NumberFormat currencyFormat = NumberFormat.currency(
    locale: 'ar_SA',
    symbol: 'ر.س',
  );

  @override
  void initState() {
    super.initState();
    _loadBudgets();
  }

  Future<void> _loadBudgets() async {
    setState(() => _isLoading = true);
    try {
      final db = Provider.of<AppDatabase>(context, listen: false);
      final dao = AccountingDao(db);
      final budgets = await dao.getAllBudgets();
      setState(() {
        _budgets = budgets;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل الميزانيات: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الميزانيات التقديرية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBudgets,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddBudgetDialog(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _budgets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_balance, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('لا توجد ميزانيات مسجلة', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text('ابدأ بإضافة ميزانية جديدة', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _budgets.length,
                  itemBuilder: (context, index) {
                    final budget = _budgets[index];
                    final variance = budget.budgetedAmount - budget.actualAmount;
                    final variancePercent = budget.budgetedAmount > 0
                        ? (variance / budget.budgetedAmount * 100)
                        : 0.0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.pie_chart,
                                  color: variance >= 0 ? Colors.green : Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    budget.name,
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: budget.status == 'active' ? Colors.green[100] : Colors.grey[300],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    budget.status == 'active' ? 'نشط' : 'مغلق',
                                    style: TextStyle(
                                      color: budget.status == 'active' ? Colors.green[800] : Colors.grey[700],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            _buildRow('الفترة', budget.period),
                            const SizedBox(height: 8),
                            _buildRow('المبلغ المقدر', currencyFormat.format(budget.budgetedAmount)),
                            const SizedBox(height: 8),
                            _buildRow('المبلغ الفعلي', currencyFormat.format(budget.actualAmount)),
                            const SizedBox(height: 8),
                            _buildRow(
                              'الانحراف',
                              '${currencyFormat.format(variance)} (${variancePercent.toStringAsFixed(1)}%)',
                              valueColor: variance >= 0 ? Colors.green : Colors.red,
                            ),
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              value: (budget.actualAmount / budget.budgetedAmount).clamp(0.0, 1.0),
                              backgroundColor: Colors.grey[300],
                              color: variance >= 0 ? Colors.green : Colors.orange,
                              minHeight: 8,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'تم استهلاك ${((budget.actualAmount / budget.budgetedAmount) * 100).clamp(0.0, 100.0).toStringAsFixed(1)}% من الميزانية',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[700],
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: valueColor ?? Colors.black,
          ),
        ),
      ],
    );
  }

  void _showAddBudgetDialog() {
    // Dialog implementation for adding new budget
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة ميزانية جديدة'),
        content: const Text('سيتم إضافة نموذج إدخال الميزانية هنا'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
