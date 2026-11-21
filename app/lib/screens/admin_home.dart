import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../widgets/adaptive_nav.dart';
import '../widgets/common.dart';
import 'bindings_screen.dart';
import 'change_password_screen.dart';
import 'ticket_detail.dart';
import 'water_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key, required this.me});
  final Staff me;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _TicketsPage(me: widget.me),
      const BindingsScreen(),
      const WaterScreen(),
      AccountPage(me: widget.me),
    ];
    return AdaptiveNavScaffold(
      selected: _tab,
      onSelect: (i) => setState(() => _tab = i),
      items: const [
        NavItem(Icons.build_outlined, 'แจ้งซ่อม'),
        NavItem(Icons.meeting_room_outlined, 'ผูกห้อง'),
        NavItem(Icons.water_drop_outlined, 'น้ำ'),
        NavItem(Icons.person_outline, 'บัญชี'),
      ],
      body: pages[_tab],
    );
  }
}

enum _Filter { open, pending, repairing, notNotified, completed }

const _filterLabels = {
  _Filter.open: 'งานค้าง',
  _Filter.pending: 'รอดำเนินการ',
  _Filter.repairing: 'กำลังซ่อม',
  _Filter.notNotified: 'รอแจ้ง LINE',
  _Filter.completed: 'ซ่อมเสร็จ',
};

/// รายการแจ้งซ่อมของผู้ดูแล
/// งานค้างและงานรอแจ้ง LINE โหลดครบทุกรายการ ส่วนงานที่ซ่อมเสร็จแบ่งหน้า
/// การค้นหาค้นจากฐานข้อมูลโดยตรง (เลขที่ใบงาน หรือเลขห้อง)
class _TicketsPage extends StatefulWidget {
  const _TicketsPage({required this.me});
  final Staff me;

  @override
  State<_TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<_TicketsPage> {
  static const pageSize = 30;
  _Filter _filter = _Filter.open;
  String? _category;
  bool _oldestFirst = false; // งานค้างเรียงเก่าสุดก่อน ไว้ไล่เคลียร์งานที่รอนาน
  int _completedLimit = pageSize;
  final _searchController = TextEditingController();
  Future<List<Ticket>>? _searchResult;
  late Future<Map<String, int>> _counts = Api.instance.counts();
  late final Stream<List<Ticket>> _open = Api.instance.openTickets();
  late final Stream<List<Ticket>> _notNotified = Api.instance.notNotifiedTickets();
  Stream<List<Ticket>>? _completed;
  int _completedFor = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshCounts() => setState(() => _counts = Api.instance.counts());

  // ตัวเลขบนตัวกรองนับจากฐานข้อมูลแยกจากรายการ เมื่อรายการแบบ realtime เปลี่ยน (งานใหม่หรือสถานะเปลี่ยน)
  // จึงสั่งนับใหม่ตาม ไม่อย่างนั้นจะเห็น "งานค้าง (0)" ทั้งที่มีงานขึ้นอยู่ในรายการ
  String? _lastSignature;
  void _countsFollow(List<Ticket> items) {
    final sig = items.map((t) => '${t.id}:${t.stage.name}').join(',');
    final changed = _lastSignature != null && _lastSignature != sig;
    _lastSignature = sig;
    if (changed) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _refreshCounts() : null);
  }

  Stream<List<Ticket>> get _stream {
    switch (_filter) {
      case _Filter.open:
      case _Filter.pending:
      case _Filter.repairing:
        return _open;
      case _Filter.notNotified:
        return _notNotified;
      case _Filter.completed:
        if (_completed == null || _completedFor != _completedLimit) {
          _completedFor = _completedLimit;
          _completed = Api.instance.completedTickets(_completedLimit);
        }
        return _completed!;
    }
  }

  List<Ticket> _byCategory(List<Ticket> items) =>
      _category == null ? items : items.where((t) => t.category == _category).toList();

  List<Ticket> _apply(List<Ticket> items) {
    final list = _byCategory(switch (_filter) {
      _Filter.pending => items.where((t) => t.stage == TicketStage.pending).toList(),
      _Filter.repairing => items.where((t) => t.stage == TicketStage.repairing).toList(),
      _Filter.open || _Filter.notNotified || _Filter.completed => List.of(items),
    });
    // ข้อมูลมาเรียงใหม่สุดก่อนอยู่แล้ว กลับลำดับอย่างเดียวพอ (ไม่ใช้กับงานเสร็จที่โหลดทีละหน้า)
    return _oldestFirst && _filter != _Filter.completed ? list.reversed.toList() : list;
  }

