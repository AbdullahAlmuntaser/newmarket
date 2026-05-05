import 'dart:developer' as developer;
import 'package:url_launcher/url_launcher.dart';

/// خدمة الاتصالات الموحدة للاتصال والـ WhatsApp و SMS
class CommunicationService {
  static final CommunicationService _instance =
      CommunicationService._internal();
  factory CommunicationService() => _instance;
  CommunicationService._internal();

  /// فتح تطبيق الهاتف للاتصال برقم معين
  Future<bool> makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) return false;
    
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    
    try {
      return await launchUrl(launchUri);
    } catch (e) {
      developer.log('Error making phone call', error: e, name: 'CommunicationService');
      return false;
    }
  }

  /// فتح WhatsApp للتحدث مع رقم معين
  /// [phoneNumber] يجب أن يكون بصيغة دولية بدون + أو 00
  /// مثال: 966501234567
  Future<bool> sendWhatsAppMessage({
    required String phoneNumber,
    String? message,
  }) async {
    if (phoneNumber.isEmpty) return false;
    
    // تنظيف الرقم وإزالة أي أحرف غير رقمية
    String cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    
    // إزالة الصفر الأول إذا كان يبدأ بـ 0 وإضافة كود الدولة
    if (cleanNumber.startsWith('0')) {
      // افتراض أن الرقم سعودي إذا لم يكن به كود دولة
      cleanNumber = '966${cleanNumber.substring(1)}';
    }
    
    try {
      Uri uri;
      if (message != null && message.isNotEmpty) {
        // تشفير الرسالة للاستخدام في URL
        final encodedMessage = Uri.encodeComponent(message);
        uri = Uri.parse(
          'https://wa.me/$cleanNumber?text=$encodedMessage',
        );
      } else {
        uri = Uri.parse('https://wa.me/$cleanNumber');
      }
      
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      developer.log('Error opening WhatsApp', error: e, name: 'CommunicationService');
      return false;
    }
  }

  /// إرسال رسالة SMS
  Future<bool> sendSMS({
    required String phoneNumber,
    required String message,
  }) async {
    if (phoneNumber.isEmpty || message.isEmpty) return false;
    
    try {
      // استخدام scheme الخاص بـ SMS
      final Uri smsUri = Uri(
        scheme: 'sms',
        path: phoneNumber,
        query: 'body=$message',
      );
      
      return await launchUrl(smsUri);
    } catch (e) {
      developer.log('Error sending SMS', error: e, name: 'CommunicationService');
      return false;
    }
  }

  /// إرسال فاتورة عبر WhatsApp
  Future<bool> sendInvoiceViaWhatsApp({
    required String phoneNumber,
    required String invoiceNumber,
    required double total,
    required String customerName,
    DateTime? dueDate,
  }) async {
    final message = '''
🧾 *فاتورة جديدة*

*رقم الفاتورة:* $invoiceNumber
*العميل:* $customerName
*الإجمالي:* ${total.toStringAsFixed(2)} ر.س
${dueDate != null ? '*تاريخ الاستحقاق:* ${_formatDate(dueDate)}' : ''}

شكراً لتعاملكم معنا! 🙏
''';
    
    return await sendWhatsAppMessage(
      phoneNumber: phoneNumber,
      message: message,
    );
  }

  /// إرسال أمر شراء للمورد عبر WhatsApp
  Future<bool> sendPurchaseOrderViaWhatsApp({
    required String phoneNumber,
    required String poNumber,
    required double total,
    required String supplierName,
    int itemCount = 0,
  }) async {
    final message = '''
📦 *أمر شراء جديد*

*رقم الأمر:* $poNumber
*المورد:* $supplierName
*عدد الأصناف:* $itemCount
*الإجمالي:* ${total.toStringAsFixed(2)} ر.س

يرجى تأكيد الاستلام. شكراً! 🙏
''';
    
    return await sendWhatsAppMessage(
      phoneNumber: phoneNumber,
      message: message,
    );
  }

  /// إرسال تنبيه مخزون منخفض للمدير عبر SMS
  Future<bool> sendLowStockAlertSMS({
    required String phoneNumber,
    required String itemName,
    required double currentQty,
    required double minQty,
  }) async {
    final message = '''
⚠️ تنبيه مخزون منخفض

الصنف: $itemName
الكمية الحالية: $currentQty
الحد الأدنى: $minQty

يرجى الت reorder فوراً!
''';
    
    return await sendSMS(
      phoneNumber: phoneNumber,
      message: message,
    );
  }

  /// إرسال تنبيه انتهاء صلاحية عبر SMS
  Future<bool> sendExpiryAlertSMS({
    required String phoneNumber,
    required String itemName,
    required DateTime expiryDate,
    required double quantity,
  }) async {
    final daysUntilExpiry = expiryDate.difference(DateTime.now()).inDays;
    final message = '''
⏰ تنبيه انتهاء صلاحية

الصنف: $itemName
الكمية: $quantity
تاريخ الانتهاء: ${_formatDate(expiryDate)}
متبقي: $daysUntilExpiry يوم

يرجى اتخاذ اللازم!
''';
    
    return await sendSMS(
      phoneNumber: phoneNumber,
      message: message,
    );
  }

  /// تنسيق التاريخ
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  /// التحقق من إمكانية الاتصال
  Future<bool> canMakePhoneCalls() async {
    return await canLaunchUrl(Uri(scheme: 'tel'));
  }

  /// التحقق من إمكانية إرسال SMS
  Future<bool> canSendSMS() async {
    return await canLaunchUrl(Uri(scheme: 'sms'));
  }

  /// التحقق من تثبيت WhatsApp
  Future<bool> isWhatsAppInstalled() async {
    return await canLaunchUrl(Uri.parse('https://wa.me/1234567890'));
  }
}
