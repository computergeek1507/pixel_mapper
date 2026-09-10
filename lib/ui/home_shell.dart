import 'package:flutter/material.dart';

import 'target_setup_page.dart';
import 'wiring_home_tab.dart';

/// App shell: two bottom tabs — "Scan & Map" (the camera-based pixel
/// scanning wizard) and "Wiring Viewer" (browse the xLights vendor catalog
/// or load a .xmodel to see its wiring order).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('xModel Tools - Pixel Mapper')),
        body: const TabBarView(children: [WiringHomeTab(), TargetSetupPage()]),
        bottomNavigationBar: Material(
          color: Theme.of(context).colorScheme.surface,
          child: const SafeArea(
            top: false,
            child: TabBar(
              tabs: [
                Tab(icon: Icon(Icons.route), text: 'Wiring Viewer'),
                Tab(icon: Icon(Icons.camera_alt), text: 'Scan & Map'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
