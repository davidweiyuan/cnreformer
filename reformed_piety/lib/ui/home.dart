import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_store.dart';
import '../core/models.dart';
import '../main.dart';
import 'readers.dart';
import 'settings.dart';

class HomeScreen extends StatefulWidget {
  final AppStore store;
  const HomeScreen({super.key, required this.store});
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> with WidgetsBindingObserver {
  int tab = 0;
  String query = '';
  List<Article>? searchResults;
  bool searching = false;
  String? searchError;
  int searchGeneration = 0, searchPage = 1;
  DateTime? lastForegroundSync;
  bool moreSearch = false;
  final searchController = TextEditingController();
  AppStore get s => widget.store;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!s.preferences.welcomed) {
        await welcome();
      }
      if (mounted) {
        lastForegroundSync = DateTime.now();
        unawaited(s.sync());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(s.cleanExpired());
      if (s.preferences.welcomed &&
          (lastForegroundSync == null ||
              DateTime.now().difference(lastForegroundSync!) >
                  const Duration(minutes: 10))) {
        lastForegroundSync = DateTime.now();
        unawaited(s.sync());
      }
    }
  }

  Future<void> welcome() async {
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/branding/icon.png',
                  width: 92,
                  height: 92,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Reformed Piety',
                style: Theme.of(ctx).textTheme.headlineSmall,
              ),
              Text(
                s.tr('歸正靈命塑造', '归正灵命塑造'),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text(
                s.tr('在每日閱讀中，扎根真理，活出信仰。', '在每日阅读中，扎根真理，活出信仰。'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                s.tr(
                  '預設儲存最新 20 篇文章、圖片及講道資料，Wi-Fi 或行動網路均可下載。你可在設定中改為手動下載。',
                  '默认保存最新 20 篇文章、图片及讲道资料，Wi-Fi 或移动网络均可下载。你可在设置中改为手动下载。',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                s.tr(
                  '本次測試先專注閱讀；通知將在下一個測試版本加入。無需註冊帳戶。',
                  '本次测试先专注阅读；通知将在下一个测试版本加入。无需注册账户。',
                ),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () async {
                  await s.changePreferences((p) => p.welcomed = true);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(s.tr('先開始閱讀', '先开始阅读')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> search({bool more = false}) async {
    final q = searchController.text.trim();
    final generation = ++searchGeneration;
    setState(() {
      query = q;
      searching = true;
      searchError = null;
      if (!more) {
        searchResults = null;
        searchPage = 1;
      }
    });
    if (q.isEmpty || tab != 0) {
      setState(() {
        searching = false;
        searchResults = null;
      });
      return;
    }
    try {
      final result = await s.search(q, page: more ? searchPage + 1 : 1);
      if (!mounted || generation != searchGeneration) return;
      setState(() {
        searchResults = more ? [...?searchResults, ...result] : result;
        if (more) searchPage++;
        moreSearch = result.length == 20;
      });
    } catch (_) {
      if (!mounted || generation != searchGeneration) return;
      setState(() {
        searchError = s.tr('無法搜尋網路內容，顯示裝置上的結果。', '无法搜索网络内容，显示设备上的结果。');
        searchResults = s.articles.values
            .where(
              (a) => '${a.title} ${a.excerpt}'.toLowerCase().contains(
                q.toLowerCase(),
              ),
            )
            .toList();
        moreSearch = false;
      });
    }
    if (mounted && generation == searchGeneration) {
      setState(() => searching = false);
    }
  }

  void selectTab(int value) {
    setState(() {
      tab = value;
      query = '';
      searchController.clear();
      searchResults = null;
      searchGeneration++;
      searching = false;
      searchError = null;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s,
    builder: (context, _) {
      final labels = [
        s.tr('靈修文章', '灵修文章'),
        s.tr('講道影片', '讲道视频'),
        s.tr('已收藏', '已收藏'),
        s.tr('設定', '设置'),
      ];
      final icons = [
        Icons.auto_stories_outlined,
        Icons.play_circle_outline,
        Icons.bookmark_border,
        Icons.tune,
      ];
      final wide = MediaQuery.sizeOf(context).width >= 800;
      final body = tab == 3
          ? SettingsScreen(store: s)
          : Column(
              children: [
                if (tab != 2)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: TextField(
                      controller: searchController,
                      onSubmitted: (_) => search(),
                      onChanged: (value) {
                        if (tab == 1) {
                          setState(() => query = value);
                        } else if (value.isEmpty) {
                          search();
                        }
                      },
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: tab == 0
                            ? s.tr('搜尋文章，按送出', '搜索文章，按发送')
                            : s.tr('搜尋已載入的影片標題', '搜索已加载的视频标题'),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  searchController.clear();
                                  search();
                                },
                                icon: const Icon(Icons.close),
                              )
                            : null,
                      ),
                    ),
                  ),
                if (s.syncing || searching)
                  const LinearProgressIndicator(minHeight: 2),
                if (s.downloading)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${s.tr('儲存離線文章', '保存离线文章')} · ${s.downloadTitle}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (s.downloadError == 'storage')
                  notice(
                    s.tr(
                      '儲存空間已滿。請取消永久保留、移除下載或提高容量。',
                      '存储空间已满。请取消永久保留、移除下载或提高容量。',
                    ),
                    action: () => selectTab(3),
                  ),
                if (searchError != null) notice(searchError!),
                if (tab == 0 && s.syncError != null)
                  notice(
                    s.tr('目前無法連線。已下載的文章仍可閱讀。', '目前无法连接。已下载的文章仍可阅读。'),
                    action: s.sync,
                  ),
                if (tab == 1 && s.videoError != null)
                  notice(
                    s.tr('暫時無法更新影片。請重試或開啟頻道。', '暂时无法更新视频。请重试或打开频道。'),
                    action: s.sync,
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: s.sync,
                    child: tab == 0
                        ? posts()
                        : tab == 1
                        ? videosList()
                        : saved(),
                  ),
                ),
              ],
            );
      return Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tab == 0 ? s.tr('歸正靈命塑造', '归正灵命塑造') : labels[tab]),
              Text(
                'REFORMED PIETY',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(letterSpacing: 2, color: gold),
              ),
            ],
          ),
          actions: [
            if (tab < 2)
              IconButton(
                tooltip: s.tr('重新整理', '刷新'),
                onPressed: s.syncing ? null : s.sync,
                icon: const Icon(Icons.refresh),
              ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          top: false,
          child: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: tab,
                      onDestinationSelected: selectTab,
                      labelType: NavigationRailLabelType.all,
                      destinations: List.generate(
                        4,
                        (i) => NavigationRailDestination(
                          icon: Icon(icons[i]),
                          label: Text(labels[i]),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1040),
                          child: body,
                        ),
                      ),
                    ),
                  ],
                )
              : body,
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: selectTab,
                destinations: List.generate(
                  4,
                  (i) => NavigationDestination(
                    icon: Icon(icons[i]),
                    label: labels[i],
                  ),
                ),
              ),
      );
    },
  );
  Widget notice(String message, {VoidCallback? action}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodySmall),
        ),
        if (action != null)
          IconButton(onPressed: action, icon: const Icon(Icons.arrow_forward)),
      ],
    ),
  );
  Widget posts() {
    final items = query.isEmpty
        ? s.latest.map((id) => s.articles[id]).whereType<Article>().toList()
        : searchResults ?? [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (query.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Text(
              s.tr('最新靈修 · 與主同行', '最新灵修 · 与主同行'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        if (items.isEmpty && !s.syncing && !searching)
          empty(
            s.tr('尚無文章', '暂无文章'),
            s.tr('下拉重新整理，或搜尋其他關鍵字。', '下拉刷新，或搜索其他关键词。'),
          ),
        for (var i = 0; i < items.length; i++)
          articleCard(items[i], featured: i == 0 && query.isEmpty),
        if (query.isEmpty && s.latest.length < s.totalPosts)
          TextButton(
            onPressed: s.syncing ? null : s.loadMore,
            child: Text(s.tr('載入較舊文章', '加载较旧文章')),
          ),
        if (query.isNotEmpty && moreSearch)
          TextButton(
            onPressed: searching ? null : () => search(more: true),
            child: Text(s.tr('更多搜尋結果', '更多搜索结果')),
          ),
      ],
    );
  }

  Widget articleCard(Article a, {bool featured = false}) {
    final downloaded = s.offline[a.id];
    final read = (s.readingSeconds[a.id] ?? 0) >= 60;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ArticleReader(store: s, id: a.id),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(featured ? 24 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${a.published.year}.${a.published.month.toString().padLeft(2, '0')}.${a.published.day.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: gold),
                  ),
                  const Spacer(),
                  if (read)
                    Text(
                      s.tr('已讀', '已读'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (downloaded != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        downloaded.failed.isEmpty
                            ? Icons.offline_pin_outlined
                            : Icons.cloud_download_outlined,
                        size: 18,
                      ),
                    ),
                  if (s.protected.contains(a.id))
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.push_pin, size: 16),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                a.title,
                style: featured
                    ? Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(height: 1.45, fontWeight: FontWeight.w600)
                    : Theme.of(context).textTheme.titleLarge
                          ?.copyWith(height: 1.4),
              ),
              if (a.excerpt.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  a.excerpt,
                  maxLines: featured ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.7,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              Row(
                children: [
                  Text(
                    s.tr('閱讀文章', '阅读文章'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.arrow_forward, size: 16),
                  const Spacer(),
                  IconButton(
                    tooltip: s.tr('收藏文章', '收藏文章'),
                    onPressed: () => s.bookmarkArticle(a.id),
                    icon: Icon(
                      s.savedArticles.contains(a.id)
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget videosList() {
    final items = s.videoOrder
        .map((id) => s.videos[id])
        .whereType<Video>()
        .where((v) => v.title.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.tr('頻道最新上傳 · 線上播放', '频道最新上传 · 在线播放'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(channelUrl)),
                child: Text(s.tr('完整頻道', '完整频道')),
              ),
            ],
          ),
        ),
        if (items.isEmpty && !s.syncing)
          empty(s.tr('尚無影片', '暂无视频'), s.tr('下拉更新，或前往頻道觀看。', '下拉更新，或前往频道观看。')),
        for (final v in items) videoCard(v),
      ],
    );
  }

  Widget videoCard(Video v) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoReader(store: s, video: v),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  v.thumbnail,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(color: navy),
                ),
                const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    color: Colors.black87,
                    child: Text(
                      v.duration,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    v.title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(height: 1.5),
                  ),
                ),
                IconButton(
                  tooltip: s.tr('收藏影片', '收藏视频'),
                  onPressed: () => s.bookmarkVideo(v.id),
                  icon: Icon(
                    s.savedVideos.contains(v.id)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget saved() => ListView(
    padding: const EdgeInsets.all(20),
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      Text(
        s.tr('收藏的文章', '收藏的文章'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      if (s.savedArticles.isEmpty)
        Text(s.tr('點選書籤，將想再讀的文章放在這裡。', '点击书签，将想再读的文章放在这里。')),
      for (final id in s.savedArticles)
        if (s.articles[id] != null) articleCard(s.articles[id]!),
      const SizedBox(height: 24),
      Text(s.tr('離線文章', '离线文章'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      if (s.offline.isEmpty) Text(s.tr('尚未下載。閱讀文章時可選擇下載。', '尚未下载。阅读文章时可选择下载。')),
      for (final id in s.offline.keys)
        if (s.articles[id] != null) articleCard(s.articles[id]!),
      const SizedBox(height: 24),
      Text(
        s.tr('收藏的影片', '收藏的视频'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      for (final id in s.savedVideos)
        if (s.videos[id] != null) videoCard(s.videos[id]!),
    ],
  );
  Widget empty(String title, String message) => Padding(
    padding: const EdgeInsets.all(40),
    child: Column(
      children: [
        const Icon(Icons.auto_stories_outlined, size: 48, color: gold),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}
