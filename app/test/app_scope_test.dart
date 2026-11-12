import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/cameras/cameras_screen.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('the app starts when the debug log folder cannot be opened', (
    tester,
  ) async {
    final app = (await tester.runAsync(
      () => createTestApp(debugLogBlocked: true),
    ))!;
    expect(app.models.debugLog.available, isFalse);
    await app.pumpApp(tester);
    await pumpUntilFound(tester, find.byType(CamerasScreen));

    await app.dispose();
  });
}
