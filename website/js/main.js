/**
 * AltDeck — Interactive Engine
 * Apple-Grade Precision • Keyboard Sandbox • Micro-Interactions
 */

document.addEventListener("DOMContentLoaded", () => {
  initHeroInteractions();
  initSandboxSwitcher();
  initCopyButtons();
  initHeaderBlur();
  initSmoothScroll();
  initFAQAccordion();
});

/* ==========================================================================
   Hero Micro-Interactions
   ========================================================================== */
function initHeroInteractions() {
  const heroCard = document.querySelector(".hero-stage-card");
  if (!heroCard) return;

  // Subtle 3D tilt on mousemove
  heroCard.addEventListener("mousemove", (e) => {
    const rect = heroCard.getBoundingClientRect();
    const x = e.clientX - rect.left - rect.width / 2;
    const y = e.clientY - rect.top - rect.height / 2;
    const rotateX = (y / (rect.height / 2)) * -3.5;
    const rotateY = (x / (rect.width / 2)) * 3.5;

    heroCard.style.transform = `perspective(1200px) rotateX(${rotateX.toFixed(2)}deg) rotateY(${rotateY.toFixed(2)}deg)`;
  });

  heroCard.addEventListener("mouseleave", () => {
    heroCard.style.transform = "perspective(1200px) rotateX(0deg) rotateY(0deg)";
  });
}

/* ==========================================================================
   Interactive Switcher Sandbox
   ========================================================================== */
