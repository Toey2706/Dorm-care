import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
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
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final h in snap.data!)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Padding(padding: EdgeInsets.only(top: 6, right: 8), child: Icon(Icons.circle, size: 8)),
                        Expanded(
                          child: Text(
                            '${h.label}${h.actorName.isEmpty ? '' : ' โดย ${h.actorName}'}'
                            '${h.note.isEmpty ? '' : '\n${h.note}'}\n${thaiDate(h.at)}',
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
