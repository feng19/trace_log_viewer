// ---------------------------------------------------------------------------
// KeyFilter hook – global "filter by keys" bar for all EDV instances.
//
// Aggregates available keys from every registered ElixirDataViewer instance
// and applies the selected key filters to all of them simultaneously.
// The UI mirrors the EDV built-in filter bar: input with autocomplete
// dropdown, pill tags for selected keys, clear button, count indicator.
// ---------------------------------------------------------------------------

const FILTER_KEYS_STORAGE_KEY = "trace_log_filter_keys";

export default {
  mounted() {
    // Restore persisted filter keys from localStorage, falling back to global state
    const saved = this._loadPersistedKeys();
    if (saved.length > 0) {
      window.__edvFilterKeys = [...saved];
    }
    this.filterKeys = [...(window.__edvFilterKeys || [])];
    this.dropdownIndex = -1;
    this.dropdownItems = [];
    this.dropdownVisible = false;

    this.buildUI();
    this.updateTags();
    this.updateInfo();
    this.updateClearBtnVisibility();

    // Apply restored filters to any already-mounted EDV instances
    if (this.filterKeys.length > 0) {
      this.applyFilters();
    }

    // Re-aggregate keys when EDV instances mount/unmount
    this._onInstanceChanged = () => {
      if (this.dropdownVisible) {
        this.showSuggestions();
      }
      this.updateInfo();
    };
    window.addEventListener("edv:instance-changed", this._onInstanceChanged);

    // Close dropdown on outside click
    this._onDocClick = (e) => {
      if (!this.el.contains(e.target)) {
        this.hideDropdown();
      }
    };
    document.addEventListener("click", this._onDocClick);
  },

  destroyed() {
    window.removeEventListener("edv:instance-changed", this._onInstanceChanged);
    document.removeEventListener("click", this._onDocClick);
  },

  // -----------------------------------------------------------------------
  // UI construction — uses Tailwind classes to match the page theme
  // -----------------------------------------------------------------------

  buildUI() {
    // The container itself already has Tailwind classes from the HEEx template.
    // We just build inner content here.
    this.el.innerHTML = "";

    // Icon
    const icon = document.createElement("span");
    icon.className = "flex items-center justify-center shrink-0 text-base-content/40";
    icon.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-4">
      <path fill-rule="evenodd" d="M2.628 1.601C5.028 1.206 7.49 1 10 1s4.973.206 7.372.601a.75.75 0 0 1 .628.74v2.288a2.25 2.25 0 0 1-.659 1.59l-4.682 4.683a2.25 2.25 0 0 0-.659 1.59v3.037c0 .684-.31 1.33-.844 1.757l-1.937 1.55A.75.75 0 0 1 8 18.25v-5.757a2.25 2.25 0 0 0-.659-1.591L2.659 6.22A2.25 2.25 0 0 1 2 4.629V2.34a.75.75 0 0 1 .628-.74Z" clip-rule="evenodd" />
    </svg>`;
    this.el.appendChild(icon);

    // Tags container
    this.tagsEl = document.createElement("div");
    this.tagsEl.className = "flex items-center gap-1.5 flex-wrap";
    this.el.appendChild(this.tagsEl);

    // Input wrapper (for dropdown positioning)
    const inputWrapper = document.createElement("div");
    inputWrapper.className = "relative flex-1 min-w-[10rem]";

    this.inputEl = document.createElement("input");
    this.inputEl.type = "text";
    this.inputEl.className =
      "w-full px-2.5 py-1 text-sm font-mono rounded-md border border-base-300 bg-base-100 text-base-content " +
      "focus:border-primary focus:ring-1 focus:ring-primary/30 outline-none transition-all duration-150 " +
      "placeholder:text-base-content/30";
    this.inputEl.placeholder = "Filter by key…";
    this.inputEl.addEventListener("input", () => this.showSuggestions());
    this.inputEl.addEventListener("focus", () => this.showSuggestions());
    this.inputEl.addEventListener("keydown", (e) => this.handleKeyDown(e));
    inputWrapper.appendChild(this.inputEl);

    // Dropdown
    this.dropdownEl = document.createElement("div");
    this.dropdownEl.className =
      "hidden absolute top-full left-0 right-0 mt-1 z-50 " +
      "max-h-56 overflow-y-auto rounded-lg border border-base-300 bg-base-100 " +
      "shadow-lg";
    inputWrapper.appendChild(this.dropdownEl);

    this.el.appendChild(inputWrapper);

    // Info (count)
    this.infoEl = document.createElement("span");
    this.infoEl.className = "text-xs text-base-content/50 whitespace-nowrap shrink-0 hidden";
    this.el.appendChild(this.infoEl);

    // Clear button
    this.clearBtn = document.createElement("button");
    this.clearBtn.className =
      "hidden items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-md " +
      "border border-error/30 text-error/70 bg-transparent " +
      "hover:bg-error/10 hover:text-error hover:border-error/50 " +
      "transition-all duration-150 cursor-pointer whitespace-nowrap shrink-0";
    this.clearBtn.title = "Clear all key filters";
    this.clearBtn.textContent = "Clear";
    this.clearBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      this.clearAll();
    });
    this.el.appendChild(this.clearBtn);
  },

  // -----------------------------------------------------------------------
  // Key aggregation
  // -----------------------------------------------------------------------

  getAllAvailableKeys() {
    const instances = window.__edvInstances || [];
    const keySet = new Set();
    for (const viewer of instances) {
      try {
        const keys = viewer.getAvailableKeys();
        for (const k of keys) {
          keySet.add(k);
        }
      } catch (_) {
        // skip instances that may have been destroyed
      }
    }
    return Array.from(keySet).sort();
  },

  // -----------------------------------------------------------------------
  // Filter application
  // -----------------------------------------------------------------------

  applyFilters() {
    window.__edvFilterKeys = [...this.filterKeys];
    this._persistKeys();
    const instances = window.__edvInstances || [];
    for (const viewer of instances) {
      try {
        viewer.setFilterKeys(this.filterKeys);
      } catch (_) {
        // skip
      }
    }
    this.updateTags();
    this.updateInfo();
    this.updateClearBtnVisibility();
  },

  addKey(key) {
    if (!this.filterKeys.includes(key)) {
      this.filterKeys.push(key);
      this.applyFilters();
    }
    if (this.inputEl) {
      this.inputEl.value = "";
    }
    this.hideDropdown();
    if (this.inputEl) {
      this.inputEl.focus();
    }
  },

  removeKey(key) {
    this.filterKeys = this.filterKeys.filter((k) => k !== key);
    this.applyFilters();
  },

  clearAll() {
    this.filterKeys = [];
    window.__edvFilterKeys = [];
    this._persistKeys();
    const instances = window.__edvInstances || [];
    for (const viewer of instances) {
      try {
        viewer.clearFilter();
      } catch (_) {
        // skip
      }
    }
    this.updateTags();
    this.updateInfo();
    this.updateClearBtnVisibility();
    if (this.inputEl) {
      this.inputEl.value = "";
    }
    this.hideDropdown();
  },

  // -----------------------------------------------------------------------
  // Tags
  // -----------------------------------------------------------------------

  updateTags() {
    if (!this.tagsEl) return;
    this.tagsEl.innerHTML = "";
    for (const key of this.filterKeys) {
      const tag = document.createElement("span");
      tag.className =
        "inline-flex items-center gap-1 px-2 py-0.5 rounded-full " +
        "bg-primary/15 text-primary text-xs font-medium font-mono " +
        "leading-relaxed whitespace-nowrap transition-colors duration-150 hover:bg-primary/25";

      const label = document.createElement("span");
      label.className = "max-w-48 overflow-hidden text-ellipsis";
      label.textContent = key;
      tag.appendChild(label);

      const removeBtn = document.createElement("button");
      removeBtn.className =
        "inline-flex items-center justify-center w-3.5 h-3.5 rounded-full " +
        "text-primary/60 hover:text-error hover:bg-error/15 " +
        "transition-colors duration-150 cursor-pointer text-xs leading-none p-0 border-0 bg-transparent";
      removeBtn.innerHTML = "×";
      removeBtn.title = `Remove "${key}" filter`;
      removeBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        this.removeKey(key);
      });
      tag.appendChild(removeBtn);

      this.tagsEl.appendChild(tag);
    }
  },

  // -----------------------------------------------------------------------
  // Info
  // -----------------------------------------------------------------------

  updateInfo() {
    if (!this.infoEl) return;
    const count = this.filterKeys.length;
    if (count > 0) {
      this.infoEl.textContent = `${count} key${count > 1 ? "s" : ""} filtered`;
      this.infoEl.classList.remove("hidden");
    } else {
      this.infoEl.textContent = "";
      this.infoEl.classList.add("hidden");
    }
  },

  updateClearBtnVisibility() {
    if (!this.clearBtn) return;
    if (this.filterKeys.length > 0) {
      this.clearBtn.classList.remove("hidden");
      this.clearBtn.classList.add("inline-flex");
    } else {
      this.clearBtn.classList.add("hidden");
      this.clearBtn.classList.remove("inline-flex");
    }
  },

  // -----------------------------------------------------------------------
  // Dropdown
  // -----------------------------------------------------------------------

  showSuggestions() {
    const query = (this.inputEl?.value || "").trim().toLowerCase();
    const available = this.getAllAvailableKeys();
    const suggestions = available.filter(
      (k) => !this.filterKeys.includes(k) && (query === "" || k.toLowerCase().includes(query))
    );

    this.dropdownItems = suggestions;
    this.dropdownIndex = -1;

    if (suggestions.length === 0) {
      this.hideDropdown();
      return;
    }

    this.dropdownEl.innerHTML = "";
    for (let i = 0; i < suggestions.length; i++) {
      const item = document.createElement("div");
      item.className =
        "px-3 py-1.5 text-sm font-mono cursor-pointer " +
        "transition-colors duration-100 text-base-content/80 " +
        "hover:bg-primary/10 hover:text-primary";
      item.textContent = suggestions[i];
      item.addEventListener("mouseenter", () => {
        this.dropdownIndex = i;
        this.updateDropdownHighlight();
      });
      item.addEventListener("click", (e) => {
        e.stopPropagation();
        this.addKey(suggestions[i]);
      });
      this.dropdownEl.appendChild(item);
    }

    this.dropdownEl.classList.remove("hidden");
    this.dropdownVisible = true;
  },

  hideDropdown() {
    if (this.dropdownEl) {
      this.dropdownEl.classList.add("hidden");
    }
    this.dropdownVisible = false;
    this.dropdownIndex = -1;
  },

  updateDropdownHighlight() {
    if (!this.dropdownEl) return;
    const items = this.dropdownEl.children;
    for (let i = 0; i < items.length; i++) {
      if (i === this.dropdownIndex) {
        items[i].classList.add("bg-primary/10", "text-primary");
      } else {
        items[i].classList.remove("bg-primary/10", "text-primary");
      }
    }
    // Scroll active item into view
    if (this.dropdownIndex >= 0 && items[this.dropdownIndex]) {
      items[this.dropdownIndex].scrollIntoView({ block: "nearest" });
    }
  },

  // -----------------------------------------------------------------------
  // Keyboard navigation
  // -----------------------------------------------------------------------

  handleKeyDown(e) {
    const count = this.dropdownItems.length;

    if (e.key === "ArrowDown" && this.dropdownVisible && count > 0) {
      e.preventDefault();
      this.dropdownIndex = Math.min(this.dropdownIndex + 1, count - 1);
      this.updateDropdownHighlight();
      return;
    }

    if (e.key === "ArrowUp" && this.dropdownVisible && count > 0) {
      e.preventDefault();
      this.dropdownIndex = Math.max(this.dropdownIndex - 1, 0);
      this.updateDropdownHighlight();
      return;
    }

    if (e.key === "Enter") {
      e.preventDefault();
      if (this.dropdownVisible && this.dropdownIndex >= 0 && this.dropdownIndex < count) {
        this.addKey(this.dropdownItems[this.dropdownIndex]);
        return;
      }
      // Try exact match on input value
      const val = (this.inputEl?.value || "").trim();
      if (val) {
        const match = this.getAllAvailableKeys().find(
          (k) => k.toLowerCase() === val.toLowerCase()
        );
        if (match && !this.filterKeys.includes(match)) {
          this.addKey(match);
        }
      }
      return;
    }

    if (e.key === "Escape") {
      this.hideDropdown();
      this.inputEl?.blur();
      return;
    }

    // Backspace on empty input removes last tag
    if (e.key === "Backspace" && (this.inputEl?.value || "") === "" && this.filterKeys.length > 0) {
      this.removeKey(this.filterKeys[this.filterKeys.length - 1]);
      return;
    }
  },

  // -----------------------------------------------------------------------
  // LocalStorage persistence
  // -----------------------------------------------------------------------

  _persistKeys() {
    try {
      if (this.filterKeys.length > 0) {
        localStorage.setItem(FILTER_KEYS_STORAGE_KEY, JSON.stringify(this.filterKeys));
      } else {
        localStorage.removeItem(FILTER_KEYS_STORAGE_KEY);
      }
    } catch (e) {
      console.warn("Failed to persist filter keys to localStorage:", e);
    }
  },

  _loadPersistedKeys() {
    try {
      const raw = localStorage.getItem(FILTER_KEYS_STORAGE_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) {
          return parsed;
        }
      }
    } catch (e) {
      console.warn("Failed to load filter keys from localStorage:", e);
    }
    return [];
  },
};
