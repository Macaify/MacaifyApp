# 设置页设计规范（Macaify）

本规范用于指导后续开发在“设置页”和相关弹窗中的交互、视觉与数据接入实现，保障一致性与可维护性。

## 导航与结构
- Settings 使用系统级 Settings 场景（Cmd-,），窗口架构为左侧侧边栏 + 右侧详情。
- 侧边栏基于 `NavigationSplitView`（macOS 13+），左侧 `List(selection:)` 单选高亮；旧系统回退为自绘 `HStack + List + Divider`。
- 顶层分组（Tabs）：
  - 账户（Account）
  - 模型与来源（Models & Sources）
  - 偏好设置（Preferences）
- 不再单独保留“Models”页；默认模型与来源统一在“模型与来源”页操作。

## 页面职责
- 账户（Account）
  - 登录状态、计划徽章、额度/使用进度、升级/管理订阅入口。
  - 文案与数据用于“价值可见”，不承载模型切换。
- 模型与来源（Models & Sources）
  - 我的模型实例：用户自建实例列表（Keychain 持有 Token），可“设为默认/编辑/删除”。
  - 账户模型：内置模型（来源于 `models.xml`），可“设为默认”。
  - 说明文案合并到“我的模型实例”分组的 footer。
- 偏好设置（Preferences）
  - 通用（开机启动）、快捷键、语言与更新、全局最大 Token。
  - 不包含默认模型选择（避免与“模型与来源”重复）。

## 交互规范
- 切换默认模型
  - 统一在“模型与来源”页：点击“设为默认”。
  - 账户模型 → `Defaults.defaultSource = "account"`；写入 `selectedModelId`、`selectedProvider`，清空 `selectedProviderInstanceId`。
  - 自定义实例 → `Defaults.defaultSource = "provider"`；写入 `selectedProviderInstanceId`、`selectedModelId = instance.modelId`、`selectedProvider = instance.provider`、`proxyAddress = instance.baseURL`。
  - 行右显示“默认”标识（当前默认项）。
- Bot 级模型选择（编辑机器人弹窗）
  - 统一模型选择器（Popover）：左列“账户模型 + 我的模型实例”，右列详情；点击即生效。
  - 选择账户模型 → `conversation.modelSource = "account"` + `conversation.modelId = modelName`；`modelInstanceId = ""`。
  - 选择实例 → `conversation.modelSource = "instance"` + `conversation.modelInstanceId = instance.id`；`modelId = ""`。
  - 模式分段（编辑/聊天）右对齐，保持表单密度。
- 弹窗规范
  - 统一使用 `NavigationStack + Form(.grouped) + toolbar`：取消/确认（必要时 destructive 删除）。
  - Provider 编辑弹窗分组：基本信息、连接、限制（最大 Token）。

## 视觉规范
- 表单：统一 `Form(.grouped)`，分组标题短语化；行内用 `LabeledContent` 表示“标签-值”结构。
- 背景：使用 `.background`（随系统外观适配），避免硬编码白色。
- 控件：
  - 分段控件（Segmented）优先用于二选项；在“行为”组右对齐。
  - 选择按钮采用“文本 + chevron.down”的紧凑样式，外层 6px 圆角描边。
- 列表页中行操作按钮使用文本样式（必要时 `.buttonStyle(.borderless)`）。
- 状态标识：
  - 默认项使用“默认”文本或轻量徽章（caption2、secondary）。
  - 锁定/升级等后续如接入，使用小标签靠右显示。

### 视觉 Token（建议值）
- 间距：页面左右 24，分组内行间 8–10，分组与分组 16–20。
- 圆角：按钮/描边容器 6；Popover 外框 12。
- 阴影：Popover 使用系统默认；不要自定义强阴影。
- 字体：标题 `.headline`；分组名 `.callout`；正文 `.body`；辅助 `.caption/secondary`。
- 颜色：遵循系统 `.primary/.secondary/.tertiary`，不要硬编码 Hex；背景用 `.background`。

## 数据模型与持久化
- Defaults 键
  - `selectedModelId: String` 账户模型名
  - `selectedProvider: String` 账户模型 Provider
  - `selectedProviderInstanceId: String` 自定义实例 id
  - `defaultSource: String` 逻辑来源（account/provider），由“设为默认”的目标推断生成，不提供 UI 切换
  - `proxyAddress: String` 选中实例的 Base URL
  - `maxToken: Int` 全局最大 Token
  - `launchAtLogin: Bool` 开机启动偏好
- 自定义模型实例
  - 结构：`id/name/modelId/baseURL/provider/contextLength?`
  - 列表存储：UserDefaults（键值 `custom.providers`）
  - Token：Keychain，账户为 `id`
- Bot（GPTConversation）
  - 持久化字段：`modelSource_`（default/account/instance）、`modelInstanceId_`、`modelId_`
  - 运行时解析优先级：
    1. 若 `modelSource == "instance"`：取实例的 token/host/provider，并可覆盖 maxToken（contextLength）
    2. 若 `modelSource == "account" && modelId 非空`：从内置模型映射出 provider/context
    3. 否则：回退到全局默认（根据 `defaultSource` 与默认模型/实例）

