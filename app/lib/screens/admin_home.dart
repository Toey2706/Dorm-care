import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../widgets/common.dart';
import 'bindings_screen.dart';
import 'ticket_detail.dart';

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
      AccountPage(me: widget.me),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.build_outlined), label: 'แจ้งซ่อม'),
          NavigationDestination(icon: Icon(Icons.meeting_room_outlined), label: 'ผูกห้อง'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'บัญชี'),
        ],
      ),
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

  List<Ticket> _apply(List<Ticket> items) {
    switch (_filter) {
      case _Filter.pending:
        return items.where((t) => t.stage == TicketStage.pending).toList();
      case _Filter.repairing:
        return items.where((t) => t.stage == TicketStage.repairing).toList();
      case _Filter.open:
      case _Filter.notNotified:
      case _Filter.completed:
        return items;
    }
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

  Widget _list(List<Ticket> items, {Widget? footer}) {
    if (items.isEmpty) return const Center(child: Text('ไม่มีรายการ'));
    return ListView(children: [
      for (final t in items) TicketTile(ticket: t, onTap: () => _openTicket(t)),
      if (footer != null) footer,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(children: [
            Expanded(child: Text('สวัสดี ${widget.me.name} (ผู้ดูแล)', style: Theme.of(context).textTheme.titleMedium)),
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
              border: const OutlineInputBorder(),
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
        Expanded(
          child: _searchResult != null
              ? FutureBuilder<List<Ticket>>(
                  future: _searchResult,
                  builder: (context, snap) {
                    if (snap.hasError) return Center(child: Text('ค้นหาไม่สำเร็จ: ${snap.error}'));
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    return _list(snap.data!);
                  },
                )
              : StreamBuilder<List<Ticket>>(
                  key: ValueKey('$_filter-$_completedLimit'),
                  stream: _stream,
                  builder: (context, snap) {
                    if (snap.hasError) return Center(child: Text('โหลดข้อมูลไม่สำเร็จ: ${snap.error}'));
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(me.name, style: Theme.of(context).textTheme.titleLarge),
        Text(me.email),
        if (me.phone != null) Text('โทร ${me.phone}'),
        Text(me.isAdmin ? 'บทบาท: ผู้ดูแลหอพัก' : 'บทบาท: ช่างซ่อมบำรุง'),
        const SizedBox(height: 24),
        OutlinedButton(onPressed: AuthService.instance.signOut, child: const Text('ออกจากระบบ')),
      ],
    );
  }
}
