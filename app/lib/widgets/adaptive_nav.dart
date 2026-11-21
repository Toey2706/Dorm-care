import 'package:flutter/material.dart';

import '../theme.dart';

const wideBreakpoint = 768.0;
const extendedBreakpoint = 1100.0;

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideBreakpoint;

class NavItem {
  const NavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}
class AdaptiveNavScaffold extends StatelessWidget {
  const AdaptiveNavScaffold({super.key, required this.items, required this.selected, required this.onSelect, required this.body});
  final List<NavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < wideBreakpoint) {
      return Scaffold(
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: onSelect,
          destinations: [for (final i in items) NavigationDestination(icon: Icon(i.icon), label: i.label)],
        ),
      );
    }
    final extended = width >= extendedBreakpoint;
    return Scaffold(
      body: SafeArea(
        child: Row(children: [
          NavigationRail(
            extended: extended,
            minExtendedWidth: 200,
            selectedIndex: selected,
            onDestinationSelected: onSelect,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: extended
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      const _Logo(),
                      const SizedBox(width: 10),
                      Text('Dorm Care', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: brand)),
                    ])
                  : const _Logo(),
            ),
            destinations: [for (final i in items) NavigationRailDestination(icon: Icon(i.icon), label: Text(i.label))],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(12)),
      child: const Icon(Icons.home_repair_service_outlined, color: Colors.white, size: 22),
    );
  }
}
class TicketListView extends StatelessWidget {
  const TicketListView({super.key, required this.children, this.footer});
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < extendedBreakpoint - 100) {
        return ListView(children: [...children, if (footer != null) footer!]);
      }
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += 2) {
        rows.add(IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: children[i]),
            Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox.shrink()),
          ]),
        ));
      }
      return ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: [...rows, if (footer != null) footer!]);
    });
  }
}
Widget readable(Widget child) {
  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: child),
  );
}
