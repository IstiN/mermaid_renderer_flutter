# dmtools_mermaid_renderer

Dart / Flutter counterpart to the Java [`dmtools-mermaid-renderer`](https://github.com/IstiN/dmtools-mermaid-renderer) library.

Renders [Mermaid](https://mermaid.js.org/) diagram DSL to **SVG** or **PNG** without a browser:

| Java version | Flutter version |
|---|---|
| GraalJS | flutter_js (QuickJS / JavaScriptCore) |
| Apache Batik SVG→PNG | flutter_svg + dart:ui PictureRecorder |
| AWT FontMetrics | JS built-in heuristics (approximate) |
| NotoSans + NotoEmoji TTF | bundled Flutter font assets |

## Features

- Flowchart, sequence, class, state, ER, mind-map, journey, quadrant, pie, gantt, git-graph, block, packet, Sankey, xychart, zenuml
- Emoji font split: mixed text/emoji nodes correctly use `Noto Emoji` so emoji glyphs appear
- Affinity Designer / Inkscape compatible SVG: no foreignObject, filters, animations; text-anchor inlined; redundant parent `<text y=…>` removed
- White-background PNG at natural SVG dimensions

## Usage

```dart
import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final renderer = MermaidRenderer();
  await renderer.init();

  // SVG string
  final svg = await renderer.renderToSvg('flowchart TD; A --> B');

  // PNG bytes
  final png = await renderer.renderToPng('flowchart TD; A --> B');

  renderer.dispose();
}
```

## Architecture

```
MermaidRenderer
  └─ flutter_js (JS engine)
       └─ mermaid-renderer.js  (11 MB bundle — Mermaid + GraalJS DOM shim)
  └─ SvgNormalizer             (Dart port of MermaidRenderer.normalizeSvgForBatik)
  └─ MermaidRenderer.svgToPng  (flutter_svg + dart:ui PictureRecorder)
```

## Running tests

```sh
flutter test
```

## Notes

- Text metrics in the JS shim use built-in heuristics (`estimateTextWidth`).
  Java-backed AWT font metrics are not available in Flutter; the visual output
  is still good because `flutter_svg` uses system fonts for final PNG rendering.
- Color emoji require `NotoColorEmoji` (CBDT/CBLC) which is not a standard TTF;
  the bundled `NotoEmoji-Regular.ttf` is monochrome only (same limitation as the
  Java version).
