import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supermarket/core/auth/auth_provider.dart';
import 'package:supermarket/core/theme/app_theme.dart';
import 'package:supermarket/core/theme/theme_provider.dart';
import 'package:supermarket/core/navigation/app_router.dart';
import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:supermarket/injection_container.dart' as di;
import 'package:supermarket/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supermarket/presentation/features/accounting/accounting_provider.dart';
import 'package:supermarket/presentation/features/products/products_provider.dart';
import 'package:supermarket/presentation/features/purchases/purchase_provider.dart';
import 'package:supermarket/presentation/features/accounting/shifts_provider.dart';
import 'package:supermarket/presentation/features/hr/hr_provider.dart';
import 'package:supermarket/presentation/features/hr/payroll_provider.dart';
import 'package:supermarket/presentation/features/inventory/stock_transfer_provider.dart';
import 'package:supermarket/presentation/features/accounting/asset_provider.dart';
import 'package:supermarket/presentation/features/customers/customer_statement_provider.dart';
import 'package:supermarket/core/services/shift_service.dart';
import 'package:supermarket/core/services/hr_service.dart';
import 'package:supermarket/core/services/stock_transfer_service.dart';
import 'package:supermarket/core/services/asset_service.dart';
import 'package:supermarket/core/services/posting_engine.dart';
import 'package:supermarket/core/services/accounting_service.dart';
import 'package:supermarket/core/services/purchase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  debugPrint("MAIN: Starting app...");
  runApp(const SplashScreen());
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = "جاري التحميل...";

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  void _updateStatus(String status) {
    if (mounted) setState(() => _status = status);
  }

  Future<void> _initializeApp() async {
    _updateStatus("جاري تهيئة النظام...");
    debugPrint("INIT: Starting dependency injection...");
    
    try {
      final initFuture = di.init();
      final timeoutFuture = Future.delayed(const Duration(seconds: 30));
      
      final completed = await Future.any([initFuture, timeoutFuture]);
      
      if (completed == null) {
        debugPrint("INIT: Timeout reached after 30 seconds!");
        if (mounted) {
          _showErrorTimeout();
        }
        return;
      }
      
      debugPrint("INIT: DI completed successfully");
      
      _updateStatus("جاري تحميل الواجهة...");
      debugPrint("INIT: Loading main interface...");
      
      if (mounted) {
        debugPrint("INIT: Navigating to MyApp...");
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MyApp()),
        );
      }
    } catch (e, stack) {
      debugPrint("INIT ERROR: $e");
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        _showError("تعذر تهيئة النظام: ${e.toString()}\n\n$stack");
      }
    }
  }

  void _showError(String error) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            appBar: AppBar(title: const Text("خطأ في التهيئة")),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 80),
                  const SizedBox(height: 20),
                  Text(error, textAlign: TextAlign.center),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const SplashScreen()),
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text("إعادة المحاولة"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showErrorTimeout() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            appBar: AppBar(title: const Text("مهلة التهيئة انتهت")),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 80),
                    const SizedBox(height: 20),
                    const Text(
                      "استغرقت تهيئة النظام أكثر من 30 ثانية",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const SplashScreen()),
                        );
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text("إعادة المحاولة"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(_status, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>(create: (_) => di.sl<AppDatabase>()),
        Provider<AccountingService>(create: (_) => di.sl<AccountingService>()),
        ChangeNotifierProvider(create: (_) => di.sl<ThemeProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<AuthProvider>()),
        ChangeNotifierProvider(create: (_) => AccountingProvider(di.sl<AppDatabase>())),
        ChangeNotifierProvider(create: (_) => di.sl<ProductsProvider>()),
        ChangeNotifierProvider(
          create: (_) => PurchaseProvider(di.sl<AppDatabase>(), di.sl<PurchaseService>()),
        ),
        ChangeNotifierProvider(create: (_) => ShiftProvider(ShiftService(di.sl<AppDatabase>()))),
        ChangeNotifierProvider(create: (_) => HRProvider(HRService(di.sl<AppDatabase>(), di.sl<PostingEngine>()))),
        ChangeNotifierProvider(create: (_) => PayrollProvider(HRService(di.sl<AppDatabase>(), di.sl<PostingEngine>()))),
        ChangeNotifierProvider(
          create: (_) => StockTransferProvider(StockTransferService(di.sl<AppDatabase>())),
        ),
        ChangeNotifierProvider(create: (_) => AssetProvider(AssetService(di.sl<AppDatabase>()))),
        ChangeNotifierProvider(create: (_) => CustomerStatementProvider()),
      ],
      child: Builder(
        builder: (context) {
          final themeProvider = Provider.of<ThemeProvider>(context);
          return MaterialApp.router(
            title: 'Supermarket ERP',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            routerConfig: appRouter,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('ar'),
          );
        },
      ),
    );
  }
}
