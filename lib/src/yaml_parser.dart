/// Minimal YAML parser for OpenAPI specs.
///
/// Produces the same types as [dart:convert]'s [jsonDecode]:
/// [Map<String, dynamic>], [List<dynamic>], [String], [int], [double],
/// [bool], or [null].
///
/// Supports:
///   - Block mappings and sequences (indentation-based)
///   - Flow mappings and sequences ({...} and [...])
///   - Quoted scalars (single and double)
///   - Literal block scalars (|) and folded block scalars (>)
///   - Line comments (#)
///   - Document start markers (---) are silently skipped
///
/// Does NOT support: anchors (&/*), tags (!), multi-document streams,
/// or YAML 1.1 boolean synonyms (yes/no/on/off).
library;

/// Parses [input] as YAML and returns the root value.
dynamic parseYaml(String input) {
  final lines = _scan(input);
  if (lines.isEmpty) return null;
  return _Ctx(lines)._block(-1);
}

// ─── Preprocessing ─────────────────────────────────────────────────────────

class _L {
  final int ind;
  final String raw; // content after leading whitespace is stripped
  const _L(this.ind, this.raw);
}

List<_L> _scan(String input) {
  final out = <_L>[];
  for (var line in input.split('\n')) {
    line = _dropComment(line);
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed == '---' || trimmed == '...') continue;
    final ind = line.length - line.trimLeft().length;
    out.add(_L(ind, line.trimLeft()));
  }
  return out;
}

// Strip # comments that appear outside quoted strings.
String _dropComment(String line) {
  var inS = false, inD = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == "'" && !inD) {
      inS = !inS;
    } else if (c == '"' && !inS) {
      inD = !inD;
    } else if (c == '#' && !inS && !inD) {
      if (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t') {
        return line.substring(0, i).trimRight();
      }
    }
  }
  return line;
}

// ─── Parser ─────────────────────────────────────────────────────────────────

class _Ctx {
  final List<_L> lines;
  int pos = 0;

  _Ctx(this.lines);

  bool get _done => pos >= lines.length;
  _L get _cur => lines[pos];

  // Parse any node whose indent is strictly greater than [pi] (parent indent).
  dynamic _block(int pi) {
    if (_done || _cur.ind <= pi) return null;
    final ln = _cur;

    if (ln.raw.startsWith('[')) {
      pos++;
      return _flowSeq(ln.raw);
    }
    if (ln.raw.startsWith('{')) {
      pos++;
      return _flowMap(ln.raw);
    }
    if (ln.raw == '-' || ln.raw.startsWith('- ')) {
      return _blockSeq(ln.ind);
    }
    if (_colonAt(ln.raw) >= 0) {
      return _blockMap(ln.ind);
    }
    pos++;
    return _scalar(ln.raw);
  }

