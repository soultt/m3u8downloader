# Flutter M3U8Down

基于 Flutter 的跨平台 M3U8 视频下载与合并工具。

## 功能特性

- 🔽 **多线程分片下载** - 支持配置并发数（1-32），断点续传，实时进度回调
- 📋 **M3U8 解析** - 支持 Master Playlist 自动选择最高码率、相对路径、AES-128/192/256 加密
- 🔐 **TS 解密** - 支持 AES-CBC 解密（通过 FFmpeg 完成）
- 🔄 **FFmpeg 合并** - 重编码规整时间戳，解决 HLS 拼接闪烁/音画不同步问题
- 💾 **任务持久化** - 基于 Hive 本地数据库，应用重启自动恢复
- 📱 **跨平台** - 支持 Windows/macOS/Linux/Android/iOS
- 🎬 **边下边播** - 未合并时快速 remux 生成预览 MP4

## 技术栈

| 分类 | 技术 |
|------|------|
| 框架 | Flutter 3.16+ |
| 网络 | Dio 5.x |
| FFmpeg | ffmpeg_kit_flutter |
| 视频播放 | video_player + chewie |
| 本地存储 | Hive + SharedPreferences |
| 状态管理 | Provider |
| 文件操作 | file_picker + path_provider |

## 项目结构

```
lib/
├── main.dart                      # 应用入口
├── app/
│   ├── models/                    # 数据模型
│   │   ├── download_task.dart     # 下载任务
│   │   ├── merge_job.dart         # 合并任务
│   │   └── settings.dart          # 设置模型
│   ├── services/                  # 核心业务逻辑
│   │   ├── m3u8_parser.dart       # M3U8 解析
│   │   ├── download_manager.dart  # 下载调度
│   │   └── merger_service.dart    # FFmpeg 合并
│   ├── ui/                        # 页面组件
│   │   ├── download_page.dart     # 下载页面
│   │   ├── merge_page.dart        # 合并页面
│   │   ├── settings_page.dart     # 设置页面
│   │   └── player_page.dart       # 播放页面
│   └── widgets/                   # 通用组件
│       ├── download_card.dart     # 下载任务卡片
│       ├── merge_job_card.dart    # 合并任务卡片
│       └── add_task_dialog.dart   # 新增任务对话框
└── utils/                         # 工具类
```

## 开发环境

- Flutter SDK: 3.16+
- Dart: 3.2+
- 支持平台：Windows/macOS/Linux/Android/iOS

## 快速开始

```bash
# 1. 克隆项目
cd F:\App\M3u8Download

# 2. 安装依赖
flutter pub get

# 3. 生成 Hive 类型适配器
flutter pub run build_runner build

# 4. 运行调试（Windows）
flutter run -d windows

# 5. 运行调试（macOS）
flutter run -d macos

# 6. 运行调试（Android）
flutter run -d android

# 7. 运行测试
flutter test
```

## 打包发布

```bash
# Windows 可执行文件
flutter build windows --release

# macOS 应用
flutter build macos --release

# Linux 可执行文件
flutter build linux --release

# Android APK
flutter build apk --release

# iOS App (需 Apple 开发者账号)
flutter build ios --release
```

## 核心算法

### M3U8 解析
- 按行解析播放列表
- 支持 `#EXT-X-KEY`、`#EXT-X-MEDIA-SEQUENCE`、`#EXT-X-STREAM-INF` 等标签
- 自动处理相对路径 URL
- Master Playlist 自动选择最高带宽子列表

### 多线程下载
- 使用 `Semaphore` 控制并发数
- 断点续传：检查本地文件存在性 + TS 合法性校验（0x47 同步字节）
- 自动重试（最多 5 次）
- 实时速度计算（1 秒采样）

### FFmpeg 合并
- **正式合并**（重编码）：
  - `setpts=PTS-STARTPTS` - 视频时间戳归零连续化
  - `fps=SRC_FPS` - 跟随源帧率 CFR 归一化
  - `aresample=async=1000:first_pts=0` - 音频同步
  - `-preset veryfast -crf 20` - 平衡速度与质量
- **快速合并**（预览）：`-c copy` 不重编码

### 进度计算
- 预探测各分片 Duration 求和
- 解析 FFmpeg `-progress pipe:1` 的 `out_time_us`
- 按累计时长反推当前片段索引和百分比

## 常见问题

### Q: 为什么需要重编码合并？
A：HLS 分片各自独立编码，PTS/DTS 从 0 开始。直接 concat 会导致拼接处画面闪烁、声音中断、播放速度异常。

### Q: FFmpeg 体积太大？
A：`ffmpeg_kit_flutter` 约 30-50MB。可使用精简版或运行时下载。

### Q: 如何实现断点续传？
A：每个分片独立文件命名（`000001.ts`），下载前验证 0x47 同步字节，持久化任务状态到 Hive。

## 许可证

Apache License 2.0