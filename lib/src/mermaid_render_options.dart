/// Optional Mermaid render-time overrides shared by SVG and PNG generation.
class MermaidRenderOptions {
  const MermaidRenderOptions({
    this.config,
    this.backgroundColor,
  });

  /// Extra Mermaid `initialize(...)` config merged into the renderer defaults.
  final Map<String, Object?>? config;

  /// PNG canvas background color in CSS hex format (`#RRGGBB` or `#AARRGGBB`).
  final String? backgroundColor;
}
