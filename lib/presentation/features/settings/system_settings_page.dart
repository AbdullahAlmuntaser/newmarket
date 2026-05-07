import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supermarket/core/services/app_config_service.dart';
import 'package:supermarket/data/datasources/local/app_database.dart';

/// صفحة إعدادات النظام العامة
/// General System Settings Page
class SystemSettingsPage extends StatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  State<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  late TextEditingController _taxRateController;
  late TextEditingController _lowStockThresholdController;
  late TextEditingController _invoiceMessageController;
  late TextEditingController _companyPhoneController;
  
  String? _defaultWarehouseId;
  String? _defaultBranchId;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _taxRateController = TextEditingController();
    _lowStockThresholdController = TextEditingController();
    _invoiceMessageController = TextEditingController();
    _companyPhoneController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    
    try {
      final db = context.read<AppDatabase>();
      final configService = AppConfigService(db);
      
      // Load tax rate
      final taxRate = await configService.getTaxRate();
      _taxRateController.text = (taxRate * 100).toStringAsFixed(2);
      
      // Load low stock threshold
      final threshold = await configService.getLowStockThreshold();
      _lowStockThresholdController.text = threshold.toString();
      
      // Load invoice message
      final invoiceMessage = await configService.getInvoiceMessage();
      _invoiceMessageController.text = invoiceMessage;
      
      // Load company phone
      final companyPhone = await configService.getString(AppConfigService.keyCompanyPhone) ?? '';
      _companyPhoneController.text = companyPhone;
      
      // Load warehouse and branch IDs
      _defaultWarehouseId = await configService.getDefaultWarehouseId();
      _defaultBranchId = await configService.getDefaultBranchId();
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل الإعدادات: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    
    try {
      final db = context.read<AppDatabase>();
      final configService = AppConfigService(db);
      
      // Save tax rate
      final taxRate = double.parse(_taxRateController.text) / 100;
      await configService.setDouble(AppConfigService.keyTaxRate, taxRate);
      
      // Save low stock threshold
      final threshold = int.parse(_lowStockThresholdController.text);
      await configService.setInt(AppConfigService.keyLowStockThreshold, threshold);
      
      // Save invoice message
      await configService.setString(
        AppConfigService.keyInvoiceMessage,
        _invoiceMessageController.text,
      );
      
      // Save company phone
      await configService.setString(
        AppConfigService.keyCompanyPhone,
        _companyPhoneController.text,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ الإعدادات بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ الإعدادات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _taxRateController.dispose();
    _lowStockThresholdController.dispose();
    _invoiceMessageController.dispose();
    _companyPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات النظام'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveSettings,
              tooltip: 'حفظ',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Tax Rate Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'الضريبة',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _taxRateController,
                            decoration: const InputDecoration(
                              labelText: 'نسبة الضريبة (%)',
                              hintText: 'مثال: 15',
                              prefixIcon: Icon(Icons.percent),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'الرجاء إدخال نسبة الضريبة';
                              }
                              final rate = double.tryParse(value);
                              if (rate == null || rate < 0 || rate > 100) {
                                return 'النسبة يجب أن تكون بين 0 و 100';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Inventory Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'المخزون',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _lowStockThresholdController,
                            decoration: const InputDecoration(
                              labelText: 'حد التنبيه للمخزون المنخفض',
                              hintText: 'مثال: 10',
                              prefixIcon: Icon(Icons.inventory_2_outlined),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'الرجاء إدخال الحد الأدنى';
                              }
                              final val = int.tryParse(value);
                              if (val == null || val < 0) {
                                return 'القيمة يجب أن تكون رقم موجب';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Invoice Settings Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'إعدادات الفواتير',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _invoiceMessageController,
                            decoration: const InputDecoration(
                              labelText: 'رسالة الفاتورة الافتراضية',
                              hintText: 'شكراً لتعاملكم معنا...',
                              prefixIcon: Icon(Icons.message),
                              border: OutlineInputBorder(),
                              alignLabelWithHint: true,
                            ),
                            maxLines: 3,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'الرجاء إدخال رسالة الفاتورة';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Company Info Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'معلومات الشركة',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _companyPhoneController,
                            decoration: const InputDecoration(
                              labelText: 'رقم هاتف الشركة',
                              hintText: '+966XXXXXXXXX',
                              prefixIcon: Icon(Icons.phone),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Warehouse & Branch Info (Read-only for now)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'المستودع والفرع',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ListTile(
                            leading: const Icon(Icons.warehouse),
                            title: const Text('المستودع الافتراضي'),
                            subtitle: Text(_defaultWarehouseId ?? 'غير محدد'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.store),
                            title: const Text('الفرع الافتراضي'),
                            subtitle: Text(_defaultBranchId ?? 'غير محدد'),
                          ),
                          const Text(
                            'ملاحظة: يمكن تغيير المستودع والفرع من شاشة نقطة البيع أو الفواتير',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Save Button
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveSettings,
                    icon: const Icon(Icons.save),
                    label: const Text('حفظ الإعدادات'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
