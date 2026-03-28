// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/open_drive";
import topbar from "../vendor/topbar";

const Hooks = {
  ResizableListColumns: {
    mounted() {
      this.storageKey =
        this.el.dataset.storageKey || "open-drive:list-column-widths";
      this.widths = this.loadWidths();
      this.activeHandle = null;
      this.dragState = null;

      this.handlePointerDown = this.handlePointerDown.bind(this);
      this.handlePointerMove = this.handlePointerMove.bind(this);
      this.handlePointerUp = this.handlePointerUp.bind(this);

      this.el.addEventListener("pointerdown", this.handlePointerDown);
      this.applyWidths();
    },

    updated() {
      this.applyWidths();
    },

    destroyed() {
      this.stopDragging();
      this.el.removeEventListener("pointerdown", this.handlePointerDown);
    },

    loadWidths() {
      try {
        return JSON.parse(localStorage.getItem(this.storageKey) || "{}");
      } catch (_error) {
        return {};
      }
    },

    saveWidths() {
      localStorage.setItem(this.storageKey, JSON.stringify(this.widths));
    },

    applyWidths() {
      ["name", "type", "modified", "size"].forEach((key) => {
        const value = this.widths[key];

        if (value) {
          this.el.style.setProperty(`--drive-col-${key}`, value);
        } else {
          this.el.style.removeProperty(`--drive-col-${key}`);
        }
      });
    },

    handlePointerDown(event) {
      const handle = event.target.closest("[data-column-resizer]");
      if (!handle || !this.el.contains(handle)) return;

      event.preventDefault();
      event.stopPropagation();

      const key = handle.dataset.columnResizer;
      const minWidth = Number(handle.dataset.minWidth || 100);
      const maxWidth = Number(handle.dataset.maxWidth || 640);
      const headerCell = this.el.querySelector(`[data-resizable-column="${key}"]`);
      const startWidth = Math.round(
        headerCell?.getBoundingClientRect().width || minWidth,
      );

      this.dragState = {
        key,
        minWidth,
        maxWidth,
        startWidth,
        startX: event.clientX,
      };

      this.activeHandle = handle;
      this.activeHandle.dataset.resizing = "true";
      document.body.classList.add("column-resize-active");

      window.addEventListener("pointermove", this.handlePointerMove);
      window.addEventListener("pointerup", this.handlePointerUp);
      window.addEventListener("pointercancel", this.handlePointerUp);
    },

    handlePointerMove(event) {
      if (!this.dragState) return;

      const nextWidth = Math.round(
        this.dragState.startWidth + (event.clientX - this.dragState.startX),
      );
      const clampedWidth = Math.max(
        this.dragState.minWidth,
        Math.min(this.dragState.maxWidth, nextWidth),
      );

      this.widths[this.dragState.key] = `${clampedWidth}px`;
      this.applyWidths();
    },

    handlePointerUp() {
      if (!this.dragState) return;

      this.saveWidths();
      this.stopDragging();
    },

    stopDragging() {
      window.removeEventListener("pointermove", this.handlePointerMove);
      window.removeEventListener("pointerup", this.handlePointerUp);
      window.removeEventListener("pointercancel", this.handlePointerUp);

      if (this.activeHandle) {
        delete this.activeHandle.dataset.resizing;
        this.activeHandle = null;
      }

      this.dragState = null;
      document.body.classList.remove("column-resize-active");
    },
  },

  DirectUploadZone: {
    mounted() {
      this.csrfToken = document
        .querySelector("meta[name='csrf-token']")
        ?.getAttribute("content");
      this.maxFileSize = Number(this.el.dataset.maxFileSize || 0);
      this.backendFallbackSize = Number(
        this.el.dataset.backendFallbackSize || 0,
      );
      this.input = this.el.querySelector("[data-direct-upload-input]");
      this.trigger = this.el.querySelector("[data-direct-upload-trigger]");
      this.queue = this.el.querySelector("[data-direct-upload-queue]");
      this.entriesContainer = this.el.querySelector(
        "[data-direct-upload-entries]",
      );
      this.errorsContainer = this.el.querySelector(
        "[data-direct-upload-errors]",
      );
      this.stats = {
        queued: this.el.querySelector('[data-upload-stat="queued"]'),
        uploading: this.el.querySelector('[data-upload-stat="uploading"]'),
        complete: this.el.querySelector('[data-upload-stat="complete"]'),
        error: this.el.querySelector('[data-upload-stat="error"]'),
      };
      this.entries = new Map();
      this.activeUploads = 0;
      this.completedSinceRefresh = false;

      this.handleTriggerClick = (event) => {
        if (event.target.closest("input, button, a, textarea, select")) return;
        this.input?.click();
      };

      this.handleTriggerKeydown = (event) => {
        if (event.key !== "Enter" && event.key !== " ") return;
        event.preventDefault();
        this.input?.click();
      };

      this.handleFileSelection = (event) => {
        this.enqueueFiles(Array.from(event.target.files || []));
        event.target.value = "";
      };

      this.handleDragOver = (event) => {
        event.preventDefault();
        this.el.classList.add("bg-sky-50/80", "ring-2", "ring-sky-400");
      };

      this.handleDragLeave = (event) => {
        if (event.currentTarget.contains(event.relatedTarget)) return;
        this.el.classList.remove("bg-sky-50/80", "ring-2", "ring-sky-400");
      };

      this.handleDrop = (event) => {
        event.preventDefault();
        this.el.classList.remove("bg-sky-50/80", "ring-2", "ring-sky-400");
        this.enqueueFiles(Array.from(event.dataTransfer?.files || []));
      };

      this.trigger?.addEventListener("click", this.handleTriggerClick);
      this.trigger?.addEventListener("keydown", this.handleTriggerKeydown);
      this.input?.addEventListener("change", this.handleFileSelection);
      this.el.addEventListener("dragover", this.handleDragOver);
      this.el.addEventListener("dragleave", this.handleDragLeave);
      this.el.addEventListener("drop", this.handleDrop);
    },

    destroyed() {
      this.trigger?.removeEventListener("click", this.handleTriggerClick);
      this.trigger?.removeEventListener("keydown", this.handleTriggerKeydown);
      this.input?.removeEventListener("change", this.handleFileSelection);
      this.el.removeEventListener("dragover", this.handleDragOver);
      this.el.removeEventListener("dragleave", this.handleDragLeave);
      this.el.removeEventListener("drop", this.handleDrop);
    },

    enqueueFiles(files) {
      files.forEach((file) => {
        const id = `${file.name}-${file.size}-${file.lastModified}-${crypto.randomUUID()}`;
        const entry = {
          id,
          file,
          status: "queued",
          progress: 0,
          error: null,
        };

        this.entries.set(id, entry);
        this.renderEntry(entry);
        this.syncQueueVisibility();
        this.syncStats();

        if (file.size > this.maxFileSize) {
          entry.status = "error";
          entry.error = "Arquivo excede o limite de 2 GB.";
          this.renderEntry(entry);
          this.syncStats();
          return;
        }

        this.uploadEntry(entry);
      });
    },

    async uploadEntry(entry) {
      entry.status = "uploading";
      this.activeUploads += 1;
      this.renderEntry(entry);
      this.syncStats();

      try {
        if (this.shouldUseBackendFallback(entry.file)) {
          await this.uploadViaBackend(entry);
          entry.status = "complete";
          entry.progress = 100;
          entry.error = null;
          this.completedSinceRefresh = true;
          return;
        }

        const initResponse = await fetch(this.el.dataset.initiateUrl, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-csrf-token": this.csrfToken,
          },
          credentials: "same-origin",
          body: JSON.stringify({
            upload: {
              folder_id: this.el.dataset.folderId || null,
              name: entry.file.name,
              content_type: entry.file.type || "application/octet-stream",
              size: entry.file.size,
            },
          }),
        });

        const initPayload = await this.readJson(initResponse);

        if (!initResponse.ok) {
          throw new Error(
            initPayload.error || "Unable to prepare this upload.",
          );
        }

        await this.uploadToStorage(
          entry,
          initPayload.upload_url,
          initPayload.upload_headers || {},
        );

        const completeResponse = await fetch(this.el.dataset.completeUrl, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-csrf-token": this.csrfToken,
          },
          credentials: "same-origin",
          body: JSON.stringify({ token: initPayload.token }),
        });

        const completePayload = await this.readJson(completeResponse);

        if (!completeResponse.ok) {
          throw new Error(
            completePayload.error || "Unable to finalize this upload.",
          );
        }

        entry.status = "complete";
        entry.progress = 100;
        entry.error = null;
        this.completedSinceRefresh = true;
      } catch (error) {
        if (
          !entry.retriedViaBackend &&
          this.canRetryViaBackend(entry.file, error)
        ) {
          entry.retriedViaBackend = true;
          entry.progress = 0;

          try {
            await this.uploadViaBackend(entry);
            entry.status = "complete";
            entry.progress = 100;
            entry.error = null;
            this.completedSinceRefresh = true;
            return;
          } catch (backendError) {
            entry.status = "error";
            entry.error = backendError.message;
            this.pushGlobalError(backendError.message);
          }
        } else {
          entry.status = "error";
          entry.error = error.message;
          this.pushGlobalError(error.message);
        }
      } finally {
        this.activeUploads = Math.max(0, this.activeUploads - 1);
        this.renderEntry(entry);
        this.syncStats();
        this.scheduleRefreshIfIdle();
      }
    },

    shouldUseBackendFallback(file) {
      return (
        this.backendFallbackSize > 0 && file.size <= this.backendFallbackSize
      );
    },

    canRetryViaBackend(file, error) {
      return (
        this.shouldUseBackendFallback(file) ||
        /cors|storage blocked|network error/i.test(error.message || "")
      );
    },

    async uploadViaBackend(entry) {
      const formData = new FormData();
      formData.append("file", entry.file);
      formData.append("name", entry.file.name);
      formData.append("_csrf_token", this.csrfToken);

      if (this.el.dataset.folderId) {
        formData.append("folder_id", this.el.dataset.folderId);
      }

      await new Promise((resolve, reject) => {
        const request = new XMLHttpRequest();
        request.open("POST", this.el.dataset.proxyUrl);
        request.setRequestHeader("x-csrf-token", this.csrfToken);

        request.upload.addEventListener("progress", (event) => {
          if (!event.lengthComputable) return;
          entry.progress = Math.min(
            99,
            Math.round((event.loaded / event.total) * 100),
          );
          this.renderEntry(entry);
          this.syncStats();
        });

        request.addEventListener("load", () => {
          if (request.status >= 200 && request.status < 300) {
            resolve();
            return;
          }

          try {
            const payload = JSON.parse(request.responseText || "{}");
            reject(new Error(payload.error || "Backend upload failed."));
          } catch (_error) {
            reject(new Error(`Backend upload failed (${request.status}).`));
          }
        });

        request.addEventListener("error", () => {
          reject(new Error("Backend upload failed."));
        });

        request.send(formData);
      });
    },

    uploadToStorage(entry, url, headers) {
      return new Promise((resolve, reject) => {
        const request = new XMLHttpRequest();
        request.open("PUT", url);

        Object.entries(headers).forEach(([name, value]) => {
          request.setRequestHeader(name, value);
        });

        request.upload.addEventListener("progress", (event) => {
          if (!event.lengthComputable) return;
          entry.progress = Math.min(
            99,
            Math.round((event.loaded / event.total) * 100),
          );
          this.renderEntry(entry);
          this.syncStats();
        });

        request.addEventListener("load", () => {
          if (request.status >= 200 && request.status < 300) {
            resolve();
          } else {
            reject(
              new Error(`Storage rejected the upload (${request.status}).`),
            );
          }
        });

        request.addEventListener("error", () => {
          reject(
            new Error(
              "Storage blocked the browser upload. Check the bucket CORS policy for PUT from this app origin.",
            ),
          );
        });

        request.send(entry.file);
      });
    },

    scheduleRefreshIfIdle() {
      if (!this.completedSinceRefresh || this.activeUploads > 0) return;

      clearTimeout(this.refreshTimer);
      this.refreshTimer = setTimeout(() => {
        this.completedSinceRefresh = false;
        this.pushEvent("refresh_after_direct_upload", {});
      }, 500);
    },

    pushGlobalError(message) {
      if (!this.errorsContainer) return;
      this.errorsContainer.hidden = false;
      this.errorsContainer.textContent = message;
    },

    syncQueueVisibility() {
      if (!this.queue) return;
      this.queue.hidden = this.entries.size === 0;
    },

    syncStats() {
      const counters = { queued: 0, uploading: 0, complete: 0, error: 0 };

      this.entries.forEach((entry) => {
        counters[entry.status] += 1;
      });

      if (this.stats.queued)
        this.stats.queued.textContent = `${counters.queued} na fila`;
      if (this.stats.uploading)
        this.stats.uploading.textContent = `${counters.uploading} enviando`;
      if (this.stats.complete)
        this.stats.complete.textContent = `${counters.complete} concluidos`;
      if (this.stats.error)
        this.stats.error.textContent = `${counters.error} com erro`;
    },

    renderEntry(entry) {
      if (!this.entriesContainer) return;

      let row = this.entriesContainer.querySelector(
        `[data-upload-entry="${entry.id}"]`,
      );

      if (!row) {
        row = document.createElement("div");
        row.dataset.uploadEntry = entry.id;
        row.className = "border-t border-slate-100 px-4 py-3 first:border-t-0";
        row.innerHTML = `
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-2">
                <span data-role="name" class="block truncate text-sm font-medium text-slate-800"></span>
                <span data-role="status" class="rounded-full px-2.5 py-1 text-[11px] font-semibold"></span>
              </div>
              <div data-role="meta" class="mt-2 flex items-center gap-2 text-[11px] text-slate-500"></div>
              <div class="mt-3 h-2 overflow-hidden rounded-full bg-slate-100">
                <div data-role="progress" class="h-full rounded-full transition-all duration-300"></div>
              </div>
              <p data-role="error" class="mt-2 text-[11px] font-medium text-rose-600 hidden"></p>
            </div>
          </div>
        `;
        this.entriesContainer.appendChild(row);
      }

      row.querySelector('[data-role="name"]').textContent = entry.file.name;
      row.querySelector('[data-role="meta"]').textContent =
        `${this.formatBytes(entry.file.size)} • ${entry.progress}% enviado`;

      const statusEl = row.querySelector('[data-role="status"]');
      const progressEl = row.querySelector('[data-role="progress"]');
      const errorEl = row.querySelector('[data-role="error"]');

      const statusStyles = {
        queued: [
          "Na fila",
          "bg-slate-100 text-slate-600 ring-1 ring-slate-200",
          "bg-slate-300",
        ],
        uploading: [
          "Enviando",
          "bg-sky-100 text-sky-700 ring-1 ring-sky-200",
          "bg-sky-500",
        ],
        complete: [
          "Concluido",
          "bg-emerald-100 text-emerald-700 ring-1 ring-emerald-200",
          "bg-emerald-400",
        ],
        error: [
          "Falhou",
          "bg-rose-100 text-rose-700 ring-1 ring-rose-200",
          "bg-rose-400",
        ],
      };

      const [label, badgeClass, progressClass] = statusStyles[entry.status];
      statusEl.textContent = label;
      statusEl.className = `rounded-full px-2.5 py-1 text-[11px] font-semibold ${badgeClass}`;
      progressEl.className = `h-full rounded-full transition-all duration-300 ${progressClass}`;
      progressEl.style.width = `${entry.progress}%`;

      if (entry.error) {
        errorEl.hidden = false;
        errorEl.textContent = entry.error;
      } else {
        errorEl.hidden = true;
        errorEl.textContent = "";
      }
    },

    async readJson(response) {
      const text = await response.text();

      if (!text) return {};

      try {
        return JSON.parse(text);
      } catch (_error) {
        return {};
      }
    },

    formatBytes(bytes) {
      if (bytes < 1024) return `${bytes} B`;
      if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
      if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)} MB`;
      return `${(bytes / 1073741824).toFixed(1)} GB`;
    },
  },

  PasswordVisibility: {
    mounted() {
      this.input = this.el.querySelector("input");
      this.button = this.el.querySelector("[data-password-toggle-button]");
      this.showIcon = this.el.querySelector(
        '[data-password-toggle-icon="show"]',
      );
      this.hideIcon = this.el.querySelector(
        '[data-password-toggle-icon="hide"]',
      );

      this.toggleVisibility = (event) => {
        event.preventDefault();

        if (!this.input || !this.button) return;

        const visible = this.input.type === "password";
        this.input.type = visible ? "text" : "password";
        this.button.setAttribute("aria-pressed", String(visible));
        this.button.setAttribute(
          "aria-label",
          visible
            ? this.button.dataset.hideLabel
            : this.button.dataset.showLabel,
        );
        this.showIcon?.classList.toggle("hidden", visible);
        this.hideIcon?.classList.toggle("hidden", !visible);
        this.input.focus({ preventScroll: true });
      };

      this.button?.addEventListener("click", this.toggleVisibility);
    },

    destroyed() {
      this.button?.removeEventListener("click", this.toggleVisibility);
    },
  },

  VideoPreview: {
    mounted() {
      this.video = this.el.querySelector("video");
      this.progress = this.el.querySelector('[data-role="progress"]');
      this.currentTimeLabel = this.el.querySelector(
        '[data-role="current-time"]',
      );
      this.durationLabel = this.el.querySelector('[data-role="duration"]');
      this.inlineDurationLabel = this.el.querySelector(
        '[data-role="duration-inline"]',
      );
      this.previewRegion = this.el.querySelector(
        '[data-role="preview-region"]',
      );
      this.previewPopover = this.el.querySelector(
        '[data-role="preview-popover"]',
      );
      this.previewCanvas = this.el.querySelector(
        '[data-role="preview-canvas"]',
      );
      this.previewTimeLabel = this.el.querySelector(
        '[data-role="preview-time"]',
      );
      this.previewContext = this.previewCanvas?.getContext("2d");
      this.speedLabel = this.el.querySelector('[data-role="speed"]');
      this.speedBadge = this.el.querySelector('[data-role="speed-badge"]');
      this.playButtons = this.el.querySelectorAll(
        '[data-action="toggle-play"]',
      );
      this.skipBackButton = this.el.querySelector(
        '[data-action="seek-backward"]',
      );
      this.skipForwardButton = this.el.querySelector(
        '[data-action="seek-forward"]',
      );
      this.speedDownButton = this.el.querySelector(
        '[data-action="speed-down"]',
      );
      this.speedUpButton = this.el.querySelector('[data-action="speed-up"]');
      this.muteButton = this.el.querySelector('[data-action="toggle-mute"]');
      this.fullscreenButton = this.el.querySelector(
        '[data-action="toggle-fullscreen"]',
      );
      this.boundTogglePlay = () => this.togglePlay();
      this.boundToggleMute = () => this.toggleMute();
      this.boundSeekBackward = () => this.skipBy(-5);
      this.boundSeekForward = () => this.skipBy(5);
      this.boundSpeedDown = () => this.adjustSpeed(-0.25);
      this.boundSpeedUp = () => this.adjustSpeed(0.25);
      this.boundToggleFullscreen = () => this.toggleFullscreen();
      this.boundSyncProgress = () => this.syncProgress();
      this.boundSyncMeta = () => this.syncMeta();
      this.boundHandleEnded = () => this.handleEnded();
      this.boundSeek = (event) => this.seek(event);
      this.boundPreviewMove = (event) => this.updatePreview(event);
      this.boundPreviewLeave = () => this.hidePreview();
      this.boundKeydown = (event) => this.handleKeydown(event);
      this.boundFullscreenChange = () => this.syncMeta();

      if (!this.video || !this.progress) return;

      this.playButtons.forEach((button) =>
        button.addEventListener("click", this.boundTogglePlay),
      );
      this.muteButton?.addEventListener("click", this.boundToggleMute);
      this.skipBackButton?.addEventListener("click", this.boundSeekBackward);
      this.skipForwardButton?.addEventListener("click", this.boundSeekForward);
      this.speedDownButton?.addEventListener("click", this.boundSpeedDown);
      this.speedUpButton?.addEventListener("click", this.boundSpeedUp);
      this.fullscreenButton?.addEventListener(
        "click",
        this.boundToggleFullscreen,
      );
      this.progress.addEventListener("input", this.boundSeek);
      this.progress.addEventListener("mousemove", this.boundPreviewMove);
      this.progress.addEventListener("mouseenter", this.boundPreviewMove);
      this.progress.addEventListener("mouseleave", this.boundPreviewLeave);
      this.video.addEventListener("timeupdate", this.boundSyncProgress);
      this.video.addEventListener("loadedmetadata", this.boundSyncMeta);
      this.video.addEventListener("durationchange", this.boundSyncMeta);
      this.video.addEventListener("play", this.boundSyncMeta);
      this.video.addEventListener("pause", this.boundSyncMeta);
      this.video.addEventListener("volumechange", this.boundSyncMeta);
      this.video.addEventListener("ratechange", this.boundSyncMeta);
      this.video.addEventListener("ended", this.boundHandleEnded);
      document.addEventListener("fullscreenchange", this.boundFullscreenChange);

      if (this.previewPopover) {
        this.previewVideo = document.createElement("video");
        this.previewVideo.src = this.video.currentSrc || this.video.src;
        this.previewVideo.preload = "metadata";
        this.previewVideo.muted = true;
        this.previewVideo.playsInline = true;
        this.previewVideo.crossOrigin = "anonymous";
        this.previewVideo.addEventListener("seeked", () =>
          this.drawPreviewFrame(),
        );
        this.previewVideo.addEventListener("loadeddata", () =>
          this.drawPreviewFrame(),
        );
      }

      if (this.el.dataset.shortcuts === "true") {
        window.addEventListener("keydown", this.boundKeydown);
      }

      this.syncMeta();
      this.syncProgress();

      if (this.el.dataset.autoplay === "true") {
        this.video.muted = false;
        this.video.play().catch(() => {});
      }
    },

    updated() {
      this.syncMeta?.();
      this.syncProgress?.();
    },

    destroyed() {
      this.video?.pause();
      this.playButtons?.forEach((button) =>
        button.removeEventListener("click", this.boundTogglePlay),
      );
      this.muteButton?.removeEventListener("click", this.boundToggleMute);
      this.skipBackButton?.removeEventListener("click", this.boundSeekBackward);
      this.skipForwardButton?.removeEventListener(
        "click",
        this.boundSeekForward,
      );
      this.speedDownButton?.removeEventListener("click", this.boundSpeedDown);
      this.speedUpButton?.removeEventListener("click", this.boundSpeedUp);
      this.fullscreenButton?.removeEventListener(
        "click",
        this.boundToggleFullscreen,
      );
      this.progress?.removeEventListener("input", this.boundSeek);
      this.progress?.removeEventListener("mousemove", this.boundPreviewMove);
      this.progress?.removeEventListener("mouseenter", this.boundPreviewMove);
      this.progress?.removeEventListener("mouseleave", this.boundPreviewLeave);
      this.video?.removeEventListener("timeupdate", this.boundSyncProgress);
      this.video?.removeEventListener("loadedmetadata", this.boundSyncMeta);
      this.video?.removeEventListener("durationchange", this.boundSyncMeta);
      this.video?.removeEventListener("play", this.boundSyncMeta);
      this.video?.removeEventListener("pause", this.boundSyncMeta);
      this.video?.removeEventListener("volumechange", this.boundSyncMeta);
      this.video?.removeEventListener("ratechange", this.boundSyncMeta);
      this.video?.removeEventListener("ended", this.boundHandleEnded);
      document.removeEventListener(
        "fullscreenchange",
        this.boundFullscreenChange,
      );
      window.removeEventListener("keydown", this.boundKeydown);
      this.previewVideo?.removeAttribute("src");
      this.previewVideo?.load?.();
    },

    togglePlay() {
      if (!this.video) return;

      if (this.video.paused) {
        this.video.play().catch(() => {});
      } else {
        this.video.pause();
      }
    },

    toggleMute() {
      if (!this.video) return;

      this.video.muted = !this.video.muted;
      this.syncMeta();
    },

    skipBy(seconds) {
      if (!this.video) return;

      const duration = Number.isFinite(this.video.duration)
        ? this.video.duration
        : null;
      const targetTime = this.video.currentTime + seconds;

      if (duration === null) {
        this.video.currentTime = Math.max(0, targetTime);
      } else {
        this.video.currentTime = Math.min(duration, Math.max(0, targetTime));
      }

      this.syncProgress();
    },

    adjustSpeed(delta) {
      if (!this.video) return;

      const nextRate = Math.min(
        2,
        Math.max(0.25, this.video.playbackRate + delta),
      );
      this.video.playbackRate = Number(nextRate.toFixed(2));
      this.syncMeta();
    },

    resetSpeed() {
      if (!this.video) return;

      this.video.playbackRate = 1;
      this.syncMeta();
    },

    toggleFullscreen() {
      if (document.fullscreenElement === this.el) {
        document.exitFullscreen?.();
        return;
      }

      this.el.requestFullscreen?.().catch(() => {});
    },

    seek(event) {
      if (!this.video || !Number.isFinite(this.video.duration)) return;

      const percentage = Number(event.target.value || 0);
      this.video.currentTime = (percentage / 100) * this.video.duration;
      this.syncProgress();
    },

    updatePreview(event) {
      if (!this.previewPopover || !this.previewCanvas || !this.previewVideo)
        return;
      if (!Number.isFinite(this.video?.duration)) return;

      const rect = this.progress.getBoundingClientRect();
      const offsetX = Math.min(
        Math.max(event.clientX - rect.left, 0),
        rect.width,
      );
      const percentage = rect.width > 0 ? offsetX / rect.width : 0;
      const previewTime = percentage * this.video.duration;

      this.previewPopover.classList.remove("hidden");
      this.previewPopover.style.left = `${offsetX}px`;

      if (this.previewTimeLabel) {
        this.previewTimeLabel.textContent = this.formatTime(previewTime);
      }

      if (
        Number.isFinite(this.previewVideo.duration) &&
        Math.abs(this.previewVideo.currentTime - previewTime) < 0.25
      ) {
        this.drawPreviewFrame();
        return;
      }

      this.pendingPreviewTime = previewTime;

      try {
        this.previewVideo.currentTime = previewTime;
      } catch (_) {}
    },

    hidePreview() {
      this.previewPopover?.classList.add("hidden");
    },

    drawPreviewFrame() {
      if (!this.previewContext || !this.previewCanvas || !this.previewVideo)
        return;
      if (this.previewVideo.readyState < 2) return;

      const width = this.previewCanvas.width;
      const height = this.previewCanvas.height;

      this.previewContext.clearRect(0, 0, width, height);
      this.previewContext.drawImage(this.previewVideo, 0, 0, width, height);
    },

    handleEnded() {
      if (!this.video) return;

      this.video.currentTime = 0;
      this.syncProgress();
      this.syncMeta();
    },

    syncMeta() {
      if (!this.video) return;

      const duration = Number.isFinite(this.video.duration)
        ? this.video.duration
        : 0;
      const playing = !this.video.paused && !this.video.ended;
      const muted = this.video.muted;
      const playbackRate = this.video.playbackRate || 1;
      const fullscreen = document.fullscreenElement === this.el;

      this.durationLabel &&
        (this.durationLabel.textContent = this.formatTime(duration));
      this.inlineDurationLabel &&
        (this.inlineDurationLabel.textContent = this.formatTime(duration));
      this.speedLabel &&
        (this.speedLabel.textContent = this.formatSpeed(playbackRate));
      this.speedBadge &&
        (this.speedBadge.textContent = this.formatSpeed(playbackRate));
      this.el.dataset.state = playing ? "playing" : "paused";

      this.playButtons?.forEach((button) => {
        button.setAttribute(
          "aria-label",
          playing ? "Pausar video" : "Reproduzir video",
        );

        const playIcon = button.querySelector('[data-icon="play"]');
        const pauseIcon = button.querySelector('[data-icon="pause"]');

        playIcon?.classList.toggle("hidden", playing);
        pauseIcon?.classList.toggle("hidden", !playing);
      });

      if (this.muteButton) {
        this.muteButton.setAttribute(
          "aria-label",
          muted ? "Ativar som" : "Silenciar video",
        );
        this.muteButton
          .querySelector('[data-icon="volume-on"]')
          ?.classList.toggle("hidden", muted);
        this.muteButton
          .querySelector('[data-icon="volume-off"]')
          ?.classList.toggle("hidden", !muted);
      }

      if (this.fullscreenButton) {
        this.fullscreenButton.setAttribute(
          "aria-label",
          fullscreen ? "Sair da tela cheia" : "Ativar tela cheia",
        );
        this.fullscreenButton
          .querySelector('[data-icon="fullscreen-enter"]')
          ?.classList.toggle("hidden", fullscreen);
        this.fullscreenButton
          .querySelector('[data-icon="fullscreen-exit"]')
          ?.classList.toggle("hidden", !fullscreen);
      }
    },

    syncProgress() {
      if (!this.video || !this.progress) return;

      const duration = Number.isFinite(this.video.duration)
        ? this.video.duration
        : 0;
      const currentTime = Number.isFinite(this.video.currentTime)
        ? this.video.currentTime
        : 0;
      const percentage = duration > 0 ? (currentTime / duration) * 100 : 0;

      this.progress.value = String(percentage);
      this.progress.style.setProperty("--video-progress", `${percentage}%`);

      if (this.currentTimeLabel) {
        this.currentTimeLabel.textContent = this.formatTime(currentTime);
      }
    },

    formatTime(value) {
      const totalSeconds = Math.max(0, Math.floor(value || 0));
      const minutes = Math.floor(totalSeconds / 60);
      const seconds = totalSeconds % 60;

      return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
    },

    formatSpeed(value) {
      const normalized = Number(value || 1);
      return `${normalized % 1 === 0 ? normalized.toFixed(0) : normalized.toFixed(2).replace(/0$/, "")}x`;
    },

    handleKeydown(event) {
      if (document.fullscreenElement && document.fullscreenElement !== this.el)
        return;

      const activeTag = document.activeElement?.tagName;
      if (["INPUT", "TEXTAREA", "SELECT"].includes(activeTag)) return;

      switch (event.key) {
        case " ":
        case "Spacebar":
          event.preventDefault();
          this.togglePlay();
          break;
        case "ArrowLeft":
          event.preventDefault();
          this.skipBy(-5);
          break;
        case "ArrowRight":
          event.preventDefault();
          this.skipBy(5);
          break;
        case "ArrowUp":
          event.preventDefault();
          this.adjustSpeed(0.25);
          break;
        case "ArrowDown":
          event.preventDefault();
          this.adjustSpeed(-0.25);
          break;
        case "r":
        case "R":
          event.preventDefault();
          this.resetSpeed();
          break;
        case "f":
        case "F":
          event.preventDefault();
          this.toggleFullscreen();
          break;
      }
    },
  },
};

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...colocatedHooks, ...Hooks },
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      // Enable server log streaming to client.
      // Disable with reloader.disableServerLogs()
      reloader.enableServerLogs();

      // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
      //
      //   * click with "c" key pressed to open at caller location
      //   * click with "d" key pressed to open at function component definition location
      let keyDown;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (_e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}
