import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'models.dart';
import 'content_service.dart';

class AppStore extends ChangeNotifier {
  final Directory root;
  final ContentService service;
  Preferences preferences = Preferences();
  final Map<int, Article> articles = {};
  final Map<String, Video> videos = {};
  final Map<int, OfflineEntry> offline = {};
  final Set<int> savedArticles = {}, protected = {};
  final Set<String> savedVideos = {};
  final Map<int, int> readingSeconds = {};
  final List<int> latest = [];
  final List<String> videoOrder = [];
  DateTime? lastSync;
  bool syncing = false, downloading = false;
  String? syncError, videoError, downloadError;
  String downloadTitle = '';
  int totalPosts = 0, currentPage = 1;
  bool _autoRunning = false;
  int? _activeDownload;
  final List<int> _queue = [];
  Future<void> _writes = Future.value();
  AppStore(this.root, {ContentService? service})
    : service = service ?? ContentService();
  int get usedBytes => offline.values.fold(0, (n, e) => n + e.bytes);
  String tr(String traditional, String simplified) =>
      preferences.simplified ? simplified : traditional;
  String get storageText =>
      '${(usedBytes / 1048576).toStringAsFixed(1)} / ${preferences.limitMB} MB';
  String folder(int id) => '${root.path}/downloads/$id';

  Future<void> initialize() async {
    await root.create(recursive: true);
    final index = File('${root.path}/state.json');
    if (await index.exists()) {
      try {
        final j =
            jsonDecode(await index.readAsString()) as Map<String, dynamic>;
        preferences = Preferences.fromJson(j['preferences'] ?? {});
        for (final a in j['articles'] ?? []) {
          final p = Article.fromJson(a);
          articles[p.id] = p;
        }
        for (final v in j['videos'] ?? []) {
          final p = Video.fromJson(v);
          videos[p.id] = p;
        }
        latest.addAll(List<int>.from(j['latest'] ?? []));
        videoOrder.addAll(List<String>.from(j['videoOrder'] ?? []));
        savedArticles.addAll(List<int>.from(j['savedArticles'] ?? []));
        savedVideos.addAll(List<String>.from(j['savedVideos'] ?? []));
        protected.addAll(List<int>.from(j['protected'] ?? []));
        (j['reading'] as Map? ?? {}).forEach(
          (k, v) => readingSeconds[int.parse(k)] = v,
        );
        _queue.addAll(List<int>.from(j['pendingDownloads'] ?? []));
        lastSync = j['lastSync'] == null ? null : date(j['lastSync']);
        for (final e in j['offline'] ?? []) {
          final entry = OfflineEntry.fromJson(e);
          if (await File('${folder(entry.id)}/post.json').exists()) {
            offline[entry.id] = entry;
          }
        }
      } catch (_) {
        syncError = 'restore';
      }
    }
    // Recover a committed entry after an interruption between directory and index writes.
    final downloads = Directory('${root.path}/downloads');
    if (await downloads.exists()) {
      await for (final entity in downloads.list()) {
        if (entity is! Directory) continue;
        if (entity.path.endsWith('.tmp')) {
          await entity.delete(recursive: true);
          continue;
        }
        Directory recovered = entity;
        if (entity.path.endsWith('.old')) {
          final target = Directory(
            entity.path.substring(0, entity.path.length - 4),
          );
          if (await target.exists()) {
            await entity.delete(recursive: true);
            continue;
          }
          recovered = await entity.rename(target.path);
        }
        try {
          final j = jsonDecode(
            await File('${recovered.path}/entry.json').readAsString(),
          );
          final entry = OfflineEntry.fromJson(j);
          offline[entry.id] = entry;
          articles.putIfAbsent(
            entry.id,
            () => Article.fromJson(
              jsonDecode(
                File('${recovered.path}/post.json').readAsStringSync(),
              ),
            ),
          );
        } catch (_) {
          /* Incomplete folders never count as usable downloads. */
        }
      }
    }
    await cleanExpired();
    notifyListeners();
  }

