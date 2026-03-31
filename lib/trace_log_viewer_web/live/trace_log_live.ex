defmodule TraceLogViewerWeb.TraceLogLive do
  use TraceLogViewerWeb, :live_view

  alias TraceLogViewer.LogParser

  import TraceLogViewerWeb.TraceLogLive.LogEntryComponent,
    only: [log_entry: 1, format_size: 1]

  # -------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Trace Log Viewer")
     |> assign(:entries, [])
     |> assign(:entries_empty?, true)
     |> assign(:filter, "all")
     |> assign(:search, "")
     |> assign(:raw_text, "")
     |> assign(:stats, %{total: 0, calls: 0, returns: 0})
     |> assign(:binary_modal_content, nil)
     |> assign(:string_modal_content, nil)
     |> assign(:string_modal_tab, "raw")
     |> allow_upload(:log_file, accept: :any, max_entries: 1, max_file_size: 50_000_000)}
  end

  # -------------------------------------------------------------------
  # Events
  # -------------------------------------------------------------------

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("upload_log", _params, socket) do
    [{text, _}] =
      consume_uploaded_entries(socket, :log_file, fn %{path: path}, _entry ->
        content = File.read!(path)
        {:ok, {content, path}}
      end)

    entries = LogParser.parse(text)
    stats = compute_stats(entries)

    {:noreply,
     socket
     |> assign(:raw_text, text)
     |> assign(:entries_empty?, entries == [])
     |> assign(:stats, stats)
     |> assign(:filter, "all")
     |> assign(:search, "")
     |> stream(:log_entries, entries, reset: true)}
  end

  @impl true
  def handle_event("paste_log", %{"log_text" => text}, socket) do
    entries = LogParser.parse(text)
    stats = compute_stats(entries)

    {:noreply,
     socket
     |> assign(:raw_text, text)
     |> assign(:entries_empty?, entries == [])
     |> assign(:stats, stats)
     |> assign(:filter, "all")
     |> assign(:search, "")
     |> stream(:log_entries, entries, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    entries = LogParser.parse(socket.assigns.raw_text)

    filtered =
      entries
      |> filter_entries(filter)
      |> search_entries(socket.assigns.search)

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> assign(:entries_empty?, filtered == [])
     |> stream(:log_entries, filtered, reset: true)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    entries = LogParser.parse(socket.assigns.raw_text)

    filtered =
      entries
      |> filter_entries(socket.assigns.filter)
      |> search_entries(search)

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:entries_empty?, filtered == [])
     |> stream(:log_entries, filtered, reset: true)}
  end

  @impl true
  def handle_event("clear", _params, socket) do
    {:noreply,
     socket
     |> assign(:raw_text, "")
     |> assign(:entries_empty?, true)
     |> assign(:stats, %{total: 0, calls: 0, returns: 0})
     |> assign(:filter, "all")
     |> assign(:search, "")
     |> stream(:log_entries, [], reset: true)}
  end

  @impl true
  def handle_event("show_binary", %{"content" => content}, socket) do
    {:noreply, assign(socket, :binary_modal_content, content)}
  end

  @impl true
  def handle_event("close_binary_modal", _params, socket) do
    {:noreply, assign(socket, :binary_modal_content, nil)}
  end

  @impl true
  def handle_event("show_string", %{"content" => content}, socket) do
    {:noreply,
     socket
     |> assign(:string_modal_content, content)
     |> assign(:string_modal_tab, "raw")}
  end

  @impl true
  def handle_event("close_string_modal", _params, socket) do
    {:noreply, assign(socket, :string_modal_content, nil)}
  end

  @impl true
  def handle_event("string_modal_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :string_modal_tab, tab)}
  end

  @impl true
  def handle_event("load_sample", _params, socket) do
    sample = sample_trace_log()
    entries = LogParser.parse(sample)
    stats = compute_stats(entries)

    {:noreply,
     socket
     |> assign(:raw_text, sample)
     |> assign(:entries_empty?, entries == [])
     |> assign(:stats, stats)
     |> assign(:filter, "all")
     |> assign(:search, "")
     |> stream(:log_entries, entries, reset: true)}
  end

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="trace-log-viewer" class="space-y-6" phx-hook=".CopyToClipboard">
        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div class="p-2 rounded-lg bg-primary/10">
              <.icon name="hero-command-line" class="size-6 text-primary" />
            </div>
            <div>
              <h1 class="text-2xl font-bold tracking-tight">Trace Log Viewer</h1>
              <p class="text-sm text-base-content/60">Explore and analyze Elixir trace logs</p>
            </div>
          </div>
          <%= if @stats.total > 0 do %>
            <button phx-click="clear" class="btn btn-sm btn-ghost text-error gap-1">
              <.icon name="hero-trash" class="size-4" /> Clear
            </button>
          <% end %>
        </div>

        <%!-- Upload / Paste area --%>
        <%= if @stats.total == 0 do %>
          <div class="space-y-4">
            <%!-- File upload --%>
            <form id="upload-form" phx-change="validate_upload" phx-submit="upload_log">
              <div class="border-2 border-dashed border-base-300 rounded-xl p-8 text-center hover:border-primary/50 transition-colors duration-200">
                <.live_file_input upload={@uploads.log_file} class="hidden" />
                <div class="flex flex-col items-center gap-3">
                  <div class="p-3 rounded-full bg-base-200">
                    <.icon name="hero-arrow-up-tray" class="size-8 text-base-content/50" />
                  </div>
                  <div>
                    <p class="font-medium">Drop a trace log file here or click to browse</p>
                    <p class="text-sm text-base-content/50 mt-1">Supports any text file up to 50MB</p>
                  </div>
                  <label
                    for={@uploads.log_file.ref}
                    class="btn btn-primary btn-sm mt-2 cursor-pointer"
                  >
                    Choose File
                  </label>
                </div>
                <%= for entry <- @uploads.log_file.entries do %>
                  <div class="mt-4 flex items-center gap-2 justify-center">
                    <.icon name="hero-document-text" class="size-5 text-success" />
                    <span class="text-sm font-medium">{entry.client_name}</span>
                    <span class="text-xs text-base-content/50">
                      ({format_size(entry.client_size)})
                    </span>
                  </div>
                <% end %>
                <%= if @uploads.log_file.entries != [] do %>
                  <button type="submit" class="btn btn-primary btn-sm mt-3">
                    <.icon name="hero-arrow-up-tray" class="size-4" /> Parse Log
                  </button>
                <% end %>
              </div>
            </form>

            <%!-- Paste area --%>
            <div class="divider text-base-content/40 text-sm">or paste log content</div>
            <form id="paste-form" phx-submit="paste_log">
              <textarea
                name="log_text"
                id="paste-textarea"
                rows="6"
                autofocus
                placeholder="Paste your trace log output here...\n\nExample:\n04:02:26.664250 MyApp.Module.function(arg1, arg2)\n04:02:26.664350 MyApp.Module.function/2 --> :ok"
                class="w-full rounded-lg border border-base-300 bg-base-200/50 p-4 font-mono text-sm focus:border-primary focus:ring-1 focus:ring-primary/30 resize-y placeholder:text-base-content/30"
              ></textarea>
              <div class="flex justify-between items-center mt-3">
                <button
                  type="button"
                  phx-click="load_sample"
                  class="btn btn-sm btn-ghost text-base-content/60 gap-1"
                >
                  <.icon name="hero-beaker" class="size-4" /> Load Sample
                </button>
                <button type="submit" class="btn btn-primary btn-sm gap-1">
                  <.icon name="hero-play" class="size-4" /> Parse
                </button>
              </div>
            </form>
          </div>
        <% end %>

        <%!-- Stats bar --%>
        <%= if @stats.total > 0 do %>
          <div class="flex flex-wrap items-center gap-3">
            <div class="flex items-center gap-2 px-3 py-1.5 rounded-full bg-base-200 text-sm font-medium">
              <.icon name="hero-queue-list" class="size-4 text-base-content/60" />
              <span>{@stats.total} entries</span>
            </div>
            <div class="flex items-center gap-2 px-3 py-1.5 rounded-full bg-info/10 text-sm font-medium text-info">
              <.icon name="hero-arrow-right-circle" class="size-4" />
              <span>{@stats.calls} calls</span>
            </div>
            <div class="flex items-center gap-2 px-3 py-1.5 rounded-full bg-success/10 text-sm font-medium text-success">
              <.icon name="hero-arrow-left-circle" class="size-4" />
              <span>{@stats.returns} returns</span>
            </div>
          </div>

          <%!-- Filter & search bar --%>
          <div class="flex flex-wrap gap-3 items-center">
            <div class="flex rounded-lg border border-base-300 overflow-hidden">
              <button
                phx-click="filter"
                phx-value-filter="all"
                class={[
                  "px-3 py-1.5 text-sm font-medium transition-colors",
                  if(@filter == "all",
                    do: "bg-primary text-primary-content",
                    else: "bg-base-200 hover:bg-base-300"
                  )
                ]}
              >
                All
              </button>
              <button
                phx-click="filter"
                phx-value-filter="calls"
                class={[
                  "px-3 py-1.5 text-sm font-medium transition-colors border-l border-base-300",
                  if(@filter == "calls",
                    do: "bg-info text-info-content",
                    else: "bg-base-200 hover:bg-base-300"
                  )
                ]}
              >
                Calls
              </button>
              <button
                phx-click="filter"
                phx-value-filter="returns"
                class={[
                  "px-3 py-1.5 text-sm font-medium transition-colors border-l border-base-300",
                  if(@filter == "returns",
                    do: "bg-success text-success-content",
                    else: "bg-base-200 hover:bg-base-300"
                  )
                ]}
              >
                Returns
              </button>
            </div>
            <div class="flex-1 min-w-[200px]">
              <form phx-change="search" id="search-form">
                <div class="relative">
                  <.icon
                    name="hero-magnifying-glass"
                    class="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-base-content/40"
                  />
                  <input
                    type="text"
                    name="search"
                    value={@search}
                    placeholder="Search logs..."
                    class="w-full pl-9 pr-4 py-1.5 text-sm rounded-lg border border-base-300 bg-base-100 focus:border-primary focus:ring-1 focus:ring-primary/30"
                    phx-debounce="300"
                  />
                </div>
              </form>
            </div>
          </div>

          <%!-- Log entries --%>
          <div id="log-entries" phx-update="stream" class="space-y-1">
            <div class="hidden only:flex items-center justify-center py-12 text-base-content/40">
              <.icon name="hero-magnifying-glass" class="size-5 mr-2" /> No matching entries found
            </div>
            <div :for={{dom_id, entry} <- @streams.log_entries} id={dom_id}>
              <.log_entry entry={entry} />
            </div>
          </div>
        <% end %>

        <%!-- Binary content modal --%>
        <%= if @binary_modal_content do %>
          <div
            id="binary-modal-overlay"
            class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm animate-fade-in"
          >
            <div
              id="binary-modal"
              class="relative mx-4 max-w-3xl w-full max-h-[80vh] flex flex-col bg-base-100 rounded-xl shadow-2xl border border-base-300 animate-scale-in"
              phx-click-away="close_binary_modal"
            >
              <%!-- Modal header --%>
              <div class="flex items-center justify-between px-5 py-3 border-b border-base-300">
                <div class="flex items-center gap-2">
                  <span class="text-warning/70 font-mono text-sm font-semibold">
                    &lt;&lt; Binary &gt;&gt;
                  </span>
                  <span class="text-xs text-base-content/40">
                    {String.length(@binary_modal_content)} chars
                  </span>
                </div>
                <div class="flex items-center gap-2">
                  <button
                    data-copy-text={"<<#{@binary_modal_content}>>"}
                    title="Copy binary"
                    class="p-1.5 rounded-lg text-base-content/40 hover:text-primary hover:bg-base-200 transition-all duration-150 cursor-pointer"
                  >
                    <.icon name="hero-clipboard-document" class="size-4" />
                  </button>
                  <button
                    phx-click="close_binary_modal"
                    class="p-1.5 rounded-lg text-base-content/40 hover:text-error hover:bg-error/10 transition-all duration-150 cursor-pointer"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              </div>
              <%!-- Modal body --%>
              <div class="flex-1 overflow-auto p-5">
                <pre class="font-mono text-sm text-warning/80 whitespace-pre-wrap break-all leading-relaxed">&lt;&lt;{@binary_modal_content}&gt;&gt;</pre>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- String content modal --%>
        <%= if @string_modal_content do %>
          <div
            id="string-modal-overlay"
            class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm animate-fade-in"
          >
            <div
              id="string-modal"
              class="relative mx-4 max-w-7xl w-full max-h-[85vh] flex flex-col bg-base-100 rounded-xl shadow-2xl border border-base-300 animate-scale-in"
              phx-click-away="close_string_modal"
              phx-hook=".StringModalSearch"
            >
              <%!-- Modal header --%>
              <div class="flex items-center justify-between px-5 py-3 border-b border-base-300">
                <div class="flex items-center gap-2">
                  <span class="text-success font-mono text-sm font-semibold">
                    String
                  </span>
                  <span class="text-xs text-base-content/40">
                    {String.length(@string_modal_content) - 2} chars
                  </span>
                </div>
                <div class="flex items-center gap-3">
                  <%!-- Search input --%>
                  <div class="flex items-center gap-1">
                    <div class="relative">
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 20 20"
                        fill="currentColor"
                        class="absolute left-2.5 top-1/2 -translate-y-1/2 size-3.5 text-base-content/30 pointer-events-none"
                      >
                        <path
                          fill-rule="evenodd"
                          d="M9 3.5a5.5 5.5 0 1 0 0 11 5.5 5.5 0 0 0 0-11ZM2 9a7 7 0 1 1 12.452 4.391l3.328 3.329a.75.75 0 1 1-1.06 1.06l-3.329-3.328A7 7 0 0 1 2 9Z"
                          clip-rule="evenodd"
                        />
                      </svg>
                      <input
                        type="text"
                        data-search-input
                        placeholder="Search…"
                        class="w-48 pl-8 pr-14 py-1 text-xs rounded-md border border-base-300 bg-base-200/50 focus:border-primary focus:ring-1 focus:ring-primary/30 font-mono"
                      />
                      <span
                        data-match-count
                        class="absolute right-2.5 top-1/2 -translate-y-1/2 text-[10px] text-base-content/40 pointer-events-none"
                      >
                      </span>
                    </div>
                    <button
                      data-search-prev
                      title="Previous match (Shift+Enter)"
                      class="p-1 rounded text-base-content/30 hover:text-base-content/70 hover:bg-base-200 transition-all duration-150 cursor-pointer"
                    >
                      <.icon name="hero-chevron-up" class="size-3.5" />
                    </button>
                    <button
                      data-search-next
                      title="Next match (Enter)"
                      class="p-1 rounded text-base-content/30 hover:text-base-content/70 hover:bg-base-200 transition-all duration-150 cursor-pointer"
                    >
                      <.icon name="hero-chevron-down" class="size-3.5" />
                    </button>
                  </div>
                  <button
                    data-copy-text={string_modal_copy_text(@string_modal_content, @string_modal_tab)}
                    title="Copy string"
                    class="p-1.5 rounded-lg text-base-content/40 hover:text-primary hover:bg-base-200 transition-all duration-150 cursor-pointer"
                  >
                    <.icon name="hero-clipboard-document" class="size-4" />
                  </button>
                  <button
                    phx-click="close_string_modal"
                    class="p-1.5 rounded-lg text-base-content/40 hover:text-error hover:bg-error/10 transition-all duration-150 cursor-pointer"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              </div>
              <%!-- Tab bar --%>
              <div class="flex border-b border-base-300 px-5 gap-1">
                <button
                  phx-click="string_modal_tab"
                  phx-value-tab="raw"
                  class={[
                    "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors cursor-pointer",
                    if(@string_modal_tab == "raw",
                      do: "border-success text-success",
                      else:
                        "border-transparent text-base-content/50 hover:text-base-content/80 hover:border-base-300"
                    )
                  ]}
                >
                  <.icon name="hero-code-bracket" class="size-4 inline mr-1" /> Raw
                </button>
                <button
                  phx-click="string_modal_tab"
                  phx-value-tab="io_puts"
                  class={[
                    "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors cursor-pointer",
                    if(@string_modal_tab == "io_puts",
                      do: "border-info text-info",
                      else:
                        "border-transparent text-base-content/50 hover:text-base-content/80 hover:border-base-300"
                    )
                  ]}
                >
                  <.icon name="hero-command-line" class="size-4 inline mr-1" /> IO.puts
                </button>
                <button
                  phx-click="string_modal_tab"
                  phx-value-tab="markdown"
                  class={[
                    "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors cursor-pointer",
                    if(@string_modal_tab == "markdown",
                      do: "border-accent text-accent",
                      else:
                        "border-transparent text-base-content/50 hover:text-base-content/80 hover:border-base-300"
                    )
                  ]}
                >
                  <.icon name="hero-document-text" class="size-4 inline mr-1" /> Markdown
                </button>
              </div>
              <%!-- Modal body --%>
              <div class="flex-1 overflow-auto p-5" data-search-content>
                <%= cond do %>
                  <% @string_modal_tab == "raw" -> %>
                    <pre class="font-mono text-sm text-success whitespace-pre-wrap break-all leading-relaxed">{@string_modal_content}</pre>
                  <% @string_modal_tab == "io_puts" -> %>
                    <pre class="font-mono text-sm text-base-content/90 whitespace-pre-wrap break-all leading-relaxed">{unescape_string(@string_modal_content)}</pre>
                  <% @string_modal_tab == "markdown" -> %>
                    <div
                      id="markdown-body"
                      class="prose prose-sm max-w-none dark:prose-invert"
                      phx-hook=".MarkdownCodeCopy"
                      phx-update="ignore"
                    >
                      {render_markdown(@string_modal_content)}
                    </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToClipboard">
      export default {
        mounted() {
          this.el.addEventListener("click", (e) => {
            const btn = e.target.closest("[data-copy-text]");
            if (!btn) return;
            e.stopPropagation();
            const text = btn.getAttribute("data-copy-text");
            navigator.clipboard.writeText(text).then(() => {
              const icon = btn.querySelector("svg, span[class*='hero-']");
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
      }
    </script>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".StringModalSearch">
      export default {
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
      }
    </script>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".MarkdownCodeCopy">
      export default {
        mounted() { this._addCopyButtons(); },
        updated() { this._addCopyButtons(); },
        _addCopyButtons() {
          this.el.querySelectorAll("pre").forEach(pre => {
            if (pre.querySelector(".code-copy-btn")) return;
            pre.style.position = "relative";

            const btn = document.createElement("button");
            btn.className = "code-copy-btn";
            btn.title = "Copy code";
            btn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-3.5"><path fill-rule="evenodd" d="M15.988 3.012A2.25 2.25 0 0 0 13.75 1h-3.5a2.25 2.25 0 0 0-2.238 2.012c-.875.092-1.6.686-1.884 1.488H11A3 3 0 0 1 14 7.5v6.378a1.75 1.75 0 0 0 1.488-1.884V5.25a2.25 2.25 0 0 0-2.012-2.238ZM13.75 2.5a.75.75 0 0 0-.75-.75h-3.5a.75.75 0 0 0-.75.75v.25h5v-.25Z" clip-rule="evenodd" /><path fill-rule="evenodd" d="M3 6a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6Zm2.5 1a.5.5 0 0 0 0 1h5a.5.5 0 0 0 0-1h-5ZM5 9.5a.5.5 0 0 1 .5-.5h5a.5.5 0 0 1 0 1h-5a.5.5 0 0 1-.5-.5Zm.5 1.5a.5.5 0 0 0 0 1h3a.5.5 0 0 0 0-1h-3Z" clip-rule="evenodd" /></svg>`;

            btn.addEventListener("click", (e) => {
              e.stopPropagation();
              const code = pre.querySelector("code");
              const text = code ? code.textContent : pre.textContent;
              navigator.clipboard.writeText(text).then(() => {
                btn.classList.add("copied");
                btn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-3.5"><path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" clip-rule="evenodd" /></svg>`;
                setTimeout(() => {
                  btn.classList.remove("copied");
                  btn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-3.5"><path fill-rule="evenodd" d="M15.988 3.012A2.25 2.25 0 0 0 13.75 1h-3.5a2.25 2.25 0 0 0-2.238 2.012c-.875.092-1.6.686-1.884 1.488H11A3 3 0 0 1 14 7.5v6.378a1.75 1.75 0 0 0 1.488-1.884V5.25a2.25 2.25 0 0 0-2.012-2.238ZM13.75 2.5a.75.75 0 0 0-.75-.75h-3.5a.75.75 0 0 0-.75.75v.25h5v-.25Z" clip-rule="evenodd" /><path fill-rule="evenodd" d="M3 6a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6Zm2.5 1a.5.5 0 0 0 0 1h5a.5.5 0 0 0 0-1h-5ZM5 9.5a.5.5 0 0 1 .5-.5h5a.5.5 0 0 1 0 1h-5a.5.5 0 0 1-.5-.5Zm.5 1.5a.5.5 0 0 0 0 1h3a.5.5 0 0 0 0-1h-3Z" clip-rule="evenodd" /></svg>`;
                }, 1500);
              });
            });

            pre.appendChild(btn);
          });
        }
      }
    </script>
    """
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp filter_entries(entries, "all"), do: entries
  defp filter_entries(entries, "calls"), do: Enum.filter(entries, &(&1.type == :call))
  defp filter_entries(entries, "returns"), do: Enum.filter(entries, &(&1.type == :return))

  defp search_entries(entries, ""), do: entries

  defp search_entries(entries, search) do
    search_down = String.downcase(search)

    Enum.filter(entries, fn entry ->
      String.contains?(String.downcase(entry.raw), search_down)
    end)
  end

  defp string_modal_copy_text(content, "raw"), do: content
  defp string_modal_copy_text(content, "io_puts"), do: unescape_string(content)
  defp string_modal_copy_text(content, "markdown"), do: unescape_string(content)
  defp string_modal_copy_text(content, _), do: content

  defp unescape_string(raw_string) do
    # Strip surrounding quotes (first and last character)
    inner =
      cond do
        String.starts_with?(raw_string, "\"") and String.ends_with?(raw_string, "\"") ->
          String.slice(raw_string, 1..-2//1)

        String.starts_with?(raw_string, "'") and String.ends_with?(raw_string, "'") ->
          String.slice(raw_string, 1..-2//1)

        true ->
          raw_string
      end

    # Process escape sequences like IO.puts would
    inner
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\r", "\r")
    |> String.replace("\\\\", "\\")
    |> String.replace("\\\"", "\"")
    |> String.replace("\\'", "'")
  end

  defp render_markdown(raw_string) do
    inner = unescape_string(raw_string)

    case Earmark.as_html(inner) do
      {:ok, html, _warnings} ->
        Phoenix.HTML.raw(html)

      {:error, _html, _errors} ->
        Phoenix.HTML.raw(
          "<pre>#{Phoenix.HTML.html_escape(inner) |> Phoenix.HTML.safe_to_string()}</pre>"
        )
    end
  end

  defp compute_stats(entries) do
    %{
      total: length(entries),
      calls: Enum.count(entries, &(&1.type == :call)),
      returns: Enum.count(entries, &(&1.type == :return))
    }
  end

  defp sample_trace_log do
    """
    04:02:26.664250 MyApp.Accounts.get_user(%{id: 42, name: "Alice", email: "alice@example.com", metadata: %{role: :admin, permissions: [:read, :write, :delete], last_login: ~U[2024-01-15 10:30:00Z]}})
    04:02:26.664350 MyApp.Repo.get(MyApp.Accounts.User, 42)
    04:02:26.665100 MyApp.Repo.get/2 --> %MyApp.Accounts.User{id: 42, name: "Alice", email: "alice@example.com", inserted_at: ~N[2024-01-01 00:00:00], updated_at: ~N[2024-01-15 10:30:00], metadata: %{role: :admin, permissions: [:read, :write, :delete]}}
    04:02:26.665200 MyApp.Accounts.get_user/1 --> {:ok, %MyApp.Accounts.User{id: 42, name: "Alice", email: "alice@example.com", inserted_at: ~N[2024-01-01 00:00:00], updated_at: ~N[2024-01-15 10:30:00], metadata: %{role: :admin, permissions: [:read, :write, :delete]}}}
    04:02:26.665300 MyApp.Cache.put(:user_42, %{id: 42, name: "Alice", ttl: 3600, tags: [:user, :admin]})
    04:02:26.665400 MyApp.Cache.put/2 --> :ok
    04:02:26.665500 MyApp.Analytics.track_event("user_lookup", %{user_id: 42, source: "api", headers: [{"content-type", "application/json"}, {"authorization", "Bearer token123"}], params: %{include: ["profile", "settings"], format: "json"}})
    04:02:26.665600 MyApp.Analytics.track_event/2 --> {:ok, %{event_id: "evt_abc123", tracked_at: ~U[2024-01-15 10:30:01Z]}}
    """
  end
end
