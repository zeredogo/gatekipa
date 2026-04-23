// lib/core/widgets/transaction_status_widget.dart
import 'package:flutter/material.dart';
import 'package:gatekeepeer/features/wallet/models/transaction_orchestration_model.dart';

/// Displays a compact status indicator for a transaction that is in any
/// lifecycle phase. Replaces optimistic "success assumed" UI with the real
/// server-authoritative status read from the `transactions` collection.
///
/// Usage:
/// ```dart
/// TransactionStatusBadge(status: tx.status)
/// ```
class TransactionStatusBadge extends StatelessWidget {
  final TxnStatus status;

  const TransactionStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case TxnStatus.pending:
      case TxnStatus.processing:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              status == TxnStatus.pending ? 'Pending…' : 'Processing…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

      case TxnStatus.success:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 14),
            const SizedBox(width: 4),
            Text(
              'Approved',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: const Color(0xFF2E7D32),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

      case TxnStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cancel_rounded, color: Color(0xFFB71C1C), size: 14),
            const SizedBox(width: 4),
            Text(
              'Failed',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: const Color(0xFFB71C1C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

      case TxnStatus.unknown:
        return Tooltip(
          message: 'Status unconfirmed — will update automatically',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.help_outline_rounded, color: Color(0xFFE65100), size: 14),
              const SizedBox(width: 4),
              Text(
                'Unknown',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: const Color(0xFFE65100),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
    }
  }
}

/// Full-width status bar variant — used in transaction detail screens.
class TransactionStatusBar extends StatelessWidget {
  final TxnStatus status;
  final String? errorMessage;

  const TransactionStatusBar({super.key, required this.status, this.errorMessage});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;
    IconData icon;

    switch (status) {
      case TxnStatus.pending:
        bgColor = const Color(0xFF1A2C40);
        textColor = const Color(0xFF90CAF9);
        label = 'Pending confirmation…';
        icon = Icons.hourglass_top_rounded;
        break;
      case TxnStatus.processing:
        bgColor = const Color(0xFF1A2C40);
        textColor = const Color(0xFF90CAF9);
        label = 'Processing transaction…';
        icon = Icons.sync_rounded;
        break;
      case TxnStatus.success:
        bgColor = const Color(0xFF0A2318);
        textColor = const Color(0xFF66BB6A);
        label = 'Transaction approved';
        icon = Icons.check_circle_rounded;
        break;
      case TxnStatus.failed:
        bgColor = const Color(0xFF2C0A0A);
        textColor = const Color(0xFFEF9A9A);
        label = errorMessage ?? 'Transaction failed';
        icon = Icons.cancel_rounded;
        break;
      case TxnStatus.unknown:
        bgColor = const Color(0xFF2D1B00);
        textColor = const Color(0xFFFFCC80);
        label = 'Status unconfirmed — checking…';
        icon = Icons.help_outline_rounded;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (status == TxnStatus.processing || status == TxnStatus.pending)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: textColor,
              ),
            ),
        ],
      ),
    );
  }
}
