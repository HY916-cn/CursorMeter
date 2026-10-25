# CursorMeter Development Guide

## Product and identity

CursorMeter is a native macOS 13+ menu bar app for Apple Silicon, adapted from
ClaudeMeter and Raycal's MIT-licensed CodexMeter (upstream 4c6baee, version 1.7.0).
Preserve LICENSE and both projects' attribution. Current version: 0.1.0, build 1.

- Product/display name: CursorMeter; bundle identifier: com.huang.CursorMeter.
- Repository: HY916-cn/CursorMeter. Keep internal CodexMeter source paths and
  core type names for upstream comparison. Shared Xcode scheme: CursorMeter.
- Keep LSUIElement enabled and use native Apple frameworks. Installed official
  Cursor CLI access requires the current non-sandboxed app configuration.
- Store history under Application Support/CursorMeter; use .cursormeterbackup
  archives and com.huang.CursorMeter.pushCredentials for Keychain credentials.
- Sparkle 2.10.0 uses this repository's GitHub feed and Release assets. Preserve
  CursorMeter's independent public key, signed feed and archive verification.
  The private EdDSA key stays in login Keychain account com.huang.CursorMeter.
  Check daily; automatic installation and prerelease inclusion default off.
- Upload and verify downloadable Release assets before publishing the signed
  appcast. Validate install/relaunch using an isolated app copy and preserve data.

## CLI integration and first run

- CodexMeterApp.swift owns the service, settings, history, and windows.
  CodexUsageService.swift adapts the installed official Cursor CLI. Keep CLI
  discovery, bounded process handling, parsing, and refresh policy testable in Core.
- Read account identity from nested `userInfo` in `agent status --format json`;
  use `agent about --format json` for supplementary plan/tier metadata. Query quota by starting interactive
  `agent` in a pseudo-terminal and entering `/usage` inside its terminal UI.
- Cursor owns authentication. Do not read authentication files, extract tokens,
  call undocumented direct usage HTTP endpoints, or submit model tasks to get quota.
  Official CLI startup may execute user-configured startup hooks or load MCP
  configuration. Do not claim these are disabled without verified CLI support.
- Users personally perform `agent login`, initial setup, and directory trust.
  Never auto-accept setup, trust, or permission prompts. Handle sign-out and
  incomplete setup explicitly with a link to README's `#first-run` tutorial.
- The tutorial must prominently show this sequence: official installer at
  https://cursor.com/install; verify `agent --version` and ~/.local/bin PATH;
  `agent login`; create and enter ~/Library/Application Support/CursorMeter/CLI;
  launch `agent`; complete prompts personally; enter `/usage` in the TUI and
  confirm real quota; then open CursorMeter. Retain GitHub IMPORTANT/WARNING
  callouts and concrete repair instructions. Login alone does not finish setup.
- Set child PWD to the dedicated CLI directory. Desktop launches must use the
  same environment and directory semantics as the tested CLI integration.
- Terminal output is unstable. Require complete recognized quota panels, bound
  runtime/output, drain output, clean up child processes, and show locally authored
  errors rather than exposing raw CLI output.

## Data and UI invariants

- Preserve configurable menu bar/popover, independent history/settings windows,
  backup/restore, accessibility, notifications, localization, and developer previews.
- Cursor's official 2026.07.13 CLI changelog describes included Auto/API pools,
  on-demand spend against a limit, plan names, and billing reset dates. Parse
  supported data actually returned; do not assume every account exposes all fields.
- Keep window names and periods dynamic. Quota is `100 - usedPercent`, clamped
  to 0...100. Do not turn missing values or unsupported output into zero use.
- The verified live panel showed Premium, Included/Auto/API quota pools, an
  on-demand spend amount, and No monthly limit. Treat these as one observed
  account, not guarantees for every plan. Keep returned windows selectable.
- Only derive percentages from monetary values when a valid budget denominator
  is present. An unlimited on-demand budget does not yield a remaining percentage.
- Live reset output supplies month/day text such as `Resets Nov 1`, without a
  year, exact time, or cycle start. Display that text as returned; current output
  does not support an exact countdown, time progress, or pace estimation. Never
  fabricate the missing fields or assume a fixed billing-cycle duration.
- Token activity, daily token counts, and banked reset opportunities stay
  unavailable when not supplied. Never infer token counts from quota percentages.
- Partition history using salted account identity; never persist raw CLI output,
  authentication data, or email. Clear visible old-account quota on identity change.
- Restore the last account-scoped history snapshot as stale with its observation
  date intact. Do not let delayed history reads overwrite fresh results or trigger
  quota alerts. Failed refreshes keep the last good sample and mark it stale.
- Missing account identity permits live display only; pause persistence and alerts.
- Poll every 10 seconds with the popover open and every 60 seconds in background.
  Popover-open/wake refreshes require at least 10 seconds since the last attempt.
  Manual refreshes also require 10 seconds. Keep single-flight protection and
  honor failure cooldowns; cached/rate-limited responses back off 5, 10, 20,
  then 30 minutes and recover to normal scheduling after success.
- Record successful non-stale changes and periodic 15-minute history anchors.
  Preserve cycle boundaries, calendar browsing, missing-data shading, raw samples,
  conservative consumption estimates, and account-scoped CSV exports.
- Backups preserve every account partition. Keep them transactionally consistent,
  bounded, integrity-checked, and recoverable after interruptions. Restore replaces
  history and pauses writes until restart; preserve the user's credentials.
- Push channels default off, use HTTPS without redirects, keep credentials in
  Keychain, redact diagnostics, and retain bounded retry/deduplication. Preview
  data must never enter live history or send notifications.
- Keep English, Simplified Chinese, and Traditional Chinese strings synchronized
  in Localizable.xcstrings. Keep source comments in English.

## Verification and maintenance

Inspect repository state before editing and scope changes to the task. Keep
README.md and this guide aligned with implementation and verified limitations.
Do not claim authenticated account acceptance based on fixture tests alone.

```bash
swift test
bash Scripts/test_cursor_cli.sh
bash Scripts/test_cursor_recovery.sh
bash Scripts/test_cursor_service.sh
bash Scripts/test_push_service.sh
bash Scripts/build_local.sh
git diff --check
xcodebuild -project CodexMeter.xcodeproj -scheme CursorMeter \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Use full Xcode when selected tools lack XCTest or the required SwiftUI macros.
The local build uses a recent Swift compiler, compatible macOS SDK, Python 3,
iconutil, and ad-hoc signing; the script supports the installed 26.5 SDK.
Run push tests with fake credentials and isolated responses, without contacting
real notification endpoints. Test login items and notification permissions in
an actual signed app. UI changes require launching one app instance and checking
the affected menu-bar and window controls. Live quota acceptance requires a
personally initialized Cursor CLI session and successful authenticated `/usage`
refresh from the app launched through Launch Services.

Commit completed changes. Push major changes to the user-authorized repository;
upstream attribution does not authorize writes to an upstream project.