function initSandboxSwitcher() {
  const cards = document.querySelectorAll(".switcher-card");
  const quickLookOverlay = document.getElementById("quicklook-modal");
  const pipOverlay = document.getElementById("pip-floating-demo");
  const snapNotice = document.getElementById("sandbox-snap-notice");
  const feedbackStatus = document.getElementById("sandbox-feedback-text");

  let currentIndex = 0;
  let isOptionHeld = false;
  let quickLookVisible = false;
  let pipVisible = false;
  let browserTabsMode = false;

  // Window Data for the Sandbox
  const appWindows = [
    {
      id: 0,
      title: "PreferencesWindowController.swift — AltDeck",
      app: "Xcode",
      icon: "assets/app-icon.png",
      badge: "SwiftPM",
      codePreview: `// AltDeck Settings & Hotkey Orchestration\nfinal class PreferencesWindowController: NSWindowController {\n    override func windowDidLoad() {\n        super.windowDidLoad()\n        setupHotKeyInterceptor()\n    }\n}`
    },
    {
      id: 1,
      title: "icaichen/altdeck: Native macOS Window Switcher",
      app: "Google Chrome",
      icon: "https://cdn.simpleicons.org/googlechrome/ffffff",
      badge: "GitHub PR #42",
      codePreview: `<!DOCTYPE html>\n<html>\n  <head><title>AltDeck Repository</title></head>\n  <body>\n    <h1>The window switcher macOS was destined to have.</h1>\n  </body>\n</html>`
    },
    {
      id: 2,
      title: "zsh — ./build-app.sh release",
      app: "Terminal",
      icon: "https://cdn.simpleicons.org/apple/ffffff",
      badge: "PID 4192",
      codePreview: `$ ./build-app.sh release\n[✓] Building AltDeck (release mode)...\n[✓] ScreenCaptureKit framework linked.\n[✓] Ad-hoc codesign verified.\n[✓] App: /Applications/AltDeck.app ready.`
    },
    {
      id: 3,
      title: "Design System: Liquid Glass Tokens",
      app: "Figma",
      icon: "https://cdn.simpleicons.org/figma/ffffff",
      badge: "AltDeck HUD",
      codePreview: `// Native Glass Design Tokens\nconst Tokens = {\n  Surface: 'NSGlassEffectView (.regular / .clear)',\n  HUD_CornerRadius: 22,\n  DismissLatency: '< 1ms Synchronous'\n};`
    }
  ];

  const browserTabs = [
    {
      id: 0,
      title: "icaichen/altdeck — GitHub",
      app: "Google Chrome • github.com",
      icon: "https://cdn.simpleicons.org/googlechrome/4285f4",
      badge: "Window 1 · Tab 1",
      codePreview: `// AltDeck BrowserTabService (Batch AppleEvents)\n// Instant switching to Chrome Window 1, Tab 1\nhttps://github.com/icaichen/tabstation`
    },
    {
      id: 1,
      title: "ScreenCaptureKit SCStream Docs",
      app: "Safari • developer.apple.com",
      icon: "https://cdn.simpleicons.org/safari/006cff",
      badge: "Window 1 · Tab 3",
      codePreview: `// Apple Developer Documentation\nclass SCStream: NSObject\n// Powers live Option-B Picture-in-Picture & thumbnails`
    },
    {
      id: 2,
      title: "Linear — AltDeck v1.0",
      app: "Arc • linear.app",
      icon: "https://cdn.simpleicons.org/arc/fcbf49",
      badge: "Window 1 · Tab 2",
      codePreview: `// Issue #14: Instant S-Key Browser Tab Filter\n// Status: Shipped with background pre-warming`
    },
    {
      id: 3,
      title: "Figma — macOS Switcher Tokens",
      app: "Google Chrome • figma.com",
      icon: "https://cdn.simpleicons.org/figma/f24e1e",
      badge: "Window 2 · Tab 1",
      codePreview: `// Figma Design Tokens\nhttps://www.figma.com/file/altdeck-hud-v1`
    }
  ];

  const defaultCardSnapshots = Array.from(cards).map((card) => ({
    title: card.querySelector(".card-title")?.textContent || "",
    app: card.querySelector(".card-app-name")?.textContent || "",
    iconSrc: card.querySelector(".card-app-icon-badge")?.getAttribute("src") || ""
  }));

  function activeItems() {
    return browserTabsMode ? browserTabs : appWindows;
  }

  let windows = appWindows;

  function updateSelection(newIndex, showToast = true) {
    if (cards.length === 0) return;
    cards.forEach((c) => c.classList.remove("active"));

    currentIndex = (newIndex + cards.length) % cards.length;
    const targetCard = cards[currentIndex];
    targetCard.classList.add("active");
    targetCard.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "center" });

    if (feedbackStatus && showToast) {
      const i18n = window.AltDeckI18n;
      const w = windows[currentIndex];
      const appName = i18n ? i18n.translateText(w.app) : w.app;
      const titleText = (i18n ? i18n.translateText(w.title) : w.title).substring(0, 36);
      feedbackStatus.textContent = i18n
        ? i18n.t(`Selected: ${appName} — ${titleText}...`, `已选中：${appName} — ${titleText}...`)
        : `Selected: ${appName} — ${titleText}...`;
    }

    if (quickLookVisible) {
      renderQuickLook();
    }
  }

  // Keyboard navigation within the sandbox
  window.addEventListener("keydown", (e) => {
    // Only capture shortcut keys if the sandbox is in view or user is interacting
    const isSandboxVisible = isElementInViewport(document.getElementById("interactive-sandbox"));
    if (!isSandboxVisible) return;

    if (e.key === "Alt") {
      isOptionHeld = true;
    }

    // Alt + Tab or Tab
    if (e.key === "Tab") {
      e.preventDefault();
      updateSelection(e.shiftKey ? currentIndex - 1 : currentIndex + 1);
      return;
    }

    // Arrow navigation
    if (e.key === "ArrowRight") {
      e.preventDefault();
      updateSelection(currentIndex + 1);
      return;
    }
    if (e.key === "ArrowLeft") {
      e.preventDefault();
      updateSelection(currentIndex - 1);
      return;
    }

    // Spacebar -> Quick Look
    if (e.code === "Space" && !e.target.matches("input, textarea, button")) {
      e.preventDefault();
      toggleQuickLook();
      return;
    }

    // P -> Picture in Picture
    if ((e.key === "p" || e.key === "P") && !e.target.matches("input, textarea")) {
      e.preventDefault();
      togglePiP();
      return;
    }

    // S -> Browser Tabs Filter
    if ((e.key === "s" || e.key === "S") && !e.target.matches("input, textarea")) {
      e.preventDefault();
      toggleBrowserTabsMode();
      return;
    }

    // W -> Close Window
    if ((e.key === "w" || e.key === "W") && !e.target.matches("input, textarea")) {
      e.preventDefault();
      simulateCloseWindow(currentIndex);
      return;
    }

    // Left Snap (Option + Left or just [ key)
    if (e.key === "[" || (e.altKey && e.key === "ArrowLeft")) {
      e.preventDefault();
      triggerSnap("Left Half (50%)");
      return;
    }

    // Right Snap (Option + Right or just ] key)
    if (e.key === "]" || (e.altKey && e.key === "ArrowRight")) {
      e.preventDefault();
      triggerSnap("Right Half (50%)");
      return;
    }

    // Escape
    if (e.key === "Escape") {
      if (quickLookVisible) {
        toggleQuickLook(false);
      }
    }
  });

  window.addEventListener("keyup", (e) => {
    if (e.key === "Alt") {
      isOptionHeld = false;
    }
  });

  // Card clicks
  cards.forEach((card, idx) => {
    card.addEventListener("click", () => {
      updateSelection(idx);
    });
  });

  // Action buttons
  const btnNext = document.getElementById("demo-btn-next");
  const btnPrev = document.getElementById("demo-btn-prev");
  const btnTabs = document.getElementById("demo-btn-tabs");
  const btnQuickLook = document.getElementById("demo-btn-quicklook");
  const btnPip = document.getElementById("demo-btn-pip");
  const btnSnapLeft = document.getElementById("demo-btn-snap-left");
  const btnSnapRight = document.getElementById("demo-btn-snap-right");

  if (btnNext) btnNext.addEventListener("click", () => updateSelection(currentIndex + 1));
  if (btnPrev) btnPrev.addEventListener("click", () => updateSelection(currentIndex - 1));
  if (btnTabs) btnTabs.addEventListener("click", () => toggleBrowserTabsMode());
  if (btnQuickLook) btnQuickLook.addEventListener("click", () => toggleQuickLook());

  function toggleBrowserTabsMode() {
    browserTabsMode = !browserTabsMode;
    windows = activeItems();
    if (btnTabs) btnTabs.classList.toggle("active", browserTabsMode);
    cards.forEach((card, idx) => {
      const titleEl = card.querySelector(".card-title");
      const appEl = card.querySelector(".card-app-name");
      const iconEl = card.querySelector(".card-app-icon-badge");
      const i18n = window.AltDeckI18n;
      if (browserTabsMode) {
        const item = browserTabs[idx];
        if (titleEl) titleEl.textContent = i18n ? i18n.translateText(item.title) : item.title;
        if (appEl) appEl.textContent = i18n ? i18n.translateText(item.app) : item.app;
        if (iconEl) iconEl.setAttribute("src", item.icon);
      } else {
        const snap = defaultCardSnapshots[idx];
        if (titleEl) titleEl.textContent = i18n ? i18n.translateText(snap.title) : snap.title;
        if (appEl) appEl.textContent = i18n ? i18n.translateText(snap.app) : snap.app;
        if (iconEl && snap.iconSrc) iconEl.setAttribute("src", snap.iconSrc);
      }
    });
    updateSelection(0, false);
    if (feedbackStatus) {
      const i18n = window.AltDeckI18n;
      feedbackStatus.textContent = browserTabsMode
        ? (i18n ? i18n.t("Browser Tabs (4) — Press S to return to app windows", "浏览器标签页（4）— 再按 S 返回应用窗口") : "Browser Tabs (4) — Press S to return to app windows")
        : (i18n ? i18n.t("Showing all app windows (Default) — Press S for Browser Tabs", "显示全部应用窗口（默认）— 按 S 切换浏览器标签页") : "Showing all app windows (Default) — Press S for Browser Tabs");
    }
  }
  if (btnPip) btnPip.addEventListener("click", () => togglePiP());
  if (btnSnapLeft) btnSnapLeft.addEventListener("click", () => triggerSnap("Left Half (50%)"));
  if (btnSnapRight) btnSnapRight.addEventListener("click", () => triggerSnap("Right Half (50%)"));

  // Card Action Capsule Pills
  document.querySelectorAll(".action-pill-btn.snap-left").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      triggerSnap("Left Half (50%)");
    });
  });

  document.querySelectorAll(".action-pill-btn.snap-right").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      triggerSnap("Right Half (50%)");
    });
  });

  document.querySelectorAll(".action-pill-btn.close").forEach((btn, idx) => {
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      simulateCloseWindow(idx);
    });
  });

  function toggleQuickLook(forceState = null) {
    quickLookVisible = forceState !== null ? forceState : !quickLookVisible;
    if (quickLookOverlay) {
      if (quickLookVisible) {
        renderQuickLook();
        quickLookOverlay.style.display = "block";
        quickLookOverlay.classList.add("active");
        if (btnQuickLook) btnQuickLook.classList.add("active");
        if (feedbackStatus) {
          const i18n = window.AltDeckI18n;
          const appName = i18n ? i18n.translateText(windows[currentIndex].app) : windows[currentIndex].app;
          feedbackStatus.textContent = i18n
            ? i18n.t(`Quick Look: Expanded view for ${appName}`, `快速预览：已展开 ${appName}`)
            : `Quick Look: Expanded view for ${appName}`;
        }
      } else {
        quickLookOverlay.classList.remove("active");
        quickLookOverlay.style.display = "none";
        if (btnQuickLook) btnQuickLook.classList.remove("active");
      }
    }
  }

  function renderQuickLook() {
    const win = windows[currentIndex];
    const i18n = window.AltDeckI18n;
    const qTitle = document.getElementById("ql-title");
    const qApp = document.getElementById("ql-app");
    const qCode = document.getElementById("ql-code");
    const appText = i18n ? i18n.translateText(win.app) : win.app;
    if (qTitle) qTitle.textContent = i18n ? i18n.translateText(win.title) : win.title;
    if (qApp) qApp.textContent = `${appText} • ${win.badge}`;
    if (qCode) qCode.textContent = win.codePreview;
  }

  function togglePiP() {
    pipVisible = !pipVisible;
    if (pipOverlay) {
      if (pipVisible) {
        const win = windows[currentIndex];
        const i18n = window.AltDeckI18n;
        const appText = i18n ? i18n.translateText(win.app) : win.app;
        document.getElementById("pip-title").textContent = i18n ? i18n.translateText(win.title) : win.title;
        document.getElementById("pip-app").textContent = appText;
        pipOverlay.style.display = "block";
        pipOverlay.classList.add("active");
        if (btnPip) btnPip.classList.add("active");
        if (feedbackStatus) {
          feedbackStatus.textContent = i18n
            ? i18n.t(`Pinned PiP: Floating Picture-in-Picture window activated for ${appText}`, `置顶画中画：已为 ${appText} 开启实时悬浮窗`)
            : `Pinned PiP: Floating Picture-in-Picture window activated for ${appText}`;
        }
      } else {
        pipOverlay.classList.remove("active");
        pipOverlay.style.display = "none";
        if (btnPip) btnPip.classList.remove("active");
      }
    }
  }

  function triggerSnap(zone) {
    const i18n = window.AltDeckI18n;
    const appText = i18n ? i18n.translateText(windows[currentIndex].app) : windows[currentIndex].app;
    if (snapNotice) {
      snapNotice.textContent = i18n
        ? i18n.t(`⚡ Snapped [${appText}] to ${zone}`, `⚡ 已将 [${appText}] 贴靠至 ${zone}`)
        : `⚡ Snapped [${appText}] to ${zone}`;
      snapNotice.classList.add("show");
      setTimeout(() => snapNotice.classList.remove("show"), 2400);
    }
    if (feedbackStatus) {
      feedbackStatus.textContent = i18n
        ? i18n.t(`Window Grid: Snapped to ${zone}`, `窗口网格：已贴靠至 ${zone}`)
        : `Window Grid: Snapped to ${zone}`;
    }
  }

  function simulateCloseWindow(index) {
    const card = cards[index];
    if (card) {
      card.style.transform = "scale(0.8) translateY(-20px)";
      card.style.opacity = "0";
      setTimeout(() => {
        card.style.display = "none";
        updateSelection(index === cards.length - 1 ? 0 : index);
        if (feedbackStatus) {
          const i18n = window.AltDeckI18n;
          const titleText = (i18n ? i18n.translateText(windows[index].title) : windows[index].title).substring(0, 30);
          feedbackStatus.textContent = i18n
            ? i18n.t(`Closed window: ${titleText}...`, `已关闭窗口：${titleText}...`)
            : `Closed window: ${titleText}...`;
        }
      }, 200);
    }
  }

  // PiP Controls
  const pipGhostBtn = document.getElementById("pip-ghost-btn");
  const pipOpacityBtn = document.getElementById("pip-opacity-btn");
  const pipCloseBtn = document.getElementById("pip-close-btn");
  const pipHud = document.getElementById("pip-hud-window");

  let pipOpacity = 1.0;
  let isGhost = false;

  if (pipGhostBtn && pipHud) {
    pipGhostBtn.addEventListener("click", () => {
      isGhost = !isGhost;
      pipGhostBtn.classList.toggle("active", isGhost);
      pipHud.classList.toggle("ghost-mode", isGhost);
      if (feedbackStatus) {
        const i18n = window.AltDeckI18n;
        feedbackStatus.textContent = isGhost
          ? (i18n ? i18n.t("PiP: Ghost Mode Enabled (Clicks pass through to background)", "画中画：已开启幽灵模式（鼠标点击可穿透）") : "PiP: Ghost Mode Enabled (Clicks pass through to background)")
          : (i18n ? i18n.t("PiP: Normal Click Mode Enabled", "画中画：已恢复正常点击模式") : "PiP: Normal Click Mode Enabled");
      }
    });
  }

  if (pipOpacityBtn && pipHud) {
    pipOpacityBtn.addEventListener("click", () => {
      if (pipOpacity === 1.0) pipOpacity = 0.8;
      else if (pipOpacity === 0.8) pipOpacity = 0.55;
      else if (pipOpacity === 0.55) pipOpacity = 0.35;
      else pipOpacity = 1.0;

      pipHud.style.opacity = pipOpacity;
      if (feedbackStatus) {
        const i18n = window.AltDeckI18n;
        feedbackStatus.textContent = i18n
          ? i18n.t(`PiP Opacity set to ${Math.round(pipOpacity * 100)}%`, `画中画不透明度已设为 ${Math.round(pipOpacity * 100)}%`)
          : `PiP Opacity set to ${Math.round(pipOpacity * 100)}%`;
      }
    });
  }

  if (pipCloseBtn) {
    pipCloseBtn.addEventListener("click", () => togglePiP());
  }

  const qlCloseBtn = document.getElementById("ql-close-btn");
  if (qlCloseBtn) {
    qlCloseBtn.addEventListener("click", () => toggleQuickLook(false));
  }
}

