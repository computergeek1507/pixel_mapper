import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pixel_color.dart';
import '../models/target_config.dart';
import '../services/camera_source.dart';
import '../services/camera_source_camera.dart';
import '../services/camera_source_rtsp.dart';
import '../services/pixel_output.dart';
import '../services/scan_controller.dart';
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
  ColorOrder _colorOrder = ColorOrder.rgb;
  PixelColor _testColor = PixelColor.white;
  bool _useRtsp = false;
  ScanMode _scanMode = ScanMode.fastBase3;
  PixelOutput? _output;
  bool _connecting = false;
  String? _status;

  int _currentPixel = 0;
  double _brightness = 1.0;
  Timer? _chaseTimer;

  bool get _connected => _output != null;

  /// RTSP (media_kit) ships only on Windows; Android/iOS use the device camera.
  static final bool _rtspSupported =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// Restores the last-used settings so the user doesn't re-enter them.
  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ipCtrl.text = p.getString('ip') ?? _ipCtrl.text;
      _countCtrl.text = p.getString('count') ?? _countCtrl.text;
      _universeCtrl.text = p.getString('universe') ?? _universeCtrl.text;
      _startChannelCtrl.text = p.getString('startChannel') ?? _startChannelCtrl.text;
      _rtspCtrl.text = p.getString('rtsp') ?? _rtspCtrl.text;
      _protocol = Protocol.values.firstWhere(
          (e) => e.name == p.getString('protocol'), orElse: () => _protocol);
      _colorOrder = ColorOrder.values.firstWhere(
          (e) => e.name == p.getString('colorOrder'), orElse: () => _colorOrder);
      _scanMode = ScanMode.values.firstWhere(
          (e) => e.name == p.getString('scanMode'), orElse: () => _scanMode);
      _useRtsp = p.getBool('useRtsp') ?? _useRtsp;
      _brightness = p.getDouble('brightness') ?? _brightness;
    });
  }

  /// Persists the current settings so they survive an app restart.
  Future<void> _saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ip', _ipCtrl.text.trim());
    await p.setString('count', _countCtrl.text.trim());
    await p.setString('universe', _universeCtrl.text.trim());
    await p.setString('startChannel', _startChannelCtrl.text.trim());
    await p.setString('rtsp', _rtspCtrl.text.trim());
    await p.setString('protocol', _protocol.name);
    await p.setString('colorOrder', _colorOrder.name);
    await p.setString('scanMode', _scanMode.name);
    await p.setBool('useRtsp', _useRtsp);
    await p.setDouble('brightness', _brightness);
  }

  @override
  void dispose() {
    _saveSettings();
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
    _saveSettings();
    // Release the manual-test output so the scan engine owns the controller
    // (two senders would fight over the same controller).
    final wasConnected = _connected;
    await _disconnect();
    final CameraSource camera = (_useRtsp && _rtspSupported)
        ? RtspCameraSource(_rtspCtrl.text.trim())
        : CameraPackageSource();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScanPage(config: cfg, camera: camera, mode: _scanMode),
    ));
    // Returning from the scan: restore the manual-test connection so the user
    // isn't silently disconnected after a scan.
    if (mounted && wasConnected) await _connect();
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
      colorOrder: _colorOrder,
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
      out.brightness = _brightness;
      await out.open(cfg);
      await out.blackout();
      setState(() {
        _output = out;
        _currentPixel = 0;
        _status = 'Connected — sending ${cfg.protocol.label} to ${cfg.ip}.';
      });
      _saveSettings();
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
    await out.lightSingle(clamped, color: _testColor);
    setState(() => _currentPixel = clamped);
  }

  /// Updates the LED drive brightness and re-sends the current frame so the
  /// change is visible without the user having to re-trigger a test.
  void _setBrightness(double value) {
    setState(() => _brightness = value);
    final out = _output;
    if (out == null) return;
    out.brightness = value;
    // Re-render whatever is currently displayed at the new brightness.
    if (_chaseTimer == null) out.render();
  }

  Widget _colorChip(String label, PixelColor c) {
    return ChoiceChip(
      label: Text(label),
      selected: _testColor == c,
      // No checkmark: it changes the chip width and reflows the row, making the
      // controls below jump when you switch colours.
      showCheckmark: false,
      onSelected: (_) {
        setState(() => _testColor = c);
        // Re-light the current pixel so the new colour shows immediately.
        if (_chaseTimer == null) _lightPixel(_currentPixel);
      },
    );
  }

  Future<void> _allOn() async {
    final out = _output;
    if (out == null) return;
    out.setAll(_testColor);
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
      body: SafeArea(
        top: false,
        child: ListView(
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
          DropdownButtonFormField<ColorOrder>(
            initialValue: _colorOrder,
            decoration: const InputDecoration(
              labelText: 'Color order',
              helperText: 'Match your LEDs (WS2811 is often GRB)',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final o in ColorOrder.values)
                DropdownMenuItem(value: o, child: Text(o.label)),
            ],
            onChanged: (o) {
              if (o == null) return;
              setState(() => _colorOrder = o);
              // Apply live so the manual test reflects it immediately.
              if (_connected) _connect();
            },
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
            Row(
              children: [
                const Text('Brightness'),
                Expanded(
                  child: Slider(
                    value: _brightness,
                    min: 0.05,
                    max: 1.0,
                    divisions: 19,
                    label: '${(_brightness * 100).round()}%',
                    onChanged: _setBrightness,
                  ),
                ),
                Text('${(_brightness * 100).round()}%'),
              ],
            ),
            Row(
              children: [
                const Text('Test color'),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      _colorChip('White', PixelColor.white),
                      _colorChip('Red', PixelColor.red),
                      _colorChip('Green', PixelColor.green),
                      _colorChip('Blue', PixelColor.blue),
                    ],
                  ),
                ),
              ],
            ),
            Text('Pixel ${_currentPixel + 1} of $pixelCount'),
            Slider(
              value: _currentPixel.toDouble(),
              min: 0,
              max: (pixelCount - 1).toDouble().clamp(0, double.infinity),
              divisions: pixelCount > 1 ? pixelCount - 1 : null,
              label: '${_currentPixel + 1}',
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
          SegmentedButton<ScanMode>(
            segments: const [
              ButtonSegment(
                value: ScanMode.fastBase3,
                label: Text('Fast (base-3)'),
                icon: Icon(Icons.bolt),
              ),
              ButtonSegment(
                value: ScanMode.sequential,
                label: Text('Sequential'),
                icon: Icon(Icons.format_list_numbered),
              ),
            ],
            selected: {_scanMode},
            onSelectionChanged: (s) => setState(() => _scanMode = s.first),
          ),
          const SizedBox(height: 4),
          Text(
            _scanMode == ScanMode.fastBase3
                ? 'Lights every pixel each frame in R/G/B; identifies all '
                    'pixels in ~log₃(N)+2 frames (xLights method).'
                : 'Lights one pixel at a time — slower but simplest.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (_rtspSupported) ...[
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
          ],
          FilledButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Start camera scan'),
          ),
        ],
        ),
      ),
    );
  }
}
