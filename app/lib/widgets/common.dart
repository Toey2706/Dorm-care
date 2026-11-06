import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';

/// ป้ายสถานะ ใช้คำเดียวกับ LINE
class StageChip extends StatelessWidget {
  const StageChip(this.ticket, {super.key});
  final Ticket ticket;

  static (String, Color) style(Ticket t) {
    switch (t.stage) {
      case TicketStage.pending:
        return (t.assignedTo == null ? 'รอดำเนินการ · ยังไม่มอบหมาย' : 'รอดำเนินการ', const Color(0xFFB26A00));
      case TicketStage.repairing:
        return ('กำลังซ่อม', const Color(0xFF1E5BB8));
      case TicketStage.completed:
        return (t.notifiedAt == null ? 'ซ่อมเสร็จ · รอแจ้ง LINE' : 'ซ่อมเสร็จแล้ว', const Color(0xFF2E7D32));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = style(ticket);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class TicketTile extends StatelessWidget {
  const TicketTile({super.key, required this.ticket, required this.onTap});
  final Ticket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text('${ticket.ticketNo} · ห้อง ${ticket.roomNo}', style: Theme.of(context).textTheme.labelMedium)),
                StageChip(ticket),
              ]),
              const SizedBox(height: 6),
              Text(ticket.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text('${ticket.categoryLabel} · ${thaiDate(ticket.createdAt)}', style: Theme.of(context).textTheme.bodySmall),
              if (ticket.assignedToName != null)
                Text('ช่าง: ${ticket.assignedToName}', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
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
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 96,
                height: 96,
                child: snap.hasData
                    ? GestureDetector(
                        onTap: () => showDialog(context: context, builder: (_) => Dialog(child: Image.network(snap.data!))),
                        child: Image.network(snap.data!, fit: BoxFit.cover),
                      )
                    : const ColoredBox(color: Color(0xFFEDEDED), child: Icon(Icons.image_outlined)),
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
