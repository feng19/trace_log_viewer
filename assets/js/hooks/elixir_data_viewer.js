import ElixirDataViewer from "../../vendor/elixir-data-viewer"

// ---------------------------------------------------------------------------
// Global EDV instance registry – allows the KeyFilter hook to aggregate keys
// and apply filters across all mounted viewers.
// ---------------------------------------------------------------------------
if (!window.__edvInstances) {
  window.__edvInstances = [];
}
if (!window.__edvFilterKeys) {
  window.__edvFilterKeys = [];
}

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

    // Register in global registry
    window.__edvInstances.push(viewer);

    // Apply any existing global filter keys (so newly streamed entries inherit)
    if (window.__edvFilterKeys.length > 0) {
      viewer.setFilterKeys(window.__edvFilterKeys);
    }

    // Notify KeyFilter hook that a new instance is available
    window.dispatchEvent(new CustomEvent("edv:instance-changed"));

    // Apply any existing search query (for newly streamed entries)
    if (window.__edvSearchQuery) {
      viewer.search(window.__edvSearchQuery, {scroll: false});
    }

    // Listen for search highlight events pushed from the server
    this.handleEvent("search_highlight", ({ query }) => {
      window.__edvSearchQuery = query || "";
      if (this.viewer) {
        if (query) {
          this.viewer.search(query, {scroll: false});
        } else {
          this.viewer.clearSearch();
        }
      }
    });
  },

  destroyed() {
    // Unregister from global registry
    if (this.viewer) {
      const idx = window.__edvInstances.indexOf(this.viewer);
      if (idx !== -1) {
        window.__edvInstances.splice(idx, 1);
      }
      window.dispatchEvent(new CustomEvent("edv:instance-changed"));
    }
  },

  updated() {
    // phx-update="ignore" means this rarely fires,
    // but handle it for safety
    if (this.viewer) {
      this.viewer.setContent(this.el.dataset.content || "");
    }
  }
};
