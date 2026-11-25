# Changelog

All notable changes to **AltDeck** will be documented in this file.

## [v1.0.2] — 2026-11-25

### What's New & Fixed / 更新内容与修复
- **True MRU Window Ordering / 真正的最近使用（MRU）窗口排序**: Replaced app-grouped Z-order sorting with true Most Recently Used window + app ordering so index 1 is always the exact previous window you were on, even when the current app has multiple windows.
- **Instant Quick `⌘Tab` Switching / 快速 `⌘Tab` 秒切上一个窗口**: Immediately commits when the hold modifier is already released on fast tap-and-release gestures instead of waiting for polling.
- **Multi-Monitor Window Moving (`D`) & Size Preservation / 多显示器循环切屏与尺寸保持**:
  - `D` now reads live window bounds via Accessibility on every press so pressing `D` repeatedly cycles smoothly across all connected displays.
  - Preserves original window width and height when moving between displays of different resolutions (clamping only when the target display is smaller).
- **Reliable In-Switcher Shortcuts After Sleep/Wake / 休眠唤醒后快捷键自动恢复**: Added `CGEventTap` self-healing (`ensureTapActive()`) on switcher open and system wake so `P`, `D`, `S`, `W`, `M`, `Space`, and arrow keys stay responsive.

## [v1.0.1] — 2026-11-14

### What's New & Fixed / 更新内容与修复
- **In-App Auto Updater / 应用内自动更新**: Periodic background checks against GitHub Releases, bilingual update window with release notes, strict code-signature + Bundle ID + Team ID verification, and atomic replace & relaunch (plus safe recovery & Finder reveal if macOS blocks overwrite).
- **Menu Bar Logo / 菜单栏专属图标**: Replaced the generic system symbol with AltDeck's stacked-cards vector template icon (adapts automatically to Light & Dark menu bars).
- **Mouse Hover Controls / 鼠标悬停防误触与开关**: Added stationary-cursor guard (`> 4pt` movement unlock after opening) and a **"Select Window on Mouse Hover / 鼠标悬停选中窗口"** toggle under **Settings → Features** (enabled by default).
- **Thumbnail & Browser Tab Stability / 缩略图与浏览器标签稳定性优化**:
  - Removed background Arc AppleScript polling during normal window pre-warming so closed browsers are never launched unexpectedly.
  - Added coalesced ScreenCaptureKit capture with bounded concurrency and fallback handling so rows 3+ thumbnails render reliably.
- **Native macOS Window Behavior & Website Link / 标准窗口快捷键与官网直达**:
  - Enabled Minimize (`⌘M` & yellow traffic light) and standard `⌘W` / `⌘,` / `⌘Q` / `⌘C`/`⌘V`/`⌘A` shortcuts in Settings, Software Update, and Onboarding windows.
  - Added direct **Official Website (`https://altdeck-two.vercel.app/`)** links in the menu bar and Settings → General.

## [v1.0.0] — 2026-11-13
- Initial public Universal (`arm64` + `x86_64`) notarized macOS release of **AltDeck**.
