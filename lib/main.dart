import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:m3u8_down/app/services/download_manager.dart';
import 'package:m3u8_down/app/services/merger_service.dart';
import 'package:m3u8_down/app/services/settings_service.dart';
import 'package:m3u8_down/app/ui/download_page.dart';
import 'package:m3u8_down/app/ui/settings_page.dart';
import 'package:m3u8_down/app/ui/merge_page.dart';
import 'package:m3u8_down/app/models/download_task.dart';
import 'package:m3u8_down/app/models/merge_job.dart';
import 'package:m3u8_down/app/models/settings.dart';
import 'package:m3u8_down/app/models/download_status_adapter.dart';
import 'package:m3u8_down/app/models/merge_status_adapter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 Hive
  await Hive.initFlutter();
  Hive.registerAdapter(DownloadTaskAdapter());
  Hive.registerAdapter(MergeJobAdapter());
  Hive.registerAdapter(AppSettingsAdapter());
  Hive.registerAdapter(DownloadStatusAdapter());
  Hive.registerAdapter(MergeStatusAdapter());

  // 初始化全局 service 实例
  final settingsService = SettingsService();
  await settingsService.init();

  final mergeService = MergeService();
  await mergeService.init();

  final downloadManager = DownloadManager(settingsService);
  downloadManager.setMergeService(mergeService);
  await downloadManager.init();

  runApp(M3u8App(
    settingsService: settingsService,
    downloadManager: downloadManager,
    mergeService: mergeService,
  ));
}

class M3u8App extends StatelessWidget {
  final SettingsService settingsService;
  final DownloadManager downloadManager;
  final MergeService mergeService;
  
  const M3u8App({super.key, required this.settingsService, required this.downloadManager, required this.mergeService});

  @override
  Widget build(BuildContext context) {
    // 使用内置 NotoSansSC.otf 作为主中文字体（从模拟器 TTC 提取）
    const chineseFontFallback = [
      'Noto Sans SC',
      'sans-serif',
    ];

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: downloadManager),
        ChangeNotifierProvider.value(value: mergeService),
        ChangeNotifierProvider.value(value: settingsService),
      ],
      child: MaterialApp(
        title: 'M3U8Down',
        debugShowCheckedModeBanner: false,
        // 使用 builder 包装整个 App，通过 DefaultTextStyle 强制应用中文字体回退
        // 这比仅设置 theme.textTheme 更可靠，能覆盖 NavigationBar 等不直接使用 textTheme 的组件
        builder: (context, child) {
          return DefaultTextStyle(
            style: const TextStyle(
              fontFamilyFallback: chineseFontFallback,
            ),
            child: child!,
          );
        },
        theme: ThemeData.light().copyWith(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF4F6FA),
          primaryColor: const Color(0xFF2563EB),
          colorScheme: ColorScheme.light(
            primary: const Color(0xFF2563EB),
            secondary: const Color(0xFF60A5FA),
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Color(0xFF2563EB),
            foregroundColor: Colors.white,
          ),
          // 主字体使用内置 NotoSansSC.otf，fallback 覆盖未包含的字符
          textTheme: const TextTheme(
            displayLarge: TextStyle(fontSize: 57, fontFamily: 'Noto Sans SC'),
            displayMedium: TextStyle(fontSize: 45, fontFamily: 'Noto Sans SC'),
            displaySmall: TextStyle(fontSize: 36, fontFamily: 'Noto Sans SC'),
            headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w500, fontFamily: 'Noto Sans SC'),
            headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w500, fontFamily: 'Noto Sans SC'),
            headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, fontFamily: 'Noto Sans SC'),
            titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, fontFamily: 'Noto Sans SC'),
            titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, fontFamily: 'Noto Sans SC'),
            titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, fontFamily: 'Noto Sans SC'),
            bodyLarge: TextStyle(fontSize: 16, fontFamily: 'Noto Sans SC'),
            bodyMedium: TextStyle(fontSize: 14, fontFamily: 'Noto Sans SC'),
            bodySmall: TextStyle(fontSize: 12, fontFamily: 'Noto Sans SC'),
            labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, fontFamily: 'Noto Sans SC'),
            labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Noto Sans SC'),
            labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, fontFamily: 'Noto Sans SC'),
          ).apply(
            fontFamilyFallback: ['sans-serif'],
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF2563EB),
            foregroundColor: Colors.white,
            titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          iconTheme: const IconThemeData(color: Colors.black87),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          // 为 NavigationBar 单独设置 labelTextStyle，确保底部导航栏中文正常
          navigationBarTheme: NavigationBarThemeData(
            labelTextStyle: WidgetStateProperty.all(
              const TextStyle(
                fontSize: 12,
                fontFamilyFallback: chineseFontFallback,
              ),
            ),
          ),
        ),
        home: const MainNavigation(),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  
  // 用 IndexedStack 保持页面存活，切换 Tab 不会销毁重建
  static final List<Widget> _pages = [
    DownloadPage(),
    MergePage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: _pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: '下载',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: '合并',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}