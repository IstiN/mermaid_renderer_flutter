import 'package:xml/xml.dart';

/// Ports the Java {@code MermaidRenderer.normalizeSvgForBatik()} pipeline to Dart.
///
/// The Java version removes Batik-specific artefacts; this Dart version removes
/// artefacts that trip up `flutter_svg` and ensures consistent, portable SVG output
/// that also displays correctly in Affinity Designer / Inkscape.
class SvgNormalizer {
  SvgNormalizer._();

  // ─── public API ────────────────────────────────────────────────────────────

  /// Normalise [svg] for use with flutter_svg and as a portable SVG file.
  static String normalize(String svg) {
    var result = svg;

    // --- string-level fixes (same order as Java) ---

    // Spacer rects with no attributes must not accidentally gain fill/stroke.
    result = result
        .replaceAll('<rect/>', '<rect fill="none" stroke="none"/>')
        .replaceAll('<rect />', '<rect fill="none" stroke="none"/>');

    // Ensure xlink namespace is present (needed for <image xlink:href=...>).
    result = result.replaceFirstMapped(
      RegExp(r'<svg\b(?![^>]*xmlns:xlink=)'),
      (m) => '<svg xmlns:xlink="http://www.w3.org/1999/xlink"',
    );

    // Remove filter effects, animations and inline filter refs.
    result = result
        .replaceAll(RegExp(r'<filter\b[^>]*>.*?</filter>', dotAll: true), '')
        .replaceAll(
            RegExp(r'@keyframes\s+[^\{]+\{.*?\}\s*\}', dotAll: true), '')
        .replaceAll(RegExp(r'animation:[^;"}\s][^;"}\n]*;?'), '')
        .replaceAll(RegExp(r'filter:[^;"}\s][^;"}\n]*;?'), '')
        .replaceAll(RegExp(r'\sfilter="url\(#[^)]+\)"'), '');

    // Strip !important — flutter_svg and Affinity may not honour it.
    result = result.replaceAll(RegExp(r'\s*!important'), '');

    // Remove malformed/empty style attributes that block CSS cascade.
    result = result.replaceAll(RegExp(r'\bstyle="[\s;undefined]*"'), '');

    // Remove empty fill / font-weight attributes that cause invisible text.
    result = result
        .replaceAll(RegExp(r'\bfill=""'), '')
        .replaceAll(RegExp(r'\bfont-weight=""'), '');

    // Fix arrow marker orientation.
    result = result.replaceAll(
        'orient="auto-start-reverse"', 'orient="auto"');

    // Fix alignment-baseline value (flutter_svg handles 'middle' but not all
    // vendors honour 'central').
    result = result.replaceAll(
        'alignment-baseline="central"', 'alignment-baseline="middle"');

    // Ensure <rect> elements have width/height (flutter_svg requires them).
    // Use replaceAllMapped because Dart's replaceAll does not expand $n groups.
    result = result
        .replaceAllMapped(
          RegExp(r'<rect([^>]*?)(?<![/]) />'),
          (m) => '<rect${m[1]}></rect>',
        )
        .replaceAllMapped(
          RegExp(r'<rect((?:(?!\bwidth=)[^>])*)>', dotAll: true),
          (m) => '<rect width="1"${m[1]}>',
        )
        .replaceAllMapped(
          RegExp(r'<rect((?:(?!\bheight=)[^>])*)>', dotAll: true),
          (m) => '<rect height="1"${m[1]}>',
        );

    // Fix image href → xlink:href.
    result = result.replaceAll(
        RegExp(r'<image\s+href='), '<image xlink:href=');

    // Remove <image> elements with no href at all (they crash some parsers).
    result = result
        .replaceAll(
          RegExp(r'<image\b(?![^>]*(?:href|xlink:href)=)[^>]*/>'),
          '',
        )
        .replaceAll(
          RegExp(
              r'<image\b(?![^>]*(?:href|xlink:href)=)[^>]*>.*?</image>',
              dotAll: true),
          '',
        );

    // Remove <foreignObject> (flutter_svg doesn't render HTML inside SVG).
    result = result
        .replaceAll(RegExp(r'<foreignObject[^>]*>.*?</foreignObject>', dotAll: true), '')
        .replaceAll(RegExp(r'<switch>\s*'), '')
        .replaceAll(RegExp(r'\s*</switch>'), '');

    // Journey section background: remove explicit dark fills so CSS applies.
    result = result.replaceAllMapped(
      RegExp(
          r'(<rect(?=[^>]*\bclass="[^"]*(?:journey-section|\btask\b)[^"]*")[^>]*?)\bfill="#[0-9a-fA-F]+"([^>]*/?>)'),
      (m) => '${m[1]}${m[2]}',
    );

    // Journey section label text: ensure dark fill so text stays readable.
    result = result.replaceAllMapped(
      RegExp(
          r'(<text(?=[^>]*\bclass="[^"]*\bjourney-section\b)(?![^>]*\btask\b)[^>]*?)\bstyle="'),
      (m) => '${m[1]} style="fill:#333;',
    );

    // Background rects without fill default to black — set fill=none.
    result = result.replaceAllMapped(
      RegExp(
          r'<rect(?=[^>]*\bclass="[^"]*\bbackground\b)(?![^>]*\bfill=)([^>]*?)(/?>)'),
      (m) => '<rect fill="none"${m[1]}${m[2]}',
    );

    // --- DOM-based fixes ---
    result = _removeRedundantTextY(result);
    result = _applyEmojiFontSpans(result);

    return result;
  }

