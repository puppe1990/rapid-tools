let ToolSearch = {
  mounted() {
    const nav = document.querySelector("[aria-label='Tools']")
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

export { ToolSearch }
