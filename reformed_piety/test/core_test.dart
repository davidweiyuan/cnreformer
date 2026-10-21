import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reformed_piety/core/models.dart';
import 'package:reformed_piety/core/content_service.dart';
import 'package:reformed_piety/core/app_store.dart';

Map<String, dynamic> post(
  int id, {
  String content = '<p>靈修</p>',
  String modified = '2026-10-20T00:00:00Z',
}) => {
  'ID': id,
  'title': '<b>信心</b> &amp; Hope',
  'URL': 'https://davidweiyuan.wordpress.com/post-$id/',
  'content': content,
  'excerpt': '<p>摘要</p>',
  'date': '2026-10-20T00:00:00Z',
  'modified': modified,
};
OfflineEntry entry(int id, int bytes, int days) => OfflineEntry(
  id: id,
  bytes: bytes,
  downloaded: DateTime.utc(2026, 1, days),
  modified: DateTime.utc(2026),
);
void main() {
  test(
    'eviction removes oldest unprotected downloads and preserves protected',
    () {
      expect(
        evictionPlan(
          [entry(1, 100, 1), entry(2, 100, 2), entry(3, 100, 3)],
          {1},
          250,
          50,
        ),
        [2],
      );
      expect(evictionPlan([entry(1, 200, 1)], {1}, 250, 100), isNull);
      expect(
        evictionPlan([entry(1, 200, 1)], {1}, 250, 220, replacing: 1),
        isEmpty,
      );
    },
  );
  test('article HTML entities and downloadable attachment discovery', () {
    final a = Article.fromWordPress(
      post(
        1,
        content: '<p><a href="https://files.test/notes.pdf">Notes</a><a href="https://files.test/film.mp4">Movie</a></p>',
      ),
    );
    expect(a.title, '信心 & Hope');
    expect(a.materials, ['https://files.test/notes.pdf']);
  });
  test('search query is encoded and pagination remains independent', () async {
    final service = ContentService(
      client: MockClient((r) async {
        expect(r.url.queryParameters['search'], '信心 & hope');
        expect(r.url.queryParameters['page'], '2');
        return http.Response(jsonEncode({'posts': [], 'found': 0}), 200);
      }),
    );
    await service.articles(search: '信心 & hope', page: 2);
  });
  test(
    'only confirmed missing posts are deletions, not gateway or auth failures',
    () async {
      for (final code in [401, 403, 500, 503]) {
        final service = ContentService(
          client: MockClient(
            (r) async => http.Response('{"error":"unknown_post"}', code),
          ),
        );
        await expectLater(service.article(1), throwsA(isA<ContentFailure>()));
      }
      final missing = ContentService(
        client: MockClient(
          (r) async => http.Response('{"error":"unknown_post"}', 404),
        ),
      );
      await expectLater(missing.article(1), throwsA(isA<DeletedPost>()));
    },
  );
  test('video parser uses regular tab, excludes live and unrelated tabs', () {
    Map<String, dynamic> item(String id, String length) => {
      'richItemRenderer': {
        'content': {
          'lockupViewModel': {
            'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
            'contentId': id,
            'metadata': {
              'lockupMetadataViewModel': {
                'title': {'content': '講道'},
              },
            },
            'contentImage': {
              'thumbnailBadgeViewModel': {'text': length},
            },
          },
        },
      },
    };
    final data = <String, dynamic>{
      'contents': {
        'twoColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'selected': true,
                'endpoint': {
                  'commandMetadata': {
                    'webCommandMetadata': {'url': '/@davidweiyuan/videos'},
                  },
                },
                'content': {
                  'contents': [
                    item('abcdefghijk', '35:41'),
                    item('live1234567', 'LIVE'),
                  ],
                },
              },
            },
          ],
        },
      },
    };
    expect(ContentService.parseVideoTab(data).map((v) => v.id), [
      'abcdefghijk',
    ]);
    expect(
      () => ContentService.parseVideoTab({}),
      throwsA(isA<ContentFailure>()),
    );
  });
  group('offline store', () {
    late Directory root;
    late AppStore store;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('rp-test-');
      store = AppStore(
        root,
        service: ContentService(
          client: MockClient((r) async {
            if (r.url.host == 'assets.test') {
              return http.Response(
                'fake-image-bytes',
                200,
                headers: {'content-type': 'image/png'},
              );
            }
            return http.Response(
              jsonEncode(post(1)),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      await store.initialize();
    });
    tearDown(() async {
      await store.persist();
      store.dispose();
      await root.delete(recursive: true);
    });
    test('text images and materials survive restart; bookmarks and protection independent', () async {
      final a = Article.fromWordPress(
        post(
          1,
          content: '<p>正文</p><img src="https://assets.test/pic.png"><a href="https://assets.test/notes.pdf">筆記</a>',
        ),
      );
      store.articles[1] = a;
      await store.download(1);
      expect(store.offline[1]?.failed, isEmpty);
      expect(store.offline[1]?.files.length, 2);
      expect(store.htmlFor(a), contains('file:'));
      expect(store.htmlFor(a), isNot(contains('src="https://assets.test')));
      await store.bookmarkArticle(1);
      expect(store.protected, isEmpty);
      await store.protect(1);
      await store.addReading(1, 35);
      await store.addReading(1, 25);
      await store.persist();
      final restored = AppStore(root);
      await restored.initialize();
      expect(restored.savedArticles, {1});
      expect(restored.protected, {1});
      expect(restored.readingSeconds[1], 60);
      expect((await restored.openArticle(1)).content, contains('正文'));
      expect(
        restored.materialPath(1, 'https://assets.test/notes.pdf'),
        isNotNull,
      );
      await restored.markUnread(1);
      expect(restored.readingSeconds[1], 0);
      restored.dispose();
    });
    test(
      'expiry removes only unprotected downloads, keeps bookmarks',
      () async {
        store.articles[1] = Article.fromWordPress(post(1));
        await store.download(1);
        await store.bookmarkArticle(1);
        final now = DateTime.now().toUtc().add(const Duration(days: 61));
        await store.protect(1);
        await store.cleanExpired(now: now);
        expect(store.offline.containsKey(1), isTrue);
        await store.protect(1);
        await store.cleanExpired(now: now);
        expect(store.offline, isEmpty);
        expect(store.savedArticles, {1});
      },
    );
    test(
      'confirmed deletion overrides protection and clears related state',
      () async {
        store.articles[1] = Article.fromWordPress(post(1));
        await store.download(1);
        await store.protect(1);
        await store.bookmarkArticle(1);
        await store.addReading(1, 60);
        await store.removeDeleted(1);
        expect(store.offline, isEmpty);
        expect(store.protected, isEmpty);
        expect(store.savedArticles, isEmpty);
        expect(store.readingSeconds, isEmpty);
        expect(await Directory(store.folder(1)).exists(), isFalse);
      },
    );
    test(
      'failed image download remains explicitly partial, not fully offline',
      () async {
        store.articles[1] = Article.fromWordPress(
          post(
            1,
            content: '<p>正文</p><img src="http://invalid.test/image.jpg">',
          ),
        );
        // HTTPS image with a rejected HTML response.
        final other = AppStore(
          root,
          service: ContentService(
            client: MockClient(
              (r) async => http.Response(
                '<html>Login</html>',
                200,
                headers: {'content-type': 'text/html'},
              ),
            ),
          ),
        );
        other.articles[2] = Article.fromWordPress(
          post(2, content: '<img src="https://invalid.test/image.jpg">'),
        );
        await other.download(2);
        expect(other.offline[2]?.failed, hasLength(1));
        expect(other.downloadError, 'partial');
        other.dispose();
      },
    );
  });
}
