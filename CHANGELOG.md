# Changelog

All notable changes to **AltDeck** will be documented in this file.

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