/* ==========================================================================
   Copy to Clipboard Helpers
   ========================================================================== */
function initCopyButtons() {
  document.querySelectorAll(".copy-btn, .btn-copy-install").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      const textToCopy = btn.getAttribute("data-copy") || "git clone https://github.com/icaichen/tabstation.git && cd tabstation && ./build-app.sh";
      navigator.clipboard.writeText(textToCopy).then(() => {
        const originalHTML = btn.innerHTML;
        const i18n = window.AltDeckI18n;
        btn.innerHTML = i18n ? i18n.t("✓ Copied", "✓ 已复制") : "✓ Copied";
        btn.classList.add("copied");
        setTimeout(() => {
          btn.innerHTML = originalHTML;
          btn.classList.remove("copied");
        }, 2200);
      });
    });
  });
}

/* ==========================================================================
   Header Dynamic Blur
   ========================================================================== */
function initHeaderBlur() {
  const header = document.querySelector(".site-header");
  if (!header) return;

  window.addEventListener("scroll", () => {
    if (window.scrollY > 20) {
      header.style.backgroundColor = "rgba(5, 5, 8, 0.88)";
      header.style.borderBottomColor = "rgba(255, 255, 255, 0.12)";
    } else {
      header.style.backgroundColor = "rgba(5, 5, 8, 0.72)";
      header.style.borderBottomColor = "rgba(255, 255, 255, 0.08)";
    }
  });
}

/* ==========================================================================
   Smooth Scrolling for Anchors
   ========================================================================== */
function initSmoothScroll() {
  document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
    anchor.addEventListener("click", function (e) {
      const href = this.getAttribute("href");
      if (href === "#") return;
      const target = document.querySelector(href);
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: "smooth" });
      }
    });
  });
}

function isElementInViewport(el) {
  if (!el) return false;
  const rect = el.getBoundingClientRect();
  return (
    rect.top <= (window.innerHeight || document.documentElement.clientHeight) &&
    rect.bottom >= 0
  );
}




/* ==========================================================================
   FAQ Accordion Logic
   ========================================================================== */
function initFAQAccordion() {
  const faqItems = document.querySelectorAll(".faq-item");

  faqItems.forEach((item) => {
    const btn = item.querySelector(".faq-question-btn");
    if (!btn) return;

    btn.addEventListener("click", () => {
      const isOpen = item.classList.contains("open");

      // Close all other accordions for a polished macOS feel
      faqItems.forEach((other) => other.classList.remove("open"));

      if (!isOpen) {
        item.classList.add("open");
      }
    });
  });
}
