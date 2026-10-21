import 'package:html/parser.dart' as html;

const blogHost = 'davidweiyuan.wordpress.com';
const channelUrl = 'https://www.youtube.com/@davidweiyuan/videos';
String plain(String value) => html.parseFragment(value).text ?? '';
DateTime date(Object? value) =>
    DateTime.tryParse('$value')?.toUtc() ?? DateTime.utc(2000);

class Article {
  final int id;
  final String title, url, content, excerpt, image;
  final DateTime published, modified;
  final List<String> materials;
  const Article({
    required this.id,
    required this.title,
    required this.url,
    required this.content,
    required this.excerpt,
    required this.published,
    required this.modified,
    this.image = '',
    this.materials = const [],
  });
  factory Article.fromWordPress(Map<String, dynamic> j) {
    final content = j['content'] as String? ?? '';
    final materialUrls = <String>{};
    final fragment = html.parseFragment(content);
    for (final a in fragment.querySelectorAll('a[href]')) {
      final url = Uri.tryParse(a.attributes['href']!);
      if (url != null && isMaterial(url)) materialUrls.add(url.toString());
    }
    final attachments = j['attachments'];
    if (attachments is Map) {
      for (final a in attachments.values) {
        final url = Uri.tryParse('${a['URL'] ?? a['url'] ?? ''}');
        if (url != null && isMaterial(url)) materialUrls.add('$url');
      }
    }
    return Article(
      id: j['ID'] as int,
      title: plain(j['title'] ?? ''),
      url: j['URL'] as String,
      content: content,
      excerpt: plain(j['excerpt'] ?? '').trim(),
      image: j['featured_image'] as String? ?? '',
      published: date(j['date']),
      modified: date(j['modified']),
      materials: materialUrls.toList(),
    );
  }
  factory Article.fromJson(Map<String, dynamic> j) => Article(
    id: j['id'],
    title: j['title'],
    url: j['url'],
    content: j['content'] ?? '',
    excerpt: j['excerpt'] ?? '',
    image: j['image'] ?? '',
    published: date(j['published']),
    modified: date(j['modified']),
    materials: List<String>.from(j['materials'] ?? []),
  );
  Map<String, dynamic> toJson({bool withContent = true}) => {
    'id': id,
    'title': title,
    'url': url,
    'content': withContent ? content : '',
    'excerpt': excerpt,
    'image': image,
    'published': published.toIso8601String(),
    'modified': modified.toIso8601String(),
    'materials': materials,
  };
  static bool isMaterial(Uri u) =>
      u.scheme == 'https' &&
      RegExp(
        r'\.(pdf|docx?|pptx?|xlsx?|rtf|txt|epub)$',
        caseSensitive: false,
      ).hasMatch(u.path);
}

class Video {
  final String id, title, duration, publishedLabel;
  const Video({
    required this.id,
    required this.title,
    this.duration = '',
    this.publishedLabel = '',
  });
  String get url => 'https://www.youtube.com/watch?v=$id';
  String get thumbnail => 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
  factory Video.fromJson(Map<String, dynamic> j) => Video(
    id: j['id'],
    title: j['title'],
    duration: j['duration'] ?? '',
    publishedLabel: j['publishedLabel'] ?? '',
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'duration': duration,
    'publishedLabel': publishedLabel,
  };
}

class Preferences {
  bool simplified, autoDownload, welcomed;
  String theme;
  double fontSize;
  int limitMB;
  Preferences({
    this.simplified = false,
    this.autoDownload = true,
    this.welcomed = false,
    this.theme = 'system',
    this.fontSize = 19,
    this.limitMB = 500,
  });
  factory Preferences.fromJson(Map<String, dynamic> j) => Preferences(
    simplified: j['simplified'] ?? false,
    autoDownload: j['autoDownload'] ?? true,
    welcomed: j['welcomed'] ?? false,
    theme: j['theme'] ?? 'system',
    fontSize: (j['fontSize'] as num? ?? 19).toDouble().clamp(15, 30),
    limitMB: (j['limitMB'] as int? ?? 500).clamp(50, 5000),
  );
  Map<String, dynamic> toJson() => {
    'simplified': simplified,
    'autoDownload': autoDownload,
    'welcomed': welcomed,
    'theme': theme,
    'fontSize': fontSize,
    'limitMB': limitMB,
  };
}

class OfflineEntry {
  final int id, bytes;
  final DateTime downloaded, modified;
  final List<String> failed;
  // URL -> relative filename, never an absolute sandbox path (iOS may move containers).
  final Map<String, String> files;
  const OfflineEntry({
    required this.id,
    required this.bytes,
    required this.downloaded,
    required this.modified,
    this.failed = const [],
    this.files = const {},
  });
  factory OfflineEntry.fromJson(Map<String, dynamic> j) => OfflineEntry(
    id: j['id'],
    bytes: j['bytes'],
    downloaded: date(j['downloaded']),
    modified: date(j['modified']),
    failed: List<String>.from(j['failed'] ?? []),
    files: Map<String, String>.from(j['files'] ?? {}),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'bytes': bytes,
    'downloaded': downloaded.toIso8601String(),
    'modified': modified.toIso8601String(),
    'failed': failed,
    'files': files,
  };
}

/// Returns oldest unprotected downloads to evict; null means protected data fills the budget.
List<int>? evictionPlan(
  Iterable<OfflineEntry> entries,
  Set<int> protected,
  int budget,
  int incoming, {
  int? replacing,
}) {
  final remaining = entries.where((e) => e.id != replacing).toList();
  var used = remaining.fold<int>(0, (n, e) => n + e.bytes);
  final candidates = remaining.where((e) => !protected.contains(e.id)).toList()
    ..sort((a, b) => a.downloaded.compareTo(b.downloaded));
  final removals = <int>[];
  for (final entry in candidates) {
    if (used + incoming <= budget) break;
    used -= entry.bytes;
    removals.add(entry.id);
  }
  return used + incoming <= budget ? removals : null;
}
