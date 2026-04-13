import ElixirDataViewer from "../../vendor/elixir-data-viewer"

export default {
  mounted() {
    const viewer = new ElixirDataViewer(this.el, {
      defaultFoldLevel: 1,
      defaultWordWrap: true,
    });
    viewer.setContent(this.el.dataset.content || "");

    // Intercept String clicks → open string modal in LiveView
    viewer.onInspect((event) => {
      if (event.type === "String") {
        event.preventDefault();
        this.pushEvent("show_string", { content: event.copyText });
      }
    });

    this.viewer = viewer;

    // Apply any existing search query (for newly streamed entries)
    if (window.__edvSearchQuery) {
      viewer.search(window.__edvSearchQuery);
    }

    // Listen for search highlight events pushed from the server
    this.handleEvent("search_highlight", ({ query }) => {
      window.__edvSearchQuery = query || "";
      if (this.viewer) {
        if (query) {
          this.viewer.search(query);
        } else {
          this.viewer.clearSearch();
        }
      }
    });
  },

  updated() {
    // phx-update="ignore" means this rarely fires,
    // but handle it for safety
    if (this.viewer) {
      this.viewer.setContent(this.el.dataset.content || "");
    }
  }
};
