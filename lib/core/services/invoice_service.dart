import 'package:supermarket/data/datasources/local/app_database.dart';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:barcode/barcode.dart';
import 'package:supermarket/core/services/app_config_service.dart';

class InvoiceService {
  final AppConfigService _configService = AppConfigService();

  Future<Uint8List> generateInvoice({
    required Sale sale,
    required List<SaleItem> items,
    required List<Product> products,
    String? customerName,
    String? companyName,
    String? companyAddress,
    String? companyVatNumber,
  }) async {
    final pdf = pw.Document();
    final taxRate = await _configService.getTaxRate();
    final taxLabel = 'VAT (${(taxRate * 100).toStringAsFixed(0)}%)';

    final qrCodeSvg = _generateZatcaQr(
      companyName ?? 'My Supermarket',
      companyVatNumber ?? '1234567890',
      sale.createdAt,
      sale.total,
      sale.tax,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(
                companyName,
                companyAddress,
                companyVatNumber,
                qrCodeSvg,
              ),
              pw.SizedBox(height: 20),

              // Invoice Info
              _buildInvoiceInfo(sale, customerName),
              pw.SizedBox(height: 20),

              // Items Table
              _buildItemsTable(items, products),
              pw.SizedBox(height: 20),

              // Totals
              _buildTotals(sale),
              pw.Spacer(),

              // Footer
              _buildFooter(),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  String _generateZatcaQr(
    String seller,
    String vatNo,
    DateTime date,
    double total,
    double tax,
  ) {
    // Basic QR code for now. For full ZATCA compliance, TLV encoding is required.
    final qrData =
        'Seller: $seller\nVAT: $vatNo\nDate: ${date.toIso8601String()}\nTotal: $total\nTax: $tax';
    final bc = Barcode.qrCode();
    return bc.toSvg(qrData, width: 100, height: 100);
  }

  pw.Widget _buildHeader(
    String? companyName,
    String? companyAddress,
    String? companyVatNumber,
    String qrSvg,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              companyName ?? 'My Supermarket',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 24),
            ),
            pw.Text(companyAddress ?? '123 Market St, City, Country'),
            pw.Text('VAT Number: ${companyVatNumber ?? 'N/A'}'),
          ],
        ),
        pw.Container(width: 80, height: 80, child: pw.SvgImage(svg: qrSvg)),
      ],
    );
  }

  pw.Widget _buildInvoiceInfo(Sale sale, String? customerName) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Bill To:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(customerName ?? 'Walk-in Customer'),
              pw.Text('Payment Method: ${sale.paymentMethod.toUpperCase()}'),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Invoice #: ${sale.id.substring(0, 8).toUpperCase()}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text('Date: ${dateFormat.format(sale.createdAt)}'),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildItemsTable(List<SaleItem> items, List<Product> products) {
    final headers = ['Item', 'Qty', 'Unit Price', 'Total'];

    final data = items.map((item) {
      final product = products.firstWhere((p) => p.id == item.productId);
      return [
        product.name,
        item.quantity.toStringAsFixed(0),
        item.price.toStringAsFixed(2),
        (item.quantity * item.price).toStringAsFixed(2),
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: null,
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
      cellHeight: 30,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.center,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
    );
  }

  pw.Widget _buildTotals(Sale sale) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            _totalRow(
              'Subtotal',
              (sale.total - sale.tax + sale.discount).toStringAsFixed(2),
            ),
            _totalRow('Discount', sale.discount.toStringAsFixed(2)),
            _totalRow(taxLabel, sale.tax.toStringAsFixed(2)),
            pw.Divider(color: PdfColors.grey),
            _totalRow(
              'Total Amount',
              sale.total.toStringAsFixed(2),
              isBold: true,
              fontSize: 16,
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _totalRow(
    String title,
    String value, {
    bool isBold = false,
    double fontSize = 12,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: fontSize,
            ),
          ),
          pw.SizedBox(width: 40),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.Divider(),
        pw.Center(
          child: pw.Text(
            'Thank you for your business!',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
          ),
        ),
      ],
    );
  }

  // Support for direct Pdf Invoice generation as used in POS
  Future<Uint8List> generatePdfInvoice({
    required Sale sale,
    required List<SaleItem> items,
    required List<Product> products,
    String? customerName,
    String? companyName,
    String? companyAddress,
    String? companyVatNumber,
  }) async {
    return await generateInvoice(
      sale: sale,
      items: items,
      products: products,
      customerName: customerName,
      companyAddress: companyAddress,
      companyVatNumber: companyVatNumber,
      companyName: companyName,
    );
  }
}
