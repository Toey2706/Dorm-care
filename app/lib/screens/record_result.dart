import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/common.dart';

/// ช่างบันทึกผลตรวจ/ผลซ่อม งานจะเป็น "ซ่อมเสร็จแล้ว"
/// การบันทึกผลไม่ส่งข้อความ LINE ถึงผู้พัก (ผู้ดูแลเป็นผู้สั่งแจ้งผล)
class RecordResultScreen extends StatefulWidget {
  const RecordResultScreen({super.key, required this.ticket});
  final Ticket ticket;

  @override
  State<RecordResultScreen> createState() => _RecordResultScreenState();
}

class _RecordResultScreenState extends State<RecordResultScreen> {
  static const maxPhotos = 3;
  late final _inspection = TextEditingController(text: widget.ticket.inspectionNote ?? '');
  late final _result = TextEditingController(text: widget.ticket.repairResult ?? '');
  final _photos = <Uint8List>[];
  bool _busy = false;

  @override
  void dispose() {
    _inspection.dispose();
    _result.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return; // ผู้ใช้ออกจากหน้าระหว่างเลือกรูป
    setState(() => _photos.add(bytes));
  }

  Future<void> _submit() async {
    if (_inspection.text.trim().isEmpty || _result.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกสิ่งที่ตรวจพบและผลการซ่อม')));
      return;
    }
    final confirmed = await confirmDialog(context, 'บันทึกผลและปิดงาน?', 'งานจะเป็น "ซ่อมเสร็จแล้ว" และแก้ไขภายหลังไม่ได้ ผู้ดูแลจะเป็นผู้แจ้งผลถึงผู้พักทาง LINE', 'บันทึกผล');
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      final paths = <String>[];
      for (final bytes in _photos) {
        paths.add(await Api.instance.uploadRepairPhoto(widget.ticket.id, bytes));
      }
      await Api.instance.submitResult(widget.ticket.id, _inspection.text.trim(), _result.text.trim(), paths);
    }, success: 'บันทึกผลแล้ว งานซ่อมเสร็จ');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    return Scaffold(
      appBar: AppBar(title: const Text('บันทึกผลการซ่อม')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${t.ticketNo} · ห้อง ${t.roomNo}', style: Theme.of(context).textTheme.titleSmall),
          Text(t.description),
          const SizedBox(height: 16),
          TextField(
            controller: _inspection,
            maxLines: 3,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'สิ่งที่ตรวจพบ *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _result,
            maxLines: 3,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'การแก้ไข / ผลการซ่อม *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Text('รูปหลังซ่อม (${_photos.length}/$maxPhotos)'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < _photos.length; i++)
              Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_photos[i], width: 96, height: 96, fit: BoxFit.cover)),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton.filledTonal(
                    iconSize: 16,
                    onPressed: _busy ? null : () => setState(() => _photos.removeAt(i)),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ]),
          ]),
          if (_photos.length < maxPhotos)
            Row(children: [
              TextButton.icon(onPressed: _busy ? null : () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('ถ่ายรูป')),
              TextButton.icon(onPressed: _busy ? null : () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('เลือกรูป')),
            ]),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('บันทึกผลและปิดงาน'),
          ),
        ],
      ),
    );
  }
}
