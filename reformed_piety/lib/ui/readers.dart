import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../core/app_store.dart';
import '../core/models.dart';
import '../core/content_service.dart';
import '../core/reading_clock.dart';
import '../main.dart';

Future<void> shareLink(BuildContext context, String url) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      text: url,
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

class ArticleReader extends StatefulWidget {
  final AppStore store;
  final int id;
  const ArticleReader({super.key, required this.store, required this.id});
  @override
  State<ArticleReader> createState() => _ArticleReaderState();
}

class _ArticleReaderState extends State<ArticleReader>
    with WidgetsBindingObserver {
  Article? article;
  bool loading = true, failed = false, deleted = false;
  Timer? timer;
  final watch = Stopwatch()..start();
  late final ReadingClock readingClock = ReadingClock(() => watch.elapsed);
  int pendingSeconds = 0;
  bool foreground = true;
  AppStore get s => widget.store;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      failed = false;
      deleted = false;
    });
    try {
      final a = await s.openArticle(widget.id);
      if (mounted) setState(() => article = a);
    } on DeletedPost {
      if (mounted) setState(() => deleted = true);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
    if (mounted) setState(() => loading = false);
  }

  void tick() {
    final active =
        foreground &&
        !loading &&
        article != null &&
        !failed &&
        ModalRoute.of(context)?.isCurrent == true;
    readingClock.update(active: active);
    pendingSeconds += readingClock.takeSeconds();
    if (pendingSeconds >= 5) flush();
  }

  void flush() {
    if (pendingSeconds > 0) {
      unawaited(s.addReading(widget.id, pendingSeconds));
      pendingSeconds = 0;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      readingClock.update(active: false);
      pendingSeconds += readingClock.takeSeconds();
      flush();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    readingClock.update(active: false);
    pendingSeconds += readingClock.takeSeconds();
    watch.stop();
    flush();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> download() async {
    await s.download(widget.id);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.downloadError == null
                ? s.tr('文章已可離線閱讀', '文章已可离线阅读')
                : s.downloadError == 'storage'
                ? s.tr('儲存空間不足，請先調整設定。', '存储空间不足，请先调整设置。')
                : s.tr('部分內容未能下載，請稍後重試。', '部分内容未能下载，请稍后重试。'),
          ),
        ),
      );
    }
  }

  Future<bool> openLink(String raw) async {
    final a = article;
    if (a == null) return false;
    final url = Uri.parse(a.url).resolve(raw);
    if (!['https', 'http', 'mailto'].contains(url.scheme)) return false;
    final local = s.materialPath(a.id, url.toString());
    if (local != null && await File(local).exists()) {
      final result = await OpenFilex.open(local);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.tr('無法預覽此檔案，可開啟原始連結。', '无法预览此文件，可打开原始链接。'))),
        );
      }
      return true;
    }
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s,
    builder: (context, _) {
      final a = article;
      final entry = s.offline[widget.id];
      final read = (s.readingSeconds[widget.id] ?? 0) >= 60;
      return Scaffold(
        appBar: AppBar(
          title: Text(s.tr('靈修閱讀', '灵修阅读')),
          actions: [
            IconButton(
              tooltip: s.tr('收藏', '收藏'),
              onPressed: () => s.bookmarkArticle(widget.id),
              icon: Icon(
                s.savedArticles.contains(widget.id)
                    ? Icons.bookmark
                    : Icons.bookmark_border,
              ),
            ),
            if (a != null)
              IconButton(
                tooltip: s.tr('分享', '分享'),
                onPressed: () => shareLink(context, a.url),
                icon: const Icon(Icons.ios_share),
              ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'download') await download();
                if (value == 'protect') await s.protect(widget.id);
                if (value == 'remove') await s.removeDownload(widget.id);
                if (value == 'unread') {
                  pendingSeconds = 0;
                  readingClock.reset();
                  await s.markUnread(widget.id);
                }
                if (value == 'original' && a != null) {
                  await launchUrl(Uri.parse(a.url));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'download',
                  enabled: !s.downloading,
                  child: Text(s.tr('下載／更新離線內容', '下载／更新离线内容')),
                ),
                if (entry != null)
                  PopupMenuItem(
                    value: 'protect',
                    child: Text(
                      s.protected.contains(widget.id)
                          ? s.tr('取消永久保留', '取消永久保留')
                          : s.tr('永久保留離線', '永久保留离线'),
                    ),
                  ),
                if (entry != null)
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(s.tr('移除下載', '移除下载')),
                  ),
                if (read)
                  PopupMenuItem(
                    value: 'unread',
                    child: Text(s.tr('標記為未讀', '标记为未读')),
                  ),
                PopupMenuItem(
                  value: 'original',
                  child: Text(s.tr('原始文章', '原始文章')),
                ),
              ],
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : failed || deleted
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        deleted
                            ? s.tr('作者已移除此文章。', '作者已移除此文章。')
                            : s.tr(
                                '無法載入文章。請連線後重試，或開啟已下載的文章。',
                                '无法加载文章。请连接后重试，或打开已下载的文章。',
                              ),
                      ),
                      TextButton(
                        onPressed: load,
                        child: Text(s.tr('重試', '重试')),
                      ),
                    ],
                  ),
                ),
              )
            : a == null
            ? const SizedBox()
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 60),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 740),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${a.published.year}.${a.published.month}.${a.published.day}  ·  朝聖之旅',
                          style: const TextStyle(color: gold),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          a.title,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.5,
                              ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (entry != null)
                              Chip(
                                avatar: Icon(
                                  entry.failed.isEmpty
                                      ? Icons.offline_pin
                                      : Icons.warning_amber,
                                  size: 17,
                                ),
                                label: Text(
                                  entry.failed.isEmpty
                                      ? s.tr('可離線閱讀', '可离线阅读')
                                      : s.tr('部分附件未下載', '部分附件未下载'),
                                ),
                              ),
                            if (s.protected.contains(a.id))
                              Chip(label: Text(s.tr('永久保留', '永久保留'))),
                            if (read) Chip(label: Text(s.tr('已讀', '已读'))),
                          ],
                        ),
                        Row(
                          children: [
                            Text(s.tr('字體大小', '字体大小')),
                            Expanded(
                              child: Slider(
                                value: s.preferences.fontSize,
                                min: 15,
                                max: 30,
                                divisions: 15,
                                label: '${s.preferences.fontSize.round()}',
                                onChanged: (v) =>
                                    s.changePreferences((p) => p.fontSize = v),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 30),
                        HtmlWidget(
                          s.htmlFor(a),
                          textStyle: TextStyle(
                            fontSize: s.preferences.fontSize,
                            height: 1.95,
                          ),
                          onTapUrl: openLink,
                          onErrorBuilder: (context, element, error) => Text(
                            s.tr('圖片未儲存或暫時無法載入', '图片未保存或暂时无法加载'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          customWidgetBuilder: (element) {
                            if (element.localName == 'img') {
                              final src = element.attributes['src'] ?? '';
                              if (src.startsWith('file:')) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Image.file(
                                    File(Uri.parse(src).toFilePath()),
                                    errorBuilder: (_, _, _) =>
                                        Text(s.tr('此圖片尚未下載', '此图片尚未下载')),
                                  ),
                                );
                              }
                            }
                            return null;
                          },
                        ),
                        if (a.materials.isNotEmpty) ...[
                          const Divider(height: 40),
                          Text(
                            s.tr('講道資料', '讲道资料'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          for (final url in a.materials)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.description_outlined),
                              title: Text(
                                Uri.decodeComponent(
                                  Uri.parse(url).pathSegments.last,
                                ),
                              ),
                              subtitle: Text(
                                s.materialPath(a.id, url) != null
                                    ? s.tr('已下載，可離線開啟', '已下载，可离线打开')
                                    : s.tr('線上檔案 · 下載文章以保留', '在线文件 · 下载文章以保留'),
                              ),
                              onTap: () => openLink(url),
                            ),
                        ],
                        const SizedBox(height: 26),
                        TextButton.icon(
                          onPressed: s.downloading ? null : download,
                          icon: const Icon(Icons.download_outlined),
                          label: Text(
                            entry == null
                                ? s.tr('下載文章與資料', '下载文章与资料')
                                : s.tr('重新下載離線內容', '重新下载离线内容'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      );
    },
  );
}

class VideoReader extends StatefulWidget {
  final AppStore store;
  final Video video;
  const VideoReader({super.key, required this.store, required this.video});
  @override
  State<VideoReader> createState() => _VideoReaderState();
}

class _VideoReaderState extends State<VideoReader> with WidgetsBindingObserver {
  late final WebViewController controller;
  bool failed = false;
  bool playerReady = false;
  int playbackState = -1;
  String? playerError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }
    controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'PlayerState',
        onMessageReceived: (message) {
          if (!mounted) return;
          setState(() {
            if (message.message == 'ready') playerReady = true;
            if (message.message.startsWith('state:')) {
              playbackState = int.tryParse(message.message.substring(6)) ?? -1;
            }
            if (message.message.startsWith('error:')) {
              failed = true;
              playerError = message.message.substring(6);
            }
          });
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => failed = true);
            }
          },
          onNavigationRequest: (request) {
            final url = Uri.tryParse(request.url);
            if (url == null) return NavigationDecision.prevent;
            if (url.scheme == 'about' ||
                url.host == 'www.youtube.com' ||
                url.host == 'www.youtube-nocookie.com' ||
                url.host == blogHost) {
              return NavigationDecision.navigate;
            }
            if (request.isMainFrame && url.scheme == 'https') {
              launchUrl(url, mode: LaunchMode.externalApplication);
            }
            return NavigationDecision.prevent;
          },
        ),
      );
    load();
  }

  void load() {
    setState(() {
      failed = false;
      playerReady = false;
      playerError = null;
    });
    controller.loadHtmlString(
      '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="strict-origin-when-cross-origin"><style>html,body,#player,iframe{margin:0;width:100%;height:100%;border:0;background:#000}</style></head><body><div id="player"></div><script>
      var player;
      function onYouTubeIframeAPIReady(){
        player=new YT.Player('player',{videoId:'${widget.video.id}',width:'100%',height:'100%',playerVars:{playsinline:1,origin:'https://$blogHost'},events:{
          onReady:function(){PlayerState.postMessage('ready');},
          onStateChange:function(e){PlayerState.postMessage('state:'+e.data);},
          onError:function(e){PlayerState.postMessage('error:'+e.data);}
        }});
      }
      </script><script src="https://www.youtube.com/iframe_api"></script></body></html>''',
      baseUrl: 'https://$blogHost',
    );
  }

  void pause() {
    unawaited(
      controller
          .runJavaScript(
            'if(window.player && player.pauseVideo) player.pauseVideo();',
          )
          .catchError((_) {}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pause();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final v = widget.video;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(s.tr('影片', '视频')),
          actions: [
            IconButton(
              tooltip: s.tr('收藏', '收藏'),
              onPressed: () => s.bookmarkVideo(v.id),
              icon: Icon(
                s.savedVideos.contains(v.id)
                    ? Icons.bookmark
                    : Icons.bookmark_border,
              ),
            ),
            IconButton(
              tooltip: s.tr('分享', '分享'),
              onPressed: () => shareLink(context, v.url),
              icon: const Icon(Icons.ios_share),
            ),
          ],
        ),
        body: ListView(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: WebViewWidget(controller: controller),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.title,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  Text(s.tr('YouTube · 線上播放，需要網路連線', 'YouTube · 在线播放，需要网络连接')),
                  if (failed) Text(s.tr('播放器暫時無法載入，請重試。', '播放器暂时无法加载，请重试。')),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    children: [
                      OutlinedButton.icon(
                        onPressed: load,
                        icon: const Icon(Icons.refresh),
                        label: Text(s.tr('重新載入', '重新加载')),
                      ),
                      TextButton(
                        onPressed: () => launchUrl(
                          Uri.parse(v.url),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Text(s.tr('在 YouTube 開啟', '在 YouTube 打开')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
