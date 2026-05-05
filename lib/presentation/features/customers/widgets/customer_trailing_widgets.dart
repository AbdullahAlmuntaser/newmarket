import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supermarket/l10n/app_localizations.dart';
import 'package:supermarket/data/datasources/local/app_database.dart';
import 'package:supermarket/core/services/communication_service.dart';
import 'package:supermarket/injection_container.dart';

class CustomerTrailingWidgets extends StatelessWidget {
  final Customer customer;
  final AppDatabase db;
  final AppLocalizations l10n;
  final Function(AppDatabase, Customer) onPayAmount;

  const CustomerTrailingWidgets({
    super.key,
    required this.customer,
    required this.db,
    required this.l10n,
    required this.onPayAmount,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final commService = sl<CommunicationService>();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              l10n.balanceLabel(customer.balance.toStringAsFixed(2)),
              style: TextStyle(
                color: customer.balance > 0
                    ? colorScheme.error
                    : colorScheme.tertiary, // Themed colors
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              l10n.limitLabel(customer.creditLimit.toStringAsFixed(2)),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
        // زر الاتصال الهاتفي
        if (customer.phone != null && customer.phone!.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.phone),
            color: colorScheme.primary,
            tooltip: 'اتصال',
            onPressed: () => commService.makePhoneCall(customer.phone!),
          ),
        const SizedBox(width: 4),
        // زر WhatsApp
        if (customer.phone != null && customer.phone!.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.message, color: Colors.green),
            tooltip: 'WhatsApp',
            onPressed: () => commService.sendWhatsAppMessage(
              phoneNumber: customer.phone!,
              message: 'مرحباً ${customer.name}، نشكرك على ثقتكم بنا.',
            ),
          ),
        const SizedBox(width: 4),
        // زر الدفع
        IconButton(
          icon: const Icon(Icons.payment),
          color: colorScheme.primary, // Themed color
          tooltip: l10n.payAmount,
          onPressed: () => onPayAmount(db, customer),
        ),
        const SizedBox(width: 4),
        // زر كشف الحساب
        IconButton(
          icon: const Icon(Icons.receipt_long),
          color: colorScheme.secondary, // Themed color
          tooltip: l10n.customerStatementTooltip,
          onPressed: () => context.push('/customers/statement/${customer.id}'),
        ),
      ],
    );
  }
}
