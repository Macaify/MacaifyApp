# Macaify – 在任何应用里用 AI，不再 ⌘‑Tab
> 
> Select → Shortcut → Done. 不切换应用，不打断思路。

Macaify 是一款专注「不打断专注流」的 Mac 原生 AI 应用：在任何 App 里选中文本，按下快捷键即可完成翻译、润色、改写、总结等操作；也支持完整的聊天模式与多模型切换。应用开源免费，可自带模型（无需配置）或使用你自己的 API Key（BYOK）。

- macOS 12.0+ · Apple 芯片与 Intel 皆可
- 免费与开源 · 需署名（见 LICENSE）
- 支持 In‑Context（任何应用）与 Chat 两种模式
- 支持 Macaify 账户模型 或 自带模型（BYOK）


## 设计理念：专注，不被切换打断
很多时候我们只是想把一句话翻译一下、把一段文字润色一下，却不得不切到 AI 工具、复制粘贴、等结果、再切回来。切换 = 打断思路 + 浪费时间。Macaify 的核心出发点是把 AI 融入你的工作流，而不是再造一个需要来回切换的“目的地”。

因此我们做了 In‑Context 模式：选中 → 快捷键 → 完成。无需切换应用、无需额外思考、不中断。聊天模式也保留了大家熟悉的体验，只是把「选中文本」钉在对话顶部作为上下文来讨论。


## 功能亮点
- In‑Context（任何应用）
  - 选中文本后按快捷键，直接在原位完成翻译、润色、改写等。
  - 可开启 Typing In Place：直接用回复替换原文本，不弹窗。
- 聊天模式（Chat）
  - 支持把选中内容作为上下文；支持 Markdown 渲染与代码高亮。
  - 会话标题自动生成与重命名；多会话管理。
- 模型与提供商
  - 内置 Macaify 账户模型（登录即用，按计划限制）。
  - 自带模型（BYOK）：OpenAI / 兼容 OpenAI API 的服务，支持自定义 Base URL。
  - 快速选择器与模板：从推荐列表一键设为默认，或从模板创建自定义实例。
- 快捷操作
  - 系统级快捷键：例如 Option+V（中英互译）、Option+S（总结）、Option+Q（快速提问）。
  - ⌘K 快捷面板：发送/重试、复制/粘贴上次回复、切换 Agent、新建会话等。
- 体验与细节
  - 原生 SwiftUI 界面；支持菜单栏入口、自动更新、无障碍引导。
  - 本地首开即内置多组实用 Prompt 模板，开箱即用。


## 截图预览
- 无障碍权限引导（视频，可在 GitHub 直接播放）：
  - docs/Assets/accessibility_guide.mp4
  
> 更多界面截图可在官网或发布页查看，也欢迎 PR 补充最新截图。


## 安装
- 从网站下载：前往官网 `https://macaify.com` 下载已签名的构建。
- 从源码构建：见下文「从源码构建」。


## 从源码构建
> Xcode 与 Swift 工具链版本会随依赖升级，请以本节为准。遇到编译差异，欢迎在 Issue 反馈。

- 系统：macOS 12.0+
- 开发工具：Xcode 16+（包含 Swift 6 工具链）
- 拉取代码与子模块：
  ```bash
  git clone --recursive git@github.com:YOUR_ORG/ChatGPTSwiftUI.git
  # 如果你已 clone，可执行：
  git submodule update --init --recursive
  ```
- 打开工程：双击 `XCAChatGPT.xcodeproj`，选择 `XCAChatGPTMac` 方案，直接运行。
- 首次运行：
  - 会按系统语言预置若干默认会话和快捷操作。
  - 可能需要授予“辅助功能”权限（用于读取选中文本、自动粘贴等本地操作）。

提示：如果只使用 BYOK（自带 API Key），无需配置任何账号；若使用 Macaify 账户模型，请确保 `macaify.com` 可达并完成登录（见设置页）。


## 快速开始
1) 选择默认模型
- 打开 设置 → 账户与模型；从“账户模型”或“我的模型实例”中设为默认。
- BYOK：点击“从模型模板添加”或“添加自定义模型”，填入 `Model ID`、`Base URL` 与 `API Key`，保存后“设为默认”。

2) 授权与热键
- 首次使用 In‑Context 会引导你开启“辅助功能”权限。
- 默认热键：
  - Option+V：中英互译（Typing In Place）
  - Option+S：总结所选文本
  - Option+Q：快速提问
  - ⌘K：快捷操作面板
