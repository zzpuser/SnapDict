# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Build & Development

```bash
# 生成 Xcode 工程（新增/删除文件后必须执行）
xcodegen generate

# 命令行构建
xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build

# 打开 Xcode
open SnapDict.xcodeproj
```

- 使用 XcodeGen 管理工程文件（`project.yml`），`sources: [SnapDict]` 自动包含目录下所有 Swift 文件
- 新增或删除 .swift 文件后需重新运行 `xcodegen generate`
- SPM 依赖：HotKey（全局快捷键）、PartialJSON（流式 JSON 容错解析）
- 无测试套件

## Architecture

macOS 菜单栏翻译词典应用（LSUIElement，无 Dock 图标），Swift 6.0 + SwiftUI + SwiftData，部署目标 macOS 15.0+。

**分层结构：**

- **Models/** — SwiftData `@Model` 持久化类（WordEntry, TranslationCache, TTSCache）和 Codable 数据结构（TranslationResult, PartialResult 等）
- **Services/** — 外部 API 调用（DeepSeekService 流式翻译, ByteDanceTTSService 豆包语音合成, DotScreenService 墨水屏推送, CacheService 缓存, HotKeyManager 快捷键）
- **Managers/** — 应用状态管理（PanelManager 浮动窗口, WordBookManager SwiftData CRUD, WordPushScheduler 定时推送, TTSManager 发音播放控制）
- **Views/** — SwiftUI 界面，UnifiedPanelView 包含 3 个 Tab（查词、单词本、设置）
- **Utilities/Constants.swift** — 所有 API 端点、UserDefaults key、枚举配置、默认值集中定义

**核心数据流：**

```
快捷键/菜单栏点击 → PanelManager.showPanel(selectedText)
  → TranslationContentView 触发翻译
  → DeepSeekService.translateWordStreaming() 返回 AsyncThrowingStream<PartialWordResult>
  → 逐步渲染（骨架屏 → 流式填充）
  → CacheService 缓存完整结果
  → 用户可收藏到 WordBookManager → WordPushScheduler 定时推送到 DotScreenService
```

**流式翻译架构：** DeepSeekService 通过 SSE 流式接收，使用 PartialJSON 库容错解析不完整 JSON，通过 AsyncThrowingStream 逐步 yield PartialWordResult/PartialSentenceResult，View 实时渲染中间状态。支持 Task 取消（用户快速输入时自动取消旧请求）。

**面板窗口管理：** PanelManager 管理 NSPanel 浮动窗口，查词 Tab 高度根据内容自适应（View 通过 callback 上报高度），单词本/设置 Tab 支持用户手动调整并记忆到 UserDefaults。单词查询宽度 420pt，短句查询宽度 840pt，切换时保持窗口中心不变。动画使用 CASpringAnimation。

**TTS 架构（历史顽固 bug，重构前必读）：** TTSManager（@MainActor）负责播放控制与状态，ByteDanceTTSService 负责 SSE 下载音频。三条铁律，违反任何一条都会复现历史 bug：
1. **AVAudioPlayer 的创建、音量设置、`prepareToPlay()` 必须在后台执行器完成**（`makePreparedPlayer`，用 `sending` 转移回 main actor）——`prepareToPlay` 内部同步 IPC 到 coreaudiod 启动音频硬件，蓝牙设备可阻塞秒级，放在 main actor 会冻结流式翻译渲染（此 bug 曾跨 4 种 TTS 后端复现）
2. **`isPlaying == true` 的每个阶段必须有终结者兜底**：下载阶段 fetch watchdog（20s 超时取消并回退）、播放阶段 delegate + finish watchdog（duration+1s）、系统语音阶段 say 子进程 terminationHandler——缺一个就会出现"动画永远不停止"
3. **播放状态通过 NotificationCenter 广播**（ttsPlaybackStateChanged），TTSManager 不用 @Observable，发音按钮是独立小 View（SpeakerButton）——避免 isPlaying 变化触发 1000+ 行翻译视图全量重渲染
此外 playbackToken（UUID）守卫所有异步回调，失败回退（handleByteDanceFailure）会换新 token 作废在途回调，防止双重播放。

## Concurrency Model

项目启用 `SWIFT_STRICT_CONCURRENCY: complete`，编译时严格检查并发安全：

- `@MainActor @Observable`: PanelManager, WordBookManager, WordPushScheduler, HotKeyManager — 所有 UI 和 SwiftData 操作
- `@MainActor`（无 @Observable）: TTSManager — 播放状态经 NotificationCenter 广播；播放器准备在后台执行器（见 TTS 架构）
- `@Observable final class: Sendable`: DeepSeekService, ByteDanceTTSService, DotScreenService — 无状态 API 服务
- `@unchecked Sendable`: CacheService — 内部使用 DispatchQueue + 临时 ModelContext 保证线程安全；写操作 fire-and-forget（queue.async），读操作 queue.sync 仅限后台调用

跨线程调用用 `Task { @MainActor in ... }` 或 `await`。

## Commit & PR Guidelines

- Commit 消息使用中文，简短祈使句（如"修复图标变暗问题"），每个提交保持职责单一
- 发版时将本地多个提交 squash 合并为一个再推送，保持远程 commit 历史干净
- 发版 squash 提交的 message 内容需与 README.md 更新日志对齐（标题 + 逐条列出变更）
- 版本更新日志不包含迭代内新功能引入的 bug 修复，只写用户可感知的功能
- PRs/patches 需包含：摘要说明、执行过的命令、UI 变更需附截图/GIF、关联的 issue 或参考链接

## Conventions

- 所有配置项通过 `Constants.UserDefaultsKey` 和 `Constants.Defaults` 集中管理，新增配置必须在此定义
- API 请求统一模式：URLRequest → URLSession.shared.data() → 状态码检查 → JSON 解码；流式请求用 URLSession.bytes(for:)
- 面板动画使用 CASpringAnimation/CABasicAnimation（PanelManager），不用 SwiftUI withAnimation
- SwiftData 查询：Manager 中用 FetchDescriptor + #Predicate，View 中用 @Query
- SSE 流式处理：每行 `data:` 前缀立即处理，不能依赖空行做事件分隔（bytes.lines 会跳过空行）
- SwiftData 数据库路径：`~/Library/Application Support/com.zzp.SnapDict/SnapDict.store`
