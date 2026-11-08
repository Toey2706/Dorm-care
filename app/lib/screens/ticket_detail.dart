import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'record_result.dart';

/// รายละเอียดใบแจ้งซ่อม ปุ่มที่แสดงขึ้นกับบทบาทและสถานะงาน
class TicketDetailScreen extends StatelessWidget {
  const TicketDetailScreen({super.key, required this.ticketId, required this.me});
  final String ticketId;
  final Staff me;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Ticket?>(
      stream: Api.instance.ticket(ticketId),
      builder: (context, snap) {
        final t = snap.data;
        return Scaffold(
          appBar: AppBar(title: Text(t?.ticketNo ?? 'ใบแจ้งซ่อม')),
          body: snap.hasError
              ? Center(child: Text('โหลดข้อมูลไม่สำเร็จ: ${snap.error}'))
              : t == null
                  ? const Center(child: CircularProgressIndicator())
                  : _Body(ticket: t),
          bottomNavigationBar: t == null ? null : _Actions(ticket: t, me: me),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final theme = Theme.of(context);
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 96, child: Text(k, style: theme.textTheme.bodySmall)),
            Expanded(child: Text(v)),
          ]),
        );
    Widget section(String title, List<Widget> children) => Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...children,
            ]),
          ),
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        section('ข้อมูลงาน', [
          Align(alignment: Alignment.centerLeft, child: StageChip(t)),
          const SizedBox(height: 8),
          row('ห้อง', t.roomNo),
          _RoomRepeat(t.roomNo),
          row('หมวดงาน', t.categoryLabel),
          row('แจ้งเมื่อ', thaiDate(t.createdAt)),
          row('ผู้แจ้ง', t.reporterName.isEmpty ? 'ผู้พัก (LINE)' : '${t.reporterName} (LINE)'),
          row('ผู้รับผิดชอบ', t.assignedToName ?? 'ยังไม่มอบหมาย'),
          if (t.completedAt != null) row('ซ่อมเสร็จเมื่อ', thaiDate(t.completedAt)),
          if (t.notifiedAt != null) row('แจ้ง LINE เมื่อ', thaiDate(t.notifiedAt)),
        ]),
        section('รายละเอียดจากผู้แจ้ง', [Text(t.description), const SizedBox(height: 8), StoragePhotos('resident-photos', t.photoPaths)]),
        if (t.repairResult != null)
          section('ผลการตรวจและซ่อม', [
            row('สิ่งที่ตรวจพบ', t.inspectionNote ?? '-'),
            row('การแก้ไข', t.repairResult ?? '-'),
            const SizedBox(height: 8),
            StoragePhotos('repair-photos', t.repairPhotoPaths),
          ]),
        section('ประวัติการดำเนินงาน', [
          StreamBuilder<List<HistoryEntry>>(
            stream: Api.instance.history(t.id),
            builder: (context, snap) {
              if (!snap.hasData) return const LinearProgressIndicator();
              final items = snap.data!;
              // เส้นเวลาแนวตั้ง จุดล่าสุดเป็นสีหลัก อ่านลำดับเหตุการณ์ได้ง่ายกว่ารายการจุดธรรมดา
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++)
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SizedBox(
                          width: 24,
                          child: Column(children: [
                            const SizedBox(height: 6),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == items.length - 1 ? brand : const Color(0xFF94A3B8),
                              ),
                            ),
                            if (i < items.length - 1)
                              Expanded(child: Container(width: 2, color: const Color(0xFFE3E8EF))),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                '${items[i].label}${items[i].actorName.isEmpty ? '' : ' โดย ${items[i].actorName}'}',
                                style: TextStyle(
                                  fontWeight: i == items.length - 1 ? FontWeight.w600 : FontWeight.w500,
                                  color: i == items.length - 1 ? brand : null,
                                ),
                              ),
                              if (items[i].note.isNotEmpty) Text(items[i].note),
                              Text(thaiDate(items[i].at), style: Theme.of(context).textTheme.bodySmall),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                ],
              );
            },
          ),
        ]),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.ticket, required this.me});
  final Ticket ticket;
  final Staff me;

  @override
  Widget build(BuildContext context) {
    final buttons = me.isAdmin ? _adminButtons(context) : _techButtons(context);
    if (buttons.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [for (final b in buttons) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: b))]),
      ),
    );
  }

  List<Widget> _adminButtons(BuildContext context) {
    final t = ticket;
    switch (t.stage) {
      case TicketStage.pending:
        return [FilledButton(onPressed: () => _assign(context), child: Text(t.assignedTo == null ? 'มอบหมายช่าง' : 'เปลี่ยนช่าง'))];
      case TicketStage.completed:
        return [
          FilledButton.icon(
            icon: const Icon(Icons.chat_outlined),
            onPressed: () async {
              final again = t.notifiedAt != null;
              if (!await confirmDialog(
                context,
                again ? 'แจ้งผลซ้ำทาง LINE?' : 'แจ้งผลถึงผู้พักทาง LINE?',
                'ระบบจะส่งผลการซ่อม ${t.ticketNo} ไปยังบัญชี LINE ของผู้แจ้ง ห้อง ${t.roomNo}',
                'แจ้งผล',
              )) {
                return;
              }
              if (context.mounted) await runAction(context, () => Api.instance.notifyResident(t.id), success: 'ส่งข้อความ LINE แล้ว');
            },
            label: Text(t.notifiedAt == null ? 'แจ้งผลทาง LINE' : 'แจ้งผลซ้ำทาง LINE'),
          ),
        ];
      case TicketStage.repairing:
        return [];
    }
  }

  List<Widget> _techButtons(BuildContext context) {
    final t = ticket;
    if (t.assignedTo != me.id) return [];
    switch (t.stage) {
      case TicketStage.pending:
        return [
          FilledButton(
            onPressed: () async {
              if (!await confirmDialog(context, 'เริ่มซ่อม?', 'สถานะจะเปลี่ยนเป็น "กำลังซ่อม"', 'เริ่มซ่อม')) return;
              if (context.mounted) await runAction(context, () => Api.instance.startRepair(t.id), success: 'เริ่มซ่อมแล้ว');
            },
            child: const Text('เริ่มซ่อม'),
          ),
        ];
      case TicketStage.repairing:
        return [
          FilledButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordResultScreen(ticket: t))),
            child: const Text('บันทึกผลการซ่อม'),
          ),
        ];
      case TicketStage.completed:
        return [];
    }
  }

  Future<void> _assign(BuildContext context) async {
    final techs = await Api.instance.technicians();
    if (!context.mounted) return;
    final chosen = await showModalBottomSheet<Staff>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('เลือกช่างที่รับผิดชอบ')),
            if (techs.isEmpty) const ListTile(title: Text('ยังไม่มีช่างในระบบ')),
            for (final s in techs)
              ListTile(
                leading: const Icon(Icons.engineering_outlined),
                title: Text(s.name),
                subtitle: Text(s.email),
                selected: s.id == ticket.assignedTo,
                onTap: () => Navigator.pop(context, s),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    await runAction(context, () => Api.instance.assign(ticket.id, chosen.id), success: 'มอบหมายให้ ${chosen.name} แล้ว');
  }
}

/// ห้องที่แจ้งซ่อมบ่อยอาจมีปัญหาที่ต้นเหตุ บอกจำนวนครั้งใน 90 วันใต้เลขห้อง
/// แสดงเฉพาะเมื่อมีใบอื่นนอกจากใบนี้ และเน้นสีเมื่อตั้งแต่ 3 ครั้งขึ้นไป
class _RoomRepeat extends StatelessWidget {
  const _RoomRepeat(this.roomNo);
  final String roomNo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: Api.instance.roomTicketCount(roomNo),
      builder: (context, snap) {
        final n = snap.data ?? 0;
        if (n < 2) return const SizedBox.shrink();
        final warn = n >= 3;
        return Padding(
          padding: const EdgeInsets.only(left: 96, bottom: 4),
          child: Text(
            'ห้องนี้แจ้งซ่อม $n ครั้งใน 90 วันที่ผ่านมา',
            style: TextStyle(fontSize: 14, color: warn ? const Color(0xFFB54708) : mutedText, fontWeight: warn ? FontWeight.w600 : FontWeight.w400),
          ),
        );
      },
    );
  }
}