## 组件规范
- 选择器 Popover（模型）
  - 布局：左列搜索 + 列表（分组）；右列详情（标题、描述、Provider、上下文、可选能力条）。
  - 行交互：点击即选中并关闭；悬停更新右侧详情。
  - ID 稳定性：账户模型 id = `provider + "_" + modelName`；自定义实例 id = `instance.id`。
- Provider 编辑器
  - 表单字段：显示名、模型（支持从内置列表选择）、Provider 类型、Base URL、API Token、最大 Token（Stepper）。
  - 保存：JSON + Keychain；刷新列表。

### 组件 API 约定（SwiftUI）
- `ModelPickerPopover(isPresented: Binding<Bool>)`
  - 输入状态：`Defaults[.selectedModelId]`、`ProviderStore.shared.providers`
  - 选择回调：内部直接写 Defaults（见“交互规范/切换默认模型”），外层只需关闭 Popover。
  - 尺寸：约 560×380；左列宽 280。
- `ProviderEditorView(provider: CustomModelInstance?, onSave: (CustomModelInstance) -> Void)`
  - `provider == nil` 时为新建；保存后回传完整实例并写入 Keychain。
  - 字段校验轻量：名称/Token 可为空但应有占位提示（真实后端接入时再增强）。

## 文案与本地化
- 统一中文文案（短句、动词在前），避免中英混排；后续集中到 `Localizable.strings`。
- 表单项命名简洁：“模型”“最大 Token”“开机启动”等。

## 无障碍与键盘
- 控件均应有明确标签（`LabeledContent`/`Text` 标签可读）。
- Popover 列表支持键盘上下移动和回车选中（后续可扩展）。

## 错误状态与回退
- 无 Token 的自定义实例不可作为默认或选项（可后续加禁用态与提示）。
- 获取 Provider 失败时保持 UI 可交互，允许改为账户模型。

## 代码组织与约定
- 文件组织
  - 顶层容器：`StandardSettingsView` + `SettingsTabs`
  - 三个页面：`AccountSettingsView`、`ProvidersSettingsView`（模型与来源）、`DefaultsSettingsView`（偏好设置）
  - 复用组件：`ModelPicker`（若复用到 Bot 与 Preferences，可抽为独立文件）
- 表单分组顺序：先高频再低频（例如“模型与来源”先是自定义实例，再是账户模型）。
- 不在设置页中放置与主流程无关的操作按钮或调试入口。

## 接入清单（Checklist）
- 新增一个设置项：
  - 放到与语义最贴近的页面；使用 `Form(.grouped)`
  - 文案中文，短句；必要时增加 `footer` 说明
  - 数据存储：优先 `Defaults` 包；键名加入到 `Defaults+Base.swift`
- 新增一个模型：
  - 账户模型：更新 `models.xml` 并确保 `LLMModelsManager` 能读取
  - 自定义实例：使用 Provider 编辑器添加；Token 自动写入 Keychain
- 新增一个弹窗：
  - 必须使用 `NavigationStack + Form(.grouped) + toolbar`
  - 具备取消/确认按钮；若涉及删除，使用 destructive

### 常见坑与避免
- `List(selection:)` 需要稳定且 `Hashable` 的 `tag`；不要用 `UUID()` 现生成作 ID。
- `Section.footer {}` 在 macOS 中不支持链式写法，请使用带 `footer:` 闭包的初始化方式。
- 侧边栏 `List(selection:)` 的 `selection` 绑定类型必须与 `.tag()` 一致（例如 `SettingsTab?` ⇄ `.tag(tab)`）。
- 使用 `.background(.background)` 而非硬编码 `Color.white`，以适配深浅色和高对比度模式。
- 模型名与 provider 必须来源于 `LLMModelsManager` 解析结果，避免魔法字符串。

## 设计原则（DO / DON’T）
- DO：统一入口进行“默认模型”设置，避免多个页面可设置导致心智负担
- DO：优先使用系统标准视觉（列表、表单、分段控件、Popover）
- DO：将说明文案放到 `footer`，减少正文噪音
- DON’T：在 Preferences 再次出现“默认模型”选择
- DON’T：同时暴露“来源开关”和“默认模型选择”两套逻辑

## 验收标准（Definition of Done）
- 侧边栏切换稳定、选中高亮；详情页为 grouped form，无额外滚动容器。
- “模型与来源”一页即可完成默认模型设置；默认项有清晰标识。
- Bot 设置弹窗：统一模型选择器，可同时看到账户模型与自定义实例；模式分段控件右对齐；关闭后持久化。
- Provider 编辑弹窗：包含最大 Token；保存后出现在“我的模型实例”并可设为默认。
- `Defaults` 与 `Keychain` 的写入路径与键名符合“数据模型与持久化”章节。

---
如需扩展：
- 可在“模型与来源”行右加入“升级/锁定/能力条”等小标签（参考 Raycast 的轻量样式）
- 模型详情面板可引入真实的速度/智能指标与价格信息
