import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_store.dart';
import '../main.dart';

class SettingsScreen extends StatelessWidget {
  final AppStore store;
  const SettingsScreen({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    final s = store;
    final p = s.preferences;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/branding/icon.png',
                    width: 72,
                    height: 72,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reformed Piety',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(s.tr('歸正靈命塑造', '归正灵命塑造')),
                      const SizedBox(height: 8),
                      Text(
                        s.tr('測試版本 0.1.0', '测试版本 0.1.0'),
                        style: const TextStyle(color: gold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        section(context, s.tr('閱讀偏好', '阅读偏好')),
        DropdownButtonFormField<bool>(
          initialValue: p.simplified,
          decoration: InputDecoration(labelText: s.tr('介面語言', '界面语言')),
          items: const [
            DropdownMenuItem(value: false, child: Text('繁體中文')),
            DropdownMenuItem(value: true, child: Text('简体中文')),
          ],
          onChanged: (v) => s.changePreferences((p) => p.simplified = v!),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: p.theme,
          decoration: InputDecoration(labelText: s.tr('外觀', '外观')),
          items: [
            DropdownMenuItem(
              value: 'system',
              child: Text(s.tr('跟隨系統', '跟随系统')),
            ),
            DropdownMenuItem(value: 'light', child: Text(s.tr('淺色', '浅色'))),
            DropdownMenuItem(value: 'dark', child: Text(s.tr('深色', '深色'))),
          ],
          onChanged: (v) => s.changePreferences((p) => p.theme = v!),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s.tr('文章字體大小', '文章字体大小')),
          trailing: Text('${p.fontSize.round()}'),
        ),
        Slider(
          value: p.fontSize,
          min: 15,
          max: 30,
          divisions: 15,
          onChanged: (v) => s.changePreferences((p) => p.fontSize = v),
        ),
        Text(
          s.tr('文章保留作者原文，不轉換繁簡。', '文章保留作者原文，不转换繁简。'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        section(context, s.tr('離線閱讀', '离线阅读')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s.tr('自動下載新文章', '自动下载新文章')),
          subtitle: Text(
            s.tr(
              '包含圖片及資料；Wi-Fi 或行動網路均可。影片僅線上播放。',
              '包含图片及资料；Wi-Fi 或移动网络均可。视频仅在线播放。',
            ),
          ),
          value: p.autoDownload,
          onChanged: (v) => s.changePreferences((p) => p.autoDownload = v),
        ),
        const SizedBox(height: 14),
        Text('${s.tr('使用容量', '使用容量')}  ${s.storageText}'),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: (s.usedBytes / (p.limitMB * 1048576)).clamp(0, 1),
          minHeight: 6,
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<int>(
          initialValue: p.limitMB,
          decoration: InputDecoration(labelText: s.tr('離線儲存上限', '离线存储上限')),
          items: [
            for (final mb in [50, 100, 250, 500, 1000, 2000, 5000])
              DropdownMenuItem(value: mb, child: Text('$mb MB')),
          ],
          onChanged: (v) => s.changePreferences((p) => p.limitMB = v!),
        ),
        const SizedBox(height: 14),
        Text(
          s.tr(
            '下載保留 60 天。容量不足時，最舊的非保護內容會先移除。「永久保留」可避免自動清理；若保護內容佔滿容量，下載將暫停。',
            '下载保留 60 天。容量不足时，最旧的非保护内容会先移除。「永久保留」可避免自动清理；若保护内容占满容量，下载将暂停。',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: s.downloading
              ? null
              : () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(s.tr('清除非保護的下載？', '清除非保护的下载？')),
                      content: Text(s.tr('書籤與閱讀進度將保留。', '书签与阅读进度将保留。')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(s.tr('取消', '取消')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(s.tr('清除', '清除')),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    for (final id
                        in s.offline.keys
                            .where((id) => !s.protected.contains(id))
                            .toList()) {
                      await s.removeDownload(id);
                    }
                  }
                },
          icon: const Icon(Icons.cleaning_services_outlined),
          label: Text(s.tr('清除非保護下載', '清除非保护下载')),
        ),
        section(context, s.tr('通知', '通知')),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.notifications_none),
          title: Text(s.tr('下一個測試版本提供', '下一个测试版本提供')),
          subtitle: Text(
            s.tr(
              '本版本不要求通知權限。稍後可選擇每日摘要時間與安靜時段。',
              '本版本不要求通知权限。稍后可选择每日摘要时间与安静时段。',
            ),
          ),
        ),
        section(context, s.tr('關於與隱私', '关于与隐私')),
        Text(
          s.tr(
            '這是 David Wei Yuan 提供給弟兄姊妹的個人靈修事工，並非教會官方出版品。',
            '这是 David Wei Yuan 提供给弟兄姊妹的个人灵修事工，并非教会官方出版物。',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          s.tr(
            '無需帳戶。收藏、下載、閱讀進度與偏好只保存在此裝置；移除 App 後即失去這些資料。沒有新增分析追蹤服務。WordPress、YouTube 與外部連結仍依其服務政策處理連線資料。',
            '无需账户。收藏、下载、阅读进度与偏好只保存在此设备；删除 App 后即失去这些数据。没有新增分析跟踪服务。WordPress、YouTube 与外部链接仍依其服务政策处理连接数据。',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton(
          onPressed: () =>
              launchUrl(Uri.parse('https://davidweiyuan.wordpress.com/')),
          child: const Text('davidweiyuan.wordpress.com'),
        ),
        const SizedBox(height: 24),
        Text(
          'Sola Scriptura · Sola Fide · Sola Gratia\nSolus Christus · Soli Deo Gloria',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: gold),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 16),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
}
