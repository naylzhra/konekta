import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/strings/driver_strings.dart';
import '../../core/strings/live_tracking_strings.dart';
import '../../core/theme/konekta_theme.dart';
import '../live_tracking/state/driver_duty_controller.dart';
import '../live_tracking/ui/route_stops_page.dart';
import '../../shared_widgets/nav_banner.dart';
import 'data/driver_trip_api.dart';

/// Pin for a stop with passengers: teal for pickups, indigo for drop-offs.
class TaskStopMarker extends StatelessWidget {
  const TaskStopMarker({super.key, required this.stop, this.isTarget = false});

  final DriverTaskStop stop;
  final bool isTarget;

  @override
  Widget build(BuildContext context) {
    final color =
        stop.phase == StopPhase.pickup ? AppColors.secondary : AppColors.tertiary;
    final size = isTarget ? 40.0 : 32.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: isTarget ? 3 : 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Icon(
              stop.phase == StopPhase.pickup ? Icons.hail : Icons.logout,
              color: Colors.white,
              size: size * 0.55),
        ),
        Icon(Icons.arrow_drop_down, color: color, size: 16),
      ],
    );
  }
}

/// Bottom sheet: before duty it lists the stops to serve; on duty it shows
/// the stop being navigated to with its arrive/depart actions.
class DriverSheet extends StatelessWidget {
  const DriverSheet({
    super.key,
    required this.duty,
    required this.tasks,
    required this.tasksFailed,
    required this.onRetryTasks,
    required this.corridorId,
    required this.navigation,
    required this.nearTarget,
    required this.actingStopId,
    required this.onChoose,
    required this.onArrived,
    required this.onDeparted,
  });

  final DriverDutyController duty;
  final List<DriverTaskStop>? tasks;
  final bool tasksFailed;
  final VoidCallback onRetryTasks;
  final String? corridorId;
  final DriverNavigation? navigation;
  final bool nearTarget;
  final String? actingStopId;
  /// Navigate to this stop id instead of the next one on the route.
  final ValueChanged<String> onChoose;
  final ValueChanged<NavStop> onArrived;
  final ValueChanged<NavStop> onDeparted;

