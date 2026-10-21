import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reformed_piety/core/app_store.dart';
import 'package:reformed_piety/ui/settings.dart';

void main() {
  testWidgets('Traditional Chinese defaults and streaming-only controls', (
    tester,
  ) async {
    final store = AppStore(Directory('/tmp/rp-widget-unused'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsScreen(store: store)),
      ),
    );
    expect(find.text('繁體中文'), findsOneWidget);
    expect(find.text('自動下載新文章'), findsOneWidget);
    expect(store.preferences.limitMB, 500);
    expect(store.preferences.autoDownload, isTrue);
    store.dispose();
  });
}
