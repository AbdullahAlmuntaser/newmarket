import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as drift;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supermarket/l10n/app_localizations.dart';
import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:supermarket/presentation/widgets/main_drawer.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final int _pageSize = 20;
  int _currentPage = 0;
  bool _isLoadingMore = false;
  
  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.purchasesHistory),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _currentPage = 0),
          ),
        ],
      ),
      drawer: const MainDrawer(),
      body: FutureBuilder<List<PurchasesWithSupplierAndWarehouse>>(
        future: _fetchPurchases(db),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _currentPage == 0) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text('حدث خطأ في تحميل البيانات', style: TextStyle(color: Colors.red[700])),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }
          
          final allPurchases = snapshot.data ?? [];
          if (allPurchases.isEmpty && _currentPage == 0) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(l10n.noPurchasesFound, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                ],
              ),
            );
          }

          final totalPages = (allPurchases.length / _pageSize).ceil();
          final start = _currentPage * _pageSize;
          final end = (start + _pageSize < allPurchases.length)
              ? start + _pageSize
              : allPurchases.length;
          final purchases = allPurchases.sublist(start, end);

          return Column(
            children: [
              // شريط معلومات
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'إجمالي ${allPurchases.length} عملية شراء',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'صفحة ${_currentPage + 1} من $totalPages',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: ListView.separated(
                  itemCount: purchases.length + (_isLoadingMore ? 1 : 0),
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index >= purchases.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    
                    final item = purchases[index];
                    final purchase = item.purchase;
                    final supplier = item.supplier;
                    final warehouse = item.warehouse;
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getStatusColor(purchase.status).withAlpha(26),
                          child: Icon(
                            _getStatusIcon(purchase.status),
                            color: _getStatusColor(purchase.status),
                          ),
                        ),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              supplier?.name ?? l10n.walkInSupplier,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            _buildStatusChip(context, purchase.status, l10n),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(DateFormat.yMMMd().format(purchase.date)),
                            if (warehouse != null)
                              Text(
                                '${l10n.warehouse}: ${warehouse.name}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            Text(
                              '#${purchase.id.substring(0, 8)}',
                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${NumberFormat.currency(symbol: '', decimalDigits: 2).format(purchase.total)} ${purchase.currencyId ?? 'USD'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (purchase.isCredit)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'آجل',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange[800],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        onTap: () => context.push('/purchases/details/${purchase.id}'),
                        onLongPress: () => _showPurchaseActions(context, purchase),
                      ),
                    );
                  },
                ),
              ),
              
              if (totalPages > 1) _buildPaginationControls(totalPages),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/purchases/new'),
        label: Text(l10n.newPurchase),
        icon: const Icon(Icons.add),
      ),
    );
  }
  
  Color _getStatusColor(String status) {
    switch (status) {
      case 'DRAFT': return Colors.grey;
      case 'ORDERED': return Colors.blue;
      case 'RECEIVED': return Colors.green;
      case 'CANCELLED': return Colors.red;
      default: return Colors.grey;
    }
  }
  
  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'DRAFT': return Icons.edit_note;
      case 'ORDERED': return Icons.local_shipping;
      case 'RECEIVED': return Icons.check_circle;
      case 'CANCELLED': return Icons.cancel;
      default: return Icons.help_outline;
    }
  }
  
  void _showPurchaseActions(BuildContext context, Purchase purchase) {
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
                context.push('/purchases/details/${purchase.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('طباعة'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('جاري تحضير الطباعة...')),
                );
              },
            ),
            if (purchase.status == 'DRAFT')
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.orange),
                title: const Text('تعديل', style: TextStyle(color: Colors.orange)),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Navigate to edit page
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ميزة التعديل قيد التطوير')),
                  );
                },
              ),
            if (purchase.status == 'DRAFT')
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('حذف', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(context, purchase);
                },
              ),
          ],
        ),
      ),
    );
  }
  
  void _confirmDelete(BuildContext context, Purchase purchase) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف عملية الشراء #${purchase.id.substring(0, 8)}؟'),
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

  Future<List<PurchasesWithSupplierAndWarehouse>> _fetchPurchases(
    AppDatabase db,
  ) async {
    final query = db.select(db.purchases).join([
      drift.leftOuterJoin(
        db.suppliers,
        db.suppliers.id.equalsExp(db.purchases.supplierId),
      ),
      drift.leftOuterJoin(
        db.warehouses,
        db.warehouses.id.equalsExp(db.purchases.warehouseId),
      ),
    ])..orderBy([drift.OrderingTerm.desc(db.purchases.date)]);

    final rows = await query.get();
    return rows.map((row) {
      return PurchasesWithSupplierAndWarehouse(
        purchase: row.readTable(db.purchases),
        supplier: row.readTableOrNull(db.suppliers),
        warehouse: row.readTableOrNull(db.warehouses),
      );
    }).toList();
  }

  Widget _buildStatusChip(
    BuildContext context,
    String status,
    AppLocalizations l10n,
  ) {
    Color chipColor;
    Color textColor = Colors.white;
    String label;
    switch (status) {
      case 'DRAFT':
        chipColor = Theme.of(context).colorScheme.onSurfaceVariant;
        textColor = Theme.of(context).colorScheme.onPrimary;
        label = l10n.draft;
        break;
      case 'ORDERED':
        chipColor = Theme.of(context).colorScheme.primary;
        textColor = Theme.of(context).colorScheme.onPrimary;
        label = l10n.ordered;
        break;
      case 'RECEIVED':
        chipColor = Theme.of(context).colorScheme.tertiary;
        textColor = Theme.of(context).colorScheme.onTertiary;
        label = l10n.received;
        break;
      case 'CANCELLED':
        chipColor = Theme.of(context).colorScheme.error;
        textColor = Theme.of(context).colorScheme.onError;
        label = l10n.cancelled;
        break;
      default:
        chipColor = Theme.of(context).colorScheme.onSurface;
        textColor = Theme.of(context).colorScheme.onPrimary;
        label = status;
    }
    return Chip(
      label: Text(label, style: TextStyle(color: textColor, fontSize: 10)),
      backgroundColor: chipColor,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

class PurchasesWithSupplierAndWarehouse {
  final Purchase purchase;
  final Supplier? supplier;
  final Warehouse? warehouse;

  const PurchasesWithSupplierAndWarehouse({
    required this.purchase,
    this.supplier,
    this.warehouse,
  });
}
