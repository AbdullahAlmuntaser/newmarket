import 'package:drift/drift.dart';
import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:supermarket/core/services/cache_service.dart';

part 'products_dao.g.dart';

class ProductWithCategory {
  final Product product;
  final Category? category;

  ProductWithCategory({required this.product, this.category});
}

class TransferItemData {
  final String productId;
  final String batchId;
  final double quantity;

  TransferItemData({
    required this.productId,
    required this.batchId,
    required this.quantity,
  });
}

@DriftAccessor(
  tables: [
    Products,
    Categories,
    Warehouses,
    ProductBatches,
    StockTransfers,
    StockTransferItems,
  ],
)
class ProductsDao extends DatabaseAccessor<AppDatabase>
    with _$ProductsDaoMixin {
  ProductsDao(super.db);
  
  final _cache = CacheService();

  Stream<List<Product>> watchAllProducts() {
    return select(products).watch();
  }

  /// Get product by ID with caching
  Future<Product?> getProductById(String id) async {
    // Try cache first
    final cached = _cache.get<Product>(CacheKeys.product(id));
    if (cached != null) {
      return cached;
    }

    // Load from database
    final product = await (select(products)..where((p) => p.id.equals(id))).getSingleOrNull();
    
    if (product != null) {
      _cache.set(CacheKeys.product(id), product, ttl: const Duration(minutes: 10));
    }
    
    return product;
  }

  /// Get product by barcode with caching and optimized query
  Future<Product?> getProductByBarcode(String barcode) async {
    // Try cache first
    final cached = _cache.get<Product>(CacheKeys.productByBarcode(barcode));
    if (cached != null) {
      return cached;
    }

    // Optimized query using index
    final product = await (select(products)..where((p) => p.barcode.equals(barcode))).getSingleOrNull();
    
    if (product != null) {
      _cache.set(CacheKeys.productByBarcode(barcode), product, ttl: const Duration(minutes: 10));
    }
    
    return product;
  }

  /// Get product by SKU with caching
  Future<Product?> getProductBySku(String sku) async {
    final cached = _cache.get<Product>(CacheKeys.productBySku(sku));
    if (cached != null) {
      return cached;
    }

    final product = await (select(products)..where((p) => p.sku.equals(sku))).getSingleOrNull();
    
    if (product != null) {
      _cache.set(CacheKeys.productBySku(sku), product, ttl: const Duration(minutes: 10));
    }
    
    return product;
  }

  /// Get all products with optional filtering - optimized with indexes
  Future<List<Product>> getProducts({
    String? categoryId,
    bool? isActive,
    bool lowStockOnly = false,
  }) async {
    var query = select(products);

    if (categoryId != null) {
      query = query..where((p) => p.categoryId.equals(categoryId));
    }
    
    if (isActive != null) {
      query = query..where((p) => p.isActive.equals(isActive));
    }
    
    if (lowStockOnly) {
      query = query..where((p) => p.stock.isSmallerOrEqual(p.alertLimit));
    }

    return query.get();
  }

  /// Watch low stock products - uses index on alertLimit
  Stream<List<Product>> watchLowStockProducts() {
    return (select(products)..where((p) => p.stock.isSmallerOrEqual(p.alertLimit))).watch();
  }

  /// Clear product cache when data changes
  void clearProductCache([String? productId]) {
    if (productId != null) {
      _cache.remove(CacheKeys.product(productId));
    } else {
      _cache.clearByPattern('product_*');
    }
  }

  // ========== Warehouse & Batch Management ==========
  Stream<List<Warehouse>> watchWarehouses() {
    return select(warehouses).watch();
  }

  Future<int> addWarehouse(WarehousesCompanion entry) {
    return into(warehouses).insert(entry);
  }

  Future<List<ProductBatch>> getProductBatches(
    String productId,
    String warehouseId,
  ) {
    return (select(productBatches)..where(
          (b) =>
              b.productId.equals(productId) &
              b.warehouseId.equals(warehouseId) &
              b.quantity.isBiggerThan(const Variable(0)),
        ))
        .get();
  }

  /// تنفيذ عملية تحويل مخزني بين مستودعين
  Future<void> transferStock({
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<TransferItemData> items,
    String? note,
  }) async {
    await transaction(() async {
      final transfer = await into(stockTransfers).insertReturning(
        StockTransfersCompanion.insert(
          fromWarehouseId: fromWarehouseId,
          toWarehouseId: toWarehouseId,
          note: Value(note),
          transferDate: Value(DateTime.now()),
        ),
      );

      final transferId = transfer.id;

      for (var item in items) {
        final sourceBatch = await (select(
          productBatches,
        )..where((b) => b.id.equals(item.batchId))).getSingle();

        if (sourceBatch.quantity < item.quantity) {
          throw Exception('الكمية المطلوبة غير متوفرة في الدفعة المحددة');
        }

        await (update(
          productBatches,
        )..where((b) => b.id.equals(item.batchId))).write(
          ProductBatchesCompanion(
            quantity: Value(sourceBatch.quantity - item.quantity),
          ),
        );

        final targetBatch =
            await (select(productBatches)..where(
                  (b) =>
                      b.productId.equals(item.productId) &
                      b.warehouseId.equals(toWarehouseId) &
                      b.batchNumber.equals(sourceBatch.batchNumber),
                ))
                .getSingleOrNull();

        if (targetBatch != null) {
          await (update(
            productBatches,
          )..where((b) => b.id.equals(targetBatch.id))).write(
            ProductBatchesCompanion(
              quantity: Value(targetBatch.quantity + item.quantity),
            ),
          );
        } else {
          await into(productBatches).insert(
            ProductBatchesCompanion.insert(
              productId: item.productId,
              warehouseId: toWarehouseId,
              batchNumber: sourceBatch.batchNumber,
              expiryDate: Value(sourceBatch.expiryDate),
              quantity: Value(item.quantity),
              initialQuantity: Value(item.quantity),
              costPrice: Value(sourceBatch.costPrice),
            ),
          );
        }

        await into(stockTransferItems).insert(
          StockTransferItemsCompanion.insert(
            transferId: transferId,
            productId: item.productId,
            batchId: item.batchId,
            quantity: item.quantity,
          ),
        );
      }
    });
  }

  // ========== Products (Items) Operations ==========
  Stream<List<ProductWithCategory>> watchProducts({
    String? searchQuery,
    String? categoryId,
  }) {
    final query = select(products).join([
      leftOuterJoin(categories, categories.id.equalsExp(products.categoryId)),
    ]);

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query.where(
        products.name.like('%$searchQuery%') |
            products.sku.like('%$searchQuery%') |
            products.barcode.like('%$searchQuery%'),
      );
    }

    if (categoryId != null && categoryId.isNotEmpty) {
      query.where(products.categoryId.equals(categoryId));
    }

    query.orderBy([OrderingTerm.asc(products.name)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return ProductWithCategory(
          product: row.readTable(products),
          category: row.readTableOrNull(categories),
        );
      }).toList();
    });
  }

  Stream<List<Product>> watchLowStockProducts() {
    return (select(
      products,
    )..where((p) => p.stock.isSmallerOrEqual(p.alertLimit))).watch();
  }

  Stream<int> watchLowStockCount() {
    final query = select(products)
      ..where((p) => p.stock.isSmallerOrEqual(p.alertLimit));
    return query.watch().map((list) => list.length);
  }

  Future<Product?> getProductById(String id) {
    return (select(products)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  Future<Product?> getProductBySku(String sku) {
    return (select(
      products,
    )..where((p) => p.sku.equals(sku))).getSingleOrNull();
  }

  Future<Product?> getProductByBarcode(String barcode) {
    return (select(
      products,
    )..where((p) => p.barcode.equals(barcode))).getSingleOrNull();
  }

  Future<int> addProduct(ProductsCompanion entry) async {
    final result = await into(products).insert(entry);
    // Clear cache when product is added
    clearProductCache();
    return result;
  }

  Future<bool> updateProduct(Product entry) async {
    final result = await update(products).replace(entry);
    // Clear cache for this specific product
    clearProductCache(entry.id);
    return result;
  }

  Future<int> deleteProduct(Product entry) async {
    final result = await delete(products).delete(entry);
    // Clear cache for deleted product
    clearProductCache(entry.id);
    return result;
  }

  // ========== Variant Operations ==========
  /// Get all variants for a specific product (parent)
  Future<List<Product>> getVariantsForProduct(String productId) {
    return (select(
      products,
    )..where((p) => p.parentProductId.equals(productId))).get();
  }

  /// Stream variants for a product
  Stream<List<Product>> watchVariantsForProduct(String productId) {
    return (select(
      products,
    )..where((p) => p.parentProductId.equals(productId))).watch();
  }

  /// Get a product with its variants (returns the parent)
  Future<ProductWithVariants?> getProductWithVariants(String productId) async {
    final product = await getProductById(productId);
    if (product == null) return null;
    final variants = await getVariantsForProduct(productId);
    return ProductWithVariants(product: product, variants: variants);
  }

  // ========== Categories ==========
  Stream<List<Category>> watchCategories() {
    return select(categories).watch();
  }

  Future<int> addCategory(CategoriesCompanion entry) {
    return into(categories).insert(entry);
  }

  Future<bool> updateCategory(Category entry) {
    return update(categories).replace(entry);
  }

  Future<int> deleteCategory(Category entry) {
    return delete(categories).delete(entry);
  }

  // ========== Expiring Batches ==========
  Stream<List<ProductBatch>> watchExpiringBatches({int daysThreshold = 30}) {
    final thresholdDate = DateTime.now().add(Duration(days: daysThreshold));
    return (select(productBatches)
          ..where(
            (b) =>
                b.expiryDate.isSmallerOrEqual(Variable(thresholdDate)) &
                b.quantity.isBiggerThan(const Variable(0)),
          )
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.expiryDate, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Future<List<ProductBatch>> getExpiringBatches({
    int daysThreshold = 30,
  }) async {
    final thresholdDate = DateTime.now().add(Duration(days: daysThreshold));
    return (select(productBatches)
          ..where(
            (b) =>
                b.expiryDate.isSmallerOrEqual(Variable(thresholdDate)) &
                b.quantity.isBiggerThan(const Variable(0)),
          )
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.expiryDate, mode: OrderingMode.asc),
          ]))
        .get();
  }
}

/// Helper class to return a product with its variants
class ProductWithVariants {
  final Product product;
  final List<Product> variants;

  ProductWithVariants({required this.product, required this.variants});
}
