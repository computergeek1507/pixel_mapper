import 'package:xml/xml.dart';

/// xLights model attribute names are inconsistently cased across files —
/// e.g. a real vendor file was seen mixing `StarStartLocation` (PascalCase)
/// with `starRatio`/`starCenterPercent` (lowercase) in the very same root
/// element. Every lookup here is case-insensitive so that inconsistency
/// never silently falls back to a wrong default.
String? _findAttr(XmlElement e, String name) {
  final direct = e.getAttribute(name);
  if (direct != null) return direct;
  final lower = name.toLowerCase();
  for (final a in e.attributes) {
    if (a.name.local.toLowerCase() == lower) return a.value;
  }
  return null;
}

/// Modern xLights model files write named attributes (e.g. `NumStrings`);
/// older files only wrote the generic `parm1`/`parm2`/`parm3`. Every geometry
/// parser reads the named attribute first, falling back to the legacy parm
/// slot, so both file vintages work.
int attrInt(
  XmlElement e,
  String name, {
  String? parmFallback,
  int fallback = 0,
}) {
  final v =
      _findAttr(e, name) ??
      (parmFallback == null ? null : _findAttr(e, parmFallback));
  return int.tryParse(v ?? '') ?? fallback;
}

double attrDouble(
  XmlElement e,
  String name, {
  String? parmFallback,
  double fallback = 0,
}) {
  final v =
      _findAttr(e, name) ??
      (parmFallback == null ? null : _findAttr(e, parmFallback));
  return double.tryParse(v ?? '') ?? fallback;
}

bool attrBool(XmlElement e, String name, {bool fallback = false}) {
  final v = _findAttr(e, name)?.trim().toLowerCase();
  if (v == null || v.isEmpty) return fallback;
  return v == 'true' || v == '1';
}

String attrString(XmlElement e, String name, {String fallback = ''}) {
  final v = _findAttr(e, name);
  return (v == null || v.isEmpty) ? fallback : v;
}
