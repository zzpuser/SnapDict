<div align="center">

# SnapDict

**macOS AI 翻译词典 | AI-Powered Dictionary for macOS**

快捷键呼出翻译面板，AI 智能助记，单词本复习，语音朗读，墨水屏推送

[![Release](https://img.shields.io/github/v/release/zzpuser/SnapDict)](https://github.com/zzpuser/SnapDict/releases/latest)
[![License](https://img.shields.io/github/license/zzpuser/SnapDict)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue)](https://github.com/zzpuser/SnapDict)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://github.com/zzpuser/SnapDict)

</div>

| 翻译面板 | 单词本 | 设置 |
|:---:|:---:|:---:|
| ![翻译面板](screenshots/translation.png) | ![单词本](screenshots/wordbook.png) | ![设置](screenshots/settings.png) |

## 功能特性

- **快捷键翻译** — 全局快捷键呼出翻译面板，支持中英互译
- **自动获取选中文字** — 开启后按快捷键自动抓取其他应用中选中的文字并查词，无需手动输入
- **AI 智能助记** — 基于 DeepSeek AI 生成词根词缀分析和联想记忆法
- **拼写纠正** — 自动检测拼写错误，支持自动纠正或手动选择
- **单词本** — 收藏生词，随时复习
- **TTS 语音朗读** — 集成豆包语音合成，支持自然语音朗读
- **墨水屏推送** — 定时推送单词卡片到墨水屏设备，支持文本和图片模式，可配置抖动算法
- **菜单栏常驻** — 轻量运行，不占用 Dock 栏

## 安装

1. 从 [Releases](https://github.com/zzpuser/SnapDict/releases/latest) 下载最新的 DMG 文件
2. 打开 DMG，将 SnapDict 拖入 Applications 文件夹
3. 终端执行 `sudo xattr -r -d com.apple.quarantine /Applications/SnapDict.app`
4. 打开 SnapDict

## 快速开始

1. 启动后在菜单栏找到 SnapDict 图标
2. 进入设置，填入 [DeepSeek API Key](https://platform.deepseek.com/)
3. 使用快捷键 `Cmd+Shift+E` 唤起翻译面板（可自定义）
4. 输入单词即可获取翻译、助记和例句

## 配置

| 服务 | 用途 | 必需 |
|------|------|:---:|
| [DeepSeek API](https://platform.deepseek.com/) | 翻译、助记、例句生成 | ✅ |
| 豆包 TTS | 语音合成 | ❌ |
| 墨水屏设备 (TRSS) | 单词推送 | ❌ |

## 从源码构建

> 要求：macOS 15.0+、Xcode 16.0+、Swift 6.0

```bash
# 安装 XcodeGen
brew install xcodegen

# 克隆并构建
git clone https://github.com/zzpuser/SnapDict.git
cd SnapDict
xcodegen generate
open SnapDict.xcodeproj
```

## 更新日志

### v1.3.0

**查词体验优化**

- 查词加载中显示骨架屏，模拟最终结果布局，替代单调的加载动画
- 助记/例句加载中也显示骨架屏占位，带从左到右扫过的闪烁动画
- 例句区域添加图标，与助记区域风格统一

**面板高度自适应**

- 查词 Tab 面板高度根据内容自动调整
- 单词本/设置 Tab 支持用户手动拖拽调整高度并记忆

**安装体验优化**

- DMG 安装页面美化：自定义背景图、图标布局和拖拽箭头引导

**修复**

- 修复缓存命中等快速响应场景下面板不展开的问题
- 修复输入中修改查询时面板塌缩闪烁的问题

### v1.2.0

**新功能：快捷键自动获取选中文字查词**

- 在任意应用中选中文字后按快捷键，面板自动填入选中内容并触发翻译，省去手动输入步骤
- 通过 macOS Accessibility API 读取前台应用的选中文字，需在系统设置中授予辅助功能权限
- 设置页新增"自动获取选中文字"开关（默认关闭），开启时自动引导授权，并实时显示权限状态
- 无论当前处于哪个 Tab，有选中文字时自动切换到查词页面

**墨水屏推送增强**

- 图片推送支持配置抖动算法类型（关闭 / 误差扩散 / 有序抖动）
- 误差扩散模式下可选择具体的扩散核函数（Floyd-Steinberg、Atkinson 等 10 种）
- 单词卡片样式优化：提升文字对比度和分隔线清晰度，优化水印显示

### v1.1.0

- 设置页优化：API Key 明文切换、墨水屏推送开关控制
- 墨水屏推送支持文本和图片两种模式

### v1.0.0

- 首个正式版本

## 技术栈

- **语言**: Swift 6.0 (Strict Concurrency)
- **框架**: SwiftUI + AppKit
- **存储**: SwiftData
- **AI**: DeepSeek API
- **TTS**: 豆包语音合成
- **依赖**: [HotKey](https://github.com/soffes/HotKey)

## License

[MIT](LICENSE)
