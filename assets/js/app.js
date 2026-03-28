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
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/open_drive"
import topbar from "../vendor/topbar"

const Hooks = {
  FilePickerTrigger: {
    mounted() {
      this.handleClick = event => {
        if (event.target.closest("input, button, a, textarea, select")) return

        const selector = this.el.dataset.fileInput
        const input = selector ? document.querySelector(selector) : null

        input?.click()
      }

      this.handleKeydown = event => {
        if (event.key !== "Enter" && event.key !== " ") return

        event.preventDefault()
        this.handleClick(event)
      }

      this.el.addEventListener("click", this.handleClick)
      this.el.addEventListener("keydown", this.handleKeydown)
    },

    destroyed() {
      this.el.removeEventListener("click", this.handleClick)
      this.el.removeEventListener("keydown", this.handleKeydown)
    },
  },

  PasswordVisibility: {
    mounted() {
      this.input = this.el.querySelector("input")
      this.button = this.el.querySelector("[data-password-toggle-button]")
      this.showIcon = this.el.querySelector('[data-password-toggle-icon="show"]')
      this.hideIcon = this.el.querySelector('[data-password-toggle-icon="hide"]')

      this.toggleVisibility = event => {
        event.preventDefault()

        if (!this.input || !this.button) return

        const visible = this.input.type === "password"
        this.input.type = visible ? "text" : "password"
        this.button.setAttribute("aria-pressed", String(visible))
        this.button.setAttribute(
          "aria-label",
          visible ? this.button.dataset.hideLabel : this.button.dataset.showLabel
        )
        this.showIcon?.classList.toggle("hidden", visible)
        this.hideIcon?.classList.toggle("hidden", !visible)
        this.input.focus({preventScroll: true})
      }

      this.button?.addEventListener("click", this.toggleVisibility)
    },

    destroyed() {
      this.button?.removeEventListener("click", this.toggleVisibility)
    },
  },

  VideoPreview: {
    mounted() {
      this.video = this.el.querySelector("video")
      this.progress = this.el.querySelector('[data-role="progress"]')
      this.currentTimeLabel = this.el.querySelector('[data-role="current-time"]')
      this.durationLabel = this.el.querySelector('[data-role="duration"]')
      this.inlineDurationLabel = this.el.querySelector('[data-role="duration-inline"]')
      this.previewRegion = this.el.querySelector('[data-role="preview-region"]')
      this.previewPopover = this.el.querySelector('[data-role="preview-popover"]')
      this.previewCanvas = this.el.querySelector('[data-role="preview-canvas"]')
      this.previewTimeLabel = this.el.querySelector('[data-role="preview-time"]')
      this.previewContext = this.previewCanvas?.getContext("2d")
      this.speedLabel = this.el.querySelector('[data-role="speed"]')
      this.speedBadge = this.el.querySelector('[data-role="speed-badge"]')
      this.playButtons = this.el.querySelectorAll('[data-action="toggle-play"]')
      this.skipBackButton = this.el.querySelector('[data-action="seek-backward"]')
      this.skipForwardButton = this.el.querySelector('[data-action="seek-forward"]')
      this.speedDownButton = this.el.querySelector('[data-action="speed-down"]')
      this.speedUpButton = this.el.querySelector('[data-action="speed-up"]')
      this.muteButton = this.el.querySelector('[data-action="toggle-mute"]')
      this.fullscreenButton = this.el.querySelector('[data-action="toggle-fullscreen"]')
      this.boundTogglePlay = () => this.togglePlay()
      this.boundToggleMute = () => this.toggleMute()
      this.boundSeekBackward = () => this.skipBy(-5)
      this.boundSeekForward = () => this.skipBy(5)
      this.boundSpeedDown = () => this.adjustSpeed(-0.25)
      this.boundSpeedUp = () => this.adjustSpeed(0.25)
      this.boundToggleFullscreen = () => this.toggleFullscreen()
      this.boundSyncProgress = () => this.syncProgress()
      this.boundSyncMeta = () => this.syncMeta()
      this.boundHandleEnded = () => this.handleEnded()
      this.boundSeek = event => this.seek(event)
      this.boundPreviewMove = event => this.updatePreview(event)
      this.boundPreviewLeave = () => this.hidePreview()
      this.boundKeydown = event => this.handleKeydown(event)
      this.boundFullscreenChange = () => this.syncMeta()

      if (!this.video || !this.progress) return

      this.playButtons.forEach(button => button.addEventListener("click", this.boundTogglePlay))
      this.muteButton?.addEventListener("click", this.boundToggleMute)
      this.skipBackButton?.addEventListener("click", this.boundSeekBackward)
      this.skipForwardButton?.addEventListener("click", this.boundSeekForward)
      this.speedDownButton?.addEventListener("click", this.boundSpeedDown)
      this.speedUpButton?.addEventListener("click", this.boundSpeedUp)
      this.fullscreenButton?.addEventListener("click", this.boundToggleFullscreen)
      this.progress.addEventListener("input", this.boundSeek)
      this.progress.addEventListener("mousemove", this.boundPreviewMove)
      this.progress.addEventListener("mouseenter", this.boundPreviewMove)
      this.progress.addEventListener("mouseleave", this.boundPreviewLeave)
      this.video.addEventListener("timeupdate", this.boundSyncProgress)
      this.video.addEventListener("loadedmetadata", this.boundSyncMeta)
      this.video.addEventListener("durationchange", this.boundSyncMeta)
      this.video.addEventListener("play", this.boundSyncMeta)
      this.video.addEventListener("pause", this.boundSyncMeta)
      this.video.addEventListener("volumechange", this.boundSyncMeta)
      this.video.addEventListener("ratechange", this.boundSyncMeta)
      this.video.addEventListener("ended", this.boundHandleEnded)
      document.addEventListener("fullscreenchange", this.boundFullscreenChange)

      if (this.previewPopover) {
        this.previewVideo = document.createElement("video")
        this.previewVideo.src = this.video.currentSrc || this.video.src
        this.previewVideo.preload = "metadata"
        this.previewVideo.muted = true
        this.previewVideo.playsInline = true
        this.previewVideo.crossOrigin = "anonymous"
        this.previewVideo.addEventListener("seeked", () => this.drawPreviewFrame())
        this.previewVideo.addEventListener("loadeddata", () => this.drawPreviewFrame())
      }

      if (this.el.dataset.shortcuts === "true") {
        window.addEventListener("keydown", this.boundKeydown)
      }

      this.syncMeta()
      this.syncProgress()

      if (this.el.dataset.autoplay === "true") {
        this.video.muted = false
        this.video.play().catch(() => {})
      }
    },

    updated() {
      this.syncMeta?.()
      this.syncProgress?.()
    },

    destroyed() {
      this.video?.pause()
      this.playButtons?.forEach(button => button.removeEventListener("click", this.boundTogglePlay))
      this.muteButton?.removeEventListener("click", this.boundToggleMute)
      this.skipBackButton?.removeEventListener("click", this.boundSeekBackward)
      this.skipForwardButton?.removeEventListener("click", this.boundSeekForward)
      this.speedDownButton?.removeEventListener("click", this.boundSpeedDown)
      this.speedUpButton?.removeEventListener("click", this.boundSpeedUp)
      this.fullscreenButton?.removeEventListener("click", this.boundToggleFullscreen)
      this.progress?.removeEventListener("input", this.boundSeek)
      this.progress?.removeEventListener("mousemove", this.boundPreviewMove)
      this.progress?.removeEventListener("mouseenter", this.boundPreviewMove)
      this.progress?.removeEventListener("mouseleave", this.boundPreviewLeave)
      this.video?.removeEventListener("timeupdate", this.boundSyncProgress)
      this.video?.removeEventListener("loadedmetadata", this.boundSyncMeta)
      this.video?.removeEventListener("durationchange", this.boundSyncMeta)
      this.video?.removeEventListener("play", this.boundSyncMeta)
      this.video?.removeEventListener("pause", this.boundSyncMeta)
      this.video?.removeEventListener("volumechange", this.boundSyncMeta)
      this.video?.removeEventListener("ratechange", this.boundSyncMeta)
      this.video?.removeEventListener("ended", this.boundHandleEnded)
      document.removeEventListener("fullscreenchange", this.boundFullscreenChange)
      window.removeEventListener("keydown", this.boundKeydown)
      this.previewVideo?.removeAttribute("src")
      this.previewVideo?.load?.()
    },

    togglePlay() {
      if (!this.video) return

      if (this.video.paused) {
        this.video.play().catch(() => {})
      } else {
        this.video.pause()
      }
    },

    toggleMute() {
      if (!this.video) return

      this.video.muted = !this.video.muted
      this.syncMeta()
    },

    skipBy(seconds) {
      if (!this.video) return

      const duration = Number.isFinite(this.video.duration) ? this.video.duration : null
      const targetTime = this.video.currentTime + seconds

      if (duration === null) {
        this.video.currentTime = Math.max(0, targetTime)
      } else {
        this.video.currentTime = Math.min(duration, Math.max(0, targetTime))
      }

      this.syncProgress()
    },

    adjustSpeed(delta) {
      if (!this.video) return

      const nextRate = Math.min(2, Math.max(0.25, this.video.playbackRate + delta))
      this.video.playbackRate = Number(nextRate.toFixed(2))
      this.syncMeta()
    },

    resetSpeed() {
      if (!this.video) return

      this.video.playbackRate = 1
      this.syncMeta()
    },

    toggleFullscreen() {
      if (document.fullscreenElement === this.el) {
        document.exitFullscreen?.()
        return
      }

      this.el.requestFullscreen?.().catch(() => {})
    },

    seek(event) {
      if (!this.video || !Number.isFinite(this.video.duration)) return

      const percentage = Number(event.target.value || 0)
      this.video.currentTime = (percentage / 100) * this.video.duration
      this.syncProgress()
    },

    updatePreview(event) {
      if (!this.previewPopover || !this.previewCanvas || !this.previewVideo) return
      if (!Number.isFinite(this.video?.duration)) return

      const rect = this.progress.getBoundingClientRect()
      const offsetX = Math.min(Math.max(event.clientX - rect.left, 0), rect.width)
      const percentage = rect.width > 0 ? offsetX / rect.width : 0
      const previewTime = percentage * this.video.duration

      this.previewPopover.classList.remove("hidden")
      this.previewPopover.style.left = `${offsetX}px`

      if (this.previewTimeLabel) {
        this.previewTimeLabel.textContent = this.formatTime(previewTime)
      }

      if (Number.isFinite(this.previewVideo.duration) && Math.abs(this.previewVideo.currentTime - previewTime) < 0.25) {
        this.drawPreviewFrame()
        return
      }

      this.pendingPreviewTime = previewTime

      try {
        this.previewVideo.currentTime = previewTime
      } catch (_) {}
    },

    hidePreview() {
      this.previewPopover?.classList.add("hidden")
    },

    drawPreviewFrame() {
      if (!this.previewContext || !this.previewCanvas || !this.previewVideo) return
      if (this.previewVideo.readyState < 2) return

      const width = this.previewCanvas.width
      const height = this.previewCanvas.height

      this.previewContext.clearRect(0, 0, width, height)
      this.previewContext.drawImage(this.previewVideo, 0, 0, width, height)
    },

    handleEnded() {
      if (!this.video) return

      this.video.currentTime = 0
      this.syncProgress()
      this.syncMeta()
    },

    syncMeta() {
      if (!this.video) return

      const duration = Number.isFinite(this.video.duration) ? this.video.duration : 0
      const playing = !this.video.paused && !this.video.ended
      const muted = this.video.muted
      const playbackRate = this.video.playbackRate || 1
      const fullscreen = document.fullscreenElement === this.el

      this.durationLabel && (this.durationLabel.textContent = this.formatTime(duration))
      this.inlineDurationLabel && (this.inlineDurationLabel.textContent = this.formatTime(duration))
      this.speedLabel && (this.speedLabel.textContent = this.formatSpeed(playbackRate))
      this.speedBadge && (this.speedBadge.textContent = this.formatSpeed(playbackRate))
      this.el.dataset.state = playing ? "playing" : "paused"

      this.playButtons?.forEach(button => {
        button.setAttribute("aria-label", playing ? "Pausar video" : "Reproduzir video")

        const playIcon = button.querySelector('[data-icon="play"]')
        const pauseIcon = button.querySelector('[data-icon="pause"]')

        playIcon?.classList.toggle("hidden", playing)
        pauseIcon?.classList.toggle("hidden", !playing)
      })

      if (this.muteButton) {
        this.muteButton.setAttribute("aria-label", muted ? "Ativar som" : "Silenciar video")
        this.muteButton.querySelector('[data-icon="volume-on"]')?.classList.toggle("hidden", muted)
        this.muteButton.querySelector('[data-icon="volume-off"]')?.classList.toggle("hidden", !muted)
      }

      if (this.fullscreenButton) {
        this.fullscreenButton.setAttribute("aria-label", fullscreen ? "Sair da tela cheia" : "Ativar tela cheia")
        this.fullscreenButton.querySelector('[data-icon="fullscreen-enter"]')?.classList.toggle("hidden", fullscreen)
        this.fullscreenButton.querySelector('[data-icon="fullscreen-exit"]')?.classList.toggle("hidden", !fullscreen)
      }
    },

    syncProgress() {
      if (!this.video || !this.progress) return

      const duration = Number.isFinite(this.video.duration) ? this.video.duration : 0
      const currentTime = Number.isFinite(this.video.currentTime) ? this.video.currentTime : 0
      const percentage = duration > 0 ? (currentTime / duration) * 100 : 0

      this.progress.value = String(percentage)
      this.progress.style.setProperty("--video-progress", `${percentage}%`)

      if (this.currentTimeLabel) {
        this.currentTimeLabel.textContent = this.formatTime(currentTime)
      }
    },

    formatTime(value) {
      const totalSeconds = Math.max(0, Math.floor(value || 0))
      const minutes = Math.floor(totalSeconds / 60)
      const seconds = totalSeconds % 60

      return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
    },

    formatSpeed(value) {
      const normalized = Number(value || 1)
      return `${normalized % 1 === 0 ? normalized.toFixed(0) : normalized.toFixed(2).replace(/0$/, "")}x`
    },

    handleKeydown(event) {
      if (document.fullscreenElement && document.fullscreenElement !== this.el) return

      const activeTag = document.activeElement?.tagName
      if (["INPUT", "TEXTAREA", "SELECT"].includes(activeTag)) return

      switch (event.key) {
        case " ":
        case "Spacebar":
          event.preventDefault()
          this.togglePlay()
          break
        case "ArrowLeft":
          event.preventDefault()
          this.skipBy(-5)
          break
        case "ArrowRight":
          event.preventDefault()
          this.skipBy(5)
          break
        case "ArrowUp":
          event.preventDefault()
          this.adjustSpeed(0.25)
          break
        case "ArrowDown":
          event.preventDefault()
          this.adjustSpeed(-0.25)
          break
        case "r":
        case "R":
          event.preventDefault()
          this.resetSpeed()
          break
        case "f":
        case "F":
          event.preventDefault()
          this.toggleFullscreen()
          break
      }
    },
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
