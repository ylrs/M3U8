(() => {
  if (window.__m3u8Injected) return;
  window.__m3u8Injected = true;

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
  const PLAYLIST_MIME_RE = /(application\/vnd\.apple\.mpegurl|application\/x-mpegURL|application\/dash\+xml)/i;

  function isLikelyMediaUrl(url) {
    if (!url) return false;
    if (url.startsWith("blob:") || url.startsWith("data:")) return true;
    return MEDIA_EXT_RE.test(url);
  }

  function post(url, source) {
    if (!url) return;
    window.postMessage(
      {
        __m3u8_media: true,
        url,
        source: source || "page"
      },
      "*"
    );
  }

  const originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function (input, init) {
      let url = input && input.url ? input.url : input;
      if (isLikelyMediaUrl(url)) {
        post(url, "fetch");
      }
      return originalFetch.apply(this, arguments).then((resp) => {
        try {
          const ct = resp.headers && resp.headers.get
            ? resp.headers.get("content-type") || ""
            : "";
          if (MEDIA_MIME_RE.test(ct) || PLAYLIST_MIME_RE.test(ct)) {
            post(resp.url || url, "fetch-ct");
          }
        } catch (e) {}
        return resp;
      });
    };
  }

  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    if (isLikelyMediaUrl(url)) {
      post(url, "xhr");
    }
    this.addEventListener("load", () => {
      try {
        const ct = this.getResponseHeader("content-type") || "";
        if (MEDIA_MIME_RE.test(ct) || PLAYLIST_MIME_RE.test(ct)) {
          post(url, "xhr-ct");
        }
      } catch (e) {}
    });
    return open.apply(this, arguments);
  };
})();
