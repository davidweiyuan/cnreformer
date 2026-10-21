import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reformed_piety/main.dart' as app;
import 'package:reformed_piety/ui/readers.dart';
import 'package:reformed_piety/ui/home.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Live WordPress, reader, bookmarks, videos and settings', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    if (find.text('先開始閱讀').evaluate().isNotEmpty) {
      await tester.tap(find.text('先開始閱讀'));
      await tester.pump();
    }
    for (var i = 0; i < 80 && find.text('閱讀文章').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('閱讀文章'), findsWidgets);
    await tester.tap(find.text('閱讀文章').first);
    for (var i = 0; i < 30 && find.byType(HtmlWidget).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(ArticleReader), findsOneWidget);
    expect(find.byType(HtmlWidget), findsOneWidget);
    await tester.tap(find.byTooltip('收藏').first);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(BackButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('講道影片').last);
    await tester.pump(const Duration(seconds: 3));
    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    for (var i = 0; i < 30 && home.store.videoOrder.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(
      home.store.videoOrder,
      isNotEmpty,
      reason: 'Public regular-video adapter must return real uploads',
    );
    final firstVideo = home.store.videos[home.store.videoOrder.first]!;
    await tester.tap(find.text(firstVideo.title).first);
    await tester.pump(const Duration(seconds: 2));
    final dynamic playerState = tester.state(find.byType(VideoReader));
    for (
      var i = 0;
      i < 40 && !playerState.playerReady && !playerState.failed;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(
      playerState.playerReady,
      isTrue,
      reason: 'YouTube iframe readiness: ${playerState.playerError}',
    );
    await playerState.controller.runJavaScript(
      'player.mute(); player.playVideo();',
    );
    for (
      var i = 0;
      i < 40 && playerState.playbackState != 1 && !playerState.failed;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(
      playerState.playbackState,
      1,
      reason: 'Muted embedded playback must start: ${playerState.playerError}',
    );
    await tester.tap(find.byType(BackButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('設定').last);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('自動下載新文章'), findsOneWidget);
    await tester.tap(find.text('靈修文章').last);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
