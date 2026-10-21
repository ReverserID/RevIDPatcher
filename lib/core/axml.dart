import 'dart:typed_data';

class ApkMeta {
  final String package;
  final String versionName;
  final int versionCode;
  const ApkMeta(this.package, this.versionName, this.versionCode);
}

class Axml {

  static ApkMeta? parseManifest(Uint8List bytes) {
    final d = ByteData.sublistView(bytes);
    if (bytes.length < 8) return null;

    if (d.getUint16(0, Endian.little) != 0x0003) return null;
    int pos = 8;
    List<String> strings = const [];
    String? package;
    String? versionName;
    int versionCode = 0;

    while (pos + 8 <= bytes.length) {
      final type = d.getUint16(pos, Endian.little);
      final size = d.getUint32(pos + 4, Endian.little);
      if (size < 8 || pos + size > bytes.length) break;
      if (type == 0x0001) {
        strings = _parseStringPool(d, pos);
      } else if (type == 0x0102) {

        final nameRef = d.getUint32(pos + 20, Endian.little);
        final name = _str(strings, nameRef);
        final attrCount = d.getUint16(pos + 28, Endian.little);
        int ap = pos + 36;
        for (int i = 0; i < attrCount && ap + 20 <= pos + size; i++) {
          final aName = _str(strings, d.getUint32(ap + 4, Endian.little));
          final rawValue = d.getUint32(ap + 8, Endian.little);
          final data = d.getUint32(ap + 16, Endian.little);
          if (name == 'manifest') {
            if (aName == 'package') {
              package = _str(strings, rawValue);
            } else if (aName == 'versionName') {
              versionName = rawValue != 0xFFFFFFFF
                  ? _str(strings, rawValue)
                  : _str(strings, data);
            } else if (aName == 'versionCode') {
              versionCode = data;
            }
          }
          ap += 20;
        }
        if (name == 'manifest' && package != null) {

          return ApkMeta(package, versionName ?? '', versionCode);
        }
      }
      pos += size;
    }
    if (package != null) {
      return ApkMeta(package, versionName ?? '', versionCode);
    }
    return null;
  }

  static String _str(List<String> pool, int ref) =>
      (ref >= 0 && ref < pool.length) ? pool[ref] : '';

  static List<String> _parseStringPool(ByteData d, int start) {
    final count = d.getUint32(start + 8, Endian.little);
    final flags = d.getUint32(start + 16, Endian.little);
    final stringsStart = d.getUint32(start + 20, Endian.little);
    final utf8 = (flags & 0x100) != 0;
    final out = <String>[];
    final base = start + stringsStart;
    for (int i = 0; i < count; i++) {
      final off = d.getUint32(start + 28 + i * 4, Endian.little);
      int p = base + off;
      try {
        if (utf8) {

          p = _skipLen8(d, p);
          int byteLen = d.getUint8(p);
          if (byteLen & 0x80 != 0) {
            byteLen = ((byteLen & 0x7F) << 8) | d.getUint8(p + 1);
            p += 2;
          } else {
            p += 1;
          }
          final b = Uint8List(byteLen);
          for (int k = 0; k < byteLen; k++) {
            b[k] = d.getUint8(p + k);
          }
          out.add(String.fromCharCodes(b));
        } else {
          int len = d.getUint16(p, Endian.little);
          p += 2;
          if (len & 0x8000 != 0) {
            len = ((len & 0x7FFF) << 16) | d.getUint16(p, Endian.little);
            p += 2;
          }
          final cu = <int>[];
          for (int k = 0; k < len; k++) {
            cu.add(d.getUint16(p + k * 2, Endian.little));
          }
          out.add(String.fromCharCodes(cu));
        }
      } catch (_) {
        out.add('');
      }
    }
    return out;
  }

  static int _skipLen8(ByteData d, int p) {
    final v = d.getUint8(p);
    return (v & 0x80 != 0) ? p + 2 : p + 1;
  }
}
