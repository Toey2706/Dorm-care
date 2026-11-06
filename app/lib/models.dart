import 'package:intl/intl.dart';

/// บทบาทพนักงาน (USR-02)
enum StaffRole { admin, technician }

class Staff {
  Staff({required this.id, required this.email, required this.name, required this.phone, required this.role, required this.active});

  final String id; // user id ของ Supabase Auth
  final String email;
  final String name;
  final String? phone; // เบอร์ติดต่อ ไม่ได้ใช้ล็อกอิน
  final StaffRole role;
  final bool active;

  bool get isAdmin => role == StaffRole.admin;

  factory Staff.fromJson(Map<String, dynamic> d) => Staff(
        id: d['user_id'] as String,
        email: (d['email'] as String?) ?? '',
        name: (d['name'] as String?) ?? '',
        phone: d['phone'] as String?,
        role: d['role'] == 'ADMIN' ? StaffRole.admin : StaffRole.technician,
        active: d['active'] != false,
      );
}

/// หมวดงาน (ต้องตรงกับ supabase/functions/_shared/conversation.js)
const categoryLabels = <String, String>{
  'PLUMBING': 'ประปา',
  'ELECTRICAL': 'ไฟฟ้า',
  'AIRCON': 'เครื่องปรับอากาศ',
  'FURNITURE': 'เฟอร์นิเจอร์',
  'OTHER': 'อื่น ๆ',
};

enum TicketStage { pending, repairing, completed }

class Ticket {
  Ticket({
    required this.id,
    required this.ticketNo,
    required this.roomNo,
    required this.reporterName,
    required this.category,
    required this.description,
    required this.photoPaths,
    required this.status,
    required this.assignedTo,
    required this.assignedToName,
    required this.inspectionNote,
    required this.repairResult,
    required this.repairPhotoPaths,
    required this.createdAt,
    required this.completedAt,
    required this.notifiedAt,
  });

  final String id;
  final String ticketNo;
  final String roomNo;
  final String reporterName;
  final String category;
  final String description;
  final List<String> photoPaths;
  final String status; // PENDING / REPAIRING / COMPLETED
  final String? assignedTo;
  final String? assignedToName;
  final String? inspectionNote;
  final String? repairResult;
  final List<String> repairPhotoPaths;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final DateTime? notifiedAt;

  String get categoryLabel => categoryLabels[category] ?? category;

  TicketStage get stage {
    if (status == 'COMPLETED') return TicketStage.completed;
    if (status == 'REPAIRING') return TicketStage.repairing;
    return TicketStage.pending;
  }

  static List<String> _list(dynamic v) => v is List ? v.whereType<String>().toList() : <String>[];

  factory Ticket.fromJson(Map<String, dynamic> d) => Ticket(
        id: d['id'] as String,
        ticketNo: (d['ticket_no'] as String?) ?? '-',
        roomNo: (d['room_no'] as String?) ?? '-',
        reporterName: (d['reporter_name'] as String?) ?? '',
        category: (d['category'] as String?) ?? 'OTHER',
        description: (d['description'] as String?) ?? '',
        photoPaths: _list(d['photo_paths']),
        status: (d['status'] as String?) ?? 'PENDING',
        assignedTo: d['assigned_to'] as String?,
        assignedToName: d['assigned_to_name'] as String?,
        inspectionNote: d['inspection_note'] as String?,
        repairResult: d['repair_result'] as String?,
        repairPhotoPaths: _list(d['repair_photo_paths']),
        createdAt: parseTime(d['created_at']),
        completedAt: parseTime(d['completed_at']),
        notifiedAt: parseTime(d['notified_at']),
      );
}

class HistoryEntry {
  HistoryEntry({required this.action, required this.note, required this.actorName, required this.at});

  final String action;
  final String note;
  final String actorName;
  final DateTime? at;

  static const _labels = <String, String>{
    'CREATE': 'ผู้พักแจ้งซ่อม',
    'ASSIGN': 'มอบหมายช่าง',
    'REASSIGN': 'เปลี่ยนช่าง',
    'START': 'เริ่มซ่อม',
    'COMPLETE': 'ช่างบันทึกผล ซ่อมเสร็จแล้ว',
    'NOTIFY_LINE': 'แจ้งผลผู้พักทาง LINE',
  };

  String get label => _labels[action] ?? action;

  factory HistoryEntry.fromJson(Map<String, dynamic> d) {
    final name = (d['actor_name'] as String?) ?? '';
    return HistoryEntry(
      action: (d['action'] as String?) ?? '',
      note: (d['note'] as String?) ?? '',
      actorName: name.isEmpty && d['actor_role'] == 'RESIDENT' ? 'ผู้พัก' : name,
      at: parseTime(d['at']),
    );
  }
}

class Binding {
  Binding({required this.id, required this.lineUserId, required this.roomNo, required this.displayName, required this.status, required this.boundAt});

  final int id;
  final String lineUserId;
  final String roomNo;
  final String displayName;
  final String status; // ACTIVE / REVOKED
  final DateTime? boundAt;

  factory Binding.fromJson(Map<String, dynamic> d) => Binding(
        id: (d['id'] as num).toInt(),
        lineUserId: d['line_user_id'] as String,
        roomNo: (d['room_no'] as String?) ?? '-',
        displayName: (d['display_name'] as String?) ?? '',
        status: (d['status'] as String?) ?? 'ACTIVE',
        boundAt: parseTime(d['bound_at']),
      );
}

DateTime? parseTime(dynamic v) => v is String ? DateTime.tryParse(v) : null;

/// วันที่แบบไทย เช่น 26 ต.ค. 2569 · 08:40
String thaiDate(DateTime? value) {
  if (value == null) return '-';
  final local = value.toLocal();
  final dm = DateFormat('d MMM', 'th').format(local);
  final time = DateFormat('HH:mm').format(local);
  return '$dm ${local.year + 543} · $time';
}
