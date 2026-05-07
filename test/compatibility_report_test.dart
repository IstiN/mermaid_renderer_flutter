import 'dart:io';

import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Generates SVG + PNG for every diagram type in MermaidDiagramFixtures (Java parity).
/// Outputs to build/mermaid-compatibility/ (same dir name as Java side).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const outputDir = 'build/mermaid-compatibility-dart';
  late MermaidRenderer renderer;

  setUpAll(() async {
    renderer = MermaidRenderer();
    await renderer.init();
    Directory(outputDir).createSync(recursive: true);
  });

  tearDownAll(() {
    renderer.dispose();
  });

  for (final (name, definition) in _fixtures) {
    test('renders $name', () async {
      String? svg;
      String? svgError;
      String? pngError;

      // --- SVG ---
      try {
        svg = await renderer.renderToSvg(definition);
        expect(svg, contains('<svg'), reason: '$name SVG must contain <svg');
        File('$outputDir/$name.svg').writeAsStringSync(svg);
      } catch (e) {
        svgError = e.toString();
      }

      // --- PNG ---
      try {
        final png = await renderer.renderToPng(definition);
        expect(png[0], 0x89, reason: '$name PNG magic byte 0');
        expect(png[1], 0x50, reason: '$name PNG magic byte 1');
        File('$outputDir/$name.png').writeAsBytesSync(png);
      } catch (e) {
        pngError = e.toString();
      }

      final status = (svgError == null ? '✅ SVG' : '❌ SVG') +
          ' | ' +
          (pngError == null ? '✅ PNG' : '❌ PNG');
      print('[$name] $status');
      if (svgError != null) print('  SVG error: $svgError');
      if (pngError != null) print('  PNG error: $pngError');

      // Fail if both outputs failed.
      if (svgError != null && pngError != null) {
        fail('$name: both SVG and PNG failed — SVG: $svgError | PNG: $pngError');
      }
    });
  }
}

// ─── Same fixture definitions as Java MermaidDiagramFixtures ─────────────────