  String _countLabel(_Filter f, Map<String, int>? c) {
    if (c == null) return _filterLabels[f]!;
    final n = switch (f) {
      _Filter.open => (c['PENDING'] ?? 0) + (c['REPAIRING'] ?? 0),
      _Filter.pending => c['PENDING'] ?? 0,
      _Filter.repairing => c['REPAIRING'] ?? 0,
      _Filter.notNotified => c['NOT_NOTIFIED'] ?? 0,
      _Filter.completed => c['COMPLETED'] ?? 0,
    };
    return '${_filterLabels[f]} ($n)';
  }

  Future<void> _openTicket(Ticket t) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TicketDetailScreen(ticketId: t.id, me: widget.me)));
    if (mounted) _refreshCounts();
  }

  Widget _categoryChips() {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final entry in <String?, String>{null: 'ทุกหมวด', ...categoryLabels}.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                visualDensity: VisualDensity.compact,
                label: Text(entry.value),
                selected: _category == entry.key,
                showCheckmark: false,
                onSelected: (_) => setState(() => _category = entry.key),
              ),
            ),
        ],
      ),
    );
  }

  Widget _list(List<Ticket> items, {Widget? footer}) {
    if (items.isEmpty) {
      return Center(child: Text(_category == null ? 'ไม่มีรายการ' : 'ไม่มีรายการในหมวด${categoryLabels[_category]}'));
    }
    return TicketListView(
      footer: footer,
      children: [for (final t in items) TicketTile(ticket: t, onTap: () => _openTicket(t))],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(children: [
            Expanded(child: Text('สวัสดี ${widget.me.name} (ผู้ดูแล)', style: Theme.of(context).textTheme.titleMedium)),
            if (_searchResult == null && _filter != _Filter.completed)
              TextButton.icon(
                onPressed: () => setState(() => _oldestFirst = !_oldestFirst),
                icon: const Icon(Icons.swap_vert),
                label: Text(_oldestFirst ? 'เก่าสุดก่อน' : 'ใหม่สุดก่อน'),
              ),
            IconButton(tooltip: 'รีเฟรชตัวเลข', onPressed: _refreshCounts, icon: const Icon(Icons.refresh)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'ค้นหาเลขที่ใบงาน (R2569-0041) หรือเลขห้อง',
              isDense: true,
              suffixIcon: _searchResult == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _searchController.clear();
                        _searchResult = null;
                      }),
                    ),
            ),
            onSubmitted: (v) => setState(() => _searchResult = v.trim().isEmpty ? null : Api.instance.search(v)),
          ),
        ),
        if (_searchResult == null)
          FutureBuilder<Map<String, int>>(
            future: _counts,
            builder: (context, c) => SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final f in _Filter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(_countLabel(f, c.data)),
                        selected: _filter == f,
                        onSelected: (_) => setState(() {
                          _filter = f;
                          _completedLimit = pageSize;
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
        _categoryChips(),
        Expanded(
          child: _searchResult != null
              ? FutureBuilder<List<Ticket>>(
                  future: _searchResult,
                  builder: (context, snap) {
                    if (snap.hasError) return LoadError(snap.error!, prefix: 'ค้นหาไม่สำเร็จ');
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    return _list(_byCategory(snap.data!));
                  },
                )
              : StreamBuilder<List<Ticket>>(
                  key: ValueKey('$_filter-$_completedLimit'),
                  stream: _stream,
                  builder: (context, snap) {
                    if (snap.hasError) return LoadError(snap.error!);
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    _countsFollow(snap.data!);
                    final items = _apply(snap.data!);
                    final more = _filter == _Filter.completed && snap.data!.length >= _completedLimit;
                    return _list(
                      items,
                      footer: more
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: OutlinedButton(
                                onPressed: () => setState(() => _completedLimit += pageSize),
                                child: const Text('โหลดเพิ่ม'),
                              ),
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// หน้าบัญชี ใช้ร่วมกับหน้าช่าง
class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.me});
  final Staff me;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(me.name, style: theme.textTheme.titleLarge),
        Text(me.email),
        if (me.phone != null) Text('โทร ${me.phone}'),
        Text(me.isAdmin ? 'บทบาท: ผู้ดูแลหอพัก' : 'บทบาท: ช่างซ่อมบำรุง'),
        const SizedBox(height: 16),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.lock_reset),
              title: const Text('เปลี่ยนรหัสผ่าน'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen(voluntary: true))),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('นโยบายความเป็นส่วนตัว'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => launchUrl(Uri.parse(privacyUrl), mode: LaunchMode.externalApplication),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: AuthService.instance.signOut, child: const Text('ออกจากระบบ')),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Dorm Care เวอร์ชัน $appVersion',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
