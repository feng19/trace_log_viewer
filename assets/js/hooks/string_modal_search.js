const StringModalSearch = {
  mounted() {
    this._input = this.el.querySelector("[data-search-input]");
    this._content = this.el.querySelector("[data-search-content]");
    this._counter = this.el.querySelector("[data-match-count]");
    this._prevBtn = this.el.querySelector("[data-search-prev]");
    this._nextBtn = this.el.querySelector("[data-search-next]");
    this._debounce = null;
    this._currentIdx = -1;
    this._totalMatches = 0;
    if (!this._input || !this._content) return;

    this._input.addEventListener("input", () => {
      clearTimeout(this._debounce);
      this._debounce = setTimeout(() => { this._highlight(); this._goTo(0); }, 150);
    });

    // Enter = next, Shift+Enter = prev
    this._input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        if (e.shiftKey) { this._goPrev(); } else { this._goNext(); }
      }
    });

    if (this._prevBtn) this._prevBtn.addEventListener("click", () => this._goPrev());
    if (this._nextBtn) this._nextBtn.addEventListener("click", () => this._goNext());

    // Cmd/Ctrl+F focuses the search input
    this._keyHandler = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "f") {
        e.preventDefault();
        this._input.focus();
        this._input.select();
      }
      if (e.key === "Escape" && document.activeElement === this._input) {
        this._input.value = "";
        this._highlight();
        this._input.blur();
      }
    };
    this.el.addEventListener("keydown", this._keyHandler);
  },

  updated() {
    this._content = this.el.querySelector("[data-search-content]");
    if (this._input && this._input.value) {
      setTimeout(() => { this._highlight(); this._goTo(0); }, 50);
    }
  },

  _goNext() {
    if (this._totalMatches === 0) return;
    this._goTo((this._currentIdx + 1) % this._totalMatches);
  },

  _goPrev() {
    if (this._totalMatches === 0) return;
    this._goTo((this._currentIdx - 1 + this._totalMatches) % this._totalMatches);
  },

  _goTo(idx) {
    const marks = this._content.querySelectorAll("mark[data-search-hl]");
    if (marks.length === 0) { this._currentIdx = -1; this._updateCounter(); return; }
    // Remove active class from previous
    marks.forEach(m => m.classList.remove("search-highlight-active"));
    this._currentIdx = idx;
    const target = marks[idx];
    if (target) {
      target.classList.add("search-highlight-active");
      target.scrollIntoView({ block: "center", behavior: "smooth" });
    }
    this._updateCounter();
  },

  _updateCounter() {
    if (!this._counter) return;
    if (this._totalMatches === 0) {
      this._counter.textContent = this._input.value.trim() ? "0" : "";
    } else {
      this._counter.textContent = `${this._currentIdx + 1}/${this._totalMatches}`;
    }
  },

  _highlight() {
    const query = this._input.value.trim();
    const container = this._content;
    if (!container) return;

    // Remove existing marks
    container.querySelectorAll("mark[data-search-hl]").forEach(m => {
      const parent = m.parentNode;
      parent.replaceChild(document.createTextNode(m.textContent), m);
      parent.normalize();
    });

    this._currentIdx = -1;
    this._totalMatches = 0;

    if (!query) {
      this._updateCounter();
      return;
    }

    let count = 0;
    const regex = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi");

    const walk = (node) => {
      if (node.nodeType === Node.TEXT_NODE) {
        const text = node.textContent;
        if (!regex.test(text)) return;
        regex.lastIndex = 0;

        const frag = document.createDocumentFragment();
        let lastIdx = 0;
        let match;
        while ((match = regex.exec(text)) !== null) {
          if (match.index > lastIdx) {
            frag.appendChild(document.createTextNode(text.slice(lastIdx, match.index)));
          }
          const mark = document.createElement("mark");
          mark.setAttribute("data-search-hl", "");
          mark.className = "search-highlight";
          mark.textContent = match[0];
          frag.appendChild(mark);
          count++;
          lastIdx = regex.lastIndex;
        }
        if (lastIdx < text.length) {
          frag.appendChild(document.createTextNode(text.slice(lastIdx)));
        }
        node.parentNode.replaceChild(frag, node);
      } else if (node.nodeType === Node.ELEMENT_NODE && node.tagName !== "MARK") {
        Array.from(node.childNodes).forEach(walk);
      }
    };

    walk(container);
    this._totalMatches = count;
  }
};

export default StringModalSearch;
