# MacContentView 现状逻辑与改造思路（Spec）

目标
- 归纳现有 `XCAChatGPTMac/MacContentView.swift` 的职责、状态与导航方式。
- 明确与周边组件的边界，作为重写的基线。
- 给出与新设计规范对齐的改造要点（不大动架构，聚焦表现与交互稳定）。

现状职责
- 作为 Mac 端顶层容器，负责承载主界面 `MainView`，以及用覆盖/弹窗形式打开若干功能：
  - 新建机器人（Add）
  - 编辑机器人（Edit）
  - 设置（Settings，调用系统设置窗口）
  - Playground（PromptPlayground）
  - 首次启动/新功能提示（StartUpView，内部再弹出 Sheet）

关键依赖
- `PathManager.shared`：集中管理导航栈，`top: Target?` 作为当前路由。
- `ConversationViewModel.shared`：主界面与聊天上下文（通过上层注入为 EnvironmentObject）。
- 子视图：`MainView`、`ChatView`（主界面内部唤起）、`ConversationPreferenceView`、`PromptPlayground`、`StartUpView`。

状态与路由
- `Target`（路径栈项）
  - `.main(command: GPTConversation?)`：主界面（可选打开指定会话）
  - `.setting`：设置（桥接到系统 Settings）
  - `.addCommand`：新建机器人
  - `.editCommand(command: GPTConversation)`：编辑机器人
  - `.playground`：提示词试验场
  - `.chat(...)`：历史遗留，现阶段实际通过 `MainView` 内部承载聊天，不再在 `MacContentView` 直接切换
- `MacContentView` 通过 `ZStack` 委托 `pathManager.top` 决定覆盖内容：
  - 主体始终是 `MainView()`；
  - 其上切换显示 `BotSettingsPresenter`（内部再弹出 `ConversationPreferenceView` Sheet）、`SettingsBridgeView`（触发系统设置并返回）、`PromptPlayground`；
  - 最顶层常驻 `StartUpView`，自身再以 Sheet 方式弹出引导或初始化。

交互要点
- 设置使用 `SettingsBridgeView` 的 `onAppear` 调用 `NSApp.sendAction("showSettingsWindow:")` 打开系统设置窗口，随后自动 `PathManager.back()` 回到主界面。
- 新建/编辑机器人使用 `BotSettingsPresenter` 在出现时立刻 `sheet(isPresented:)`；关闭后 `PathManager.back()`。
- 聊天进入：`MainView` 内部根据选择状态切换右侧 `ChatView`，并未通过 `MacContentView` 的路由切换。

现状问题（与新规范的偏差）
- 路由展示以 `ZStack` 直接叠加视图，存在层级管理分散、Sheet 触发二次包裹的心智成本。
- 背景色在下游视图中存在硬编码白色（不完全符合“使用系统 `.background`/material”的建议）。
- Add/Edit/Playground/Settings 的入口交互模式不统一：有的直接放视图叠加，有的再二次弹 Sheet。

改造目标（保持功能不大动）
- 统一为“主视图 + sheet(item:) 弹窗”的结构：
  - 主体固定为 `MainView`；
  - 根据 `PathManager.top` 同步一个 `ActiveSheet?`，用 `.sheet(item:)` 统一呈现 Add/Edit/Playground/SettingsBridge；
  - `StartUpView` 保持常驻（内部自我管理 Sheet）。
- 视觉遵循规范：顶层容器背景用 `.background(.background)`，避免新加硬编码颜色。
- 保持设置页的系统窗口调用方式（`SettingsBridgeView`）。

验收点
- 现有入口（底栏按钮、快捷键）仍可唤起 Add/Edit/Playground/Settings。
- 关闭任一 Sheet 后能正确回到主界面，不多退也不少退。
- 不改变聊天承载位置（仍在 `MainView` 内右侧区域）。

后续建议（非本次变更）
- 将 `MainView` 背景与分隔材质逐步切换到系统 `.background`/`.regularMaterial`，减少硬编码白色不透明背景。
- 将模型选择器统一复用 `ConversationPreferenceView` 中的 Popover 组件，进一步提升一致性。


---

## 新主界面（MainSplitView）聊天页控件规范（补充）

适用范围：`XCAChatGPTMac/business/main/NewMainView.swift` 中的聊天详情（`ChatDetailView`）。该部分与 MacContentView 并行存在，用于新版主窗口方案。

### Toolbar（全局/会话态）
- 中心标题：显示当前 Bot 名称。
- `上下文开关`：切换携带上下文（会话级），按钮风格，图标随状态变化。
- `清空`：清空当前会话历史。
- `Bot 设置`：打开旧有 `ConversationPreferenceView`。
- `模型徽章（只读）`：展示当前正在使用的 `provider:model`（如 `openai:gpt-4o-mini` 或 `compatible:xxx`）。仅作状态提示，不改动模型。

### 聊天区上方（紧贴消息列表上方）
- `模型切换按钮`（紧凑徽章样式，带 chevron）
  - 点击弹出 Popover（`ModelQuickPicker`）。
  - Popover 内容：
    - 账户默认：展示 `Defaults.selectedProvider + Defaults.selectedModelId`，一键切换；“更改默认…”直达系统设置的“模型与来源”。
    - 我的实例：列表展示 `ProviderStore.shared.providers`；点击即切换为实例（未配置 Token 显示“未配置Token”提示）；“管理实例…”直达系统设置。
  - 切换行为：即时写回当前 Bot 的 `modelSource/modelId/modelInstanceId` 并保存，随后重建会话 API，无需“切换-切回”即可生效。
- `配置提示横幅`（蓝色，可选出现）：
  - 实例：未配置 Token；provider ≠ openai 且 BaseURL 为空；
  - 账户：未设置账户 API Key；
  - 提供“Bot 设置”“打开设置”按钮；后者跳转到对应设置 Tab（实例→模型与来源，账户→Account）。
- `错误横幅`（红色，可选出现）：显示最近一次流式错误文案，右侧 X 关闭。

### 输入区（右侧动作汇总）
- 发送按钮 / 生成中按钮（Stop）
- 溢出菜单（…）：
  - 复制最后回答
  - 粘贴到前台应用（沿用 `TypingInPlace.paste` 行为）
  - 重新生成（对最后一条用户消息重试）
  - 清空聊天

### 键盘快捷键
- Return：发送消息
- Shift+Return：换行
- Command+Return：复制最后一条助手回答并隐藏 App
- Command+.：中断流式生成
- Command+D：清空聊天
- Escape：隐藏 App

### 即时生效（重要）
- 监听并触发会话重建：
  - 关闭 Bot 设置弹窗后；
  - `store.bots` 数据变化；
  - `UserDefaults.didChangeNotification`（默认模型/代理改变时）；
  均会在“当前选中的 Bot 不变”的前提下，重建 Chat API 以使用最新配置。

### 诊断与隐私
- 发送前打印关键参数（仅在控制台）：`provider/model/baseURL/apiKey(掩码)/withContext/systemPromptLen/convId` 与选择来源快照；
- API Key 仅保留后 6 位，其余以 `*` 掩码；
- 流式错误将打印到控制台，并插入一条错误消息与顶部横幅提示。
