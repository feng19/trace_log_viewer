defmodule TraceLogViewerWeb.TraceLogLive.LogEntryComponent do
  @moduledoc """
  Function component for rendering a single trace log entry
  (call or return) with its arguments / return value tree.
  """

  use TraceLogViewerWeb, :html

  import TraceLogViewerWeb.TraceLogLive.TermComponents, only: [term_node: 1]

  # -------------------------------------------------------------------
  # Public component
  # -------------------------------------------------------------------

  attr :entry, :map, required: true

  def log_entry(assigns) do
    ~H"""
    <div class={[
      "group/entry rounded-lg border transition-all duration-150 hover:shadow-sm",
      if(@entry.type == :call,
        do: "border-info/20 hover:border-info/40 bg-info/[0.02]",
        else: "border-success/20 hover:border-success/40 bg-success/[0.02]"
      )
    ]}>
      <div class="flex items-start gap-3 px-4 py-3">
        <%!-- Line number --%>
        <span class="shrink-0 text-xs font-mono text-base-content/30 pt-0.5 w-8 text-right select-none">
          {@entry.line_number}
        </span>

        <%!-- Type badge --%>
        <span class={[
          "shrink-0 mt-0.5 text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-full",
          if(@entry.type == :call,
            do: "bg-info/15 text-info",
            else: "bg-success/15 text-success"
          )
        ]}>
          {if @entry.type == :call, do: "CALL", else: "RETURN"}
        </span>

        <%!-- Timestamp --%>
        <span class="shrink-0 font-mono text-xs text-base-content/50 pt-0.5">
          {@entry.timestamp}
        </span>

        <%!-- Content --%>
        <div class="flex-1 min-w-0">
          <%!-- Module.function --%>
          <div class="flex items-baseline gap-1 flex-wrap">
            <span class="font-mono text-sm">
              <span class="text-warning/80">{@entry.module}</span><span class="text-base-content/30">.</span><span class="font-semibold text-base-content">{@entry.function}</span>
            </span>
            <%= if @entry.pid do %>
              <span class="text-xs font-mono text-base-content/30 ml-2">{@entry.pid}</span>
            <% end %>
          </div>

          <%!-- Call args --%>
          <%= if @entry.type == :call && @entry.args_parsed do %>
            <div class="mt-2 space-y-1.5">
              <%= for {arg, idx} <- Enum.with_index(@entry.args_parsed) do %>
                <div class="group/arg flex items-start gap-2">
                  <span class="shrink-0 text-[10px] font-mono text-base-content/30 bg-base-200 rounded px-1.5 py-0.5 mt-0.5">
                    {"arg#{idx}"}
                  </span>
                  <div class="flex-1 min-w-0 font-mono text-xs term-tree">
                    <.term_node node={arg.parsed} raw={arg.raw} depth={0} />
                  </div>
                  <button
                    data-copy-text={arg.raw}
                    title="Copy argument"
                    class="copy-btn shrink-0 opacity-0 group-hover/arg:opacity-100 p-1 rounded-md text-base-content/30 hover:text-primary hover:bg-base-200 transition-all duration-150 cursor-pointer"
                  >
                    <.icon name="hero-clipboard-document" class="size-3.5" />
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>

          <%!-- Return value --%>
          <%= if @entry.type == :return && @entry.return_parsed do %>
            <div class="group/ret mt-2 flex items-start gap-2">
              <span class="shrink-0 text-[10px] font-mono text-base-content/30 bg-base-200 rounded px-1.5 py-0.5 mt-0.5">
                ret
              </span>
              <div class="flex-1 min-w-0 font-mono text-xs term-tree">
                <.term_node node={@entry.return_parsed} raw={@entry.return_value} depth={0} />
              </div>
              <button
                data-copy-text={@entry.return_value}
                title="Copy return value"
                class="copy-btn shrink-0 opacity-0 group-hover/ret:opacity-100 p-1 rounded-md text-base-content/30 hover:text-primary hover:bg-base-200 transition-all duration-150 cursor-pointer"
              >
                <.icon name="hero-clipboard-document" class="size-3.5" />
              </button>
            </div>
          <% end %>
        </div>

        <%!-- Copy raw line button --%>
        <button
          data-copy-text={@entry.raw}
          title="Copy raw line"
          class="copy-btn shrink-0 opacity-0 group-hover/entry:opacity-100 p-1 rounded-md text-base-content/30 hover:text-primary hover:bg-base-200 transition-all duration-150 cursor-pointer mt-0.5"
        >
          <.icon name="hero-clipboard-document" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  @doc false
  def format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  def format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
