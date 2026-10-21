import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/konekta_theme.dart';

class DriverStopsTab extends StatefulWidget {
  const DriverStopsTab(
      {super.key, required this.token, required this.feederId});

  final String token;
  final String? feederId;

  @override
  State<DriverStopsTab> createState() => _DriverStopsTabState();
}

class _DriverStopsTabState extends State<DriverStopsTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>>? _stops;
  bool _loading = false;
  String? _error;
  String? _actingStop;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DriverStopsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feederId != widget.feederId) {
      _stops = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    if (widget.feederId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          await _api.send('GET', '/driver/stops', token: widget.token);
      if (!response.isSuccess || response.body is! Map<String, dynamic>) {
        throw Exception();
      }
      final items =
          (response.body as Map<String, dynamic>)['items'] as List<dynamic>;
      if (mounted) setState(() => _stops = items.cast<Map<String, dynamic>>());
    } catch (_) {
      if (mounted) setState(() => _error = 'Daftar halte belum dapat dimuat.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _event(Map<String, dynamic> stop, String action) async {
    if (action == 'departed') {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: const Text('Berangkat dari halte?'),
                content: const Text(
                    'Penumpang yang belum naik akan tercatat tidak hadir.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Batal')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Berangkat')),
                ],
              ));
      if (confirmed != true || !mounted) return;
    }
    final id = stop['stop_id'] as String;
    setState(() => _actingStop = id);
    try {
      final response = await _api.send('POST', '/driver/stops/$id/$action',
          token: widget.token, body: {'feeder_id': widget.feederId});
      if (!response.isSuccess) throw Exception();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(action == 'arrived'
                ? 'Kedatangan dicatat'
                : 'Keberangkatan dicatat')));
      }
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Status halte belum tersimpan. Coba lagi.')));
      }
    } finally {
      if (mounted) setState(() => _actingStop = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Halte tugas'), actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Muat ulang',
              onPressed: _load),
        ]),
        body: widget.feederId == null
            ? const Center(child: Text('Memuat feeder Anda...'))
            : _loading && _stops == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _stops == null
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!),
                        TextButton(
                            onPressed: _load, child: const Text('Coba lagi')),
                      ]))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                            padding: const EdgeInsets.all(
                                AppSpacing.containerMargin),
                            children: [
                              const Text('Tugas aktif',
                                  style: AppTextStyles.headlineLgMobile),
                              const SizedBox(height: AppSpacing.xs),
                              const Text(
                                  'Daftar berubah saat penumpang memesan atau naik. Tarik untuk memuat ulang.',
                                  style: AppTextStyles.bodySm),
                              const SizedBox(height: AppSpacing.lg),
                              if (_stops?.isEmpty ?? true)
                                const ListTile(
                                    leading: Icon(Icons.route_outlined),
                                    title: Text('Belum ada halte tugas'),
                                    subtitle: Text(
                                        'Halte penjemputan dan penurunan aktif akan muncul di sini.')),
                              for (final stop
                                  in _stops ?? <Map<String, dynamic>>[])
                                Card(
                                    color: AppColors.surfaceContainerLow,
                                    margin: const EdgeInsets.only(
                                        bottom: AppSpacing.sm),
                                    child: Padding(
                                        padding:
                                            const EdgeInsets.all(AppSpacing.md),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  stop['name'] as String? ??
                                                      'Halte',
                                                  style:
                                                      AppTextStyles.headlineMd),
                                              const SizedBox(
                                                  height: AppSpacing.xs),
                                              Text(
                                                  '${stop['phase'] == 'pickup' ? 'Penjemputan' : 'Penurunan'} · '
                                                  '${stop['type'] == 'virtual' ? 'Halte virtual' : 'Halte tetap'} · '
                                                  '${stop['seats']} kursi',
                                                  style: AppTextStyles.bodySm),
                                              const SizedBox(
                                                  height: AppSpacing.md),
                                              Wrap(
                                                  spacing: AppSpacing.xs,
                                                  children: [
                                                    FilledButton(
                                                        onPressed:
                                                            _actingStop == null
                                                                ? () => _event(
                                                                    stop,
                                                                    'arrived')
                                                                : null,
                                                        child: const Text(
                                                            'Saya tiba')),
                                                    if (stop['phase'] ==
                                                        'pickup')
                                                      OutlinedButton(
                                                          onPressed:
                                                              _actingStop ==
                                                                      null
                                                                  ? () => _event(
                                                                      stop,
                                                                      'departed')
                                                                  : null,
                                                          child: const Text(
                                                              'Saya berangkat')),
                                                  ]),
                                            ]))),
                            ]),
                      ),
      );
}
