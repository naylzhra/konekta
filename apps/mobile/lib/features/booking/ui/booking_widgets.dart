import 'package:flutter/material.dart';

import '../../../core/strings/booking_strings.dart';
import '../../../core/theme/konekta_theme.dart';
import '../domain/booking_failure.dart';
import '../domain/booking_models.dart';
import '../domain/booking_state_machine.dart';

class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Material (not a colored Container) so ListTiles inside paint their
    // ink on the card.
    return Material(
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

class BookingStatusChip extends StatelessWidget {
  const BookingStatusChip({super.key, required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      BookingStatus.completed => (AppColors.secondaryContainer, AppColors.onSecondaryContainer),
      BookingStatus.cancelled ||
      BookingStatus.failed ||
      BookingStatus.noShow ||
      BookingStatus.expired =>
        (AppColors.errorContainer, AppColors.onErrorContainer),
      _ => (AppColors.surfaceContainerHigh, AppColors.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.base),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Text(
        BookingStrings.statusLabel(status),
        style: AppTextStyles.labelMd.copyWith(color: foreground, letterSpacing: 0),
      ),
    );
  }
}

/// Static halte vs virtual (time-bound) stop: the UI must say which (DESIGN.md §1).
class StopTypeBadge extends StatelessWidget {
  const StopTypeBadge({super.key, required this.type});

  final StopType type;

  @override
  Widget build(BuildContext context) {
    final isVirtual = type == StopType.virtualStop;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: isVirtual ? AppColors.tertiaryContainer : AppColors.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        BookingStrings.stopType(type),
        style: AppTextStyles.labelMd.copyWith(
          letterSpacing: 0,
          color: isVirtual ? AppColors.onTertiaryContainer : AppColors.onSecondaryContainer,
        ),
      ),
    );
  }
}

class StopRow extends StatelessWidget {
  const StopRow({super.key, required this.label, required this.name, required this.type, this.icon, this.footnote});

  final String label;
  final String name;
  final StopType type;
  final IconData? icon;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon ?? Icons.place_outlined, size: 20, color: AppColors.primary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.labelMd),
              const SizedBox(height: 2),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.base,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(name, style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600)),
                  StopTypeBadge(type: type),
                ],
              ),
              if (footnote != null) ...[
                const SizedBox(height: 2),
                Text(footnote!, style: AppTextStyles.bodySm),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.bodySm)),
          Text(value, style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Inline notice: offline/reconnecting, errors, stop moved.
class BookingNotice extends StatelessWidget {
  const BookingNotice({super.key, required this.message, this.isError = false, this.icon, this.action});

  final String message;
  final bool isError;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final foreground = isError ? AppColors.onErrorContainer : AppColors.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: isError ? AppColors.errorContainer : AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.standard),
      ),
      child: Row(
        children: [
          Icon(icon ?? (isError ? Icons.error_outline : Icons.info_outline), size: 18, color: foreground),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(message, style: AppTextStyles.bodySm.copyWith(color: foreground))),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class BookingErrorNotice extends StatelessWidget {
  const BookingErrorNotice({super.key, required this.error, this.onRetry, this.onDismiss});

  final BookingException error;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    if (error.code.isTransient) return const SizedBox.shrink();
    return BookingNotice(
      message: BookingStrings.failure(error.code),
      isError: true,
      action: onRetry != null
          ? TextButton(onPressed: onRetry, child: const Text(BookingStrings.retry))
          : onDismiss != null
              ? IconButton(
                  tooltip: BookingStrings.dismiss,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDismiss,
                )
              : null,
    );
  }
}

/// Asks before cancelling; returns true when the passenger confirms.
Future<bool> confirmCancel(BuildContext context, {int feeIdr = 0}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(BookingStrings.cancelDialogTitle),
      content: Text(BookingStrings.cancelDialogBody(feeIdr)),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(BookingStrings.cancelDialogKeep)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text(BookingStrings.cancelDialogConfirm),
        ),
      ],
    ),
  );
  return result ?? false;
}
