// lib/core/widgets/gk_card_list_tile.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../features/cards/models/virtual_card_model.dart';
import '../theme/app_colors.dart';

class GkCardListTile extends StatelessWidget {
  final VirtualCardModel card;
  final VoidCallback onTap;

  const GkCardListTile({
    super.key,
    required this.card,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: card.isBlocked 
                    ? AppColors.error.withValues(alpha: 0.1) 
                    : AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.credit_card_rounded,
                color: card.isBlocked ? AppColors.error : AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.displayName,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.onSurface,
                      decoration: card.isBlocked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '•••• ${card.last4 ?? '****'}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (card.rule.maxAmountPerTransaction != null)
              Text(
                '₦${card.rule.maxAmountPerTransaction!.toStringAsFixed(0)} limit',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.outline),
          ],
        ),
      ),
    );
  }
}
