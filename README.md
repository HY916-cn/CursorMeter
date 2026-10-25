# CursorMeter

CursorMeter 是一款原生 macOS 菜单栏应用，通过本机安装的 **官方 Cursor CLI** 读取账户额度，显示剩余比例、CLI 提供的重置日期和本地历史曲线。当前版本为 **0.1.0（build 1）**，支持 **Apple Silicon / macOS 13 及以上**。

本项目基于 [ClaudeMeter](https://github.com/HY916-cn/ClaudeMeter) 适配，沿用 [Raycal 的 CodexMeter](https://github.com/raycalrui/CodexMeter)（上游提交 `4c6baee`、版本 1.7.0）的 SwiftUI 菜单栏、图表、设置与历史存储设计。CursorMeter 是独立社区项目，与 Cursor / Anysphere 无隶属关系。

- [GitHub 仓库](https://github.com/HY916-cn/CursorMeter)
- [发行版本与安装包](https://github.com/HY916-cn/CursorMeter/releases)

下载适用于 Apple Silicon 的 ZIP，解压后将 `CursorMeter.app` 拖入“应用程序”。发行包使用 ad-hoc 签名，未经过 Apple 公证；首次打开可能需要在“系统设置 → 隐私与安全性”中确认打开。**请先按下面的顺序完成 CLI 配置，再打开应用。**

<a id="first-run"></a>

## 首次使用：按顺序完成四步

> [!IMPORTANT]
> **安装 CLI、登录账户、完成专用目录的首次设置并看到 `/usage` 额度，全部完成后才能使用 CursorMeter。**
>
> **CLI 登录成功仍需继续第 3 步。** CursorMeter 在后台读取额度，无法替你回答登录、首次设置或目录信任提示。请亲自在 `~/Library/Application Support/CursorMeter/CLI` 中完成引导，并确认终端能显示真实额度。

### 1. 安装官方 Cursor CLI

打开 macOS“终端”，运行 [Cursor 官方安装命令](https://cursor.com/docs/cli/installation)：

```bash
curl https://cursor.com/install -fsS | bash
```

安装结束后重新打开终端，确认命令可用：

```bash
agent --version
```

如果提示 `command not found`，将安装目录 `~/.local/bin` 加入 PATH。macOS 默认 zsh 可运行：

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
source "$HOME/.zshrc"
agent --version
```

使用当前官方 CLI，并确认其支持交互式 `/usage`。Cursor 的 [2026.07.13 更新说明](https://cursor.com/docs/cli/changelog#v20260713)记录了套餐额度、Auto / API 额度池、按需用量预算与账期重置日期的显示；具体可用字段取决于你的账户和 CLI 版本。

### 2. 亲自登录 Cursor 账户

```bash
agent login
```

按提示在浏览器中完成个人账户登录，再回到终端检查：

```bash
agent status --format json
```

确认结果显示已认证且账户正确。登录流程由 [Cursor CLI 管理](https://cursor.com/docs/cli/reference/authentication)。**这里只确认登录状态，请继续完成第 3 步。**

### 3. 初始化专用目录，在 CLI 内输入 `/usage`

**将以下整段复制到终端执行，保留路径两侧的双引号：**

```bash
mkdir -p "$HOME/Library/Application Support/CursorMeter/CLI" && \
cd "$HOME/Library/Application Support/CursorMeter/CLI" && \
agent
```

1. 按实际出现的提示完成首次设置。
2. 若出现目录信任提示，核对目录为 `~/Library/Application Support/CursorMeter/CLI`，由你亲自确认。
3. 若要求登录，完成登录后继续。
4. 进入 Cursor CLI 的交互输入框后，输入下面的斜杠命令并按回车：

```text
/usage
```

**`/usage` 要输入在 Cursor CLI 的交互界面中。成功标志是终端出现账户额度面板，能看到适用于你的套餐的用量、额度池或预算，而非登录页、设置页或信任提示。**

确认额度后，按 CLI 显示的退出快捷键退出；需要时可按 `Ctrl+C` 结束。以后终端不需要一直开着。

### 4. 打开 CursorMeter 并刷新

打开 `CursorMeter.app`，点击菜单栏指示器，再点击刷新。读取成功后应显示额度及更新时间，并开始记录本地历史。应用中的配置帮助可返回[本教程](https://github.com/HY916-cn/CursorMeter#first-run)。

> [!WARNING]
> **应用提示未登录：** 回到第 2 步，亲自执行 `agent login`，确认账户后再刷新。
>
> **已登录，但应用仍提示完成首次设置或目录信任：** 重新执行第 3 步的整段命令，并在指定目录完成引导；在其他目录完成的设置不能作为该目录已就绪的证明。
>
> **终端中的 `/usage` 本身没有显示额度：** 先处理终端中的账户、网络、CLI 版本或服务提示，确认能看到额度后再回到应用。反复点击刷新无法完成交互式设置。

## 功能

- 菜单栏双环、百分比和紧凑显示方式；自动选择剩余额度最紧张的窗口，或手动固定窗口。
- 展示 CLI 实际返回且可解析的额度池及文本重置日期。
- 本地历史曲线、周期及日历区间浏览、CSV 导出、保留期限设置和 `.cursormeterbackup` 备份恢复。
- 菜单栏和弹窗配置、浅色 / 深色外观、英文、简体中文及繁体中文。
- 本地额度通知、登录时启动，以及 Bark / Gotify / Telegram / Discord 渠道配置与测试。额度恢复推送需要 CLI 提供明确重置时刻；当前日期文本不满足此条件。
- 独立历史和设置窗口、开发者预览，以及 Sparkle 应用内更新。

## 数据来源与限制

CursorMeter 从 `agent status --format json` 的 `userInfo` 读取账户身份，并通过 `agent about --format json` 补充套餐信息；额度来自伪终端中的交互式 `agent` 和 `/usage`。认证由官方 CLI 管理；应用不读取认证文件或访问未公开的用量 HTTP 接口。额度读取只发送 CLI 用量命令，不提交模型任务。官方 CLI 启动时仍可能执行用户配置的 startup hooks 或加载 MCP 配置，其行为由 CLI 及你的配置决定。

`/usage` 是终端界面，**不是稳定的结构化用量 API**。账户方案、CLI 版本和终端输出格式会影响可读取的字段。窗口名称、周期和重置时间以实际数据为准；应用不会假定固定周期。只有完整、可识别的额度数据才会更新显示；缺失数据不会被解释为 0% 用量。

支持 CLI 的 Included / Auto / API 额度池及按需支出面板。界面显示账户实际返回的套餐和预算；`No monthly limit` 表示按需支出没有设置月度上限，不代表套餐内额度无限。

CLI 的重置字段可能只有 `Resets Nov 1` 这类月日文本，缺少年份、准确时刻及周期开始时间。CursorMeter 保留并显示该文本；当前不会据此推测精确倒计时、时间进度或消耗速度。

Token 明细、每日活动统计和可手动领取的额度重置机会，在 CLI 未提供时保持不可用。应用不会用额度百分比推算 Token，也不会推测账户预算。按需支出没有预算上限时，应用不将其转换为剩余百分比。

### “数据可能已过期”如何处理

> [!IMPORTANT]
> **过期标记表示本次没有取得新数据，不代表额度用完。** 应用保留上次成功读取的数值及原始更新时间，直到下一次成功刷新。恢复的历史数据不会触发新的额度通知。

出现网络错误、CLI 超时、格式不受支持或限流时，先查看应用提示；有重试时间时等待自动重试。若持续失败，在专用目录按[第 3 步](#first-run)打开 CLI 并检查 `/usage`。终端也失败时先处理 CLI 提示；终端正常而应用失败时，报告应用版本、`agent --version` 和应用错误信息，分享前移除账户及其他敏感内容。

正常自动刷新为弹窗打开时每 10 秒、后台每 60 秒；手动刷新至少间隔 10 秒。失败后的冷却和并发保护优先于正常频率。缓存或明确限流会按 5、10、20、30 分钟逐步延长重试间隔，成功后恢复正常刷新。无法确认账户身份时，只显示即时额度，暂停历史记录及额度通知。

## 应用内更新

CursorMeter 使用 [Sparkle 2.10.0](https://sparkle-project.org/)；更新清单来自本仓库，安装包来自 [GitHub Releases](https://github.com/HY916-cn/CursorMeter/releases)。更新使用 CursorMeter 独立的 EdDSA 密钥校验。

打开 **设置 → 关于 → 软件更新**，可手动检查更新。应用默认每天检查一次；**自动下载并安装更新**和**包含预发布版本**默认关闭，可在同页调整。更新检查连接 GitHub，不上传额度历史。GitHub 暂时不可达时可稍后重试，或从发行页手动下载。

## 本地数据与隐私

- 应用标识：`com.huang.CursorMeter`。
- 历史数据库：`~/Library/Application Support/CursorMeter/UsageHistory.sqlite`。
- CLI 工作目录：`~/Library/Application Support/CursorMeter/CLI`。
- 推送凭据：本机钥匙串中的 `com.huang.CursorMeter.pushCredentials`。
- 历史按本机加盐后的账户标识隔离；不保存账户邮箱、认证 Token 或原始 CLI 响应。
- 备份包含历史数据库和账户分区所需盐值，不含认证或推送凭据；恢复会替换现有历史，完成后需重新打开应用。
- 远程通知默认关闭；开启后仅向你配置的服务发送额度窗口名称和实际观测的剩余额度。

## 开发与验证

源码和核心模块保留 `CodexMeter` / `CodexMeterCore` 名称，应用产物和 Xcode scheme 为 `CursorMeter`。本地构建脚本使用 Swift、macOS SDK、Python 3 与 `iconutil`，获取并校验固定版本 Sparkle 后执行 ad-hoc 签名：

```bash
bash Scripts/build_local.sh
open dist/CursorMeter.app
```

构建需要支持源码的近期 Swift 编译器及 SDK。macOS 27 SDK 的 SwiftUI 宏依赖完整 Xcode；本地脚本可使用已安装的 Command Line Tools 26.5 SDK，也可通过 `SDKROOT` 指定 SDK。使用完整 Xcode 时：

```bash
xcodebuild -project CodexMeter.xcodeproj -scheme CursorMeter \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

验证命令：

```bash
swift test
bash Scripts/test_cursor_cli.sh
bash Scripts/test_cursor_recovery.sh
bash Scripts/test_cursor_service.sh
bash Scripts/test_push_service.sh
git diff --check
```

CLI 测试覆盖解析、进程与失败处理；推送测试使用模拟服务。完整 Swift Package 测试需要提供 XCTest 的 Xcode 环境。**真实账户验收需要亲自完成 CLI 设置后，使用实际登录账户成功刷新 `/usage`；模拟数据和解析测试无法证明这一点。** 菜单栏操作、通知权限、登录时启动和更新后的重启，需要在实际签名应用中验证。

### 维护者发布更新

维护者使用 Sparkle `generate_keys --account com.huang.CursorMeter` 管理专属 EdDSA 密钥；私钥保存在维护者登录钥匙串，仓库仅保存公钥。妥善备份并持续使用同一签名身份。

递增应用版本和 build 后，构建、打包并生成更新清单；下面以 `0.1.0` 为例：

```bash
bash Scripts/build_local.sh
ditto -c -k --sequesterRsrc --keepParent dist/CursorMeter.app CursorMeter-0.1.0-macOS-arm64.zip
zsh Scripts/prepare_sparkle_update.sh v0.1.0 CursorMeter-0.1.0-macOS-arm64.zip .build/sparkle-2.10.0/bin
bash Scripts/verify_sparkle_update.sh CursorMeter-0.1.0-macOS-arm64.zip
```

**先上传并确认 GitHub Release 附件可下载，再发布已签名的 `appcast.xml`。** 清单改变后应重新生成签名；预发布版本可在准备脚本末尾追加 `beta`。打包时保持 framework 符号链接及可执行权限。

## License

[MIT License](LICENSE)。Original project copyright © 2026 Raycal。保留 CodexMeter 原始许可证和作者归属，并致谢 [ClaudeMeter](https://github.com/HY916-cn/ClaudeMeter) 提供的 CLI 适配基础。
