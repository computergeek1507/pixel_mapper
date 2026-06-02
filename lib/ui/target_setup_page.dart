import 'dart:async';

import 'package:flutter/material.dart';

import '../models/pixel_color.dart';
import '../models/target_config.dart';
import '../services/camera_source.dart';
import '../services/camera_source_camera.dart';
import '../services/camera_source_rtsp.dart';
import '../services/pixel_output.dart';
import 'scan_page.dart';

/// Phase 1 UI: configure the controller target and manually exercise pixels
/// (light one, step through, chase, blackout) to verify DDP / sACN output
/// against real WS2811 hardware before any camera work.
class TargetSetupPage extends StatefulWidget {
  const TargetSetupPage({super.key});

  @override
  State<TargetSetupPage> createState() => _TargetSetupPageState();
}

class _TargetSetupPageState extends State<TargetSetupPage> {
  final _ipCtrl = TextEditingController(text: '192.168.1.50');
  final _countCtrl = TextEditingController(text: '50');
  final _universeCtrl = TextEditingController(text: '1');
  final _startChannelCtrl = TextEditingController(text: '1');
  final _rtspCtrl = TextEditingController(text: 'rtsp://');

  Protocol _protocol = Protocol.ddp;
  bool _useRtsp = false;
  PixelOutput? _output;
  bool _connecting = false;
  String? _status;

  int _currentPixel = 0;
  Timer? _chaseTimer;

  bool get _connected => _output != null;

  @override
  void dispose() {
    _chaseTimer?.cancel();
    _output?.blackout();
    _output?.close();
    _ipCtrl.dispose();
    _countCtrl.dispose();
    _universeCtrl.dispose();
    _startChannelCtrl.dispose();
    _rtspCtrl.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    final cfg = _buildConfig();
    if (cfg == null) return;
    // Release the manual-test output so the scan engine owns the controller.
    await _disconnect();
    final CameraSource camera = _useRtsp
        ? RtspCameraSource(_rtspCtrl.text.trim())
        : CameraPackageSource();
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScanPage(config: cfg, camera: camera),
    ));
  }

  TargetConfig? _buildConfig() {
    final ip = _ipCtrl.text.trim();
    final count = int.tryParse(_countCtrl.text.trim()) ?? 0;
    if (ip.isEmpty || count <= 0) {
      setState(() => _status = 'Enter a valid IP and pixel count.');
      return null;
    }
    return TargetConfig(
      ip: ip,
      pixelCount: count,
      protocol: _protocol,
      startUniverse: int.tryParse(_universeCtrl.text.trim()) ?? 1,
      startChannel: int.tryParse(_startChannelCtrl.text.trim()) ?? 1,
    );
  }

  Future<void> _connect() async {
    final cfg = _buildConfig();
    if (cfg == null) return;
    setState(() {
      _connecting = true;
      _status = null;
    });
    try {
      await _output?.close();
      final out = createPixelOutput(cfg.protocol);
      await out.open(cfg);
      await out.blackout();
      setState(() {
        _output = out;
        _currentPixel = 0;
        _status = 'Connected — sending ${cfg.protocol.label} to ${cfg.ip}.';
      });
    } catch (e) {
      setState(() => _status = 'Connect failed: $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    _chaseTimer?.cancel();
    _chaseTimer = null;
    await _output?.blackout();
    await _output?.close();
    setState(() {
      _output = null;
      _status = 'Disconnected.';
    });
  }

  Future<void> _lightPixel(int index) async {
    final out = _output;
    if (out == null) return;
    final clamped = index.clamp(0, out.pixelCount - 1);
    await out.lightSingle(clamped);
    setState(() => _currentPixel = clamped);
  }

  Future<void> _allOn() async {
    final out = _output;
    if (out == null) return;
    out.setAll(PixelColor.white);
    await out.render();
  }

  Future<void> _blackout() async {
    _chaseTimer?.cancel();
    _chaseTimer = null;
    await _output?.blackout();
    if (mounted) setState(() {});
  }

  void _toggleChase() {
    final out = _output;
    if (out == null) return;
    if (_chaseTimer != null) {
      _chaseTimer!.cancel();
      setState(() => _chaseTimer = null);
      return;
    }
    final timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final next = (_currentPixel + 1) % out.pixelCount;
      _lightPixel(next);
    });
    setState(() => _chaseTimer = timer);
  }

  @override
  Widget build(BuildContext context) {
    final pixelCount = _output?.pixelCount ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Pixel Mapper — Target')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _ipCtrl,
            decoration: const InputDecoration(
              labelText: 'Controller IP',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            enabled: !_connected,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _countCtrl,
            decoration: const InputDecoration(
              labelText: 'Pixel count',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            enabled: !_connected,
          ),
          const SizedBox(height: 12),
          SegmentedButton<Protocol>(
            segments: const [
              ButtonSegment(value: Protocol.ddp, label: Text('DDP')),
              ButtonSegment(value: Protocol.sacn, label: Text('sACN')),
            ],
            selected: {_protocol},
            onSelectionChanged: _connected
                ? null
                : (s) => setState(() => _protocol = s.first),
          ),
          if (_protocol == Protocol.sacn) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _universeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Start universe',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    enabled: !_connected,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _startChannelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Start channel',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    enabled: !_connected,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _connecting
                ? null
                : (_connected ? _disconnect : _connect),
            icon: Icon(_connected ? Icons.link_off : Icons.link),
            label: Text(_connected ? 'Disconnect' : 'Connect'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const Divider(height: 32),
          Text('Manual test', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (!_connected)
            const Text('Connect to enable pixel tests.')
          else ...[
            Text('Pixel $_currentPixel of ${pixelCount - 1}'),
            Slider(
              value: _currentPixel.toDouble(),
              min: 0,
              max: (pixelCount - 1).toDouble().clamp(0, double.infinity),
              divisions: pixelCount > 1 ? pixelCount - 1 : null,
              label: '$_currentPixel',
              onChanged: (v) => _lightPixel(v.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filledTonal(
                  onPressed: () => _lightPixel(_currentPixel - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton.filledTonal(
                  onPressed: () => _lightPixel(_currentPixel + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _lightPixel(_currentPixel),
                  icon: const Icon(Icons.lightbulb),
                  label: const Text('Light current'),
                ),
                OutlinedButton.icon(
                  onPressed: _allOn,
                  icon: const Icon(Icons.brightness_high),
                  label: const Text('All on'),
                ),
                OutlinedButton.icon(
                  onPressed: _toggleChase,
                  icon: Icon(_chaseTimer == null
                      ? Icons.play_arrow
                      : Icons.stop),
                  label: Text(_chaseTimer == null ? 'Chase' : 'Stop chase'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _blackout,
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Blackout'),
                ),
              ],
            ),
          ],
          const Divider(height: 32),
          Text('Camera scan', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use RTSP network camera'),
            subtitle: const Text(
                'Off: device camera / Windows webcam / Connected Camera'),
            value: _useRtsp,
            onChanged: (v) => setState(() => _useRtsp = v),
          ),
          if (_useRtsp)
            TextField(
              controller: _rtspCtrl,
              decoration: const InputDecoration(
                labelText: 'RTSP URL',
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Start camera scan'),
          ),
        ],
      ),
    );
  }
}
