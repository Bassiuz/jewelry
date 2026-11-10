/// Centre of the first node in a `uiautomator dump` XML whose text or
/// content-desc matches [text] case-insensitively. Null when absent.
({int x, int y})? findNodeCenter(String xml, String text) {
  final wanted = text.toLowerCase();
  for (final node in RegExp(r'<node [^>]*>').allMatches(xml)) {
    final attrs = node.group(0)!;
    final label = RegExp(r'text="([^"]*)"').firstMatch(attrs)?.group(1) ?? '';
    final desc =
        RegExp(r'content-desc="([^"]*)"').firstMatch(attrs)?.group(1) ?? '';
    if (label.toLowerCase() != wanted && desc.toLowerCase() != wanted) continue;
    final b = RegExp(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
        .firstMatch(attrs);
    if (b == null) continue;
    final (x1, y1, x2, y2) = (
      int.parse(b.group(1)!),
      int.parse(b.group(2)!),
      int.parse(b.group(3)!),
      int.parse(b.group(4)!),
    );
    return (x: (x1 + x2) ~/ 2, y: (y1 + y2) ~/ 2);
  }
  return null;
}

/// Centres of every node whose resource-id ends with [idSuffix], in dump
/// order. The notification shade's expand chevrons are `…:id/expand_button`.
List<({int x, int y})> findNodeCentersById(String xml, String idSuffix) => [
  for (final node in RegExp(r'<node [^>]*>').allMatches(xml))
    if ((RegExp(r'resource-id="([^"]*)"').firstMatch(node.group(0)!)?.group(1) ?? '')
        .endsWith(idSuffix))
      ?_center(node.group(0)!),
];

({int x, int y})? _center(String attrs) {
  final b = RegExp(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"').firstMatch(attrs);
  if (b == null) return null;
  final v = [for (var i = 1; i <= 4; i++) int.parse(b.group(i)!)];
  return (x: (v[0] + v[2]) ~/ 2, y: (v[1] + v[3]) ~/ 2);
}
