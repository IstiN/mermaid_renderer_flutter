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
    // Inline CSS fill/stroke from complex selectors as presentation attributes.
    // flutter_svg's vector_graphics_compiler does not support complex CSS
    // selectors like "#id .class element" — same limitation as Batik.
    result = _inlineCssFillStroke(result);
    // Cascade font-size/font-family from ancestor <g> elements to <text> nodes.
    // vector_graphics_compiler does not inherit presentation attributes from groups.
    result = _cascadeFontAttrsToText(result);
    result = _removeRedundantTextY(result);
    // Convert em units in positioning attrs — vector_graphics_compiler resolves
    // them to 0 which places text off-screen.
    result = _convertEmUnitsToPixels(result);
    result = _applyEmojiFontSpans(result);

    return result;
  }

  // ─── CSS inlining ──────────────────────────────────────────────────────────

  static String _inlineCssFillStroke(String svg) {
    final styleMatch =
        RegExp(r'<style>(.*?)</style>', dotAll: true).firstMatch(svg);
    if (styleMatch == null) return svg;
    final css = styleMatch.group(1)!;

    final rules = <_CssRule>[];
    final ruleRe = RegExp(r'([^{}]+)\{([^}]+)\}');
    for (final rm in ruleRe.allMatches(css)) {
      final selectorGroup = rm.group(1)!.trim();
      final body = rm.group(2)!.trim();

      final fill = _extractCssProp(body, 'fill');
      final stroke = _extractCssProp(body, 'stroke');
      final strokeDasharray = _extractCssProp(body, 'stroke-dasharray');
      final strokeWidth = _extractCssProp(body, 'stroke-width');
      final textAnchor = _extractCssProp(body, 'text-anchor');
      final fontSize = _extractCssProp(body, 'font-size');
      final fontFamily = _extractCssProp(body, 'font-family');
      if (fill == null &&
          stroke == null &&
          strokeDasharray == null &&
          strokeWidth == null &&
          textAnchor == null &&
          fontSize == null &&
          fontFamily == null) continue;

      for (final sel in selectorGroup.split(',')) {
        final rule = _parseCssSelector(
            sel.trim(), fill, stroke, strokeDasharray, strokeWidth, textAnchor,
            fontSize: fontSize, fontFamily: fontFamily);
        if (rule != null) rules.add(rule);
      }
    }
    if (rules.isEmpty) return svg;

    try {
      final doc = XmlDocument.parse(svg);
      _inlineOnElement(doc.rootElement, rules, {});
      return doc.toXmlString();
    } catch (_) {
      return svg;
    }
  }

  static void _inlineOnElement(
      XmlElement element, List<_CssRule> rules, Set<String> ancestorClasses) {
    final tag = element.localName;
    final classAttr = element.getAttribute('class') ?? '';
    final classes =
        classAttr.split(RegExp(r'\s+')).where((c) => c.isNotEmpty).toList();

    // Best matching properties (last matching rule wins — CSS cascade order).
    String? bestFill;
    String? bestStroke;
    String? bestStrokeDasharray;
    String? bestStrokeWidth;
    String? bestTextAnchor;
    String? bestFontSize;
    String? bestFontFamily;

    for (final rule in rules) {
      if (rule.matches(tag, classes, ancestorClasses)) {
        if (rule.fill != null) bestFill = rule.fill;
        if (rule.stroke != null) bestStroke = rule.stroke;
        if (rule.strokeDasharray != null) {
          bestStrokeDasharray = rule.strokeDasharray;
        }
        if (rule.strokeWidth != null) bestStrokeWidth = rule.strokeWidth;
        if (rule.textAnchor != null) bestTextAnchor = rule.textAnchor;
        if (rule.fontSize != null) bestFontSize = rule.fontSize;
        if (rule.fontFamily != null) bestFontFamily = rule.fontFamily;
      }
    }

    // Inject as presentation attributes only if the element doesn't already
    // have them (matching Java: "!element.hasAttribute(...)").
    void setIfAbsent(String attr, String? value) {
      if (value != null && element.getAttribute(attr) == null) {
        element.setAttribute(attr, value);
      }
    }

    setIfAbsent('fill', bestFill);
    setIfAbsent('stroke', bestStroke);
    setIfAbsent('stroke-dasharray', bestStrokeDasharray);
    setIfAbsent('stroke-width', bestStrokeWidth);
    setIfAbsent('text-anchor', bestTextAnchor);
    setIfAbsent('font-size', bestFontSize);
    setIfAbsent('font-family', bestFontFamily);

    // Recurse — pass current element's classes as ancestor context.
    final childAncestors = {...ancestorClasses, ...classes};
    for (final child in element.childElements) {
      _inlineOnElement(child, rules, childAncestors);
    }
  }

  static String? _extractCssProp(String body, String propName) {
    final re = RegExp('(?:^|;)\\s*$propName\\s*:\\s*([^;}{]+?)\\s*(?:;|\$)');
    String? last;
    for (final m in re.allMatches(body)) {
      last = m.group(1)!.trim();
    }
    return last;
  }

  // ─── DOM: cascade font-size/font-family from groups to text elements ────────
  // vector_graphics_compiler does not inherit font presentation attributes from
  // ancestor <g> elements — copy them directly onto <text> nodes.

  static String _cascadeFontAttrsToText(String svg) {
    try {
      final doc = XmlDocument.parse(svg);
      _cascadeFontOnElement(doc.rootElement, null, null);
      return doc.toXmlString();
    } catch (_) {
      return svg;
    }
  }

  static void _cascadeFontOnElement(
      XmlElement el, String? inheritedSize, String? inheritedFamily) {
    // Current effective values (own attr overrides inherited).
    final size = el.getAttribute('font-size') ?? inheritedSize;
    final family = el.getAttribute('font-family') ?? inheritedFamily;

    final tag = el.localName;
    if ((tag == 'text' || tag == 'tspan') && size != null) {
      // Apply to text/tspan if not already set.
      if (el.getAttribute('font-size') == null) {
        el.setAttribute('font-size', size);
      }
      if (family != null && el.getAttribute('font-family') == null) {
        el.setAttribute('font-family', family);
      }
    }

    for (final child in el.childElements) {
      _cascadeFontOnElement(child, size, family);
    }
  }

  static _CssRule? _parseCssSelector(
      String selector,
      String? fill,
      String? stroke,
      String? strokeDasharray,
      String? strokeWidth,
      String? textAnchor, {
      String? fontSize,
      String? fontFamily}) {
    // Strip leading #id part (e.g., "#dmtools-mermaid ")
    var sel = selector.replaceFirst(RegExp(r'^#[\w-]+\s+'), '');
    if (sel.startsWith('#')) return null; // pure id selector for another element

    final parts = sel.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return null;

    final lastPart = parts.last;
    final requiredClasses = <String>[];
    String? targetElement;

    if (lastPart.contains('.')) {
      final dotIdx = lastPart.indexOf('.');
      if (dotIdx > 0) targetElement = lastPart.substring(0, dotIdx);
      for (final cls in lastPart.substring(lastPart.indexOf('.')).split('.')) {
        if (cls.isNotEmpty) requiredClasses.add(cls);
      }
    } else {
      targetElement = lastPart;
    }

    final ancestorClasses = <String>[];
    for (final part in parts.sublist(0, parts.length - 1)) {
      if (part.contains('.')) {
        for (final cls in part.split('.')) {
          if (cls.isNotEmpty && !cls.startsWith('#')) {
            ancestorClasses.add(cls);
          }
        }
      }
    }

    return _CssRule(
      targetElement: targetElement,
      requiredClasses: requiredClasses,
      ancestorClasses: ancestorClasses,
      fill: fill,
      stroke: stroke,
      strokeDasharray: strokeDasharray,
      strokeWidth: strokeWidth,
      textAnchor: textAnchor,
      fontSize: fontSize,
      fontFamily: fontFamily,
    );
  }

  // ─── DOM: convert em units to px in text positioning attributes ──────────
  // vector_graphics_compiler resolves unknown units to 0, which moves text off-screen.

  static String _convertEmUnitsToPixels(String svg) {
    if (!svg.contains('em')) return svg;
    try {
      final doc = XmlDocument.parse(svg);
      // Extract global font-size from <style> block (e.g. "font-size:16px").
      double baseFontSize = 16.0;
      final styleEl = doc.descendants
          .whereType<XmlElement>()
          .where((e) => e.localName == 'style')
          .firstOrNull;
      if (styleEl != null) {
        final m = RegExp(r'font-size\s*:\s*([\d.]+)px').firstMatch(styleEl.innerText);
        if (m != null) baseFontSize = double.tryParse(m.group(1)!) ?? 16.0;
      }

      _convertEmOnElement(doc.rootElement, baseFontSize);
      return doc.toXmlString();
    } catch (_) {
      return svg;
    }
  }

  static void _convertEmOnElement(XmlElement el, double fontSize) {
    // Resolve current font-size (handles font-size="14px" on the element).
    double currentFontSize = fontSize;
    final fsPx = _parseEmAttr(el.getAttribute('font-size'), fontSize);
    if (fsPx != null) currentFontSize = fsPx;

    for (final attr in ['x', 'y', 'dx', 'dy']) {
      final raw = el.getAttribute(attr);
      if (raw != null && raw.trim().endsWith('em')) {
        final px = _parseEmAttr(raw, currentFontSize);
        if (px != null) {
          el.setAttribute(attr, _formatPx(px));
        }
      }
    }

    for (final child in el.childElements) {
      _convertEmOnElement(child, currentFontSize);
    }
  }

  static double? _parseEmAttr(String? raw, double fontSize) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.endsWith('em')) {
      final factor = double.tryParse(trimmed.substring(0, trimmed.length - 2));
      if (factor != null) return factor * fontSize;
    } else if (trimmed.endsWith('px')) {
      return double.tryParse(trimmed.substring(0, trimmed.length - 2));
    }
    return null;
  }

  static String _formatPx(double px) {
    // Return integer if whole, otherwise 1 decimal place.
    if (px == px.roundToDouble()) return px.toInt().toString();
    return px.toStringAsFixed(1);
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

// ─── helper data classes ────────────────────────────────────────────────────

class _CssRule {
  final String? targetElement; // null = any element
  final List<String> requiredClasses;
  final List<String> ancestorClasses;
  final String? fill;
  final String? stroke;
  final String? strokeDasharray;
  final String? strokeWidth;
  final String? textAnchor;
  final String? fontSize;
  final String? fontFamily;

  const _CssRule({
    required this.targetElement,
    required this.requiredClasses,
    required this.ancestorClasses,
    this.fill,
    this.stroke,
    this.strokeDasharray,
    this.strokeWidth,
    this.textAnchor,
    this.fontSize,
    this.fontFamily,
  });

  bool matches(
      String elemTag, List<String> elemClasses, Set<String> elemAncestors) {
    if (targetElement != null && targetElement != elemTag) return false;
    for (final rc in requiredClasses) {
      if (!elemClasses.contains(rc)) return false;
    }
    for (final ac in ancestorClasses) {
      if (!elemAncestors.contains(ac)) return false;
    }
    return true;
  }
}

class _EmojiRun {
  final String text;
  final bool emoji;
  const _EmojiRun(this.text, this.emoji);
}

