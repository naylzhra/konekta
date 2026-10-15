import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_client.dart';
import '../../core/location/user_location_provider.dart';
import '../../core/strings/live_tracking_strings.dart';
import '../../core/theme/konekta_theme.dart';
import '../../shared_widgets/loading_indicator.dart';
import '../live_tracking/data/feeder_api.dart';
import '../live_tracking/state/driver_duty_controller.dart';
import '../live_tracking/ui/service_area_map.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key, required this.token});

  final String token;

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  final _mapController = MapController();
  late final GeolocatorUserLocationProvider _location;
  late final DriverDutyController _duty;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _location = GeolocatorUserLocationProvider(settings: _dutyLocationSettings())..rationale = _showRationale;
    _duty = DriverDutyController(api: FeederApi(ApiClient()), token: widget.token, location: _location)
      ..addListener(_followDriver)
      ..load();
  }

  @override
  void dispose() {
    _duty
      ..removeListener(_followDriver)
      ..dispose();
    _mapController.dispose();
    super.dispose();
  }

  static LocationSettings _dutyLocationSettings() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const LocationSettings(accuracy: LocationAccuracy.high);
    }
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      intervalDuration: const Duration(seconds: 5),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: LiveTrackingStrings.notificationTitle,
        notificationText: LiveTrackingStrings.notificationText,
        notificationChannelName: LiveTrackingStrings.notificationChannel,
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }

  Future<bool> _showRationale() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(LiveTrackingStrings.rationaleTitle),
        content: const Text(LiveTrackingStrings.rationaleBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(LiveTrackingStrings.rationaleCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(LiveTrackingStrings.rationaleContinue),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  void _followDriver() {
    final fix = _duty.lastLocation;
    if (!_mapReady || fix == null || !_duty.isOnDuty) return;
    _mapController.move(LatLng(fix.lat, fix.lng), _mapController.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(LiveTrackingStrings.driverTitle)),
      body: ListenableBuilder(
        listenable: _duty,
        builder: (context, _) => switch (_duty.status) {
          DutyStatus.loading => const LoadingIndicator(),
          DutyStatus.loadFailed => _Message(
              text: _duty.issue == DutyIssue.sessionExpired
                  ? LiveTrackingStrings.sessionExpired
                  : LiveTrackingStrings.loadFailed,
              action: TextButton(onPressed: _duty.load, child: const Text(LiveTrackingStrings.retry)),
            ),
          DutyStatus.noFeeder => const _Message(text: LiveTrackingStrings.noFeeder),
          _ => Column(
              children: [
                Expanded(
                  child: ServiceAreaMap(
                    controller: _mapController,
                    onMapReady: () => _mapReady = true,
                    markers: [
                      if (_duty.lastLocation != null)
                        Marker(
                          point: LatLng(_duty.lastLocation!.lat, _duty.lastLocation!.lng),
                          width: 44,
                          height: 44,
                          child: const _FeederMarker(),
                        ),
                    ],
                  ),
                ),
                _DutyPanel(duty: _duty),
              ],
            ),
        },
      ),
    );
  }
}

class _DutyPanel extends StatelessWidget {
  const _DutyPanel({required this.duty});

  final DriverDutyController duty;

  @override
  Widget build(BuildContext context) {
    final feeder = duty.feeder;
    final issue = _issueText(duty.issue);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.containerMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (feeder != null)
              Text(LiveTrackingStrings.feederLabel(feeder.number, feeder.corridorName), style: AppTextStyles.headlineMd),
            const SizedBox(height: AppSpacing.xs),
            Text(_statusText(), style: AppTextStyles.bodyMd),
            if (issue != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(issue, style: AppTextStyles.bodySm.copyWith(color: AppColors.error)),
            ],
            if (duty.issue == DutyIssue.permissionDeniedForever)
              const TextButton(onPressed: Geolocator.openAppSettings, child: Text(LiveTrackingStrings.openSettings)),
            if (duty.issue == DutyIssue.locationServiceDisabled)
              const TextButton(
                onPressed: Geolocator.openLocationSettings,
                child: Text(LiveTrackingStrings.openSettings),
              ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: switch (duty.status) {
                DutyStatus.offDuty => duty.startDuty,
                DutyStatus.onDuty => duty.stopDuty,
                _ => null,
              },
              style: duty.isOnDuty ? ElevatedButton.styleFrom(backgroundColor: AppColors.error) : null,
              child: Text(duty.isOnDuty ? LiveTrackingStrings.stopDuty : LiveTrackingStrings.startDuty),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText() {
    switch (duty.status) {
      case DutyStatus.starting:
        return LiveTrackingStrings.starting;
      case DutyStatus.onDuty:
        final sent = duty.lastSentAt;
        if (sent == null) return '${LiveTrackingStrings.onDuty}\n${LiveTrackingStrings.waitingFirstFix}';
        return '${LiveTrackingStrings.onDuty}\n${LiveTrackingStrings.lastSent(_clock(sent.toLocal()))}';
      default:
        return LiveTrackingStrings.offDuty;
    }
  }

  static String _clock(DateTime t) =>
      [t.hour, t.minute, t.second].map((v) => v.toString().padLeft(2, '0')).join(':');

  static String? _issueText(DutyIssue issue) => switch (issue) {
        DutyIssue.none => null,
        DutyIssue.permissionDenied => LiveTrackingStrings.permissionDenied,
        DutyIssue.permissionDeniedForever => LiveTrackingStrings.permissionDeniedForever,
        DutyIssue.locationServiceDisabled => LiveTrackingStrings.locationServiceDisabled,
        DutyIssue.outsideServiceArea => LiveTrackingStrings.outsideServiceArea,
        DutyIssue.weakGps => LiveTrackingStrings.weakGps,
        DutyIssue.sendFailed => LiveTrackingStrings.sendFailed,
        DutyIssue.sessionExpired => LiveTrackingStrings.sessionExpired,
      };
}

class _FeederMarker extends StatelessWidget {
  const _FeederMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.onPrimary, width: 3),
      ),
      child: const Icon(Icons.directions_bus, color: AppColors.onPrimary, size: 22),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.containerMargin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: AppTextStyles.bodyMd, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: AppSpacing.md), action!],
          ],
        ),
      ),
    );
  }
}
