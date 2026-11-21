import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/common.dart';

class WaterScreen extends StatefulWidget {
  const WaterScreen({super.key});

  @override
  State<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends State<WaterScreen> {
  List<WaterDevice>? _devices;
  Object? _error;
  bool _loading = false;
  Timer? _timer;
  late final Stream<List<WaterAlert>> _alerts = Api.instance.waterAlerts();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final list = await Api.instance.waterStatus();
      if (mounted) setState(() {
        _devices = list;
        _error = null;
      });
    } catch (e) {
      if (mounted && _devices == null) setState(() => _error = e);
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('อุปกรณ์วัดน้ำ', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_error != null)
            Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('$_error'), trailing: TextButton(onPressed: _load, child: const Text('ลองใหม่'))))
          else if (_devices == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_devices!.isEmpty)
            const Card(child: ListTile(title: Text('ยังไม่มีห้องที่ติดอุปกรณ์วัดน้ำ')))
          else
            for (final d in _devices!) _DeviceCard(device: d),
          const SizedBox(height: 16),
          Text('แจ้งเตือนน้ำไหลต่อเนื่อง', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          StreamBuilder<List<WaterAlert>>(
            stream: _alerts,
            builder: (context, snap) {
              if (snap.hasError) return Card(child: ListTile(title: Text('โหลดแจ้งเตือนไม่สำเร็จ: ${snap.error}')));
              if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              final items = snap.data!;
              if (items.isEmpty) return const Card(child: ListTile(title: Text('ยังไม่มีแจ้งเตือน')));
              return Column(children: [for (final a in items) _AlertTile(alert: a)]);
            },
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});
  final WaterDevice device;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final scheme = Theme.of(context).colorScheme;
    final (stateText, stateColor, stateIcon) = switch (d.state) {
      _ when !d.online => ('ออฟไลน์', scheme.outline, Icons.cloud_off_outlined),
      'LEAK' => ('สงสัยน้ำรั่ว', scheme.error, Icons.warning_amber_rounded),
      'FLOWING' => ('น้ำกำลังไหล', scheme.primary, Icons.water_drop),
      _ => ('ไม่มีน้ำไหล', scheme.onSurfaceVariant, Icons.water_drop_outlined),
    };
    final flowFor = d.flowSeconds == null || d.flowSeconds == 0 ? null : _duration(d.flowSeconds!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('ห้อง ${d.roomNo}', style: Theme.of(context).textTheme.titleLarge)),
                Icon(stateIcon, color: stateColor, size: 20),
                const SizedBox(width: 4),
                Text(stateText, style: TextStyle(color: stateColor, fontWeight: FontWeight.w600)),
              ],
            ),
            if (d.label.isNotEmpty) Text('${d.label} · ${d.id}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _Metric(label: 'อัตราไหล', value: d.flowLpm == null ? '-' : d.flowLpm!.toStringAsFixed(1), unit: 'L/min')),
                Expanded(child: _Metric(label: 'ปริมาณรวม', value: d.totalL == null ? '-' : d.totalL!.toStringAsFixed(1), unit: 'L')),
              ],
            ),
            if (d.usedToday != null) ...[
              const SizedBox(height: 12),
              Text('ปริมาณน้ำที่ใช้', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: _Metric(label: 'วันนี้', value: _liters(d.usedToday), unit: 'L')),
                  Expanded(child: _Metric(label: '7 วัน', value: _liters(d.usedWeek), unit: 'L')),
                  Expanded(child: _Metric(label: '30 วัน', value: _liters(d.usedMonth), unit: 'L')),
                ],
              ),
            ],
            const SizedBox(height: 8),
            if (flowFor != null) Text('ไหลต่อเนื่องมาแล้ว $flowFor'),
            Text(
              [
                'อัปเดตล่าสุด ${thaiDate(d.lastSeen)}',
                if (d.rssi != null) 'Wi-Fi ${d.rssi} dBm',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (d.error != null) Text(d.error!, style: TextStyle(color: scheme.error)),
          ],
        ),
      ),
    );
  }

  static String _liters(double? v) => v == null ? '-' : v.toStringAsFixed(1);

  static String _duration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m == 0 ? '$s วินาที' : '$m นาที $s วินาที';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.unit});
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.bodySmall),
        Text.rich(TextSpan(children: [
          TextSpan(text: value, style: t.headlineSmall),
          TextSpan(text: ' $unit', style: t.bodyMedium),
        ])),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});
  final WaterAlert alert;

  static const _resultLabels = {
    'NORMAL': 'ใช้น้ำปกติ',
    'LEAK': 'พบน้ำรั่ว ให้ผู้พักแจ้งซ่อม',
  };

  Future<void> _close(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('ปิดเรื่องห้อง ${alert.roomNo}'), subtitle: const Text('เลือกผลการตรวจสอบ')),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(_resultLabels['NORMAL']!),
              onTap: () => Navigator.pop(context, 'NORMAL'),
            ),
            ListTile(
              leading: const Icon(Icons.plumbing),
              title: Text(_resultLabels['LEAK']!),
              onTap: () => Navigator.pop(context, 'LEAK'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    await runAction(context, () => Api.instance.closeWaterAlert(alert.id, result), success: 'ปิดเรื่องแล้ว');
  }

  @override
  Widget build(BuildContext context) {
    final a = alert;
    final scheme = Theme.of(context).colorScheme;
    final leak = a.result == 'LEAK';
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                !a.acked ? Icons.warning_amber_rounded : leak ? Icons.plumbing : Icons.check_circle_outline,
                color: !a.acked ? scheme.error : leak ? scheme.primary : scheme.outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ห้อง ${a.roomNo} · ไหลต่อเนื่อง ${a.minutes} นาที', style: t.titleMedium),
                  Text(
                    [
                      thaiDate(a.createdAt),
                      '${a.flowLpm.toStringAsFixed(1)} L/min',
                      'ส่ง LINE ${a.lineSent} คน',
                    ].join(' · '),
                    style: t.bodySmall,
                  ),
                  if (a.acked) Text('${_resultLabels[a.result] ?? 'ปิดเรื่องแล้ว'} · โดย ${a.ackedName ?? '-'}', style: t.bodyMedium),
                  if (!a.acked)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                        onPressed: () => _close(context),
                        child: const Text('ปิดเรื่อง'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