const List<(String, String)> _fixtures = [
  ('flowchart', '''
flowchart TD
  A[Start] --> B{Is blocked?}
  B -->|Yes| C[Check blockers]
  C --> D{All done?}
  D -->|No| E[Keep blocked]
  D -->|Yes| F[Move to Backlog]
  B -->|No| G[Work normally]
'''),
  ('class', '''
classDiagram
  class MermaidRenderer
  MermaidRenderer : +renderToSvg(String)
  MermaidRenderer : +renderToPng(String, Path)
  class GraalBridge
  GraalBridge : +eval(String)
  class SvgTranscoder
  SvgTranscoder : +toPng(String, Path)
  MermaidRenderer --> GraalBridge : uses
  MermaidRenderer --> SvgTranscoder : converts
'''),
  ('sequence', '''
sequenceDiagram
  participant User
  participant DMTools
  participant Renderer
  User->>DMTools: mermaid_to_png
  DMTools->>Renderer: renderToPng()
  Renderer-->>DMTools: png path
  DMTools-->>User: output path
'''),
  ('entity-relationship', '''
erDiagram
  CUSTOMER ||--o{ ORDER : places
  ORDER ||--|{ LINE_ITEM : contains
  PRODUCT ||--o{ LINE_ITEM : includes
  CUSTOMER {
    string id
    string name
    string email
  }
  ORDER {
    string id
    date createdAt
    string status
  }
  LINE_ITEM {
    string id
    int quantity
  }
  PRODUCT {
    string sku
    string title
  }
'''),
  ('state', '''
stateDiagram-v2
  [*] --> Still
  Still --> Moving
  Moving --> Still
  Moving --> Crash
  Crash --> [*]
'''),
  ('mindmap', '''
mindmap
  root((DMTools))
    Renderer
      SVG
      PNG
    Integrations
      Jira
      GitHub
    CLI
      mermaid_to_svg
      mermaid_to_png
'''),
  ('architecture', '''
architecture-beta
  group api(cloud)[DMTools]
  service cli(server)[CLI] in api
  service renderer(server)[Renderer] in api
  service jira(database)[Jira] in api
  cli:R --> L:renderer
  renderer:R --> L:jira
'''),
  ('block', '''
block
  columns 3
  A["Input Mermaid"]
  B["Render SVG"]
  C["Convert PNG"]
  A --> B
  B --> C
'''),
  ('c4', '''
C4Context
  title DMTools Mermaid Renderer
  Person(user, "User")
  System(dmtools, "DMTools CLI")
  System(renderer, "Mermaid Renderer")
  Rel(user, dmtools, "Runs")
  Rel(dmtools, renderer, "Delegates rendering")
'''),
  ('gantt', '''
gantt
  title Renderer Production Plan
  dateFormat  YYYY-MM-DD
  section Renderer
  DOM shim           :a1, 2026-05-01, 7d
  Mermaid bundle     :a2, after a1, 5d
  Visual validation  :a3, after a2, 4d
'''),
  ('git', '''
gitGraph
  commit id: "init"
  commit id: "renderer"
  branch renderer
  checkout renderer
  commit id: "svg"
  commit id: "png"
  checkout main
  commit id: "docs"
  merge renderer
  commit id: "release"
'''),
  ('ishikawa', '''
ishikawa-beta
  Rendering quality
    DOM
      Missing layout
      Text metrics
    SVG
      CSS support
      ViewBox
    PNG
      Batik
      Transparency
    Tests
      Fixtures
      Visual report
'''),
  ('kanban', '''
kanban
  backlog[Backlog]
    dom[DOM shim]
    bundle[Mermaid bundle]
  progress[In Progress]
    cli[CLI adapter]
  done[Done]
    repo[Renderer repo]
'''),
  ('packet', '''
packet-beta
  title TCP Packet
  0-15: "Source Port"
  16-31: "Destination Port"
  32-63: "Sequence Number"
  64-95: "Acknowledgment Number"
'''),
  ('pie', '''
pie title Renderer work split
  "DOM shim" : 45
  "Mermaid bundle" : 30
  "Tests" : 25
'''),
  ('quadrant', '''
quadrantChart
  title Renderer Options
  x-axis Low effort --> High effort
  y-axis Low quality --> High quality
  quadrant-1 Production
  quadrant-2 Risky
  quadrant-3 Avoid
  quadrant-4 Quick win
  Browser: [0.8, 0.9]
  Toy renderer: [0.2, 0.3]
  Graal DOM shim: [0.7, 0.85]
'''),
  ('radar', '''
radar-beta
  axis Quality, Coverage, Speed, Maintenance, Portability
  curve MermaidEngine["Mermaid Engine"]{90,85,70,80,95}
  curve ToyRenderer["Toy Renderer"]{35,20,95,30,90}
'''),
  ('requirement', '''
requirementDiagram
  requirement renderer {
    id: 1
    text: Render Mermaid to PNG
    risk: medium
    verifymethod: test
  }
  element cli {
    type: interface
  }
  cli - satisfies -> renderer
'''),
  ('sankey', '''
sankey-beta
  Mermaid,SVG,100
  SVG,PNG,80
  SVG,Diagnostics,20
'''),
  ('timeline', '''
timeline
  title Mermaid Renderer
  POC : Toy renderer
  Extraction : Standalone Java repo
  Production : Real Mermaid bundle
  Validation : Visual samples
'''),
  ('treeview', '''
treeView-beta
    "dmtools/"
        "mermaid_to_svg"
        "mermaid_to_png"
        "renderer/"
            "graaljs"
            "batik"
'''),
  ('treemap', '''
treemap-beta
  "Renderer"
    "DOM shim": 40
    "Mermaid bundle": 35
    "Batik": 15
    "Tests": 10
'''),
  ('user-journey', '''
journey
  title Developer renders diagram
  section CLI
    Writes Mermaid text: 5: Developer
    Runs dmtools mermaid_to_png: 4: Developer
  section Renderer
    Generates SVG: 5: Renderer
    Converts PNG: 5: Renderer
'''),
  ('venn', '''
venn-beta
  title Renderer Concerns
  set Quality:40
  set Portability:35
  set Speed:25
  union Quality,Portability:15
  union Quality,Speed:10
'''),
  ('wardley', '''
wardley-beta
  title Renderer Strategy
  anchor User [0.95, 0.65]
  component DMTools CLI [0.75, 0.55]
  component Mermaid Renderer [0.55, 0.45]
  component DOM Shim [0.35, 0.35]
  User->DMTools CLI
  DMTools CLI->Mermaid Renderer
  Mermaid Renderer->DOM Shim
'''),
  ('xy', '''
xychart-beta
  title "Renderer quality over iterations"
  x-axis [POC, Extracted, MermaidEngine, Validated]
  y-axis "Quality" 0 --> 100
  line [20, 45, 85, 95]
'''),
  ('zenuml', '''
zenuml
  title Renderer call
  User->DMTools: mermaid_to_png
  DMTools->Renderer: renderToPng()
  Renderer-->DMTools: path
'''),
];
