import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../services/errors.dart';
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
                // ถ้าป้ายสถานะยาวจนไม่พอในบรรทัดเดียวกับเลขห้อง (เช่นบนจอมือถือแคบ) ให้ป้ายลงไปบรรทัดใหม่แทนการตัดคำ
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text('ห้อง ${ticket.roomNo}', style: theme.textTheme.titleMedium?.copyWith(fontSize: 19, fontWeight: FontWeight.w700)),
                    StageChip(ticket),
                  ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(ticket.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  '${ticket.ticketNo} · ${ticket.categoryLabel} · ${thaiDate(ticket.createdAt)}'
                  '${ticket.assignedToName == null ? '' : '\nช่าง: ${ticket.assignedToName}'}',
                  style: theme.textTheme.bodySmall,
                ),
                AgeLabel(ticket),
                if (ticket.residentIssue)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('ผู้พักแจ้งว่ายังมีปัญหา', style: TextStyle(color: Color(0xFF8A3B07), fontWeight: FontWeight.w600)),
                  )
                else if (ticket.residentRating != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('คะแนนผู้พัก ${ticket.residentRating}/5', style: theme.textTheme.bodySmall),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// บอกว่างานที่ยังไม่เสร็จค้างมากี่วัน ผู้ดูแลจะเห็นงานที่ถูกลืมโดยไม่ต้องเปิดดูทีละใบ
/// ไม่แสดงในวันแรก ๆ เพื่อไม่ให้รายการรก สีเข้มขึ้นเมื่อค้างนาน
class AgeLabel extends StatelessWidget {
  const AgeLabel(this.ticket, {super.key});
  final Ticket ticket;

  static int? daysOpen(Ticket t, [DateTime? now]) {
    if (t.stage == TicketStage.completed || t.createdAt == null) return null;
    return (now ?? DateTime.now()).difference(t.createdAt!).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final days = daysOpen(ticket);
    if (days == null || days < 2) return const SizedBox.shrink();
    final color = days >= 7 ? const Color(0xFFB42318) : (days >= 3 ? const Color(0xFFB54708) : mutedText);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.hourglass_bottom, size: 16, color: color),
        const SizedBox(width: 4),
        Text('ค้าง $days วัน', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ]),
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
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final messenger = ScaffoldMessenger.of(context);
  while (true) {
    try {
      await action().timeout(timeout);
      if (success != null) messenger.showSnackBar(SnackBar(content: Text(success)));
      return true;
    } catch (e) {
      if (isSessionError(e)) {
        await AuthService.instance.expireSession();
        return false;
      }
      if (isNetworkError(e) && context.mounted) {
        if (await retryDialog(context)) continue;
        return false;
      }
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      return false;
    }
  }
}

Future<bool> retryDialog(BuildContext context) async {
  final retry = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.wifi_off_rounded),
      title: const Text('การเชื่อมต่อขัดข้อง'),
      content: const Text('กรุณาตรวจสอบสัญญาณอินเทอร์เน็ตแล้วลองใหม่อีกครั้ง'),
      actions: [dialogButtons(
        primary: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ลองใหม่')),
        secondary: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('ปิด')),
      )],
    ),
  );
  return retry ?? false;
}

class LoadError extends StatelessWidget {
  const LoadError(this.error, {super.key, this.prefix = 'โหลดข้อมูลไม่สำเร็จ', this.onRetry});
  final Object error;
  final String prefix;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final network = isNetworkError(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(network ? Icons.wifi_off_rounded : Icons.error_outline, color: mutedText, size: 36),
          const SizedBox(height: 8),
          Text(network ? networkErrorMessage : '$prefix: ${friendlyError(error)}', textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('ลองใหม่')),
          ],
        ]),
      ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, String title, String body, String okLabel) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      // ปุ่มยกเลิกต้องกดง่ายเท่าปุ่มยืนยัน จึงให้กว้างเต็มและสูงเท่ากัน วางซ้อนกันแทนการวางข้างกัน
      actions: [dialogButtons(
        primary: FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(okLabel)),
        secondary: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
      )],
    ),
  );
  return ok ?? false;
}

Widget dialogButtons({required Widget primary, required Widget secondary}) {
  return SizedBox(
    width: double.maxFinite,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [primary, const SizedBox(height: 8), secondary],
    ),
  );
}
