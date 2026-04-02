# VoiceTok — 项目状态与开发路线图

> **文档类型**：工程状态追踪 + 产品路线图
> **最后更新**：2026-04-01
> **当前版本**：v1.0.0（5 commits，BUILD SUCCEEDED ✅）
> **仓库**：https://github.com/ViffyGwaanl/VoiceAiTok

---

## 一、交付清单 — v1.0

### 核心功能

| 功能 | 状态 | Commit |
|------|------|--------|
| 项目框架（SwiftUI、MVVM、AppState DI） | ✅ 完成 | d6a1814 |
| MobileVLCKit 3.7 CocoaPods 集成 | ✅ 完成 | 8f5e0c7 |
| WhisperKit 0.18 SPM 集成 | ✅ 完成 | 8f5e0c7 |
| AVMediaPlayerService 备用播放器 | ✅ 完成 | d6a1814 |
| VLCPlayerService + VLCVideoRepresentable | ✅ 完成 | 8f5e0c7 |
| TranscriptionService（WhisperKit 封装） | ✅ 完成 | d6a1814 |
| 实时转录进度回调（WindowId 估算） | ✅ 完成 | 25cdca9 |
| 音频提取（AVAssetReader → 16kHz WAV） | ✅ 完成 | d6a1814 |
| MediaLibraryService（导入、缩略图、持久化） | ✅ 完成 | d6a1814 |
| ChatService — Claude / OpenAI / Ollama | ✅ 完成 | d6a1814 |
| 流式 SSE 响应（三种后端） | ✅ 完成 | 25cdca9 |
| API 密钥 → iOS Keychain（KeychainService） | ✅ 完成 | 25cdca9 |
| 长文本 Token 截断（80k 上限） | ✅ 完成 | 25cdca9 |
| 转录结果持久化到媒体库 | ✅ 完成 | 25cdca9 |
| PlayerView 转录面板（实时字幕同步） | ✅ 完成 | d6a1814 |
| LibraryView（搜索、排序、滑动删除） | ✅ 完成 | d6a1814 |
| ChatView（流式气泡、快捷操作） | ✅ 完成 | d6a1814 |
| SettingsView（API 配置、转录偏好） | ✅ 完成 | d6a1814 |
| ContentView 齿轮按钮（设置入口） | ✅ 完成 | 25cdca9 |
| Xcode 工程生成（project.yml / xcodegen） | ✅ 完成 | 8f5e0c7 |
| WhisperKit API 兼容性修复（v0.18） | ✅ 完成 | 8f5e0c7 |
| MobileVLCKit API 修复（parse(options:)） | ✅ 完成 | 8f5e0c7 |
| 简体中文本地化（zh-Hans） | ✅ 完成 | d86d238 |
| WhisperKit 模型下载与管理 UI | ✅ 完成 | aec0fe9 |

---

## 二、功能矩阵

| 模块 | 已实现内容 | 备注 |
|------|-----------|------|
| **播放** | VLCKit（100+ 格式）+ AVPlayer 备用 | `#if canImport(MobileVLCKit)` 切换 |
| **转录** | WhisperKit 本地，10 种模型，词级时间戳 | 设备端 Neural Engine |
| **模型管理** | 下载、切换、删除、进度 UI | 缓存在 `Documents/huggingface/` |
| **AI 对话** | Claude（流式）、OpenAI（流式）、Ollama | SSE + 非流式回退 |
| **媒体库** | 导入文件/链接，搜索，5 种排序 | JSON 存 UserDefaults |
| **安全** | API 密钥存 Keychain | `kSecAttrAccessibleAfterFirstUnlock` |
| **本地化** | 英语 + 简体中文 | `zh-Hans.lproj`，~100 条字符串 |

---

## 三、已解决的技术债务

初始审计发现的 7 项 P0/P1/P2 问题已全部关闭：

| ID | 问题 | 修复方案 | Commit |
|----|------|---------|--------|
| TD-001 | 转录结果不保存 | PlayerViewModel 调用 `mediaLibraryService.updateItem()` | 25cdca9 |
| TD-002 | PlayerView 使用不可变 `let mediaItem` | 改读 `viewModel.mediaItem` | 25cdca9 |
| TD-003 | WhisperKit 无进度回调 | `TranscriptionCallback` 通过 `windowId` 估算 | 25cdca9 |
| TD-004 | API 密钥明文存 UserDefaults | 迁移到 `KeychainService` | 25cdca9 |
| TD-005 | 长转录无 Token 截断 | `buildSystemContext()` 80k 上限 + 截断提示 | 25cdca9 |
| TD-006 | VLCKit 被注释掉无法编译 | `#if canImport(MobileVLCKit)` 条件编译 | 25cdca9 |
| TD-007 | 无设置入口 | ContentView 工具栏齿轮按钮 | 25cdca9 |

---

## 四、当前已知局限

| 问题 | 影响 | 计划 |
|------|------|------|
| WhisperKit 模拟器为 CPU 模式 | 模拟器转录慢 | 预期行为，Neural Engine 仅真机 |
| 大模型下载需要 Wi-Fi | 用户体验 | 下载前显示大小警告（v1.1） |
| 转录文件不同步 iCloud | 重装丢数据 | v1.1 目标 |
| VLCKit 仅支持 `-iphonesimulator` 构建 | 模拟器调试限制 | CocoaPods XCFramework 特性 |

---

## 五、路线图

### v1.1 — 云同步与分享
- [ ] iCloud Drive 同步转录 JSON 文件
- [ ] Share Sheet 扩展 — 从任意 App 触发转录
- [ ] 导出格式：SRT 字幕、JSON、纯文本
- [ ] 说话人分离（多说话人检测）

### v1.2 — 集成扩展
- [ ] 直接导入 YouTube / 播客流 URL
- [ ] Siri 快捷指令："转录最新导入"
- [ ] 主屏小组件：当前播放 + 快速转录
- [ ] CarPlay 音频支持

### v2.0 — 多平台
- [ ] iPad 多列布局（视频 + 转录 + 对话同屏）
- [ ] macOS（Catalyst）支持，含菜单栏控制
- [ ] 批量转录队列 + 后台处理
- [ ] 每条媒体独立配置 AI 系统提示词
- [ ] 领域词汇 Whisper 微调模型支持

---

## 六、构建说明

```bash
git clone https://github.com/ViffyGwaanl/VoiceAiTok.git && cd VoiceAiTok
pod install                        # 安装 MobileVLCKit 3.7
open VoiceTok.xcworkspace         # WhisperKit SPM 自动解析
# Xcode：设置 Development Team → 连接 iPhone → ⌘R
```

**xcodegen**（如需从 project.yml 重新生成 .xcodeproj）：
```bash
brew install xcodegen && xcodegen generate && pod install
```

**模拟器构建（无需签名）：**
```bash
xcodebuild build -workspace VoiceTok.xcworkspace -scheme VoiceTok \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

---

## 七、依赖版本表

| 包 | 版本 | 来源 |
|----|------|------|
| MobileVLCKit | 3.7.3 | CocoaPods |
| WhisperKit | 0.18.0 | SPM (argmaxinc/WhisperKit) |
| swift-transformers | 1.1.9 | SPM（传递依赖） |
| swift-crypto | 4.3.1 | SPM（传递依赖） |
| Xcode | 16+ | 必需 |
| iOS Deployment Target | 17.0 | 最低版本 |