  // Index of the YAML mapping colon (`:` followed by space or end-of-string,
  // outside any quoted region).  Returns -1 if not found.
  int _colonAt(String s) {
    var inS = false, inD = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == "'" && !inD) {
        inS = !inS;
      } else if (c == '"' && !inS) {
        inD = !inD;
      } else if (c == ':' && !inS && !inD) {
        if (i + 1 >= s.length || s[i + 1] == ' ') return i;
      }
    }
    return -1;
  }

  Map<String, dynamic> _blockMap(int ind) {
    final map = <String, dynamic>{};
    while (!_done && _cur.ind == ind && _colonAt(_cur.raw) >= 0) {
      final ln = _cur;
      pos++;
      final ci = _colonAt(ln.raw);
      final key = _scalar(ln.raw.substring(0, ci)) as String;
      final rest = ln.raw.substring(ci + 1).trim();

      dynamic val;
      if (rest == '|') {
        val = _litScalar(ind);
      } else if (rest == '>') {
        val = _foldScalar(ind);
      } else if (rest.isEmpty) {
        val = (!_done && _cur.ind > ind) ? _block(ind) : null;
      } else if (rest.startsWith('[')) {
        val = _flowSeq(rest);
      } else if (rest.startsWith('{')) {
        val = _flowMap(rest);
      } else {
        val = _scalar(rest);
      }
      map[key] = val;
    }
    return map;
  }

  List<dynamic> _blockSeq(int ind) {
    final list = <dynamic>[];
    while (!_done &&
        _cur.ind == ind &&
        (_cur.raw == '-' || _cur.raw.startsWith('- '))) {
      final ln = _cur;
      pos++;
      final rest = ln.raw.length > 1 ? ln.raw.substring(2).trim() : '';

      if (rest.isEmpty) {
        list.add((!_done && _cur.ind > ind) ? _block(ind) : null);
      } else if (rest.startsWith('[')) {
        list.add(_flowSeq(rest));
      } else if (rest.startsWith('{')) {
        list.add(_flowMap(rest));
      } else if (_colonAt(rest) >= 0) {
        // Inline first key-value pair; further entries may follow on next lines.
        final ci = _colonAt(rest);
        final key = _scalar(rest.substring(0, ci)) as String;
        final v = rest.substring(ci + 1).trim();
        final Map<String, dynamic> item = {};
        if (v.isEmpty) {
          item[key] = (!_done && _cur.ind > ind) ? _block(ind) : null;
        } else {
          item[key] = _scalar(v);
        }
        if (!_done && _cur.ind > ind) {
          item.addAll(_blockMap(_cur.ind));
        }
        list.add(item);
      } else {
        list.add(_scalar(rest));
      }
    }
    return list;
  }

  String _litScalar(int ind) {
    final buf = StringBuffer();
    while (!_done && _cur.ind > ind) {
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(_cur.raw);
      pos++;
    }
    return buf.toString();
  }

  String _foldScalar(int ind) {
    final parts = <String>[];
    while (!_done && _cur.ind > ind) {
      parts.add(_cur.raw);
      pos++;
    }
    return parts.join(' ');
  }

  Map<String, dynamic> _flowMap(String s) {
    s = s.trim();
    if (s.startsWith('{')) s = s.substring(1);
    if (s.endsWith('}')) s = s.substring(0, s.length - 1);
    final map = <String, dynamic>{};
    for (final entry in _flowSplit(s)) {
      final t = entry.trim();
      final ci = _colonAt(t);
      if (ci < 0) continue;
      final key = _scalar(t.substring(0, ci)) as String;
      map[key] = _scalarOrFlow(t.substring(ci + 1).trim());
    }
    return map;
  }

  List<dynamic> _flowSeq(String s) {
    s = s.trim();
    if (s.startsWith('[')) s = s.substring(1);
    if (s.endsWith(']')) s = s.substring(0, s.length - 1);
    return _flowSplit(s).map((e) => _scalarOrFlow(e.trim())).toList();
  }

  dynamic _scalarOrFlow(String s) {
    if (s.startsWith('{')) return _flowMap(s);
    if (s.startsWith('[')) return _flowSeq(s);
    return _scalar(s);
  }

  // Split a flow item string by top-level commas.
  List<String> _flowSplit(String s) {
    final items = <String>[];
    var depth = 0;
    var inS = false, inD = false;
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == "'" && !inD) {
        inS = !inS;
      } else if (c == '"' && !inS) {
        inD = !inD;
      } else if (!inS && !inD) {
        if (c == '{' || c == '[') depth++;
        else if (c == '}' || c == ']') depth--;
        else if (c == ',' && depth == 0) {
          items.add(s.substring(start, i));
          start = i + 1;
        }
      }
    }
    if (start < s.length) items.add(s.substring(start));
    return items.where((e) => e.trim().isNotEmpty).toList();
  }

  dynamic _scalar(String s) {
    s = s.trim();
    if (s.isEmpty || s == 'null' || s == '~') return null;
    if (s == 'true') return true;
    if (s == 'false') return false;
    if (s.startsWith('"') && s.endsWith('"')) return _dquote(s);
    if (s.startsWith("'") && s.endsWith("'")) {
      return s.substring(1, s.length - 1).replaceAll("''", "'");
    }
    final iv = int.tryParse(s);
    if (iv != null) return iv;
    final dv = double.tryParse(s);
    if (dv != null) return dv;
    return s;
  }

  String _dquote(String s) {
    s = s.substring(1, s.length - 1);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '\\' && i + 1 < s.length) {
        switch (s[i + 1]) {
          case 'n':
            buf.write('\n');
            i++;
          case 't':
            buf.write('\t');
            i++;
          case 'r':
            buf.write('\r');
            i++;
          case '"':
            buf.write('"');
            i++;
          case '\\':
            buf.write('\\');
            i++;
          default:
            buf.write(s[i]);
        }
      } else {
        buf.write(s[i]);
      }
    }
    return buf.toString();
  }
}