  Future<void> persist() {
    final snapshot = jsonEncode({
      'preferences': preferences.toJson(),
      'articles': articles.values
          .map((a) => a.toJson(withContent: false))
          .toList(),
      'videos': videos.values.map((v) => v.toJson()).toList(),
      'latest': latest,
      'videoOrder': videoOrder,
      'savedArticles': savedArticles.toList(),
      'savedVideos': savedVideos.toList(),
      'protected': protected.toList(),
      'reading': readingSeconds.map((k, v) => MapEntry('$k', v)),
      'offline': offline.values.map((e) => e.toJson()).toList(),
      'lastSync': lastSync?.toIso8601String(),
      'pendingDownloads': {..._queue, ?_activeDownload}.toList(),
    });
    _writes = _writes.catchError((_) {}).then((_) async {
      final temp = File('${root.path}/state.tmp');
      await temp.writeAsString(snapshot, flush: true);
      await temp.rename('${root.path}/state.json');
    });
    return _writes;
  }

  Future<void> changePreferences(void Function(Preferences) change) async {
    final wasAutomatic = preferences.autoDownload;
    final oldLimit = preferences.limitMB;
    change(preferences);
    notifyListeners();
    await persist();
    if (oldLimit != preferences.limitMB) await cleanExpired();
    if (preferences.autoDownload && !wasAutomatic) {
      queueDownloads(latest);
    }
  }

  Future<void> sync() async {
    if (syncing) return;
    syncing = true;
    syncError = null;
    videoError = null;
    notifyListeners();
    try {
      await cleanExpired();
      final first = await service.articles();
      for (final a in first.posts) {
        articles[a.id] = a;
      }
      latest
        ..clear()
        ..addAll(first.posts.map((a) => a.id));
      totalPosts = first.total;
      currentPage = 1;
      final fresh = <int>[if (lastSync == null) ...latest];
      // Catch up every newly published article, including multiple posts per day.
      if (lastSync != null) {
        var page = 1;
        while (true) {
          final result = await service.articles(page: page, after: lastSync);
          for (final a in result.posts) {
            articles[a.id] = a;
            fresh.add(a.id);
          }
          if (result.posts.isEmpty || page * 20 >= result.total) break;
          page++;
        }
      }
      // Use latest server publication time, avoiding clock skew/skipping during pagination.
      if (first.posts.isNotEmpty) {
        lastSync = first.posts
            .map((a) => a.published)
            .reduce((a, b) => a.isAfter(b) ? a : b)
            .subtract(const Duration(seconds: 1));
      }
      await persist();
      notifyListeners();
      if (preferences.autoDownload) queueDownloads(fresh);
    } catch (_) {
      syncError = 'network';
    }
    try {
      final freshVideos = await service.videos();
      for (final v in freshVideos) {
        videos[v.id] = v;
      }
      videoOrder
        ..clear()
        ..addAll(freshVideos.map((v) => v.id));
    } catch (_) {
      videoError = 'videosUnavailable';
    }
    syncing = false;
    await persist();
    notifyListeners();
    // Verify cached items, including protected ones, without interpreting feed absence as deletion.
    unawaited(reconcileDownloads());
  }

  Future<void> loadMore() async {
    if (syncing || latest.length >= totalPosts) return;
    syncing = true;
    notifyListeners();
    try {
      final result = await service.articles(page: currentPage + 1);
      for (final a in result.posts) {
        articles[a.id] = a;
        if (!latest.contains(a.id)) latest.add(a.id);
      }
      currentPage++;
      totalPosts = result.total;
      syncError = null;
      await persist();
    } catch (_) {
      syncError = 'network';
    }
    syncing = false;
    notifyListeners();
  }

  Future<List<Article>> search(String query, {int page = 1}) async {
    final result = await service.articles(search: query, page: page);
    for (final a in result.posts) {
      articles[a.id] = a;
    }
    await persist();
    return result.posts;
  }

  Future<Article> openArticle(int id) async {
    final cached = File('${folder(id)}/post.json');
    if (offline.containsKey(id) && await cached.exists()) {
      return Article.fromJson(jsonDecode(await cached.readAsString()));
    }
    if (articles[id]?.content.isNotEmpty == true) return articles[id]!;
    try {
      final a = await service.article(id);
      articles[id] = a;
      return a;
    } on DeletedPost {
      await removeDeleted(id);
      rethrow;
    }
  }

  void queueDownloads(Iterable<int> ids) {
    final ordered = ids.toSet().toList()
      ..sort(
        (a, b) => (articles[a]?.published ?? DateTime(2000)).compareTo(
          articles[b]?.published ?? DateTime(2000),
        ),
      );
    for (final id in ordered) {
      final a = articles[id];
      final e = offline[id];
      if (a != null &&
          (e == null || e.modified != a.modified || e.failed.isNotEmpty) &&
          !_queue.contains(id)) {
        _queue.add(id);
      }
    }
    unawaited(persist());
    unawaited(_runQueue());
  }

