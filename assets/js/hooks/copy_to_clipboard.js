const CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-copy-text]");
      if (!btn) return;
      e.stopPropagation();
      const text = btn.getAttribute("data-copy-text");
      navigator.clipboard.writeText(text).then(() => {
        btn.classList.add("text-success");
        btn.classList.remove("text-base-content/30", "text-base-content/40");
        const originalTitle = btn.title;
        btn.title = "Copied!";
        setTimeout(() => {
          btn.classList.remove("text-success");
          btn.classList.add("text-base-content/30");
          btn.title = originalTitle;
        }, 1500);
      });
    });
  }
};

export default CopyToClipboard;
