import 'package:dmtools_mermaid_renderer/src/svg_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dart port of NormalizeSvgForBatikTest.java
///
/// Each group covers a specific normalization step so regressions in one area
/// do not silently break others.
void main() {
  // ── helpers ──────────────────────────────────────────────────────────────

  String svgWrap(String body, {String style = ''}) {
    return '<svg id="dmtools-mermaid" xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 200 100">'
        '<style>$style</style>'
        '$body'
        '</svg>';
  }

  // ── !important stripping ─────────────────────────────────────────────────

  group('ImportantStripping', () {
    test('strips !important from CSS property', () {
      final svg = svgWrap(
        '<rect width="10" height="10"/>',
        style: '.marker{fill:none !important;}',
      );
      final result = SvgNormalizer.normalize(svg);
      expect(result, isNot(contains('!important')));
      expect(result, contains('fill:none'));
    });

    test('strips multiple !important declarations', () {
      final svg = svgWrap(
        '<rect width="10" height="10"/>',
        style: '.a{fill:red !important;stroke:blue !important;}',
      );
      final result = SvgNormalizer.normalize(svg);
      expect(result, isNot(contains('!important')));
      expect(result, contains('fill:red'));
      expect(result, contains('stroke:blue'));
    });
  });

  // ── style="undefined" cleanup ─────────────────────────────────────────────

  group('UndefinedStyleCleanup', () {
    test('removes style with only undefined', () {
      final svg = svgWrap('<path style="undefined;;;undefined" d="M0,0L10,10"/>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, isNot(contains('style="undefined')));
    });

    test('removes empty style attribute', () {
      final svg = svgWrap('<path style="  ;; " d="M0,0L10,10"/>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, isNot(contains('style="  ;; "')));
    });

    test('preserves valid style attribute', () {
      final svg = svgWrap('<path style="stroke: none" d="M0,0L10,10"/>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, contains('stroke: none'));
    });
  });

  // ── empty fill / font-weight cleanup ─────────────────────────────────────

  group('EmptyFillCleanup', () {
    test('removes empty fill attribute', () {
      final svg = svgWrap('<text fill="" class="taskText">Hello</text>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, isNot(contains('fill=""')));
    });

    test('preserves non-empty fill attribute', () {
      final svg = svgWrap('<text fill="#333" class="taskText">Hello</text>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, contains('fill="#333"'));
    });

    test('removes empty font-weight attribute', () {
      final svg = svgWrap(
          '<g style="font-weight: bolder" class="label">'
          '<tspan font-weight="">MermaidRenderer</tspan>'
          '</g>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, isNot(contains('font-weight=""')));
    });

    test('preserves non-empty font-weight attribute', () {
      final svg = svgWrap('<tspan font-weight="bold">Header</tspan>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, contains('font-weight="bold"'));
    });
  });

  // ── orient="auto-start-reverse" fix ──────────────────────────────────────

  group('OrientFix', () {
    test('replaces auto-start-reverse with auto', () {
      final svg = svgWrap('<marker orient="auto-start-reverse"/>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, contains('orient="auto"'));
      expect(result, isNot(contains('auto-start-reverse')));
    });
  });

  // ── rect normalization ────────────────────────────────────────────────────

  group('RectNormalization', () {
    test('adds default width when missing', () {
      final svg = svgWrap('<rect height="30"></rect>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, contains('width="'));
    });

    test('adds default height when missing', () {
      final svg = svgWrap('<rect width="50"></rect>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, contains('height="'));
    });

    test('preserves existing width and height', () {
      final svg = svgWrap('<rect width="50" height="30"></rect>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, contains('width="50"'));
      expect(result, contains('height="30"'));
    });
  });

  // ── xlink:href image fix ─────────────────────────────────────────────────

  group('ImageHrefFix', () {
    test('converts image href to xlink:href', () {
      final svg = svgWrap('<image href="logo.png" width="50" height="50"/>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, contains('xlink:href="logo.png"'));
    });

    test('removes image element with no href', () {
      final svg = svgWrap('<image width="50" height="50"/>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, isNot(contains('<image')));
    });
  });

  // ── foreignObject removal ─────────────────────────────────────────────────

  group('ForeignObjectRemoval', () {
    test('removes foreignObject blocks', () {
      final svg = svgWrap(
          '<switch><foreignObject width="100" height="50">'
          '<div xmlns="http://www.w3.org/1999/xhtml">Label</div>'
          '</foreignObject>'
          '<text>fallback</text></switch>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, isNot(contains('foreignObject')));
      expect(result, isNot(contains('<switch>')));
      expect(result, contains('fallback'));
    });
  });

  // ── alignment-baseline fix ────────────────────────────────────────────────

  group('AlignmentBaselineFix', () {
    test('replaces central with middle', () {
      final svg =
          svgWrap('<text alignment-baseline="central">Label</text>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, contains('alignment-baseline="middle"'));
      expect(result, isNot(contains('alignment-baseline="central"')));
    });
  });

  // ── emoji tspan splitting ─────────────────────────────────────────────────

  group('EmojiFontSpans', () {
    test('wraps emoji runs with Noto Emoji font family', () {
      final svg =
          svgWrap('<text><tspan>Done ✅ and robot 🤖</tspan></text>');
      final result = SvgNormalizer.normalize(svg);

      expect(
        result,
        contains(
            'font-family="Noto Emoji, Apple Color Emoji, Segoe UI Emoji, sans-serif"'),
        reason:
            'emoji runs should use an explicit emoji font for proper rendering',
      );
      expect(
        result,
        contains('style="fill:#111111;"'),
        reason: 'emoji runs should force a readable dark fill',
      );
      expect(result, contains('Done'),
          reason: 'non-emoji text should remain');
      expect(
        result,
        isNot(contains('<tspan>Done ✅ and robot 🤖</tspan>')),
        reason: 'mixed text should be split into separate runs',
      );
    });

    test('leaves plain text without emoji font tspans', () {
      final svg =
          svgWrap('<text><tspan>Done without emoji</tspan></text>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, isNot(contains('font-family="Noto Emoji')));
    });
  });

  // ── Affinity text positioning ─────────────────────────────────────────────

  group('AffinityTextPositioning', () {
    test('removes parent text y when rows have explicit y', () {
      final svg = svgWrap(
          '<text y="-10.1">'
          '<tspan class="text-outer-tspan row" x="0" y="-0.1em" dy="1.1em">SM adds</tspan>'
          '<tspan class="text-outer-tspan row" x="0" y="1em" dy="1.1em">BEFORE dispatch</tspan>'
          '</text>');
      final result = SvgNormalizer.normalize(svg);

      expect(
        result,
        isNot(contains('<text y="-10.1"')),
        reason: 'parent text y should be removed so row y is single source',
      );
      expect(result, contains('y="-1.6"'),
          reason: 'row tspan y em should be converted to px');
    });

    test('keeps text y when rows are not explicitly positioned', () {
      final svg =
          svgWrap('<text y="20"><tspan>Plain label</tspan></text>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, contains('<text y="20"'),
          reason: 'single-line/plain text still needs its parent y');
    });
  });

  // ── journey section background ────────────────────────────────────────────

  group('JourneySectionBackground', () {
    test('removes explicit fill from journey-section rect', () {
      final svg = svgWrap(
          '<rect class="journey-section" fill="#333333" width="200" height="50"/>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, isNot(contains('fill="#333333"')));
    });

    test('adds dark fill to journey section label text', () {
      final svg = svgWrap(
          '<text class="journey-section label" style="font-size:14px">Section</text>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, contains('fill:#333'));
    });
  });

  // ── background rect fill fallback ─────────────────────────────────────────

  group('BackgroundRectFillFallback', () {
    test('sets fill=none on background rect with no fill', () {
      final svg =
          svgWrap('<rect class="background" width="200" height="100"/>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, contains('fill="none"'));
    });

    test('does not override existing fill on background rect', () {
      final svg = svgWrap(
          '<rect class="background" fill="white" width="200" height="100"/>');
      final result = SvgNormalizer.normalize(svg);
      expect(result, contains('fill="white"'));
      // Should not add a second fill="none"
      expect('fill="none"'.allMatches(result).length, 0);
    });
  });
}
