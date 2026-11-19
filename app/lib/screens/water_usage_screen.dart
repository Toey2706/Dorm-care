import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/api.dart';

class WaterUsageScreen extends StatefulWidget {
  const WaterUsageScreen({super.key});

  @override
  State<WaterUsageScreen> createState() => _WaterUsageScreenState();
}

class _WaterUsageScreenState extends State<WaterUsageScreen> {
  late Future<List<String>> _rooms = Api.instance.rooms();
  String? _roomNo;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('การใช้น้ำ', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        FutureBuilder<List<String>>(
          future: _rooms,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('โหลดรายชื่อห้องไม่สำเร็จ'),
                  TextButton(
                    onPressed: () =>
                        setState(() => _rooms = Api.instance.rooms()),
                    child: const Text('ลองใหม่'),
                  ),
                ],
              );
            }
            final rooms = snapshot.data;
            if (rooms == null) return const LinearProgressIndicator();
            if (rooms.isEmpty) return const Text('ไม่มีห้องที่เปิดใช้งาน');

            return Card(
              margin: EdgeInsets.zero,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  isExpanded: true,
                  value: _roomNo,
                  hint: const Text('เลือกห้อง'),
                  items: [
                    for (final room in rooms)
                      DropdownMenuItem(value: room, child: Text('ห้อง $room')),
                  ],
                  onChanged: (room) => setState(() => _roomNo = room),
                ),
              ),
            );
          },
        ),
        if (_roomNo case final room?)
          // เปลี่ยนห้องแล้วทิ้งค่ากับคำขอของห้องก่อนหน้า
          _RoomWaterUsage(key: ValueKey(room), roomNo: room),
      ],
    );
  }
}

class _RoomWaterUsage extends StatefulWidget {
  const _RoomWaterUsage({super.key, required this.roomNo});

  final String roomNo;

  @override
  State<_RoomWaterUsage> createState() => _RoomWaterUsageState();
}

class _RoomWaterUsageState extends State<_RoomWaterUsage> {
  late Future<WaterUsage> _reading;
  late final Timer _poll;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _reading = _fetch();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _poll.cancel();
    super.dispose();
  }

  Future<WaterUsage> _fetch() async {
    _fetching = true;
    try {
      return await Api.instance.waterUsage(widget.roomNo);
    } finally {
      _fetching = false;
    }
  }

  void _refresh() {
    if (_fetching) return;
    setState(() => _reading = _fetch());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WaterUsage>(
      future: _reading,
      builder: (context, snapshot) {
        final refreshing = snapshot.connectionState == ConnectionState.waiting;
        final current = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ค่าล่าสุด',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'รีเฟรชค่าน้ำ',
                  onPressed: refreshing ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (refreshing) const LinearProgressIndicator(),
            if (!refreshing && snapshot.hasError)
              Text(
                snapshot.error is ApiException
                    ? '${snapshot.error}'
                    : 'โหลดข้อมูลการใช้น้ำไม่สำเร็จ กรุณาลองใหม่',
              ),
            if (current case final WaterReading reading)
              _WaterReadingCard(reading: reading),
            if (current case WaterUnavailable(:final isConfigured))
              Text(
                isConfigured
                    ? 'ยังไม่มีค่าการใช้น้ำจากมิเตอร์'
                    : 'ห้องนี้ยังไม่ได้ตั้งค่ามิเตอร์น้ำ',
              ),
          ],
        );
      },
    );
  }
}

class _WaterReadingCard extends StatelessWidget {
  const _WaterReadingCard({required this.reading});

  final WaterReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = NumberFormat.decimalPatternDigits(
      locale: 'th',
      decimalDigits: 2,
    );
    final updated = thaiDate(
      reading.receivedAt,
      utcOffset: const Duration(hours: 7),
      showSeconds: true,
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.water_drop_outlined),
            title: const Text('อัตราการไหล'),
            subtitle: Text(
              '${format.format(reading.flowLpm)} ลิตร/นาที',
              style: theme.textTheme.titleLarge,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.water_outlined),
            title: const Text('ปริมาณสะสมตั้งแต่เปิดเครื่อง'),
            subtitle: Text(
              '${format.format(reading.totalLiters)} ลิตร',
              style: theme.textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'อัปเดตล่าสุด $updated (เวลาไทย)',
                  style: theme.textTheme.bodySmall,
                ),
                if (reading.stale)
                  Text(
                    'ข้อมูลเก่า',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
