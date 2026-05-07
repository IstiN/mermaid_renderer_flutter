/// Headless Mermaid SVG/PNG renderer for Flutter.
///
/// Drop-in Dart/Flutter counterpart to the Java `dmtools-mermaid-renderer` library.
/// Uses `flutter_js` (QuickJS / JavaScriptCore) for headless Mermaid rendering and
/// `flutter_svg` + `dart:ui` for pixel-perfect PNG output.
library dmtools_mermaid_renderer;

export 'src/mermaid_renderer.dart';
export 'src/svg_normalizer.dart';
