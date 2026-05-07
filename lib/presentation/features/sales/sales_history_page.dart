import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';
import 'package:supermarket/l10n/app_localizations.dart';
import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:supermarket/presentation/widgets/main_drawer.dart';
import 'package:supermarket/presentation/features/sales/widgets/sale_details_bottom_sheet.dart';

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  final int _pageSize = 20;
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sales)),
      drawer: const MainDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/sales/invoice'),
        icon: const Icon(Icons.add),
        label: const Text('فاتورة مبيعات'),
      ),
      body: FutureBuilder<List<Sale>>(
        future: (db.select(
          db.sales,
        )..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)])).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final allSales = snapshot.data ?? [];
          if (allSales.isEmpty) {
            return Center(child: Text(l10n.noSalesFound));
          }

          final totalPages = (allSales.length / _pageSize).ceil();
          final start = _currentPage * _pageSize;
          final end = (start + _pageSize < allSales.length)
              ? start + _pageSize
              : allSales.length;
          final sales = allSales.sublist(start, end);

          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  itemCount: sales.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final sale = sales[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary.withAlpha(26),
                        child: Icon(
                          sale.paymentMethod == 'cash'
                              ? Icons.money
                              : Icons.credit_card,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text(l10n.saleIdLabel(sale.id.substring(0, 8))),
                      subtitle: Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(sale.createdAt),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            sale.total.toStringAsFixed(2),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            sale.syncStatus == 0 ? l10n.synced : l10n.pending,
                            style: TextStyle(
                              fontSize: 10,
                              color: sale.syncStatus == 0
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _showSaleDetails(context, db, sale, l10n),
                    );
                  },
                ),
              ),
              if (totalPages > 1) _buildPaginationControls(totalPages),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPaginationControls(int totalPages) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentPage > 0
                ? () => setState(() => _currentPage--)
                : null,
          ),
          Text('صفحة ${_currentPage + 1} من $totalPages'),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPage + 1 < totalPages
                ? () => setState(() => _currentPage++)
                : null,
          ),
        ],
      ),
    );
  }

  void _showSaleDetails(
    BuildContext context,
    AppDatabase db,
    Sale sale,
    AppLocalizations l10n,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          SaleDetailsBottomSheet(sale: sale, db: db, l10n: l10n),
    );
  }
  
  void _showSaleActions(BuildContext context, Sale sale) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text('عرض التفاصيل'),
              onTap: () {
                Navigator.pop(context);
                _showSaleDetails(context, Provider.of<AppDatabase>(context, listen: false), sale, AppLocalizations.of(context)!);
              },
            ),
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('طباعة الفاتورة'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement print functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('جاري تحضير الطباعة...')),
                );
              },
            ),
            if (sale.syncStatus == 0)
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.orange),
                title: const Text('تعديل الفاتورة', style: TextStyle(color: Colors.orange)),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Navigate to edit page
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ميزة التعديل قيد التطوير')),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('حذف الفاتورة', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, sale);
              },
            ),
          ],
        ),
      ),
    );
  }
  
  void _confirmDelete(BuildContext context, Sale sale) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف الفاتورة ${sale.id.substring(0, 8)}؟\nهذا الإجراء لا يمكن التراجع عنه.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // TODO: Implement delete functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ميزة الحذف قيد التطوير')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  
  Future<List<Sale>> _loadSales(AppDatabase db) async {
    setState(() => _isLoadingMore = true);
    
    try {
      final allSales = await (db.select(
        db.sales,
      )..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)])).get();
      
      return allSales;
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }
}
