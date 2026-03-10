(function () {
  const BUTTON_ID = "m3u8-convert-fab";
  const PANEL_ID = "m3u8-convert-panel";
  const SCHEME = "m3u8converter://add";
  let detectedList = [];

  function findM3U8Urls() {
    const urls = new Set();

    document.querySelectorAll("video, source").forEach((el) => {
      const src = el.currentSrc || el.src;
      if (src && src.includes(".m3u8")) {
        urls.add(src);
      }
    });

    document.querySelectorAll("a[href]").forEach((el) => {
      const href = el.getAttribute("href");
      if (href && href.includes(".m3u8")) {
        urls.add(new URL(href, location.href).toString());
      }
    });

    try {
      performance.getEntriesByType("resource").forEach((entry) => {
        if (entry.name && entry.name.includes(".m3u8")) {
          urls.add(entry.name);
        }
      });
    } catch (e) {}

    return Array.from(urls);
  }

  function ensureButton() {
    if (document.getElementById(BUTTON_ID)) {
      return;
    }
    const btn = document.createElement("button");
    btn.id = BUTTON_ID;
    btn.textContent = "M3U8";
    btn.classList.add("m3u8-disabled");
    btn.addEventListener("click", () => {
      if (!detectedList.length) {
        alert("未检测到 m3u8 视频");
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
        <span>检测到的 m3u8</span>
        <span class="m3u8-panel-close">×</span>
      </div>
      <ul class="m3u8-panel-list"></ul>
      <div class="m3u8-panel-empty">未检测到 m3u8 视频</div>
    `;
    panel.addEventListener("click", (e) => {
      if (e.target.classList.contains("m3u8-panel-close")) {
        panel.style.display = "none";
      }
    });
    document.documentElement.appendChild(panel);
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
      const short = url.length > 60 ? url.slice(0, 60) + "..." : url;
      li.textContent = `${idx + 1}. ${short}`;
      li.title = url;
      li.addEventListener("click", () => {
        const title = document.title || "M3U8 Video";
        const u = encodeURIComponent(url);
        const t = encodeURIComponent(title);
        const target = `${SCHEME}?url=${u}&title=${t}`;
        window.location.href = target;
      });
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
    ensureButton();
    ensurePanel();
    updateState();
    setInterval(updateState, 2000);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
