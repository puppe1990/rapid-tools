import jsQR from "../vendor/jsqr.js"

let QrScanner = {
  mounted() {
    this.video = document.createElement("video")
    this.canvas = document.createElement("canvas")
    this.context = this.canvas.getContext("2d", {willReadFrequently: true})
    this.stream = null
    this.frameId = null
    this.scanned = false

    this.video.setAttribute("playsinline", "true")
    this.video.className = "h-72 w-full object-cover"
    this.canvas.className = "hidden"

    this.el.appendChild(this.video)
    this.el.appendChild(this.canvas)

    if (this.isActive()) {
      this.start()
    }
  },

  updated() {
    if (this.isActive()) {
      this.start()
    } else {
      this.stop()
    }
  },

  destroyed() {
    this.stop()
  },

  isActive() {
    return this.el.dataset.active === "true"
  },

  start() {
    if (this.stream || this.scanned) return

    if (!navigator.mediaDevices?.getUserMedia) {
      return
    }

    navigator.mediaDevices
      .getUserMedia({video: {facingMode: "environment"}})
      .then((stream) => {
        this.stream = stream
        this.video.srcObject = stream
        this.video.play()
        this.scanFrame()
      })
      .catch(() => {})
  },

  stop() {
    if (this.frameId) {
      cancelAnimationFrame(this.frameId)
      this.frameId = null
    }

    if (this.stream) {
      this.stream.getTracks().forEach((track) => track.stop())
      this.stream = null
    }

    if (this.video) {
      this.video.srcObject = null
    }
  },

  scanFrame() {
    if (!this.stream || this.scanned || !this.isActive()) {
      return
    }

    if (this.video.readyState === this.video.HAVE_ENOUGH_DATA) {
      this.canvas.width = this.video.videoWidth
      this.canvas.height = this.video.videoHeight
      this.context.drawImage(this.video, 0, 0, this.canvas.width, this.canvas.height)

      const imageData = this.context.getImageData(0, 0, this.canvas.width, this.canvas.height)
      const code = jsQR(imageData.data, imageData.width, imageData.height, {
        inversionAttempts: "dontInvert",
      })

      if (code?.data) {
        this.scanned = true
        this.stop()
        this.pushEvent("scan-result", {text: code.data})
        return
      }
    }

    this.frameId = requestAnimationFrame(() => this.scanFrame())
  },
}

let ToolSearch = {
  mounted() {
    const nav = document.querySelector("#tool-nav")
    this.el.querySelector("input").addEventListener("input", (e) => {
      const query = e.target.value.toLowerCase().trim()
      const items = nav ? nav.querySelectorAll("[data-search-text]") : []
      items.forEach((item) => {
        const text = item.getAttribute("data-search-text") || ""
        item.style.display = query === "" || text.includes(query) ? "" : "none"
      })
    })
  },
}

let PreserveScroll = {
  mounted() {
    const key = `scroll-${this.el.id || "sidebar"}`
    const saved = sessionStorage.getItem(key)
    if (saved) {
      this.el.scrollTop = parseInt(saved, 10)
    }
    this.el.addEventListener("scroll", () => {
      sessionStorage.setItem(key, this.el.scrollTop)
    })
  },
}

export { QrScanner, ToolSearch, PreserveScroll }
