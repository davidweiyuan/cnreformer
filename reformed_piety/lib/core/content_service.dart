import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ContentFailure implements Exception {
  final String code;
  ContentFailure(this.code);
  @override
  String toString() => code;
}

class DeletedPost implements Exception {}

class ArticlePage {
  final List<Article> posts;
  final int total;
  ArticlePage(this.posts, this.total);
}

class ContentService {
  final http.Client client;
  ContentService({http.Client? client}) : client = client ?? http.Client();
  static const base =
      'https://public-api.wordpress.com/rest/v1.1/sites/$blogHost';
  static const fields =
      'ID,title,URL,date,modified,content,excerpt,attachments,featured_image';
  Future<ArticlePage> articles({
    int page = 1,
    String search = '',
    DateTime? after,
  }) async {
    final u = Uri.parse('$base/posts/').replace(
      queryParameters: {
        'number': '20',
        'page': '$page',
        'fields': fields,
        'order': 'DESC',
        'order_by': 'date',
        if (search.isNotEmpty) 'search': search,
        if (after != null) 'after': after.toIso8601String(),
      },
    );
    final r = await client.get(u).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw ContentFailure('network');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final posts = (j['posts'] as List)
        .map((e) => Article.fromWordPress(Map<String, dynamic>.from(e)))
        .where((p) => Uri.tryParse(p.url)?.host == blogHost)
        .toList();
    return ArticlePage(posts, j['found'] as int);
  }

  Future<Article> article(int id) async {
    final r = await client
        .get(
          Uri.parse('$base/posts/$id')
              .replace(queryParameters: {'fields': fields}),
        )
        .timeout(const Duration(seconds: 25));
    if (r.statusCode == 404 || r.statusCode == 410) {
      // Do not interpret arbitrary gateway/authentication errors as deletion.
      try {
        final j = jsonDecode(r.body);
        if (['unknown_post', 'not_found'].contains(j['error'])) {
          throw DeletedPost();
        }
      } on FormatException {
        /* retain local copy */
      }
    }
    if (r.statusCode != 200) throw ContentFailure('network');
    return Article.fromWordPress(jsonDecode(utf8.decode(r.bodyBytes)));
  }

  Future<List<Video>> videos() async {
    // Test-build adapter: only YouTube's regular Videos tab, not uploads playlist/RSS.
    // No API key, internal API calls, video streams or downloading are involved.
    final r = await client
        .get(
          Uri.parse(channelUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0',
            'Accept-Language': 'en-US,en;q=0.9',
          },
        )
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw ContentFailure('videosUnavailable');
    final match = RegExp(
      r'var ytInitialData = (.*?);</script>',
      dotAll: true,
    ).firstMatch(r.body);
    if (match == null) throw ContentFailure('videosUnavailable');
    return parseVideoTab(jsonDecode(match.group(1)!));
  }

  static List<Video> parseVideoTab(Map<String, dynamic> data) {
    final tabs =
        data['contents']?['twoColumnBrowseResultsRenderer']?['tabs'] as List? ??
        [];
    Map? selected;
    for (final t in tabs) {
      final tab = t['tabRenderer'];
      if (tab?['selected'] == true &&
          '${tab?['endpoint']?['commandMetadata']?['webCommandMetadata']?['url']}'
              .endsWith('/videos')) {
        selected = tab;
      }
    }
    if (selected == null) throw ContentFailure('videosUnavailable');
    final output = <String, Video>{};
    void visit(dynamic node) {
      if (node is Map) {
        final v = node['lockupViewModel'];
        if (v is Map && v['contentType'] == 'LOCKUP_CONTENT_TYPE_VIDEO') {
          final id = v['contentId'] as String? ?? '';
          final title =
              v['metadata']?['lockupMetadataViewModel']?['title']?['content']
                  as String? ??
              '';
          final badges = <String>[];
          void collect(dynamic x) {
            if (x is Map) {
              final b = x['thumbnailBadgeViewModel'];
              if (b is Map) badges.add('${b['text']}');
              for (final value in x.values) {
                collect(value);
              }
            } else if (x is List) {
              for (final value in x) {
                collect(value);
              }
            }
          }

          collect(v['contentImage']);
          final duration =
              badges
                  .where((s) => RegExp(r'^\d+:\d{2}(:\d{2})?$').hasMatch(s))
                  .firstOrNull ??
              '';
          final meta =
              v['metadata']?['lockupMetadataViewModel']?['metadata']?['contentMetadataViewModel']?['metadataRows'];
          final labels = <String>[];
          if (meta is List) {
            for (final row in meta) {
              for (final p in row['metadataParts'] ?? []) {
                labels.add('${p['text']?['content'] ?? ''}');
              }
            }
          }
          final live =
              badges.any((b) => b.toUpperCase().contains('LIVE')) ||
              labels.any((s) => s.toLowerCase().contains('streamed'));
          if (RegExp(r'^[\w-]{11}$').hasMatch(id) &&
              title.isNotEmpty &&
              duration.isNotEmpty &&
              !live) {
            output[id] = Video(
              id: id,
              title: title,
              duration: duration,
              publishedLabel:
                  labels.where((s) => s.contains('ago')).firstOrNull ?? '',
            );
          }
        }
        // Old renderer retained for YouTube's alternate public page layout.
        final old = node['videoRenderer'];
        if (old is Map &&
            old['lengthText'] != null &&
            !jsonEncode(old['badges'] ?? []).contains('LIVE') &&
            !'${old['publishedTimeText']}'.toLowerCase().contains('streamed')) {
          final id = old['videoId'] as String? ?? '';
          if (RegExp(r'^[\w-]{11}$').hasMatch(id)) {
            output[id] = Video(
              id: id,
              title: (old['title']?['runs'] as List? ?? [])
                  .map((e) => e['text'])
                  .join(),
              duration: old['lengthText']?['simpleText'] ?? '',
            );
          }
        }
        for (final value in node.values) {
          visit(value);
        }
      } else if (node is List) {
        for (final value in node) {
          visit(value);
        }
      }
    }

    visit(selected['content']);
    if (output.isEmpty) throw ContentFailure('videosUnavailable');
    return output.values.toList();
  }
}
