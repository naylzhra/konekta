import 'package:flutter/material.dart';

import '../../core/strings/driver_strings.dart';
import '../../core/theme/konekta_theme.dart';
import '../live_tracking/domain/feeder_models.dart';

/// Origin and destination terminal of each direction, from the route lists.
typedef DirectionEnds = Map<RouteDirection, (String from, String to)>;

/// Asks which way the driver starts the corridor. No typing: the two
/// terminals are fixed and the swap button flips them.
Future<RouteDirection?> pickDirection(
  BuildContext context, {
  required DirectionEnds ends,
  required RouteDirection initial,
}) =>
    showDialog<RouteDirection>(
      context: context,
      builder: (_) => _DirectionDialog(ends: ends, initial: initial),
    );

class _DirectionDialog extends StatefulWidget {
  const _DirectionDialog({required this.ends, required this.initial});

  final DirectionEnds ends;
  final RouteDirection initial;

  @override
  State<_DirectionDialog> createState() => _DirectionDialogState();
}

class _DirectionDialogState extends State<_DirectionDialog> {
  late RouteDirection _direction = widget.initial;

  @override
  Widget build(BuildContext context) {
    final (from, to) = widget.ends[_direction] ?? ('-', '-');
    return AlertDialog(
      title: const Text(DriverStrings.pickDirectionTitle),
      content: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Terminal(
                    label: DriverStrings.from, name: from, icon: Icons.trip_origin),
                Padding(
                  padding: const EdgeInsets.only(left: 11),
                  child: Container(
                      width: 2, height: 20, color: AppColors.outlineVariant),
                ),
                _Terminal(label: DriverStrings.to, name: to, icon: Icons.place),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: DriverStrings.swapDirection,
            icon: const Icon(Icons.swap_vert),
            onPressed: () => setState(() => _direction = _direction.reversed),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(DriverStrings.cancel)),
        FilledButton(
            onPressed: () => Navigator.pop(context, _direction),
            child: const Text(DriverStrings.startWithDirection)),
      ],
    );
  }
}

class _Terminal extends StatelessWidget {
  const _Terminal({required this.label, required this.name, required this.icon});

  final String label;
  final String name;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.bodySm),
                Text(name, style: AppTextStyles.bodyLg),
              ],
            ),
          ),
        ],
      );
}
