import 'dart:convert';
import 'package:drift/drift.dart';
import '../datasources/local/app_database.dart';

/// محرك تقارير متقدم لتوليد التقارير المالية والمخزنية
class ReportEngineService {
  final AppDatabase _db;

  ReportEngineService(this._db);

  /// تقرير الأصناف الأكثر مبيعاً
  Future<List<Map<String, dynamic>>> getTopSellingProducts({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 10,
  }) async {
    final query = _db.select(_db.saleItems).join([
      leftOuterJoin(
        _db.products,
        _db.products.id.equalsExp(_db.saleItems.productId),
      ),
      leftOuterJoin(
        _db.sales,
        _db.sales.id.equalsExp(_db.saleItems.saleId),
      ),
    ]);

    if (startDate != null) {
      query.addWhere((_db.sales.createdAt.isBiggerOrEqualValue(startDate)));
    }
    if (endDate != null) {
      query.addWhere((_db.sales.createdAt.isSmallerOrEqualValue(endDate)));
    }

    final results = await query.get();
    
    // تجميع البيانات حسب المنتج
    final Map<String, Map<String, dynamic>> productStats = {};
    
    for (final row in results) {
      final productId = row.readTable(_db.saleItems).productId;
      final productName = row.readTableOrNull(_db.products)?.name ?? 'Unknown';
      final quantity = row.readTable(_db.saleItems).quantity;
      final price = row.readTable(_db.saleItems).price;
      
      if (!productStats.containsKey(productId)) {
        productStats[productId] = {
          'productId': productId,
          'productName': productName,
          'totalQuantity': 0,
          'totalRevenue': 0.0,
        };
      }
      
      productStats[productId]!['totalQuantity'] += quantity;
      productStats[productId]!['totalRevenue'] += (quantity * price);
    }

    final report = productStats.values.toList()
      ..sort((a, b) => (b['totalQuantity'] as int).compareTo(a['totalQuantity'] as int));

    return report.take(limit).toList();
  }

  /// تقرير هامش الربح
  Future<List<Map<String, dynamic>>> getProfitMarginReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final salesQuery = _db.select(_db.sales);
    
    if (startDate != null) {
      salesQuery.addWhere((s) => s.createdAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      salesQuery.addWhere((s) => s.createdAt.isSmallerOrEqualValue(endDate));
    }

    final sales = await salesQuery.get();
    final report = <Map<String, dynamic>>[];

    for (final sale in sales) {
      final items = await (_db.select(_db.saleItems)
            ..where((i) => i.saleId.equals(sale.id)))
          .get();

      double totalCost = 0;
      double totalRevenue = sale.total;

      for (final item in items) {
        final product = await (_db.select(_db.products)
              ..where((p) => p.id.equals(item.productId)))
            .getSingle();
        
        totalCost += (product.costPrice * item.quantity);
      }

      final profit = totalRevenue - totalCost;
      final margin = totalRevenue > 0 ? (profit / totalRevenue) * 100 : 0;

      report.add({
        'saleId': sale.id,
        'date': sale.createdAt,
        'revenue': totalRevenue,
        'cost': totalCost,
        'profit': profit,
        'margin': margin,
      });
    }

    return report;
  }

  /// تقرير حركة صنف
  Future<List<Map<String, dynamic>>> getProductMovementReport(String productId) async {
    final movements = <Map<String, dynamic>>[];

    // حركات المبيعات
    final sales = await (_db.select(_db.saleItems)
          ..where((i) => i.productId.equals(productId)))
        .join([
      leftOuterJoin(
        _db.sales,
        _db.sales.id.equalsExp(_db.saleItems.saleId),
      ),
    ]).get();

    for (final sale in sales) {
      movements.add({
        'type': 'sale',
        'date': sale.readTable(_db.sales).createdAt,
        'quantity': -sale.readTable(_db.saleItems).quantity,
        'reference': sale.readTable(_db.sales).id,
        'balance': 0, // سيتم حسابه لاحقاً
      });
    }

    // حركات المشتريات
    final purchases = await (_db.select(_db.purchaseItems)
          ..where((i) => i.productId.equals(productId)))
        .join([
      leftOuterJoin(
        _db.purchaseOrders,
        _db.purchaseOrders.id.equalsExp(_db.purchaseItems.purchaseId),
      ),
    ]).get();

    for (final purchase in purchases) {
      movements.add({
        'type': 'purchase',
        'date': purchase.readTable(_db.purchaseOrders).createdAt,
        'quantity': purchase.readTable(_db.purchaseItems).quantity,
        'reference': purchase.readTable(_db.purchaseOrders).id,
        'balance': 0,
      });
    }

    // حركات المخزون
    final stockMovements = await (_db.select(_db.stockMovements)
          ..where((m) => m.productId.equals(productId)))
        .get();

    for (final movement in stockMovements) {
      movements.add({
        'type': movement.movementType,
        'date': movement.date,
        'quantity': movement.quantity,
        'reference': movement.id,
        'balance': 0,
      });
    }

    // ترتيب حسب التاريخ وحساب الرصيد التراكمي
    movements.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    
    int runningBalance = 0;
    for (final movement in movements) {
      runningBalance += movement['quantity'] as int;
      movement['balance'] = runningBalance;
    }

    return movements;
  }

  /// تصدير التقرير إلى JSON
  String exportToJson(List<Map<String, dynamic>> data) {
    return JsonEncoder.withIndent('  ').convert(data);
  }

  /// تصدير التقرير إلى CSV
  String exportToCsv(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return '';

    final headers = data.first.keys.join(',');
    final rows = data.map((row) => row.values.map((v) => v.toString()).join(','));
    
    return [headers, ...rows].join('\n');
  }

  /// تقرير المبيعات اليومية
  Future<List<Map<String, dynamic>>> getDailySalesReport({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final dailySales = <String, Map<String, dynamic>>{};

    final sales = await (_db.select(_db.sales)
          ..where((s) => s.createdAt.isBetweenValues(startDate, endDate)))
        .get();

    for (final sale in sales) {
      final dateKey = DateFormat('yyyy-MM-dd').format(sale.createdAt);
      
      if (!dailySales.containsKey(dateKey)) {
        dailySales[dateKey] = {
          'date': dateKey,
          'totalSales': 0.0,
          'totalTransactions': 0,
          'cashSales': 0.0,
          'cardSales': 0.0,
        };
      }

      dailySales[dateKey]!['totalSales'] += sale.total;
      dailySales[dateKey]!['totalTransactions']++;
      
      if (sale.paymentMethod == 'cash') {
        dailySales[dateKey]!['cashSales'] += sale.total;
      } else {
        dailySales[dateKey]!['cardSales'] += sale.total;
      }
    }

    return dailySales.values.toList()
      ..sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));
  }

  /// تقرير قيمة المخزون
  Future<Map<String, dynamic>> getInventoryValuationReport() async {
    final products = await _db.select(_db.products).get();
    
    double totalValue = 0;
    int totalItems = 0;
    final categories = <String, double>{};

    for (final product in products) {
      final value = product.costPrice * product.stockQuantity;
      totalValue += value;
      totalItems += product.stockQuantity;

      final categoryName = product.categoryId ?? 'Uncategorized';
      categories[categoryName] = (categories[categoryName] ?? 0) + value;
    }

    return {
      'totalValue': totalValue,
      'totalItems': totalItems,
      'byCategory': categories,
      'generatedAt': DateTime.now(),
    };
  }
}
