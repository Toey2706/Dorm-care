import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

// realtime_client ก็มีคลาสชื่อ Binding ซ่อนไว้ให้ใช้ของเราใน models.dart
import 'package:supabase_flutter/supabase_flutter.dart' hide Binding;

import '../models.dart';

/// แอปอ่านตารางได้ตาม RLS เท่านั้น การเปลี่ยนสถานะทุกอย่างเรียกฟังก์ชันในฐานข้อมูล (rpc)
/// ซึ่งตรวจบทบาทและสถานะในทรานแซกชันเดียวกับที่เขียน
class Api {
  Api._();
  static final Api instance = Api._();

  SupabaseClient get _sb => Supabase.instance.client;

  Future<Staff?> me() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _sb.from('staff').select().eq('user_id', uid).maybeSingle();
    return row == null ? null : Staff.fromJson(row);
  }

  // stream ของ Supabase กรองที่เซิร์ฟเวอร์ ถ้าแก้แถวจนหลุดเงื่อนไข (เช่น แจ้งผลแล้ว awaiting_notify เป็น false)
  // เซิร์ฟเวอร์จะไม่ส่งการแก้ไขนั้นมา แถวเลยค้างบนหน้าจอ รายการที่งานย้ายเข้าออกได้จึงใช้ _liveTickets แทน
  Stream<List<Ticket>> openTickets() => _liveTickets(() => _sb
      .from('tickets')
      .select()
      .eq('is_open', true)
      .order('created_at', ascending: false));

  Stream<List<Ticket>> notNotifiedTickets() => _liveTickets(() => _sb
      .from('tickets')
      .select()
      .eq('awaiting_notify', true)
      .order('created_at', ascending: false));

  /// ฟังทุกการเปลี่ยนแปลงของ tickets ที่ RLS ให้เห็น แล้วดึงรายการตามเงื่อนไขใหม่ทั้งชุด
  /// หอพักมีงานไม่กี่สิบรายการต่อวัน การดึงใหม่ทุกครั้งจึงไม่หนัก
  /// Stream.multi ทำให้ StreamBuilder ฟังใหม่ได้ทุกครั้งที่สลับตัวกรอง เหมือน stream เดิมของ Supabase
  Stream<List<Ticket>> _liveTickets(Future<List<Map<String, dynamic>>> Function() fetch) => Stream.multi((out) {
        var seq = 0;
        Future<void> load() async {
          final mine = ++seq;
          try {
            final rows = await fetch();
            // ผลของคำขอเก่าที่กลับมาช้ากว่าคำขอใหม่ต้องทิ้ง ไม่งั้นรายการจะย้อนกลับไปเป็นข้อมูลเก่า
            if (mine == seq && !out.isClosed) out.add(rows.map(Ticket.fromJson).toList());
          } catch (e, st) {
            if (!out.isClosed) out.addError(e, st);
          }
        }

        final channel = _sb
            .channel('tickets-live-${_channelSeq++}')
            .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'tickets', callback: (_) => load())
            // โหลดอีกครั้งตอนต่อ realtime สำเร็จ เผื่อมีงานเปลี่ยนระหว่างโหลดครั้งแรกกับตอนเริ่มฟัง
            .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) load();
        });
        // ช่างที่ถูกเปลี่ยนออกจากงานจะไม่ได้รับเหตุการณ์นั้น เพราะ RLS ไม่ให้เห็นแถวหลังแก้แล้ว
        // จึงดึงใหม่ทุก 30 วินาทีด้วย งานจะหายจากรายการช่างเดิมภายในเวลานั้น
        final timer = Timer.periodic(const Duration(seconds: 30), (_) => load());
        load();
        out.onCancel = () {
          timer.cancel();
          return _sb.removeChannel(channel);
        };
      });
  static int _channelSeq = 0;

  /// งานที่ซ่อมเสร็จแล้ว แบ่งหน้า (เพิ่ม limit เมื่อกด "โหลดเพิ่ม")
  /// ช่างเห็นเฉพาะงานของตัวเองอยู่แล้วจาก RLS ไม่ต้องกรองซ้ำ
  Stream<List<Ticket>> completedTickets(int limit) => _sb
      .from('tickets')
      .stream(primaryKey: ['id'])
      .eq('status', 'COMPLETED')
      .order('created_at', ascending: false)
      .limit(limit)
      .map((rows) => rows.map(Ticket.fromJson).toList());

  // ใช้ _liveTickets เพราะเมื่อผู้ดูแลเปลี่ยนช่าง งานต้องหายจากรายการของช่างคนเดิม
  Stream<List<Ticket>> myOpenTickets(String userId) => _liveTickets(() => _sb
          .from('tickets')
          .select()
          .eq('assigned_to', userId)
          .neq('status', 'COMPLETED')
          .order('created_at', ascending: false));

  /// ค้นในฐานข้อมูลตรง ๆ เพราะรายการซ่อมเสร็จบนหน้าจอโหลดมาแค่บางหน้า
  Future<List<Ticket>> search(String input) async {
    final q = input.trim().toUpperCase();
    if (q.isEmpty) return [];
    final byNo = RegExp(r'^R\d{4}-\d{1,4}$').firstMatch(q);
    final List<Map<String, dynamic>> rows;
    if (byNo != null) {
      final parts = q.split('-');
      rows = await _sb.from('tickets').select().eq('ticket_no', '${parts[0]}-${parts[1].padLeft(4, '0')}').limit(5);
    } else {
      rows = await _sb.from('tickets').select().eq('room_no', q).order('created_at', ascending: false).limit(100);
    }
    return rows.map(Ticket.fromJson).toList();
  }

  /// นับจากฐานข้อมูล เพราะรายการซ่อมเสร็จบนหน้าจอโหลดไม่ครบ
  Future<Map<String, int>> counts() async {
    Future<int> c(String column, Object value) async =>
        (await _sb.from('tickets').select('id').eq(column, value).count(CountOption.exact)).count;
    final r = await Future.wait([
      c('status', 'PENDING'),
      c('status', 'REPAIRING'),
      c('status', 'COMPLETED'),
      c('awaiting_notify', true),
    ]);
    return {'PENDING': r[0], 'REPAIRING': r[1], 'COMPLETED': r[2], 'NOT_NOTIFIED': r[3]};
  }

  Stream<Ticket?> ticket(String id) => _sb
      .from('tickets')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .map((rows) => rows.isEmpty ? null : Ticket.fromJson(rows.first));

  // supabase_flutter เรียงจากมากไปน้อยถ้าไม่ระบุ ascending ทุกรายการในไฟล์นี้จึงระบุทิศทางเอง
  Stream<List<HistoryEntry>> history(String ticketId) => _sb
      .from('ticket_history')
      .stream(primaryKey: ['id'])
      .eq('ticket_id', ticketId)
      .order('at', ascending: true)
      .map((rows) => rows.map(HistoryEntry.fromJson).toList());

  Future<List<Staff>> technicians() async {
    final rows = await _sb.from('staff').select().eq('role', 'TECHNICIAN').eq('active', true).order('name', ascending: true);
    return rows.map(Staff.fromJson).toList();
  }

  Stream<List<Binding>> bindings(String status) => _sb
      .from('line_bindings')
      .stream(primaryKey: ['id'])
      .eq('status', status)
      .order('room_no', ascending: true)
      .map((rows) => rows.map(Binding.fromJson).toList());

  Future<List<String>> rooms() async {
    final rows = await _sb.from('rooms').select('room_no').eq('active', true).order('room_no', ascending: true);
    return rows.map((r) => r['room_no'] as String).toList();
  }

  /// รูปจากผู้พักอยู่ใน resident-photos รูปหลังซ่อมอยู่ใน repair-photos ทั้งสองเป็น bucket ส่วนตัว
  /// ลิงก์ที่ได้ใช้ได้ 1 ชั่วโมง
  Future<String> photoUrl(String bucket, String path) => _sb.storage.from(bucket).createSignedUrl(path, 3600);

  Future<dynamic> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      return await _sb.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      // ฟังก์ชันในฐานข้อมูลส่งข้อความภาษาไทยมาใน message อยู่แล้ว
      throw ApiException(e.code == 'P0001' ? e.message : 'ทำรายการไม่สำเร็จ กรุณาลองใหม่');
    }
  }

  Future<void> assign(String ticketId, String technicianId) =>
      _rpc('assign_ticket', {'p_ticket_id': ticketId, 'p_technician_id': technicianId});

  Future<void> startRepair(String ticketId) => _rpc('start_repair', {'p_ticket_id': ticketId});

  Future<void> submitResult(String ticketId, String inspectionNote, String repairResult, List<String> photoPaths) =>
      _rpc('submit_result', {
        'p_ticket_id': ticketId,
        'p_inspection': inspectionNote,
        'p_result': repairResult,
        'p_photo_paths': photoPaths,
      });

  /// รหัสคำขอที่ยังส่งไม่สำเร็จต่อใบงาน: กดลองใหม่หลังล้มเหลวจะใช้รหัสเดิม LINE จึงไม่ส่งซ้ำ
  final _pendingNotify = <String, String>{};

  Future<void> notifyResident(String ticketId) async {
    final requestId = _pendingNotify.putIfAbsent(ticketId, _uuidV4);
    try {
      await _sb.functions.invoke('notify-resident', body: {'ticket_id': ticketId, 'request_id': requestId});
    } on FunctionException catch (e) {
      final d = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : <String, dynamic>{};
      throw ApiException((d['message'] as String?) ?? 'ส่งข้อความ LINE ไม่สำเร็จ กรุณาลองใหม่');
    }
    _pendingNotify.remove(ticketId); // สำเร็จแล้ว การกดครั้งต่อไปคือ "แจ้งผลซ้ำ" โดยตั้งใจ ใช้รหัสใหม่
  }

  static String _uuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// ออกรหัสผูกห้อง 6 หลัก คืน (รหัส, วันหมดอายุ) รหัสแสดงครั้งเดียว ฐานข้อมูลเก็บแค่ค่า Hash
  Future<(String, DateTime)> createInviteCode(String roomNo) async {
    final data = Map<String, dynamic>.from(await _rpc('create_invite_code', {'p_room_no': roomNo}) as Map);
    return (data['code'] as String, DateTime.parse(data['expires_at'] as String));
  }

  Future<void> revokeBinding(String lineUserId) => _rpc('revoke_binding', {'p_line_user_id': lineUserId});

  /// อัปโหลดรูปผลซ่อมไปที่ repair-photos/{ticketId}/... คืนตำแหน่งไฟล์
  /// อัปโหลดได้เฉพาะช่างที่รับงานนี้และงานกำลังซ่อม (storage policy)
  Future<String> uploadRepairPhoto(String ticketId, Uint8List bytes) async {
    final path = '$ticketId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await _sb.storage.from('repair-photos').uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    } on StorageException catch (e) {
      throw ApiException('อัปโหลดรูปไม่สำเร็จ: ${e.message}');
    }
    return path;
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