  Future<void> _runQueue() async {
    if (_autoRunning) return;
    _autoRunning = true;
    try {
      while (_queue.isNotEmpty && preferences.autoDownload) {
        if (downloading) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        final id = _queue.removeAt(0);
        final existing = offline[id];
        if (existing != null &&
            existing.modified == articles[id]?.modified &&
            existing.failed.isEmpty) {
          continue;
        }
        await download(id);
        if (downloadError == 'storage' || downloadError == 'network') {
          _queue.insert(0, id);
          await persist();
          break;
        }
      }
    } finally {
      _autoRunning = false;
    }
  }

  Future<void> download(int id) async {
    if (downloading) return;
    downloading = true;
    _activeDownload = id;
    downloadError = null;
    downloadTitle = articles[id]?.title ?? '';
    notifyListeners();
    final staging = Directory('${folder(id)}.tmp');
    try {
      final a = articles[id]?.content.isNotEmpty == true
          ? articles[id]!
          : await service.article(id);
      articles[id] = a;
      final budget = preferences.limitMB * 1048576;
      if (evictionPlan(
            offline.values,
            protected,
            budget,
            utf8.encode(a.content).length,
            replacing: id,
          ) ==
          null) {
        throw ContentFailure('storage');
      }
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      final fragment = html.parseFragment(a.content);
      final urls = <String>{...a.materials};
      for (final image in fragment.querySelectorAll('img')) {
        final raw = image.attributes['src'];
        if (raw != null) {
          final u = Uri.parse(a.url).resolve(raw);
          urls.add('$u');
        }
      }
      if (a.image.isNotEmpty) urls.add(a.image);
      final files = <String, String>{};
      final failed = <String>[];
      var bytes = 0;
      for (final url in urls) {
        final uri = Uri.tryParse(url);
        if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
          failed.add(url);
          continue;
        }
        final extension = uri.path.split('.').last.toLowerCase();
        final safeExtension = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(extension)
            ? extension
            : 'bin';
        final name = 'asset_${files.length}.$safeExtension';
        final file = File('${staging.path}/$name');
        IOSink? sink;
        try {
          final response = await service.client
              .send(http.Request('GET', uri))
              .timeout(const Duration(seconds: 25));
          final type = response.headers['content-type'] ?? '';
          if (response.statusCode != 200 ||
              type.startsWith('video/') ||
              type.contains('text/html')) {
            throw ContentFailure('asset');
          }
          // Per-file and total staging bounds prevent oversized remote attachments exhausting storage.
          final maximum = (budget - bytes).clamp(0, 100 * 1048576);
          if ((response.contentLength ?? 0) > maximum) {
            throw ContentFailure('asset');
          }
          sink = file.openWrite();
          var size = 0;
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 25),
          )) {
            size += chunk.length;
            if (size > maximum) throw ContentFailure('asset');
            sink.add(chunk);
          }
          await sink.flush();
          await sink.close();
          sink = null;
          files[url] = name;
          bytes += size;
        } catch (_) {
          if (sink != null) {
            await sink.close();
          }
          if (await file.exists()) await file.delete();
          failed.add(url);
        }
      }
      final encoded = jsonEncode(a.toJson());
      await File('${staging.path}/post.json').writeAsString(encoded);
      bytes += utf8.encode(encoded).length;
      // Preserve initial download age during silent edits; don't reset the retention clock.
      var entry = OfflineEntry(
        id: id,
        bytes: bytes,
        downloaded: offline[id]?.downloaded ?? DateTime.now().toUtc(),
        modified: a.modified,
        files: files,
        failed: failed,
      );
      bytes += utf8.encode(jsonEncode(entry.toJson())).length + 32;
      entry = OfflineEntry(
        id: id,
        bytes: bytes,
        downloaded: entry.downloaded,
        modified: entry.modified,
        files: files,
        failed: failed,
      );
      final remove = evictionPlan(
        offline.values,
        protected,
        budget,
        bytes,
        replacing: id,
      );
      if (remove == null) throw ContentFailure('storage');
      for (final victim in remove) {
        await removeDownload(victim);
      }
      await File('${staging.path}/entry.json')
          .writeAsString(jsonEncode(entry.toJson()), flush: true);
      final target = Directory(folder(id));
      final old = Directory('${folder(id)}.old');
      if (await old.exists()) await old.delete(recursive: true);
      if (await target.exists()) await target.rename(old.path);
      await staging.rename(target.path);
      offline[id] = entry;
      await persist();
      if (await old.exists()) await old.delete(recursive: true);
      if (failed.isNotEmpty) downloadError = 'partial';
    } on DeletedPost {
      await removeDeleted(id);
      downloadError = 'deleted';
    } catch (e) {
      downloadError = e is ContentFailure && e.code == 'storage'
          ? 'storage'
          : 'network';
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
      downloading = false;
      _activeDownload = null;
      downloadTitle = '';
      await persist();
      notifyListeners();
    }
  }

  String htmlFor(Article article) {
    final fragment = html.parseFragment(article.content);
    for (final element in fragment.querySelectorAll(
      'script,iframe,video,audio,form,style',
    )) {
      element.remove();
    }
    final e = offline[article.id];
    if (e != null) {
      for (final img in fragment.querySelectorAll('img')) {
        final raw = img.attributes['src'] ?? '';
        final source = Uri.parse(article.url).resolve(raw).toString();
        final local = e.files[source];
        img.attributes.remove('srcset');
        img.attributes.remove('sizes');
        // Offline readers never silently fetch missing images over the network.
        img.attributes['src'] = local == null
            ? 'file:///missing-offline-image'
            : Uri.file('${folder(article.id)}/$local').toString();
      }
    }
    return fragment.outerHtml;
  }

  String? materialPath(int id, String url) {
    final file = offline[id]?.files[url];
    return file == null ? null : '${folder(id)}/$file';
  }

  Future<void> removeDownload(int id) async {
    final dir = Directory(folder(id));
    if (await dir.exists()) await dir.delete(recursive: true);
    offline.remove(id);
    protected.remove(id);
    await persist();
    notifyListeners();
  }

  Future<void> removeDeleted(int id) async {
    await removeDownload(id);
    savedArticles.remove(id);
    readingSeconds.remove(id);
    articles.remove(id);
    latest.remove(id);
    _queue.remove(id);
    await persist();
    notifyListeners();
  }

  Future<void> cleanExpired({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now().toUtc()).subtract(
      const Duration(days: 60),
    );
    final expired = offline.values
        .where(
          (e) => e.downloaded.isBefore(cutoff) && !protected.contains(e.id),
        )
        .map((e) => e.id)
        .toList();
    for (final id in expired) {
      await removeDownload(id);
    }
    final removals = evictionPlan(
      offline.values,
      protected,
      preferences.limitMB * 1048576,
      0,
    );
    if (removals == null) {
      downloadError = 'storage';
    } else {
      for (final id in removals) {
        await removeDownload(id);
      }
    }
  }

  Future<void> reconcileDownloads() async {
    for (final id in offline.keys.toList()) {
      try {
        final a = await service.article(id);
        articles[id] = a;
        if (offline[id]?.modified != a.modified ||
            offline[id]?.failed.isNotEmpty == true) {
          while (downloading) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          if (offline.containsKey(id)) await download(id);
        }
      } on DeletedPost {
        await removeDeleted(id);
      } catch (_) {
        break;
      } // network errors never cause removal; retry at the next sync.
    }
    await persist();
    notifyListeners();
  }

  Future<void> bookmarkArticle(int id) async {
    savedArticles.contains(id)
        ? savedArticles.remove(id)
        : savedArticles.add(id);
    await persist();
    notifyListeners();
  }

  Future<void> bookmarkVideo(String id) async {
    savedVideos.contains(id) ? savedVideos.remove(id) : savedVideos.add(id);
    await persist();
    notifyListeners();
  }

  Future<void> protect(int id) async {
    protected.contains(id) ? protected.remove(id) : protected.add(id);
    await persist();
    notifyListeners();
  }

  Future<void> addReading(int id, int seconds) async {
    readingSeconds[id] = ((readingSeconds[id] ?? 0) + seconds).clamp(0, 60);
    await persist();
    notifyListeners();
  }

  Future<void> markUnread(int id) async {
    readingSeconds[id] = 0;
    await persist();
    notifyListeners();
  }
}
