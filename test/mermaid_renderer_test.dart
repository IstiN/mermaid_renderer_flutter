import 'dart:io';

import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Integration test — renders a real Mermaid diagram via flutter_js and writes
/// SVG + PNG to build/render-output/.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const outputDir = 'build/render-output';

  const definition = '''
flowchart TD
    A["📥 Intake"] --> B["🤖 AI Triage"]
    B --> C{"Priority?"}
    C -->|High| D["🚨 Escalate"]
    C -->|Low| E["📋 Backlog"]
    D --> F["✅ Resolve"]
    E --> F
  ''';

  late MermaidRenderer renderer;

  setUpAll(() async {
    renderer = MermaidRenderer();
    await renderer.init();
    Directory(outputDir).createSync(recursive: true);
  });

  tearDownAll(() {
    renderer.dispose();
  });

  test('renders flowchart to SVG file', () async {
    final svg = await renderer.renderToSvg(definition);

    expect(svg, contains('<svg'));
    expect(svg, contains('</svg>'));
    expect(svg, isNot(contains('foreignObject')));
    // emoji should be split into tspans
    // (flowchart uses emoji labels)

    final file = File('$outputDir/flowchart.svg');
    file.writeAsStringSync(svg);
    print('✅ SVG written: ${file.absolute.path}');
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(1000));
  });

  test('renders flowchart to PNG file', () async {
    final png = await renderer.renderToPng(definition);

    expect(png.length, greaterThan(1000));
    // PNG magic bytes: 0x89 0x50 0x4E 0x47
    expect(png[0], 0x89);
    expect(png[1], 0x50);
    expect(png[2], 0x4E);
    expect(png[3], 0x47);

    final file = File('$outputDir/flowchart.png');
    file.writeAsBytesSync(png);
    print('✅ PNG written: ${file.absolute.path}');
    expect(file.existsSync(), isTrue);
  });

  test('renders sequence diagram to SVG', () async {
    const seq = '''
sequenceDiagram
    participant User
    participant AI
    User->>AI: Send ticket
    AI-->>User: Priority label
    ''';
    final svg = await renderer.renderToSvg(seq);
    expect(svg, contains('<svg'));
    final file = File('$outputDir/sequence.svg');
    file.writeAsStringSync(svg);
    print('✅ Sequence SVG: ${file.absolute.path}');
  });

  test('applies custom theme config and background color', () async {
    const options = MermaidRenderOptions(
      backgroundColor: '#111827',
      config: <String, Object?>{
        'theme': 'base',
        'darkMode': true,
        'themeVariables': <String, Object?>{
          'background': '#111827',
          'primaryColor': '#1F2937',
          'primaryTextColor': '#F9FAFB',
          'lineColor': '#8B5CF6',
        },
      },
    );

    final svg = await renderer.renderToSvg(definition, options: options);
    final defaultSvg = await renderer.renderToSvg(definition);
    final themedPng = await renderer.renderToPng(definition, options: options);
    final defaultPng = await renderer.renderToPng(definition);

    expect(svg, contains('<svg'));
    expect(svg, isNot(equals(defaultSvg)));
    expect(themedPng, isNot(equals(defaultPng)));
  });
}