  @override
  Widget build(BuildContext context) {
    final onDuty = duty.isOnDuty;
    return DraggableScrollableSheet(
      initialChildSize: onDuty ? 0.30 : 0.38,
      minChildSize: 0.16,
      maxChildSize: 0.8,
      snap: true,
      builder: (context, controller) => Material(
        color: AppColors.surfaceContainerLowest,
        elevation: 12,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(AppSpacing.containerMargin,
              AppSpacing.xs, AppSpacing.containerMargin, AppSpacing.lg),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            ...onDuty ? _onDuty(context) : _offDuty(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _offDuty(BuildContext context) {
    final feeder = duty.feeder;
    return [
      if (feeder != null)
        Text(LiveTrackingStrings.feederLabel(feeder.number, feeder.corridorName),
            style: AppTextStyles.headlineMd),
      const SizedBox(height: AppSpacing.xs),
      Text(_statusText(), style: AppTextStyles.bodySm),
      ..._issue(),
      const SizedBox(height: AppSpacing.md),
      ElevatedButton.icon(
        onPressed: duty.status == DutyStatus.offDuty ? duty.startDuty : null,
        icon: const Icon(Icons.navigation),
        label: const Text(LiveTrackingStrings.startDuty),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('${DriverStrings.tasksTitle}${tasks == null ? '' : ' (${tasks!.length})'}',
          style: AppTextStyles.headlineMd),
      const SizedBox(height: AppSpacing.xs),
      ..._taskList(context, tasks ?? const [], onTap: null),
      if (corridorId != null)
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => RouteStopsPage(corridorId: corridorId!))),
          icon: const Icon(Icons.format_list_numbered),
          label: const Text(DriverStrings.routeOrder),
        ),
    ];
  }

  List<Widget> _onDuty(BuildContext context) {
    final nav = navigation;
    final target = nav?.target;
    final busy = actingStopId != null;
    final listed = {target?.stopId, ...?nav?.upcoming.map((u) => u.stopId)};
    final otherTasks = [
      for (final t in tasks ?? const <DriverTaskStop>[])
        if (!listed.contains(t.stopId)) t,
    ];
    return [
      if (target != null) ...[
        NavEtaRow(durationS: nav!.durationS, distanceM: nav.distanceM),
        const SizedBox(height: AppSpacing.xs),
        Text(
            target.position == null
                ? DriverStrings.nextStop
                : DriverStrings.nextStopNumbered(target.position!),
            style: AppTextStyles.bodySm),
        Text(target.name, style: AppTextStyles.headlineMd),
        if (target.hasPassengers) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(DriverStrings.passengersAt(target.pickupSeats, target.dropoffSeats),
              style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w700)),
          if (nearTarget) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(DriverStrings.arrivedNear,
                style: AppTextStyles.bodySm.copyWith(color: navGreen)),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(
              child: FilledButton(
                style: nearTarget
                    ? FilledButton.styleFrom(backgroundColor: navGreen)
                    : null,
                onPressed: busy ? null : () => onArrived(target),
                child: const Text(DriverStrings.arrived),
              ),
            ),
            if (target.pickupSeats > 0) ...[
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => onDeparted(target),
                  child: const Text(DriverStrings.departed),
                ),
              ),
            ],
          ]),
        ],
        if (nav.upcoming.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const Text(DriverStrings.afterThat, style: AppTextStyles.headlineMd),
          const SizedBox(height: AppSpacing.xs),
          for (final stop in nav.upcoming)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: stop.hasPassengers
                    ? AppColors.secondary
                    : AppColors.surfaceContainerHigh,
                child: Text(stop.position?.toString() ?? 'V',
                    style: AppTextStyles.labelMd.copyWith(
                        color: stop.hasPassengers
                            ? Colors.white
                            : AppColors.onSurface)),
              ),
              title: Text(stop.name, style: AppTextStyles.bodyMd),
              subtitle: stop.hasPassengers
                  ? Text(DriverStrings.passengersAt(
                      stop.pickupSeats, stop.dropoffSeats))
                  : null,
              trailing: IconButton(
                tooltip: DriverStrings.navigateHere,
                icon: const Icon(Icons.directions),
                onPressed: () => onChoose(stop.stopId),
              ),
            ),
        ],
      ],
      if (otherTasks.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        const Text(DriverStrings.otherTaskStops, style: AppTextStyles.headlineMd),
        const SizedBox(height: AppSpacing.xs),
        ..._taskList(context, otherTasks, onTap: (t) => onChoose(t.stopId)),
      ],
      const SizedBox(height: AppSpacing.md),
      Text(_statusText(), style: AppTextStyles.bodySm),
      ..._issue(),
      const SizedBox(height: AppSpacing.sm),
      OutlinedButton(
        style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error)),
        onPressed: duty.stopDuty,
        child: const Text(LiveTrackingStrings.stopDuty),
      ),
    ];
  }

  List<Widget> _taskList(BuildContext context, List<DriverTaskStop> stops,
      {ValueChanged<DriverTaskStop>? onTap}) {
    if (tasks == null && tasksFailed) {
      return [
        const Text(DriverStrings.tasksFailed, style: AppTextStyles.bodySm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
              onPressed: onRetryTasks, child: const Text(LiveTrackingStrings.retry)),
        ),
      ];
    }
    if (tasks == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Center(child: CircularProgressIndicator()),
        )
      ];
    }
    if (stops.isEmpty) {
      return const [Text(DriverStrings.tasksEmpty, style: AppTextStyles.bodySm)];
    }
    return [
      for (final stop in stops)
        Card(
          color: AppColors.surfaceContainerLow,
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: ListTile(
            leading: TaskStopMarker(stop: stop),
            title: Text(stop.name, style: AppTextStyles.bodyLg),
            subtitle: _TaskChips(stop: stop),
            trailing: onTap == null
                ? null
                : IconButton(
                    tooltip: DriverStrings.navigateHere,
                    icon: const Icon(Icons.directions),
                    onPressed: () => onTap(stop),
                  ),
            onTap: onTap == null ? null : () => onTap(stop),
          ),
        ),
    ];
  }

  List<Widget> _issue() {
    final text = _issueText(duty.issue);
    return [
      if (text != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(text, style: AppTextStyles.bodySm.copyWith(color: AppColors.error)),
      ],
      if (duty.issue == DutyIssue.permissionDeniedForever)
        const TextButton(
            onPressed: Geolocator.openAppSettings,
            child: Text(LiveTrackingStrings.openSettings)),
      if (duty.issue == DutyIssue.locationServiceDisabled)
        const TextButton(
            onPressed: Geolocator.openLocationSettings,
            child: Text(LiveTrackingStrings.openSettings)),
    ];
  }

  String _statusText() {
    switch (duty.status) {
      case DutyStatus.starting:
        return LiveTrackingStrings.starting;
      case DutyStatus.onDuty:
        final sent = duty.lastSentAt;
        if (sent == null) {
          return '${LiveTrackingStrings.onDuty} · ${LiveTrackingStrings.waitingFirstFix}';
        }
        return '${LiveTrackingStrings.onDuty} · ${LiveTrackingStrings.lastSent(_clock(sent.toLocal()))}';
      default:
        return LiveTrackingStrings.offDuty;
    }
  }

  static String _clock(DateTime t) => [t.hour, t.minute, t.second]
      .map((v) => v.toString().padLeft(2, '0'))
      .join(':');

  static String? _issueText(DutyIssue issue) => switch (issue) {
        DutyIssue.none => null,
        DutyIssue.permissionDenied => LiveTrackingStrings.permissionDenied,
        DutyIssue.permissionDeniedForever =>
          LiveTrackingStrings.permissionDeniedForever,
        DutyIssue.locationServiceDisabled =>
          LiveTrackingStrings.locationServiceDisabled,
        DutyIssue.outsideServiceArea => LiveTrackingStrings.outsideServiceArea,
        DutyIssue.weakGps => LiveTrackingStrings.weakGps,
        DutyIssue.sendFailed => LiveTrackingStrings.sendFailed,
        DutyIssue.sessionExpired => LiveTrackingStrings.sessionExpired,
      };
}

class _TaskChips extends StatelessWidget {
  const _TaskChips({required this.stop});

  final DriverTaskStop stop;

  @override
  Widget build(BuildContext context) => Text(
        '${stop.phase == StopPhase.pickup ? DriverStrings.pickup : DriverStrings.dropoff} · '
        '${DriverStrings.seats(stop.seats)} · '
        '${stop.isVirtual ? DriverStrings.virtualStop : DriverStrings.staticStop}',
        style: AppTextStyles.bodySm,
      );
}
