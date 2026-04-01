const COPY_ICON = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-3.5"><path fill-rule="evenodd" d="M15.988 3.012A2.25 2.25 0 0 0 13.75 1h-3.5a2.25 2.25 0 0 0-2.238 2.012c-.875.092-1.6.686-1.884 1.488H11A3 3 0 0 1 14 7.5v6.378a1.75 1.75 0 0 0 1.488-1.884V5.25a2.25 2.25 0 0 0-2.012-2.238ZM13.75 2.5a.75.75 0 0 0-.75-.75h-3.5a.75.75 0 0 0-.75.75v.25h5v-.25Z" clip-rule="evenodd" /><path fill-rule="evenodd" d="M3 6a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6Zm2.5 1a.5.5 0 0 0 0 1h5a.5.5 0 0 0 0-1h-5ZM5 9.5a.5.5 0 0 1 .5-.5h5a.5.5 0 0 1 0 1h-5a.5.5 0 0 1-.5-.5Zm.5 1.5a.5.5 0 0 0 0 1h3a.5.5 0 0 0 0-1h-3Z" clip-rule="evenodd" /></svg>`;

const CHECK_ICON = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-3.5"><path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" clip-rule="evenodd" /></svg>`;

const MarkdownCodeCopy = {
  mounted() { this._addCopyButtons(); },
  updated() { this._addCopyButtons(); },

  _addCopyButtons() {
    this.el.querySelectorAll("pre").forEach(pre => {
      if (pre.querySelector(".code-copy-btn")) return;
      pre.style.position = "relative";

      const btn = document.createElement("button");
      btn.className = "code-copy-btn";
      btn.title = "Copy code";
      btn.innerHTML = COPY_ICON;

      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        const code = pre.querySelector("code");
        const text = code ? code.textContent : pre.textContent;
        navigator.clipboard.writeText(text).then(() => {
          btn.classList.add("copied");
          btn.innerHTML = CHECK_ICON;
          setTimeout(() => {
            btn.classList.remove("copied");
            btn.innerHTML = COPY_ICON;
          }, 1500);
        });
      });

      pre.appendChild(btn);
    });
  }
};

export default MarkdownCodeCopy;