- 你可在 设置 → 快捷键 自行调整。

3) 立即上手
- 在任意 App 选中文本 → 按热键 → 等待流式结果。
- 聊天模式：从主窗口新建/切换会话，支持将选中内容固定在顶部作为上下文。


## 配置说明
- 账户模型（无需 Key）
  - 在设置中登录后即可使用官方推荐的多家模型（按计划可用）。
  - 身份验证与订阅由 `macaify.com` 提供（见代码 `XCAChatGPTMac/XCAChatGPTMacApp.swift:1` 与 `Shared/backend/BackendEnvironment.swift:1`）。
- BYOK（自带 API Key）
  - 在“我的模型实例”中添加自定义实例：`modelId`、`baseURL`（OpenAI 兼容，建议带 `/v1`）、`provider`（一般为 `openai`）。
  - Token 本地保存（UserDefaults），仅用于直连你配置的 API 服务端，请勿泄露。
  - 可在编辑页点击“测试连接”验证配置是否可用。


## 隐私与数据
- In‑Context 模式读取选中文本、模拟粘贴等仅发生在本机，不上传。
- 使用 Macaify 账户模型时，会与 `macaify.com` 通信以完成鉴权、配额判断与转发调用。
- 使用 BYOK 时，所有请求直接发往你配置的 API 服务端。
- 我们不做与功能无关的数据分析。详见源代码相关实现。


## 项目结构（节选）
- `XCAChatGPTMac/`：Mac App 入口与业务视图（主窗口、菜单栏、设置）。
- `Shared/`：跨平台共享（会话存储、消息渲染、Chat API、组件等）。
- `Packages/`：本地依赖（`BetterAuthSwift`、`AppUpdater`、`OpenAI`、`MacaifyServiceKit` 等）。
- 相关文件：
  - Chat API 实现：`Shared/ChatGPTAPI.swift`
  - 模型与提供商：`XCAChatGPTMac/business/settings/ProvidersSettingsView.swift`
  - 后端环境：`Shared/backend/BackendEnvironment.swift`
  - 设置与快捷键：`XCAChatGPTMac/business/settings/*.swift`


## 路线图与设计文档
- 产品需求：`docs/Product/Requirements.md`
- 路线图：`docs/Product/Roadmap.md`
- 设计规范：`docs/Design/Settings-Design.md`、`docs/Design/Settings-Guidelines.md`
- 组件/颜色规范：`docs/Design/Components.md`、`docs/Design/Colors.md`


## 常见问题（FAQ）
- Q: 构建报 Swift 工具链版本不匹配？
  - A: 依赖中包含 Swift 6+ 的包，建议使用 Xcode 16+。若确需旧版本，请自行降级/替换相关包后编译。
- Q: BYOK 要不要填 `/v1`？
  - A: 绝大多数 OpenAI 兼容服务需要 `baseURL` 末尾包含 `/v1`。项目会在必要时补齐，推荐直接填写。
- Q: Token 存哪？安全吗？
  - A: 本地 `UserDefaults`。请避免公用电脑；也可只在需要时粘贴临时 Token 使用。
- Q: 不登录能用吗？
  - A: 可以。选择 BYOK 即可完全离线于账号体系之外使用（需你自行承担相应服务费用）。


## 贡献
非常欢迎 Issue / PR：
- 提交前请尽量复现问题、配上系统版本与具体操作路径；
- 代码变更建议小步提交、聚焦单一问题；
- UI/文案/本地化改进也同样欢迎；
- 若涉及协议或权限变更，请在 PR 描述中明确说明。


## 致谢
- 原始项目与早期灵感来自开源社区（仓库历史与 `LICENSE` 中已标注）。
- 第三方依赖：OpenAI SDK、MarkdownView、Moya/Alamofire、BetterAuth、KeyboardShortcuts 等。


## 许可
请遵循 `LICENSE` 中的署名使用声明：允许修改、分发与商用（可闭源），但必须在产品对终端用户可见的位置显著标注“Powered by Macaify — https://macaify.com”，并保留版权及第三方组件的许可/归属信息。本项目原始 MIT 许可文本保存在 `LICENSE-BASE` 以供参考。

——
如果这个项目对你有帮助，欢迎点亮 Star；也欢迎通过官网体验稳定发布版本并支持 Pro 订阅，用于覆盖模型调用与开发维护成本。谢谢！