  // ─── DOM: remove redundant parent <text y=…> when row-tspans have own y ───

  static String _removeRedundantTextY(String svg) {
    if (!svg.contains('text-outer-tspan row')) return svg;
    try {
      final doc = XmlDocument.parse(svg);
      for (final text in doc.descendants
          .whereType<XmlElement>()
          .where((e) => e.localName == 'text')) {
        if (_hasPositionedRowTspan(text)) {
          text.removeAttribute('y');
        }
      }
      return doc.toXmlString();
    } catch (_) {
      return svg;
    }
  }

  static bool _hasPositionedRowTspan(XmlElement text) {
    for (final child in text.childElements) {
      if (child.localName == 'tspan') {
        final cls = child.getAttribute('class') ?? '';
        if (cls.contains('text-outer-tspan') &&
            cls.contains('row') &&
            child.getAttribute('y') != null) {
          return true;
        }
      }
    }
    return false;
  }

  // ─── DOM: split mixed text/emoji into separate tspan runs ──────────────────

  static String _applyEmojiFontSpans(String svg) {
    if (!_containsEmoji(svg)) return svg;
    try {
      final doc = XmlDocument.parse(svg);
      _applyEmojiFontSpansNode(doc.rootElement);
      return doc.toXmlString();
    } catch (_) {
      return svg;
    }
  }

  static void _applyEmojiFontSpansNode(XmlNode node) {
    final childrenSnapshot = node.children.toList();
    for (final child in childrenSnapshot) {
      if (child is XmlText &&
          _isTextContainer(node) &&
          _containsEmoji(child.value)) {
        _replaceTextNodeWithEmojiSpans(child);
      } else if (child is XmlElement) {
        _applyEmojiFontSpansNode(child);
      }
    }
  }

  static bool _isTextContainer(XmlNode node) {
    if (node is! XmlElement) return false;
    return node.localName == 'text' || node.localName == 'tspan';
  }

  static void _replaceTextNodeWithEmojiSpans(XmlText textNode) {
    final parent = textNode.parent;
    if (parent == null) return;
    final runs = _splitEmojiRuns(textNode.value);
    final newNodes = runs.map((run) {
      if (run.emoji) {
        return XmlElement(
          XmlName('tspan'),
          [
            XmlAttribute(XmlName('font-family'),
                'Noto Emoji, Apple Color Emoji, Segoe UI Emoji, sans-serif'),
            XmlAttribute(XmlName('fill'), '#111111'),
            XmlAttribute(XmlName('style'), 'fill:#111111;'),
          ],
          [XmlText(run.text)],
        );
      } else {
        return XmlElement(
          XmlName('tspan'),
          [],
          [XmlText(run.text)],
        );
      }
    }).toList();

    final idx = parent.children.indexOf(textNode);
    parent.children.removeAt(idx);
    for (var i = 0; i < newNodes.length; i++) {
      parent.children.insert(idx + i, newNodes[i]);
    }
  }

  // ─── emoji helpers ──────────────────────────────────────────────────────────

  static bool _containsEmoji(String text) =>
      text.runes.any(_isEmojiCodePoint);

  static bool _isEmojiCodePoint(int cp) =>
      (cp >= 0x1F000 && cp <= 0x1FAFF) ||
      (cp >= 0x2600 && cp <= 0x27BF) ||
      (cp >= 0x2300 && cp <= 0x23FF);

  static bool _isEmojiModifier(int cp) =>
      (cp >= 0x1F3FB && cp <= 0x1F3FF) || (cp >= 0xE0020 && cp <= 0xE007F);

  static List<_EmojiRun> _splitEmojiRuns(String text) {
    final runs = <_EmojiRun>[];
    final buf = StringBuffer();
    bool? currentEmoji;
    bool joinNext = false;

    for (final cp in text.runes) {
      final emoji = _isEmojiCodePoint(cp) ||
          _isEmojiModifier(cp) ||
          cp == 0xFE0E ||
          cp == 0xFE0F ||
          cp == 0x200D ||
          joinNext;

      if (currentEmoji != null && currentEmoji != emoji) {
        runs.add(_EmojiRun(buf.toString(), currentEmoji));
        buf.clear();
      }
      buf.writeCharCode(cp);
      currentEmoji = emoji;
      joinNext = cp == 0x200D;
    }
    if (buf.isNotEmpty) {
      runs.add(_EmojiRun(buf.toString(), currentEmoji ?? false));
    }
    return runs;
  }
}

class _EmojiRun {
  final String text;
  final bool emoji;
  const _EmojiRun(this.text, this.emoji);
}
