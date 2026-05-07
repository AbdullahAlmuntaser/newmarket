import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'core/auth/auth_provider.dart';
import 'core/services/permission_service.dart';
import 'core/services/app_settings_service.dart';
import 'core/services/app_config_service.dart';
import 'core/services/inventory_service.dart';
import 'core/services/accounting_service.dart';
import 'core/services/event_bus_service.dart';
import 'core/services/financial_control_service.dart';
import 'core/services/grn_service.dart';
import 'core/utils/drive_backup_service.dart';
import 'core/theme/theme_provider.dart';
import 'core/services/unit_conversion_service.dart';
import 'data/datasources/local/app_database.dart';
import 'data/datasources/local/daos/products_dao.dart';
import 'data/datasources/local/daos/product_units_dao.dart';
import 'core/services/posting_engine.dart';
import 'core/services/inventory_costing_service.dart';
import 'data/datasources/local/daos/stock_movement_dao.dart';
import 'data/datasources/local/daos/audit_dao.dart';
import 'core/services/audit_service.dart';
import 'data/repositories/inventory_repository_impl.dart';
import 'data/repositories/item_repository_impl.dart';
import 'domain/repositories/inventory_repository.dart';
import 'domain/repositories/item_repository.dart';
import 'domain/usecases/create_item.dart';
import 'domain/usecases/add_stock.dart';
import 'core/services/bom_service.dart';
import 'core/services/sales_service.dart';
import 'core/services/purchase_service.dart';
import 'core/services/reorder_service.dart';
import 'core/services/supplier_analytics_service.dart';
import 'core/services/statement_service.dart';
import 'core/services/report_service.dart';
import 'core/services/pricing_service.dart';
import 'core/services/transaction_engine.dart';
import 'core/services/communication_service.dart';
import 'presentation/features/pos/bloc/pos_bloc.dart';
import 'presentation/features/products/products_provider.dart';

final sl = GetIt.instance;
AppDatabase? _database;

Future<void> initDatabase() async {
  debugPrint("DI: ==== Opening Database ====");
  try {
    _database = AppDatabase();
    sl.registerLazySingleton<AppDatabase>(() => _database!);
    debugPrint("DI: Database opened successfully");
  } catch (e, stack) {
    debugPrint("DI: Database opening error: $e");
    debugPrintStack(stackTrace: stack);
    rethrow;
  }
}

Future<void> initServices() async {
  debugPrint("DI: ==== Initializing Services ====");
  try {
    final db = sl<AppDatabase>();
    
    debugPrint("DI: Registering DAOs...");
    sl.registerLazySingleton<AuditDao>(() => AuditDao(db));
    sl.registerLazySingleton<StockMovementDao>(() => StockMovementDao(db));
    sl.registerLazySingleton<ProductsDao>(() => ProductsDao(db));
    sl.registerLazySingleton<ProductUnitsDao>(() => ProductUnitsDao(db));
    
    debugPrint("DI: Registering UnitConversionService...");
    sl.registerLazySingleton<UnitConversionService>(
      () => UnitConversionService(
        productsDao: sl<ProductsDao>(),
        productUnitsDao: sl<ProductUnitsDao>(),
      ),
    );
    debugPrint("DI: DAOs registered");

    debugPrint("DI: Registering core services...");
    sl.registerLazySingleton<EventBusService>(() => EventBusService());
    sl.registerLazySingleton<InventoryCostingService>(
      () => InventoryCostingService(sl<StockMovementDao>(), sl<AppDatabase>()),
    );
    sl.registerLazySingleton<PostingEngine>(
      () => PostingEngine(db, costingService: sl<InventoryCostingService>()),
    );
    sl.registerLazySingleton<AccountingService>(
      () => AccountingService(db, sl<EventBusService>()),
    );
    sl.registerLazySingleton<PermissionService>(() => PermissionService(db));
    sl.registerLazySingleton<AuditService>(() => AuditService(db));
    sl.registerLazySingleton<InventoryService>(() => InventoryService(db));
    sl.registerLazySingleton<AppConfigService>(() => AppConfigService(db));
    sl.registerLazySingleton<AppSettingsService>(() => AppSettingsService(db));
    debugPrint("DI: Core services registered");

    debugPrint("DI: Registering business services...");
    sl.registerLazySingleton<PurchaseService>(
      () => PurchaseService(db, sl<PostingEngine>(), sl<InventoryCostingService>(), sl<AppConfigService>()),
    );
    sl.registerLazySingleton<SalesService>(
      () => SalesService(sl<PostingEngine>(), sl<InventoryService>(), sl<AppSettingsService>(), sl<PermissionService>()),
    );
    sl.registerLazySingleton<StatementService>(
      () => StatementService(sl<PostingEngine>()),
    );
    sl.registerLazySingleton<ReportService>(
      () => ReportService(sl<PostingEngine>()),
    );
    debugPrint("DI: Business services registered");

    debugPrint("DI: Registering repositories...");
    sl.registerLazySingleton<AuthProvider>(
      () => AuthProvider(sl<AppDatabase>(), sl<PermissionService>()),
    );
    sl.registerLazySingleton<ItemRepository>(
      () => ItemRepositoryImpl(sl<ProductsDao>()),
    );
    sl.registerLazySingleton<InventoryRepository>(
      () => InventoryRepositoryImpl(sl<StockMovementDao>(), sl<ProductsDao>()),
    );
    sl.registerLazySingleton<CreateItemUseCase>(
      () => CreateItemUseCase(sl<ItemRepository>()),
    );
    sl.registerLazySingleton<AddStockUseCase>(
      () => AddStockUseCase(sl<InventoryRepository>()),
    );
    debugPrint("DI: Repositories registered");

    debugPrint("DI: Registering additional services...");
    sl.registerLazySingleton<ThemeProvider>(() => ThemeProvider());
    sl.registerLazySingleton(() => BomService(db, sl<AccountingService>()));
    sl.registerLazySingleton<GrnService>(() => GrnService(db));
    sl.registerLazySingleton<ReorderService>(() => ReorderService(db));
    sl.registerLazySingleton<SupplierAnalyticsService>(() => SupplierAnalyticsService(db));
    sl.registerLazySingleton<DriveBackupService>(() => DriveBackupService(db));
    sl.registerLazySingleton<FinancialControlService>(
      () => FinancialControlService(
        db,
        costingService: sl<InventoryCostingService>(),
      ),
    );
    sl.registerLazySingleton<PricingService>(() => PricingService(db));
    sl.registerLazySingleton<TransactionEngine>(() {
      final engine = TransactionEngine(db, sl<EventBusService>());
      engine.setCostingService(sl<InventoryCostingService>());
      return engine;
    });
    sl.registerLazySingleton<CommunicationService>(() => CommunicationService());
    debugPrint("DI: Additional services registered");

    debugPrint("DI: Registering providers...");
    sl.registerLazySingleton<ProductsProvider>(() => ProductsProvider(db));
    sl.registerFactory<PosBloc>(
      () => PosBloc(db, sl<PricingService>(), sl<TransactionEngine>()),
    );
    debugPrint("DI: Providers registered");
    
    debugPrint("DI: ==== Services Initialization Complete ====");
  } catch (e, stack) {
    debugPrint("DI: Services initialization error: $e");
    debugPrintStack(stackTrace: stack);
    rethrow;
  }
}

Future<void> init() async {
  await initDatabase();
  await initServices();
}