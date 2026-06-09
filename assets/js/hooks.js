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

export { ToolSearch, PreserveScroll }
