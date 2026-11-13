/* ==========================================================================
   AltDeck Website Localization (EN / 简体中文)
   Non-destructive DOM text node translator preserving inline markup & SVGs.
   ========================================================================== */
(function () {
  const STORAGE_KEY = "altdeck-lang";

  // Exact normalized-English -> Simplified Chinese translation map
  const ZH_MAP = {
    // <title> & Navbar
    "AltDeck — Fast Native macOS Window Switcher & Alt-Tab Alternative": "AltDeck — 极速原生 macOS 窗口切换器与 AltTab 替代品",
    "v1.0 Open Source": "v1.0 开源版",
    "Why AltDeck": "为什么选择",
    "Interactive Demo": "在线交互演示",
    "Comparison": "功能对比",
    "Open Source": "免费开源",
    "Shortcuts": "快捷键",
    "FAQ": "常见问题",
    "Get Free": "免费下载",

    // Hero
    "✦ Pure Swift + AppKit": "✦ 纯正 Swift + AppKit 原生构建",
    "Native Liquid Glass": "原生液态玻璃",
    "Free & Open Source (MIT)": "永久免费开源 (MIT)",
    "The window switcher macOS was destined to have.": "macOS 本该如此的窗口切换体验。",
    "Apple’s ⌘Tab was conceived in 1984 for whole applications. Today, our real work spans dozens of windows, tabs, and displays. AltDeck brings native Liquid Glass aesthetics, sub-millisecond responsiveness, natural hold-to-preview, browser tab jumping, and modular window tiling into one clean, tactile gesture.": "苹果的 ⌘Tab 诞生于 1984 年，只以“应用”为单位切换。但今天的工作同时跨越数十个窗口、浏览器标签和外接屏幕。AltDeck 将原生液态玻璃美学、亚毫秒级响应、自然悬停预览、浏览器标签直达与模块化窗口分屏，融于一个利落的指尖手势。",
    "View on GitHub (v1.0)": "查看 GitHub (v1.0)",
    "Try Interactive Sandbox": "体验交互沙盒",
    "macOS 14+ (Native Liquid Glass on macOS 26+)": "支持 macOS 14+（macOS 26+ 原生液态玻璃）",
    "Apple Silicon & SwiftPM Open Source": "支持 Apple Silicon 与 SwiftPM 源码构建",

    // Hero Stage
    "AltDeck HUD — Active Option+Tab Strip": "AltDeck 悬浮条 — Option+Tab 窗口列表",
    "Liquid Glass • ScreenCaptureKit": "液态玻璃 • ScreenCaptureKit",
    "Same-App Window Cycle": "同应用窗口切换",
    "Isolate Xcode or Browser windows": "快速轮换同一应用下的多个窗口",
    "Floating PiP & Ghost Mode": "画中画置顶与幽灵穿透",
    "Live SCStream mirror + click-through": "SCStream 实时镜像 + 鼠标点击穿透",

    // Section: Why AltDeck
    "The Competitive Edge": "核心竞争力",
    "Why we are good.": "为何出众。",
    "What we do that others cannot.": "做到他人做不到的体验。",
    "We did not merely rebuild AltTab or skin a legacy window picker. We solved the structural shortcomings of the macOS WindowServer and built capabilities unavailable in any other utility on Earth.": "我们并非简单复刻 AltTab，更不是给老工具套壳。AltDeck 从 macOS WindowServer 底层重新设计，解决了同类工具长期存在的结构性卡顿与局限。",

    "Unprecedented Capability": "突破性能力",
    "Deep Browser Tab Traversal": "深入浏览器标签页直达",
    "✕ AltTab & ⌘Tab: Treat browser as 1 opaque block": "✕ ⌘Tab 与传统工具：整个浏览器只算作 1 个应用块",
    "✓ AltDeck: Direct tab-level jumping": "✓ AltDeck：一键按标签页精准直达",
    "Every other switcher sees Google Chrome or Safari as a single opaque block. AltDeck keeps your default strip uncluttered with apps & windows only—then press": "其他切换器只能把 Chrome 或 Safari 当成一个黑盒。AltDeck 默认主列表只显示应用与窗口，保持干净清爽——只需随时按下",
    "anytime for instant, pre-warmed switching across live Chrome, Safari, Edge, Arc, and Brave tabs (or mix tabs in by default in Settings).": "即可毫秒级展开并切换 Chrome、Safari、Edge、Arc 与 Brave 的实时标签页（也可在设置中开启默认混排）。",
    "⚡ Live Browser Tabs discovered across Chrome, Safari & Arc:": "⚡ 已秒级预加载 Chrome、Safari 与 Arc 实时标签页：",
    "Arc Browser • 3m ago": "Arc 浏览器 • 3 分钟前",
    "Safari • Live": "Safari • 实时",
    "Chrome • 5m ago": "Chrome • 5 分钟前",

    "On-Demand SCStream": "按需启动 SCStream",
    "Live Floating PiP + Ghost Mode": "实时画中画置顶 + 幽灵模式",
    "Press": "按下",
    "to pin any window in an on-demand": "即可将任意窗口钉选为按需驱动的",
    "live mirror. Watch builds or videos while Ghost Mode lets mouse clicks pass straight through.": "实时画面悬浮窗。看编译进度或视频的同时，开启幽灵模式可让鼠标直接穿透操作下层软件。",
    "Live SCStream Mirror": "SCStream 实时镜像",

    "Thumbnails First": "缩略图优先",
    "Thumbnails Only & Hold-to-Preview": "仅缩略图模式与停顿预览",
    "Ships in clean": "默认采用极简直观的",
    "Thumbnails Only": "仅缩略图",
    "mode with subtle shortcut hints by default, or switch to minimalist": "模式并附带底部快捷提示，也可随心切换至纯图标",
    "Icons Only": "仅应用图标",
    ": pause ~0.36s on an icon while holding": "模式：按住切换键并在图标上停顿约 0.36 秒",
    "for a Retina preview—or lock it anytime with": "即可浮现 Retina 实时预览——随时按",
    ".": "锁定查看。",
    "Hold-to-Preview HUD": "停顿悬停预览",
    "Pause 0.36s · Space": "停顿 0.36s · Space 锁定",

    "Modular Control": "自由定制",
    "Toggleable Arrow-Key Tiling": "可开关的方向键分屏贴靠",
    "Tap": "按",
    "to cycle 1/2, 1/3, and 2/3 screen splits,": "可在 1/2、1/3、2/3 屏幕分栏间循环切换，按",
    "to maximize/restore, or": "最大化或还原窗口，按",
    "to center. Prefer pure arrow navigation? Flip it off in": "居中 70%。只想用方向键选窗口？在",
    "Settings → Features": "设置 → 功能",
    "so": "中一键关闭，让",
    "rotate icons instead.": "恢复为左右移动焦点。",
    "Works in Tiling mode (1/2 ➔ 1/3 ➔ 2/3) or Icon Rotation mode": "支持分屏贴靠（1/2 ➔ 1/3 ➔ 2/3）与纯光标移动两种模式随心切换",

    "Multi-Monitor Perfection": "多屏无缝协同",
    "Cursor Monitor & Key: D Teleport": "随鼠标唤出与 D 键一键跨屏",
    "AltDeck opens automatically on whichever monitor your cursor is on. Need to move a window across dual Studio Displays or an ultrawide? Press": "切换器总会自动出现在你当前鼠标所在的显示器上。想把窗口甩到外接 Studio Display 或副屏？只需按下",
    "to teleport it to the next screen.": "即可瞬间跨屏传送。",
    "1-Key Display Teleport": "单键跨屏传送",
    "No dragging across giant desktops": "告别在大屏之间拖拽窗口",

    "Architectural Masterclass": "底层架构保障",
    "Crash-Safe SkyLight WindowServer ⌘Tab Override": "防崩溃级 SkyLight 系统 ⌘Tab 接管与自动恢复",
    "Many users want to replace the macOS default ⌘Tab completely, but traditional utilities use dangerous hacks that can leave your system switcher permanently broken if the app terminates unexpectedly. AltDeck communicates directly with SkyLight WindowServer SPI via": "很多用户希望能彻底用 AltDeck 接管系统自带 ⌘Tab，但粗糙的修改手段一旦崩溃，常导致系统快捷键彻底失灵。AltDeck 直接通过",
    ", accompanied by POSIX signal handlers (SIGINT, SIGTERM, SIGHUP) that restore Apple's native switcher instantaneously upon termination or quit.": "与 SkyLight WindowServer 通信，并注册 POSIX 信号捕获（SIGINT、SIGTERM、SIGHUP），一旦退出或异常终止立即还原系统原生 ⌘Tab。",
    "100% Fail-Safe Guarantee": "100% 安全兜底",
    "If AltDeck is closed, native ⌘Tab is restored before the next frame is drawn.": "只要 AltDeck 退出，下一帧绘制前即自动恢复原生 ⌘Tab。",

    // Interactive Sandbox
    "Interactive Simulator": "在线交互模拟器",
    "Feel the speed.": "亲手体验速度。",
    "Right here in your browser.": "直接在网页中试用。",
    "Test the exact physics and gestures of AltDeck. Use your keyboard (": "亲自感受 AltDeck 的交互逻辑与快捷键。你可以直接敲击键盘（",
    ", Arrow keys,": "、方向键、",
    ") or click the controls below.": "），或点击下方的模拟控制按钮。",
    "Live HUD Simulation": "实时 HUD 模拟面板",
    "— Press": "— 按",
    "or": "或",
    "to cycle,": "轮换窗口，按",
    "for Quick Look,": "快速预览，按",
    "for PiP.": "开启画中画。",
    "Ready. Press Tab to cycle.": "已就绪，请按 Tab 键切换窗口。",
    "Next": "下一个",
    "Peek": "预览",
    "Snap": "贴靠",
    "PiP": "画中画",
    "Display": "跨屏",
    "Tabs": "标签页",
    "Close": "关闭",
    "Release modifier to activate": "松开修饰键立即激活选中窗口",
    "Xcode • Active Window": "Xcode • 当前激活窗口",
    "✕ Close (Esc)": "✕ 关闭 (Esc)",
    "Pinned Window": "已置顶窗口",
    "● Floating Window Mirror": "● 悬浮窗实时镜像",
    "Toggle Ghost Mode for click-through opacity": "开启/关闭幽灵模式与鼠标穿透",
    "← Previous Window": "← 上一个窗口",
    "Next Window →": "下一个窗口 →",
    "Browser Tabs (S)": "浏览器标签页 (S)",
    "Toggle Spacebar Quick Look": "空格快速预览 (Space)",
    "Toggle Floating PiP (P)": "置顶画中画 (P)",
    "Snap Left Half (←)": "左半屏贴靠 (←)",
    "Snap Right Half (→)": "右半屏贴靠 (→)",

    // Sandbox Mock Window Cards
    "Xcode • AltDeck Project": "Xcode • AltDeck 工程",
    "Google Chrome • GitHub": "Google Chrome • GitHub",
    "Terminal • AltDeck Build": "终端 • AltDeck 构建",
    "Figma • Architecture Drafts": "Figma • 架构设计稿",

    // Comparison Table
    "Objective Benchmark": "客观能力对比",
    "How AltDeck compares.": "与众不同的硬实力。",
    "See why demanding engineers, designers, and power users choose AltDeck over legacy tools and Apple’s built-in switcher.": "看看为什么越来越多工程师、设计师与效率玩家选择用 AltDeck 替代系统自带切换器与老牌付费工具。",
    "Multitasking Capability": "核心多任务能力",
    "Apple ⌘Tab (macOS Native)": "Apple ⌘Tab（系统原生）",
    "Standard AltTab Utilities": "常规 AltTab 类工具",
    "AltDeck (Pure Swift)": "AltDeck（纯 Swift 原生）",

    "Individual Window Selection": "精细到单窗口的切换",
    "Switch directly to a specific window rather than just the parent application": "直接切换至某个具体窗口，而不是笼统把整个应用全部前置",
    "✕ App-level only": "✕ 仅支持应用级切换",
    "✓ Yes": "✓ 支持",
    "Instant AXUI": "瞬时 AXUI 唤醒",

    "Native Liquid Glass & Adaptive Layout": "原生液态玻璃与自适应网格",
    "macOS 26+ NSGlassEffectView, Clear Glass, Solid matte, Light/Dark themes & auto-scaling grid": "支持 macOS 26+ NSGlassEffectView、通透玻璃、深浅主题与窗口数量自适应换行排版",
    "✓ System Native": "✓ 系统原生外观",
    "✕ Fixed Strip": "✕ 固定单行长条",
    "Auto-Scale": "自适应缩放",

    "Modern ScreenCaptureKit Engine": "现代 ScreenCaptureKit 采集引擎",
    "On-demand Retina capture strictly matching each window’s native aspect ratio": "按需捕获 Retina 清晰度缩略图，严格保持每个窗口原生纵横比",
    "✕ No Thumbnails": "✕ 无窗口画面预览",
    "✕ Legacy CGWindowList": "✕ 老旧 CGWindowList",
    "Zero Letterbox": "无黑边裁切",

    "Captures Fully Covered Windows": "捕获被完全遮挡的底层窗口",
    "Renders live window contents even when occluded by other full-screen apps": "即使目标窗口被其他全屏应用挡住，依然能实时抓取最新画面",
    "✕ None": "✕ 不支持",
    "✕ Partial / Stale": "✕ 易失效/旧缓存",
    "✓ 100% Supported": "✓ 100% 完整支持",

    "Deep Browser Tab Switching": "浏览器标签页直达",
    "Surfaces individual browser tabs from Chrome, Safari, Edge, Arc & Brave": "按 S 即可一键展开并直达 Chrome、Safari、Edge、Arc、Brave 的各个标签页",
    "✕ Not supported": "✕ 不支持",
    "✓ Native Tab Hooks": "✓ 原生标签联动",
    "Toggleable": "按需展开/可配置",

    "Floating Picture-in-Picture & Ghost Mode": "悬浮画中画置顶与幽灵穿透",
    "On-demand ScreenCaptureKit live stream mirror with opacity & Ghost click-through": "任意窗口一键变身 30fps 实时悬浮画中画，支持透明度与鼠标穿透",
    "✕ Video only": "✕ 仅支持视频播放",
    "✓ Live SCStream PiP": "✓ 实时 SCStream PiP",
    "Optional": "可选开关",

    "Hold-to-Preview & Spacebar Quick Look": "图标悬停预览与空格放大",
    "Auto-peeks cleanly on icon pause without cluttering quick switches": "仅图标模式下停顿自动预览，快速切屏零干扰，按空格即锁定大预览",
    "✓ Pause + Space": "✓ 悬停 + 空格预览",

    "Modular Arrow Keys (Tiling or Rotation)": "方向键分屏或移动焦点自由切换",
    "Snap halves/thirds/maximize or switch cleanly to left/right icon rotation in Settings": "默认支持 1/2、1/3、2/3 快速分屏，也可在设置里一键改为纯方向键选窗",
    "✕ Manual Drag": "✕ 仅支持手动拖拽",
    "✓ Arrow Navigate": "✓ 仅方向键移动",
    "✓ Both Modes Toggleable": "✓ 两种模式均可切换",

    "Multi-Display Teleport (Key: D)": "一键跨屏移动窗口 (按 D)",
    "Throw the active window to an external display in a single keystroke": "无需拖拽窗口跨越双屏，单键将目标窗口直接甩到下一台显示器",
    "✕ Drag across screens": "✕ 需手动跨屏拖拽",
    "✓ 1-Key Multi-Monitor": "✓ 单键跨多显示器",

    "Instant Dismiss & Featherweight Binary": "瞬时收起与超轻量原生体积",
    "Xcode Live Mirror": "Xcode 实时镜像",
    "Terminal — Logs": "终端 — 构建日志",
    "2-Tier": "双层",
    "0 Telemetry": "零遥测",
    "Liquid Glass": "液态玻璃",
    "APIs.": "API 接口。",
    "Synchronous ~0.5ms panel dismiss inside a tiny 1.5 MB native Swift + AppKit bundle": "松手瞬间 ~0.5ms 同步收起 HUD，整个原生 Swift + AppKit 安装包仅约 1.5 MB",
    "✓ WindowServer Native": "✓ 系统窗口服务原生",
    "Heavier Bundle": "体积偏重",
    "✓ 1.5 MB Native Swift": "✓ 1.5 MB 纯 Swift 原生",

    "Telemetry & Analytics": "遥测追踪与隐私收集",
    "Zero analytics beacons, zero usage tracking, 100% open-source MIT Swift": "零埋点、零遥测数据上报，MIT 协议完全开源可审计",
    "Apple System Telemetry": "包含系统级遥测",
    "Varies": "视实现而定",
    "✓ Zero Telemetry": "✓ 零遥测零联网",

    "Safe ⌘Tab Interception with Auto-Restore": "安全接管 ⌘Tab 与退避还原",
    "SkyLight private SPI with crash-proof POSIX signal restoration": "通过 SkyLight SPI 安全拦截并配备 POSIX 信号捕获，退出瞬间自动恢复",
    "Default": "系统默认",
    "Manual Reset": "需手动恢复",
    "✓ Crash-Safe Fail-Safe": "✓ 崩溃自动安全恢复",

    // Specs Section
    "System Architecture": "底层工程架构",
    "Engineered for raw speed.": "为纯粹速度而生。",
    "AltDeck is crafted with obsessive discipline. No web frameworks, no bloated bundles, and zero compromises on battery life.": "AltDeck 以近乎洁癖的性能标准打磨：拒绝重型网页壳，拒绝多余依赖，全天候后台零负担。",
    "Synchronous Dismiss": "同步零延迟收起",
    "Key release orders out the HUD synchronously (": "松开修饰键的瞬间，通过 WindowServer flush 同步（",
    ") via WindowServer flush while AXUIElement & browser activation run off the main thread.": "）完成界面收起，同时将 AXUIElement 与浏览器窗口前置卸载到后台队列，彻底告别卡顿。",
    "Tiny App Bundle": "约 1.5 MB 轻量体积",
    "Zero Electron, zero Chromium runtime, zero bundled frameworks. Compiled directly to native machine code via Swift Package Manager.": "无 Electron、无 Chromium 内核、无臃肿运行时，通过 Swift Package Manager 直接编译为原生机器码。",
    "On-Demand Architecture": "按需唤醒零空转",
    "Driven by": "仅由",
    ", background window cache refresh, and ScreenCaptureKit snapshots only when needed—never polling at 60fps in the background.": "事件触发与增量窗口缓存驱动，绝不在后台以 60fps 持续轮询偷电。",
    "Retina Aspect Cache": "双层原比例画质缓存",
    "Separates thumbnail strip captures from full-resolution previews while strictly preserving each window’s real aspect ratio—zero black bars.": "列表缩略图与大图预览分级缓存，严格遵循窗口真实宽高比，零黑边畸变。",
    "Private & Auditable": "离线隐私可审计",
    "Zero analytics SDKs, zero tracking beacons, zero auto-updaters phoning home. Read every line of Swift source yourself under MIT.": "零分析 SDK、零埋点上报、零静默联网。MIT 开源协议下每一行 Swift 代码均公开透明。",
    "Native macOS Aesthetics": "原生液态玻璃美学",
    "Supports Apple": "支持苹果原生",
    "on macOS 26+, Clear Glass, and Solid matte surfaces with Light/Dark themes and continuous squircle geometry.": "（macOS 26+）、通透玻璃与纯色磨砂材质，搭配连续超椭圆圆角与自定义高亮主题。",

    // Shortcuts Section
    "Intuitive Control": "肌肉记忆操控",
    "Shortcuts designed for muscle memory.": "符合直觉的快捷手势。",
    "Every command is an extension of standard macOS conventions. Customize any trigger chord inside AltDeck Preferences (": "每个按键都延续 macOS 原生使用习惯，且均可在设置界面（",
    ").": "）中自由录制或按需关闭。",
    "Next Window": "切换下一窗口",
    "Opens switcher & advances selection (+Shift for reverse)": "打开切换栏并切换选中（搭配 Shift 反向选择）",
    "Cycle Same Application": "同应用窗口轮换",
    "Isolates windows of the active app without leaving context": "只过滤当前活跃应用的多个窗口，专注工作流",
    "Hold": "停顿",
    "Pause": "悬停",
    "Hold-to-Preview (Icons Only)": "悬停预览（仅图标模式）",
    "Rest briefly (~0.36s) on an icon to auto-peek; hides as soon as you switch": "按住停留在应用图标约 0.36 秒自动预览窗口，切换即收起",
    "Persistent Quick Look": "空格常驻预览",
    "Locks/toggles live window preview while navigating (toggleable)": "在选中卡片时按空格锁定放大预览（可在设置中关闭）",
    "Pin Picture-in-Picture": "置顶悬浮画中画",
    "Pins window floating on top with Ghost click-through (toggleable)": "将目标窗口置顶为支持鼠标穿透的画中画浮窗（可开关）",
    "Snap Halves & Thirds / Rotate": "分屏贴靠 / 光标移动",
    "Cycles 1/2 ➔ 1/3 ➔ 2/3 tiling, or rotates icons when tiling is off": "循环切换 1/2 ➔ 1/3 ➔ 2/3 分栏贴靠，关闭分屏后则用于左右选中",
    "Maximize & Restore Window": "最大化与还原尺寸",
    "Fills current monitor or restores geometry (": "铺满当前显示器或一键还原尺寸（",
    "centers at 70%)": "以 70% 比例屏幕居中）",
    "Display Dispatcher": "跨显示器移动",
    "Teleports target window to the next physical display": "把当前选中的窗口直接传送到下一台显示器",
    "Browser Tabs Filter": "浏览器标签直达",
    "Jump directly to open tabs across Chrome, Safari, Arc, Edge & Brave": "一键过滤显示 Chrome、Safari、Arc、Edge 与 Brave 标签页",
    "Close Window": "关闭选中窗口",
    "Closes the selected window immediately": "立即关闭当前选中的窗口",
    "Minimize Window": "最小化窗口",
    "Stashes target window into the Dock": "将当前选中的窗口最小化收入程序坞",

    // Open Source Section
    "✦ 100% Free & Open Source": "✦ 100% 永久免费开源",
    "MIT License": "MIT 开源协议",
    "Zero Paywalls": "零付费墙",
    "Crafted for people, not for profit.": "为人而写，而非逐利。",
    "Not everything in life needs to be monetized. We built AltDeck to solve real frustrations with macOS window multitasking. Every single superpower—from deep browser tab traversal to interactive Picture-in-Picture—is completely free, open source, and yours forever.": "并非每一款工具都要用“Pro 会员订阅”卡住好功能。我们做 AltDeck 只是为了解决自己在 macOS 上切窗口切标签页时的真实痛点。所有能力——从跨浏览器标签直达到实时画中画置顶——全部免费开源，永远属于每一位用户。",
    "Zero Paywalls. No Pro Tier.": "零付费墙，无 Pro 收费档。",
    "Every feature is fully unlocked out of the box. No trial clocks, no watermark nag screens, no subscription traps, and no gated \"Pro\" tiers.": "安装即解锁全部能力。没有试用倒计时、没有弹窗催付、没有订阅陷阱，更不拆分成“基础版 / Pro 收费版”。",
    "Air-Gapped Privacy & Trust": "彻底本地离线与隐私守护",
    "Screen recording and accessibility permissions stay 100% private. Zero network sockets, zero tracking beacons. Inspect every single line of Swift code yourself.": "所有窗口数据与画面均在本地内存瞬时处理，零网络请求、零统计上报，每行代码都经得起开源审查。",
    "Community Driven on GitHub": "GitHub 社区共建",
    "Openly licensed under MIT. Built with love for developers, designers, and power users. Star the repo, file issues, submit PRs, or fork it freely.": "基于宽松的 MIT 协议开源。欢迎点亮 Star、在 GitHub 提交想法、Issue 或 Pull Request，想要什么新功能都可以一起来完善。",
    "Star on GitHub ★": "在 GitHub 点亮 Star ★",
    "Download AltDeck Free": "免费获取 AltDeck",

    // FAQ
    "Answers & Clarity": "答疑解惑",
    "Frequently asked questions.": "常见问题解答。",
    "Everything you need to know about architecture, security, permissions, and licensing.": "关于底层架构、权限说明、安全保障与开源协议的一切解答。",
    "How does AltDeck differ from AltTab for Mac?": "AltDeck 和老牌的 AltTab 有什么区别？",
    "While AltTab is a pioneer in bringing the Windows-style switcher to macOS, AltDeck was built from scratch in pure Swift and AppKit. AltDeck v1.0 delivers macOS 26+ native Liquid Glass (": "AltTab 率先在 macOS 上带来了缩略图切窗体验，而 AltDeck 则是从零开始使用纯 Swift 与 AppKit 打造。AltDeck v1.0 原生支持 macOS 26+ 液态玻璃（",
    "), natural Hold-to-Preview on pause in Icons Only mode, deep browser tab switching across Chrome/Safari/Edge/Arc/Brave, floating Picture-in-Picture, and a Settings → Features tab letting you enable or disable every power feature individually.": "）、仅图标模式悬停自动预览、跨 Chrome/Safari/Edge/Arc/Brave 的按 S 键直达浏览器标签、实时画中画置顶，以及可在「设置 → 功能」单独开关每一项高阶特性的模块化控制。",
    "Is AltDeck completely free and open source?": "AltDeck 真的是完全免费且开源的吗？",
    "Yes, 100% free and open source under the MIT License.": "是的，基于 MIT 开源协议 100% 免费且完全开源。",
    "Every capability—including Liquid Glass themes, Hold-to-Preview, browser tab switching, floating Picture-in-Picture, and window tiling—is unlocked forever with zero paywalls and zero subscriptions.": "包括液态玻璃主题、悬停预览、浏览器标签切换、悬浮画中画、窗口分屏在内的所有功能永久开放，绝无内购、无订阅、无收费门槛。",
    "Why did you make AltDeck entirely free instead of charging for it?": "为什么选择把所有功能完全免费开放，而不是做付费软件？",
    "Because not everything in software needs to be a business. We built AltDeck to solve real, daily frustrations with macOS multitasking, and we believe the best tools should be accessible to every creator, developer, and thinker. It is our gift to the Mac community.": "因为好用的桌面工具不该一上来就谈订阅变现。写 AltDeck 的初衷就是为了解决自己日常在 Mac 上找窗口的痛点，把它免费开源出来，是送给每一位 Mac 创作者与开发者的礼物。",
    "How can I support or contribute to AltDeck?": "如何支持或参与 AltDeck 的开发？",
    "The greatest way to support AltDeck is to": "支持我们最好的方式就是去 GitHub 为项目",
    "star the project on GitHub": "点亮一颗 Star",
    ", share it with colleagues and friends, report bugs on our issue tracker, and submit pull requests. Community word-of-mouth is what powers our growth.": "，也可以分享给身边使用 Mac 的朋友，或在 Issues 中留言告诉我们你还希望增加什么功能——呼声最高的新特性我们会优先跟进开发。",
    "Why does AltDeck ask for Accessibility, Screen Recording, and Automation?": "为什么 AltDeck 需要“辅助功能”、“屏幕录制”和“自动化”权限？",
    "macOS enforces strict TCC privacy boundaries:": "macOS 对系统权限实施严格的 TCC 隐私隔离：",
    "observes your hold modifier via": "仅用于监听切换快捷键并调用苹果",
    "and raises specific app windows through Apple’s": "API 精准激活窗口。",
    "powers live ScreenCaptureKit window thumbnails and on-demand Picture-in-Picture streams (never recorded to disk or sent over the network).": "仅用于在内存中实时渲染缩略图与画中画预览（绝不写盘、绝不上传网络）。",
    "Automation (optional, for": "自动化权限（可选，仅在按下",
    "is prompted once when you press": "时请求一次）用于获取 Chrome、Safari、Edge、Brave 或 Arc 中当前打开的标签页列表。你随时可以在",
    "to list open tabs in Chrome, Safari, Edge, Brave, or Arc. You can inspect or manage all three anytime inside": "读取各浏览器标签并直达切换。所有三项权限都可在应用内",
    "Settings → General": "设置 → 通用",
    "How does AltDeck discover tabs in Chrome, Safari, and Arc?": "AltDeck 是如何读取 Chrome、Safari、Arc 等浏览器标签页的？",
    "AltDeck queries the AppleScript scripting dictionaries of running browsers via a dedicated high-performance service. It enumerates window IDs and tab titles without injecting code or modifying browser processes. When you select a tab in AltDeck, it activates the target browser window and brings that exact tab to the front.": "AltDeck 通过后台专用的轻量服务向已运行的浏览器发起批量 AppleEvent 查询，既不向浏览器注入任何脚本，也不影响隐私扩展。选定后直接唤醒对应窗口并跳转到该精确标签页。",
    "Is it safe to replace macOS native Command-Tab?": "用 AltDeck 接管系统原生的 ⌘Tab 安全吗？",
    "Yes. Unlike fragile hacks, AltDeck communicates with the SkyLight WindowServer via": "完全安全。不同于暴力劫持方案，AltDeck 通过苹果底层",
    ". Crucially, AltDeck registers POSIX signal handlers (SIGINT, SIGTERM, SIGHUP) and termination hooks that restore Apple’s native Command-Tab immediately if AltDeck is ever quit or terminated.": "安全切换系统符号热键，并注册了 POSIX 信号保护钩子，无论正常退出还是意外终止都会在毫秒间还原原生 ⌘Tab。",
    "Does AltDeck run on Apple Silicon and macOS 26+ Liquid Glass?": "支持 Apple Silicon M 系列芯片和 macOS 26+ 液态玻璃吗？",
    "Yes. AltDeck runs natively on Apple Silicon Macs (M1 through M4) on macOS 14.0 Sonoma, macOS 15.0 Sequoia, and macOS 26+ (where it automatically uses native": "支持。AltDeck 原生编译支持 M1 至 M4 全系芯片以及 macOS 14 Sonoma、macOS 15 Sequoia 与 macOS 26+（自动启用苹果原生",
    "Liquid Glass). You can also build from source cleanly on Intel or Apple Silicon with": "液态玻璃质感）。无论是 Intel 还是 Apple Silicon，均可克隆仓库后一键执行",

    // Download CTA & Footer
    "Upgrade your macOS multitasking today.": "今天就开始升级你的 macOS 切屏效率。",
    "Free, open source, and built with love for power users. No subscriptions, no telemetry, no compromises.": "永久免费、MIT 开源、为真正重度工作流而生——零订阅、零追踪、零妥协。",
    "Download AltDeck v1.0": "免费下载 AltDeck v1.0",
    "Copy Build Command": "复制源码构建命令",
    "Version 1.0.0": "版本 1.0.0",
    "~1.5 MB App": "体积约 1.5 MB",
    "MIT Open Source": "MIT 开源",
    "macOS 14+ (Liquid Glass on 26+)": "macOS 14+（26+ 支持液态玻璃）",
    "A high-performance native macOS window switcher crafted with Swift and AppKit. Designed for developers, designers, and thinkers who demand absolute precision.": "用纯正 Swift 与 AppKit 锻造的高性能 macOS 原生窗口切换器。献给每一位追求极致流畅与精密掌控的开发者、设计师与创作者。",
    "Product": "产品",
    "Features": "功能特性",
    "Interactive Sandbox": "在线交互沙盒",
    "Comparison Matrix": "对比矩阵",
    "Technology": "技术栈",
    "Zero Electron": "零 Electron 架构",
    "Community": "社区",
    "GitHub Repository": "GitHub 源码仓库",
    "Report Issue": "问题反馈 / 提需求",
    "Release Notes": "更新日志",
    "License": "MIT 协议",
    "© 2026 AltDeck. Open source under MIT License. All product names, logos, and brands are property of their respective owners.": "© 2026 AltDeck. 基于 MIT 协议开源发布。文中提及的第三方商标均归其各自所有者。",
    "● All Systems Nominal (macOS 14/15/26+)": "● 全平台就绪 (macOS 14 / 15 / 26+)",
    "Accessibility": "辅助功能",
    "Screen Recording": "屏幕录制",
    "Automation (optional, for": "自动化控制（可选，按下",
  };

  const EN_MAP = Object.fromEntries(Object.entries(ZH_MAP).map(([en, zh]) => [zh, en]));

  let currentLang = "en";
  const trackedNodes = [];
  let isInitialized = false;

  function detectInitialLanguage() {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved === "zh" || saved === "en") return saved;
    } catch (_) {}
    return "en";
  }

  function normalizeText(str) {
    return str.replace(/\s+/g, " ").trim();
  }

  function collectTextNodes() {
    if (isInitialized) return;
    isInitialized = true;

    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!node.parentElement) return NodeFilter.FILTER_REJECT;
        const tag = node.parentElement.tagName;
        if (tag === "SCRIPT" || tag === "STYLE" || tag === "SVG" || node.parentElement.closest("svg")) {
          return NodeFilter.FILTER_REJECT;
        }
        if (node.parentElement.closest("#lang-toggle-btn")) {
          return NodeFilter.FILTER_REJECT;
        }
        const normalized = normalizeText(node.nodeValue || "");
        if (!normalized || !ZH_MAP[normalized]) return NodeFilter.FILTER_SKIP;
        return NodeFilter.FILTER_ACCEPT;
      },
    });

    let node;
    while ((node = walker.nextNode())) {
      const raw = node.nodeValue || "";
      const normalized = normalizeText(raw);
      const leadingMatch = raw.match(/^\s*/);
      const trailingMatch = raw.match(/\s*$/);
      trackedNodes.push({
        node,
        orig: raw,
        key: normalized,
        lead: leadingMatch ? leadingMatch[0] : "",
        trail: trailingMatch ? trailingMatch[0] : "",
      });
    }
  }

  function updateToggleUI(lang) {
    const btn = document.getElementById("lang-toggle-btn");
    if (!btn) return;
    btn.querySelectorAll(".lang-option").forEach((opt) => {
      opt.classList.toggle("is-active", opt.dataset.lang === lang);
    });
  }

  function applyLanguage(lang) {
    collectTextNodes();
    currentLang = lang === "zh" ? "zh" : "en";
    document.documentElement.lang = currentLang === "zh" ? "zh-CN" : "en";

    if (ZH_MAP["AltDeck — Fast Native macOS Window Switcher & Alt-Tab Alternative"]) {
      document.title =
        currentLang === "zh"
          ? ZH_MAP["AltDeck — Fast Native macOS Window Switcher & Alt-Tab Alternative"]
          : "AltDeck — Fast Native macOS Window Switcher & Alt-Tab Alternative";
    }

    for (const entry of trackedNodes) {
      if (currentLang === "zh") {
        entry.node.nodeValue = entry.lead + ZH_MAP[entry.key] + entry.trail;
      } else {
        entry.node.nodeValue = entry.orig;
      }
    }

    updateToggleUI(currentLang);

    try {
      localStorage.setItem(STORAGE_KEY, currentLang);
    } catch (_) {}

    window.dispatchEvent(new CustomEvent("altdeck:langchange", { detail: { lang: currentLang } }));
  }

  window.AltDeckI18n = {
    get lang() {
      return currentLang;
    },
    setLang(lang) {
      applyLanguage(lang);
    },
    t(en, zh) {
      return currentLang === "zh" ? zh : en;
    },
    translateText(text) {
      if (!text) return text;
      const key = normalizeText(text);
      if (currentLang === "zh") {
        return ZH_MAP[key] || text;
      }
      return EN_MAP[key] || text;
    },
  };

  document.addEventListener("DOMContentLoaded", () => {
    collectTextNodes();
    const initial = detectInitialLanguage();
    applyLanguage(initial);

    const toggleBtn = document.getElementById("lang-toggle-btn");
    if (toggleBtn) {
      toggleBtn.addEventListener("click", (e) => {
        const option = e.target.closest(".lang-option");
        const nextLang =
          option && option.dataset.lang
            ? option.dataset.lang
            : currentLang === "zh"
              ? "en"
              : "zh";
        applyLanguage(nextLang);
      });
    }
  });
})();
