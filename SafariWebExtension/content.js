(function () {
  const BUTTON_ID = "m3u8-convert-fab";
  const PANEL_ID = "m3u8-convert-panel";
  const SCHEME = "m3u8converter://add";
  let detectedList = [];
  const detectedMap = new Map();
  const isTopWindow = window.top === window;
  const MEDIA_EXTENSIONS = [
    "m3u8",
    "mp4",
    "mov",
    "m4v",
    "webm",
    "mkv",
    "avi",
    "flv",
    "ts",
    "mpeg",
    "mpd",
    "mp3",
    "aac",
    "m4a",
    "ogg",
    "wav",
    "flac"
  ];
  const MEDIA_EXT_RE = new RegExp(`\\.(${MEDIA_EXTENSIONS.join("|")})(\\?|#|$)`, "i");
  const MEDIA_MIME_RE = /^(video|audio)\//i;

  function normalizeUrl(input) {
    if (!input) return null;
    try {
      if (typeof input === "string") {
        if (input.startsWith("blob:") || input.startsWith("data:")) return input;
        return new URL(input, location.href).toString();
      }
      if (input instanceof URL) {
        return input.toString();
      }
    } catch (e) {}
    return null;
  }

  function isLikelyMediaUrl(url) {
    if (!url) return false;
    if (url.startsWith("blob:") || url.startsWith("data:")) return true;
    return MEDIA_EXT_RE.test(url);
  }

  function remember(url, source) {
    const normalized = normalizeUrl(url);
    if (!normalized) return;
    if (detectedMap.has(normalized)) return;
    detectedMap.set(normalized, source || "unknown");
    if (!isTopWindow) {
      try {
        window.top.postMessage(
          {
            __m3u8_media: true,
            url: normalized,
            source: source || "frame"
          },
          "*"
        );
      } catch (e) {}
    }
  }

  function findM3U8Urls() {
    const urls = new Set(detectedMap.keys());

    document.querySelectorAll("video, audio, source").forEach((el) => {
      const src = el.currentSrc || el.src || el.getAttribute("src");
      if (src && isLikelyMediaUrl(src)) {
        urls.add(normalizeUrl(src));
      }
      const type = el.getAttribute("type");
      if (type && MEDIA_MIME_RE.test(type) && src) {
        urls.add(normalizeUrl(src));
      }
    });

    document.querySelectorAll("a[href]").forEach((el) => {
      const href = el.getAttribute("href");
      if (href && isLikelyMediaUrl(href)) {
        urls.add(new URL(href, location.href).toString());
      }
    });

    try {
      performance.getEntriesByType("resource").forEach((entry) => {
        if (entry.name && isLikelyMediaUrl(entry.name)) {
          urls.add(entry.name);
        }
      });
    } catch (e) {}

    return Array.from(urls).filter(Boolean);
  }

  function ensureButton() {
    if (document.getElementById(BUTTON_ID)) {
      return;
    }
    const btn = document.createElement("button");
    btn.id = BUTTON_ID;
    btn.textContent = "视频";
    btn.classList.add("m3u8-disabled");
    btn.addEventListener("click", () => {
      if (!detectedList.length) {
        alert("未检测到视频");
        return;
      }
      togglePanel();
    });
    document.documentElement.appendChild(btn);
  }

  function ensurePanel() {
    if (document.getElementById(PANEL_ID)) {
      return;
    }
    const panel = document.createElement("div");
    panel.id = PANEL_ID;
    panel.innerHTML = `
      <div class="m3u8-panel-header">
        <span>检测到的视频</span>
        <span class="m3u8-panel-close">×</span>
      </div>
      <ul class="m3u8-panel-list"></ul>
      <div class="m3u8-panel-empty">未检测到视频</div>
    `;
    panel.addEventListener("click", (e) => {
      if (e.target.classList.contains("m3u8-panel-close")) {
        panel.style.display = "none";
      }
    });
    document.documentElement.appendChild(panel);
  }

  function getDisplayLabel(url, source) {
    if (!url) return "";
    if (url.startsWith("blob:")) {
      return "blob:// (仅检测，无法直接下载)";
    }
    if (url.startsWith("data:")) {
      return "data:// (仅检测，无法直接下载)";
    }
    return url;
  }

  function updatePanel() {
    const panel = document.getElementById(PANEL_ID);
    if (!panel) return;
    const list = panel.querySelector(".m3u8-panel-list");
    const empty = panel.querySelector(".m3u8-panel-empty");
    list.innerHTML = "";
    if (!detectedList.length) {
      empty.style.display = "block";
      return;
    }
    empty.style.display = "none";
    detectedList.forEach((url, idx) => {
      const li = document.createElement("li");
      li.className = "m3u8-panel-item";
      const display = getDisplayLabel(url);
      const short = display.length > 60 ? display.slice(0, 60) + "..." : display;
      li.textContent = `${idx + 1}. ${short}`;
      li.title = display;
      if (url.startsWith("blob:") || url.startsWith("data:")) {
        li.style.opacity = "0.6";
      } else {
        li.addEventListener("click", () => {
          const title = document.title || "Video";
          const u = encodeURIComponent(url);
          const t = encodeURIComponent(title);
          const target = `${SCHEME}?url=${u}&title=${t}`;
          window.location.href = target;
        });
      }
      list.appendChild(li);
    });
  }

  function updateBadge() {
    const btn = document.getElementById(BUTTON_ID);
    if (!btn) return;
    let badge = btn.querySelector(".m3u8-badge");
    if (!badge) {
      badge = document.createElement("span");
      badge.className = "m3u8-badge";
      btn.appendChild(badge);
    }
    badge.textContent = detectedList.length.toString();
    badge.style.display = detectedList.length ? "block" : "none";
  }

  function togglePanel() {
    const panel = document.getElementById(PANEL_ID);
    if (!panel) return;
    panel.style.display = panel.style.display === "block" ? "none" : "block";
  }

  function updateState() {
    detectedList = findM3U8Urls();
    const btn = document.getElementById(BUTTON_ID);
    if (!btn) return;
    if (detectedList.length) {
      btn.classList.remove("m3u8-disabled");
    } else {
      btn.classList.add("m3u8-disabled");
    }
    updateBadge();
    updatePanel();
  }

  function boot() {
    injectPageHook();
    hookNetworkCapture();
    observeMediaElements();
    if (isTopWindow) {
      ensureButton();
      ensurePanel();
      updateState();
      setInterval(updateState, 2000);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }

  function hookNetworkCapture() {
    if (window.__m3u8Hooked) return;
    window.__m3u8Hooked = true;

    const originalFetch = window.fetch;
    if (originalFetch) {
      window.fetch = function (input, init) {
        try {
          const url = input && input.url ? input.url : input;
          if (isLikelyMediaUrl(url)) {
            remember(url, "fetch");
          }
        } catch (e) {}
        return originalFetch.apply(this, arguments);
      };
    }

    const open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
      try {
        if (isLikelyMediaUrl(url)) {
          remember(url, "xhr");
        }
      } catch (e) {}
      return open.apply(this, arguments);
    };

    window.addEventListener("message", (e) => {
      const data = e.data;
      if (!data || !data.__m3u8_media || !data.url) return;
      if (isLikelyMediaUrl(data.url)) {
        remember(data.url, data.source || "page");
        if (isTopWindow) {
          updateState();
        }
      }
    });
  }

  function observeMediaElements() {
    const scan = () => {
      document.querySelectorAll("video, audio, source").forEach((el) => {
        const src = el.currentSrc || el.src || el.getAttribute("src");
        if (isLikelyMediaUrl(src)) {
          remember(src, "dom");
        }
      });
    };

    scan();
    const observer = new MutationObserver(() => scan());
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["src", "currentSrc", "type"]
    });
  }

  function injectPageHook() {
    if (document.getElementById("m3u8-page-hook")) return;
    const script = document.createElement("script");
    script.id = "m3u8-page-hook";
    try {
      const runtime = typeof browser !== "undefined" ? browser : chrome;
      script.src = runtime.runtime.getURL("page-hook.js");
    } catch (e) {
      script.textContent = "";
    }
    script.onload = () => {
      script.remove();
    };
    document.documentElement.appendChild(script);
  }
})();
