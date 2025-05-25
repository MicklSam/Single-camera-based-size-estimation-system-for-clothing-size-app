import 'package:flutter_test/flutter_test.dart';
import 'package:test1/main.dart';
import 'package:camera/camera.dart';

void main() {
  testWidgets('Widget test', (WidgetTester tester) async {
    // استخدم كاميرا افتراضية أو يمكنك تعليق هذا الاختبار مؤقتًا
    final cameras = await availableCameras();
    final firstCamera = cameras.first;

    await tester.pumpWidget(MyApp(camera: firstCamera));
    expect(find.text('كشف وضعية الجسم'), findsOneWidget);
  });
}
