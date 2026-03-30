import 'package:flutter_test/flutter_test.dart';
import 'package:claude_remote/main.dart';

void main() {
  testWidgets('App renders connect screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ClaudeRemoteApp());
    expect(find.text('Claude Remote'), findsOneWidget);
  });
}
