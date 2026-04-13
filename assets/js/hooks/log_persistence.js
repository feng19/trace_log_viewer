const STORAGE_KEY = "trace_log_raw_text";

const LogPersistence = {
  mounted() {
    // On mount, check localStorage for previously saved raw_text and restore it
    const savedRawText = localStorage.getItem(STORAGE_KEY);
    if (savedRawText) {
      this.pushEvent("restore_log", { raw_text: savedRawText });
    }

    // Listen for save event from server (after upload/paste/sample)
    this.handleEvent("save_raw_text", ({ raw_text }) => {
      try {
        localStorage.setItem(STORAGE_KEY, raw_text);
      } catch (e) {
        console.warn("Failed to save raw_text to localStorage:", e);
      }
    });

    // Listen for clear event from server
    this.handleEvent("clear_raw_text", () => {
      localStorage.removeItem(STORAGE_KEY);
    });
  },
};

export default LogPersistence;
