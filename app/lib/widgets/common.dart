import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../theme.dart';

/// ป้ายสถานะ ใช้คำเดียวกับ LINE แสดงสี ไอคอน และข้อความคู่กันเสมอ คนที่แยกสีไม่ออกก็อ่านได้
class StageChip extends StatelessWidget {
  const StageChip(this.ticket, {super.key});
  final Ticket ticket;

  static (String, StageStyle) style(Ticket t) {
    switch (t.stage) {
      case TicketStage.pending:
        return (t.assignedTo == null ? 'รอดำเนินการ · ยังไม่มอบหมาย' : 'รอดำเนินการ', StageStyle.pending);
      case TicketStage.repairing:
        return ('กำลังซ่อม', StageStyle.repairing);
      case TicketStage.completed:
        return t.notifiedAt == null ? ('ซ่อมเสร็จ · รอแจ้ง LINE', StageStyle.awaitingLine) : ('ซ่อมเสร็จแล้ว', StageStyle.done);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, st) = style(ticket);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: st.background, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(st.icon, size: 15, color: st.foreground),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label, style: TextStyle(color: st.foreground, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class TicketTile extends StatelessWidget {
  const TicketTile({super.key, required this.ticket, required this.onTap});
  final Ticket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: const Color(0xFFEEF3FA), borderRadius: BorderRadius.circular(12)),
              child: Icon(categoryIcons[ticket.category] ?? Icons.handyman_outlined, color: brand),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // เลขห้องตัวใหญ่ เพราะเป็นสิ่งที่ผู้ดูแลมองหาก่อนเมื่อไล่รายการ
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text('ห้อง ${ticket.roomNo}', style: theme.textTheme.titleMedium?.copyWith(fontSize: 19, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  // จำกัดความกว้างป้ายไว้ ป้ายยาวจะตัดบรรทัดแทนการดันเลขห้องจนล้น
                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 190), child: StageChip(ticket)),
                ]),
                const SizedBox(height: 4),
                Text(ticket.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  '${ticket.ticketNo} · ${ticket.categoryLabel} · ${thaiDate(ticket.createdAt)}'
                  '${ticket.assignedToName == null ? '' : '\nช่าง: ${ticket.assignedToName}'}',
                  style: theme.textTheme.bodySmall,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class StoragePhotos extends StatelessWidget {
  const StoragePhotos(this.bucket, this.paths, {super.key});
  final String bucket;
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const Text('ไม่มีรูป');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in paths)
          FutureBuilder<String>(
            future: Api.instance.photoUrl(bucket, p),
            builder: (context, snap) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 96,
                height: 96,
                child: snap.hasData
                    ? GestureDetector(
                        onTap: () => showDialog(context: context, builder: (_) => Dialog(child: Image.network(snap.data!))),
                        child: Image.network(snap.data!, fit: BoxFit.cover),
                      )
                    : const ColoredBox(color: Color(0xFFE3E8EF), child: Icon(Icons.image_outlined, color: mutedText)),
              ),
            ),
          ),
      ],
    );
  }
}

/// เรียกงานที่อาจล้มเหลว แล้วแสดงผลเป็น SnackBar
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (success != null) messenger.showSnackBar(SnackBar(content: Text(success)));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    return false;
  }
}

Future<bool> confirmDialog(BuildContext context, String title, String body, String okLabel) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(okLabel)),
      ],
    ),
  );
  return ok ?? false;
}
