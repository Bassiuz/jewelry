import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/src/device/ui_dump.dart';

void main() {
  const xml =
      '<?xml version="1.0"?><hierarchy>'
      '<node index="0" text="Demo" bounds="[0,100][500,160]" />'
      '<node index="1" text="" content-desc="Open now" class="android.widget.Button" bounds="[40,300][240,380]" />'
      '<node index="2" text="Later" bounds="[260,300][460,380]" />'
      '</hierarchy>';

  test('finds the centre of a node by text, case-insensitively', () {
    expect(findNodeCenter(xml, 'later'), (x: 360, y: 340));
  });

  test('matches content-desc too', () {
    expect(findNodeCenter(xml, 'open now'), (x: 140, y: 340));
  });

  test('returns null when absent', () {
    expect(findNodeCenter(xml, 'overslaan'), isNull);
  });

  test('finds expand chevrons by resource-id suffix, in order', () {
    const shade =
        '<hierarchy>'
        '<node resource-id="com.android.systemui:id/expand_button" bounds="[600,200][700,260]" />'
        '<node resource-id="com.android.systemui:id/title" bounds="[0,0][10,10]" />'
        '<node resource-id="com.android.systemui:id/expand_button" bounds="[600,500][700,560]" />'
        '</hierarchy>';
    expect(findNodeCentersById(shade, ':id/expand_button'), [
      (x: 650, y: 230),
      (x: 650, y: 530),
    ]);
  });
}
