import 'package:flutter/material.dart';

import 'konekta_navbar.dart';


class KonektaTabScaffold extends StatefulWidget {
  const KonektaTabScaffold({
    super.key,
    required this.items,
    required this.tabs,
    this.initialIndex = 0,
  });

  final List<KonektaNavItem> items;
  final List<Widget> tabs;
  final int initialIndex;

  @override
  State<KonektaTabScaffold> createState() => _KonektaTabScaffoldState();
}

class _KonektaTabScaffoldState extends State<KonektaTabScaffold> {
  late int _currentIndex = widget.initialIndex;

  void _onTabSelected(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.items.length == widget.tabs.length,
      'items and tabs must have the same length',
    );
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _currentIndex = 0);
      },
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(index: _currentIndex, children: widget.tabs),
        ),
        bottomNavigationBar: KonektaNavBar(
          items: widget.items,
          currentIndex: _currentIndex,
          onTap: _onTabSelected,
        ),
      ),
    );
  }
}
