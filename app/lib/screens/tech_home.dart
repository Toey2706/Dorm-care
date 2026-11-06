import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/common.dart';
import 'admin_home.dart' show AccountPage;
import 'ticket_detail.dart';

/// หน้าหลักช่าง: เห็นเฉพาะงานที่ได้รับมอบหมาย (REQ-F05)
/// งานที่ยังไม่ปิดโหลดครบทุกรายการ ส่วนงานที่เสร็จแล้วแบ่งหน้า
class TechHome extends StatefulWidget {
  const TechHome({super.key, required this.me});
  final Staff me;

  @override
  State<TechHome> createState() => _TechHomeState();
}

class _TechHomeState extends State<TechHome> {
  static const pageSize = 30;
  bool _account = false;
  int _doneLimit = pageSize;
  late final Stream<List<Ticket>> _open = Api.instance.myOpenTickets(widget.me.id);
  late Stream<List<Ticket>> _done = Api.instance.completedTickets(_doneLimit);

  void _more() => setState(() {
        _doneLimit += pageSize;
        _done = Api.instance.completedTickets(_doneLimit);
      });

  Widget _list(Stream<List<Ticket>> stream, {bool paged = false}) {
    return StreamBuilder<List<Ticket>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('โหลดข้อมูลไม่สำเร็จ: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) return const Center(child: Text('ไม่มีรายการ'));
        return ListView(children: [
          for (final t in items)
            TicketTile(
              ticket: t,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TicketDetailScreen(ticketId: t.id, me: widget.me)),
              ),
            ),
          if (paged && items.length >= _doneLimit)
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton(onPressed: _more, child: const Text('โหลดเพิ่ม')),
            ),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _account
        ? AccountPage(me: widget.me)
        : DefaultTabController(
            length: 2,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('สวัสดี ${widget.me.name} (ช่าง)', style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              const TabBar(tabs: [Tab(text: 'ต้องดำเนินการ'), Tab(text: 'เสร็จแล้ว')]),
              Expanded(child: TabBarView(children: [_list(_open), _list(_done, paged: true)])),
            ]),
          );
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _account ? 1 : 0,
        onDestinationSelected: (i) => setState(() => _account = i == 1),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.handyman_outlined), label: 'งานของฉัน'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'บัญชี'),
        ],
      ),
    );
  }
}
