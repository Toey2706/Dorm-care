import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/common.dart';

/// ผู้ดูแลออกรหัสผูกห้อง 6 หลักให้ผู้พัก และยกเลิกการผูกเมื่อผู้พักย้ายออก
/// ผู้พักกด "ผูกเลขห้อง" ใน LINE แล้วพิมพ์รหัส ระบบผูกห้องทันที (รหัสใช้ได้ครั้งเดียว)
class BindingsScreen extends StatelessWidget {
  const BindingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _issueCode(context),
        icon: const Icon(Icons.vpn_key_outlined),
        label: const Text('ออกรหัสผูกห้อง'),
      ),
      body: StreamBuilder<List<Binding>>(
        stream: Api.instance.bindings('ACTIVE'),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('โหลดข้อมูลไม่สำเร็จ: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!..sort((a, b) => a.roomNo.compareTo(b.roomNo));
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              const ListTile(title: Text('บัญชี LINE ที่ผูกห้องแล้ว')),
              if (items.isEmpty) const ListTile(title: Text('ยังไม่มีผู้พักผูกห้อง')),
              for (final b in items)
                ListTile(
                  leading: CircleAvatar(child: Text(b.roomNo, style: const TextStyle(fontSize: 11))),
                  title: Text(b.displayName.isEmpty ? 'ผู้ใช้ LINE' : b.displayName),
                  subtitle: Text('ห้อง ${b.roomNo} · ผูกเมื่อ ${thaiDate(b.boundAt)}'),
                  trailing: TextButton(
                    onPressed: () async {
                      if (!await confirmDialog(context, 'ยกเลิกการผูกห้อง ${b.roomNo}?', 'ใช้เมื่อผู้พักย้ายออก บัญชีนี้จะแจ้งซ่อมห้องนี้ไม่ได้ทันที', 'ยกเลิกการผูก')) return;
                      if (context.mounted) await runAction(context, () => Api.instance.revokeBinding(b.lineUserId), success: 'ยกเลิกการผูกแล้ว');
                    },
                    child: const Text('ยกเลิกการผูก'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _issueCode(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    List<String> rooms;
    try {
      rooms = await Api.instance.rooms();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('โหลดรายชื่อห้องไม่สำเร็จ: $e')));
      return;
    }
    if (!context.mounted) return;
    final roomNo = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('เลือกห้องที่จะออกรหัส')),
            if (rooms.isEmpty) const ListTile(title: Text('ยังไม่มีห้องในระบบ')),
            for (final r in rooms) ListTile(title: Text('ห้อง $r'), onTap: () => Navigator.pop(context, r)),
          ],
        ),
      ),
    );
    if (roomNo == null || !context.mounted) return;

    try {
      final (code, expiresAt) = await Api.instance.createInviteCode(roomNo);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('รหัสผูกห้อง $roomNo'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SelectableText(code, style: Theme.of(context).textTheme.displaySmall?.copyWith(letterSpacing: 6)),
            const SizedBox(height: 12),
            Text('ใช้ได้ครั้งเดียว หมดอายุ ${thaiDate(expiresAt)}\nแจ้งรหัสนี้ให้ผู้พักกด "ผูกเลขห้อง" ใน LINE แล้วพิมพ์รหัส\nรหัสจะแสดงครั้งเดียว ระบบไม่เก็บตัวรหัส'),
          ]),
          actions: [dialogButtons(
            primary: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('เสร็จ')),
            secondary: OutlinedButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              icon: const Icon(Icons.copy),
              label: const Text('คัดลอก'),
            ),
          )],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}
