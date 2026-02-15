defmodule TraceLogViewerWeb.TraceLogLive.TermComponents do
  @moduledoc """
  Function components for rendering parsed Elixir term trees
  (literals, maps, structs, lists, keywords, tuples, binaries).
  """

  use TraceLogViewerWeb, :html

  @binary_collapse_threshold 80
  @string_collapse_threshold 120

  # -------------------------------------------------------------------
  # Public component
  # -------------------------------------------------------------------

  attr :node, :any, required: true
  attr :raw, :string, default: ""
  attr :depth, :integer, default: 0

  def term_node(%{node: {:literal, val}} = assigns) do
    is_long_string =
      (String.starts_with?(val, "\"") or String.starts_with?(val, "'")) and
        String.length(val) > @string_collapse_threshold

    # Calculate content length (excluding surrounding quotes)
    content_len = if is_long_string, do: String.length(val) - 2, else: 0

    preview =
      if is_long_string do
        quote_char = String.first(val)
        String.slice(val, 0, 80) <> "…" <> quote_char
      else
        val
      end

    assigns =
      assigns
      |> assign(:val, val)
      |> assign(:is_long_string, is_long_string)
      |> assign(:preview, preview)
      |> assign(:content_len, content_len)

    ~H"""
    <%= if @is_long_string do %>
      <span
        class="inline-flex items-center gap-1.5 cursor-pointer group/str rounded px-1 -mx-1 hover:bg-success/5 transition-colors"
        phx-click="show_string"
        phx-value-content={@val}
      >
        <span class={[literal_class(@val), "whitespace-pre-wrap"]}>{@preview}</span>
        <span class="text-[10px] text-base-content/30 group-hover/str:text-primary transition-colors whitespace-nowrap">
          {@content_len} chars <.icon name="hero-arrows-pointing-out" class="size-3 inline" />
        </span>
      </span>
    <% else %>
      <span class={[literal_class(@val), "whitespace-pre-wrap"]}>{@val}</span>
    <% end %>
    """
  end

  def term_node(%{node: {:map, []}} = assigns) do
    assigns = assign(assigns, :empty_map, "%{}")

    ~H"""
    <span class="text-base-content/50">{@empty_map}</span>
    """
  end

  def term_node(%{node: {:map, pairs}} = assigns) do
    display_pairs = Enum.map(pairs, fn {k, v} -> {k, v, atom_key?(k)} end)

    is_simple_single =
      length(pairs) == 1 and
        (fn [{k, v}] ->
           not TraceLogViewer.TermParser.complex?(v) and
             not TraceLogViewer.TermParser.complex?(k)
         end).(pairs)

    assigns =
      assigns
      |> assign(:display_pairs, display_pairs)
      |> assign(:count, length(pairs))
      |> assign(:open, "%{")
      |> assign(:close, "}")
      |> assign(:is_simple_single, is_simple_single)
      |> assign(:auto_collapse, length(pairs) > 3 or (assigns.depth > 0 and length(pairs) > 1))

    ~H"""
    <%= if @is_simple_single do %>
      <span class="text-base-content/50">{@open}</span>
      <%= for {{k, v, is_atom_key}, _idx} <- Enum.with_index(@display_pairs) do %>
        <%= if is_atom_key do %>
          <span class="text-info">{atom_key_name(k)}:</span>
        <% else %>
          <.term_node node={k} depth={@depth + 1} /> <span class="text-base-content/30">=&gt;</span>
        <% end %>
        <.term_node node={v} depth={@depth + 1} />
      <% end %>
      <span class="text-base-content/50">{@close}</span>
    <% else %>
      <details class="inline" open={!@auto_collapse}>
        <summary class="cursor-pointer select-none inline-flex items-center gap-1 hover:text-primary transition-colors">
          <span class="text-base-content/50">{@open}</span>
          <span class={["text-base-content/30 text-[10px]", @count == 1 && "hide-when-open"]}>
            {@count} entries
          </span>
          <span class="text-base-content/50 hide-when-open">{@close}</span>
        </summary>
        <div class="ml-4 pl-3 border-l-2 border-base-300/50 mt-1 space-y-0.5">
          <%= for {{k, v, is_atom_key}, idx} <- Enum.with_index(@display_pairs) do %>
            <div class="flex items-start gap-1 flex-wrap">
              <%= if is_atom_key do %>
                <span class="text-info">{atom_key_name(k)}:</span>
              <% else %>
                <.term_node node={k} depth={@depth + 1} />
                <span class="text-base-content/30">=&gt;</span>
              <% end %>
              <.term_node node={v} depth={@depth + 1} />
              <%= if idx < @count - 1 do %>
                <span class="text-base-content/20">,</span>
              <% end %>
            </div>
          <% end %>
        </div>
        <span class="text-base-content/50">{@close}</span>
      </details>
    <% end %>
    """
  end

  def term_node(%{node: {:struct, name, []}} = assigns) do
    assigns =
      assigns
      |> assign(:name, name)
      |> assign(:empty_struct, "%#{name}{}")

    ~H"""
    <span class="text-accent">{@empty_struct}</span>
    """
  end

  def term_node(%{node: {:struct, name, pairs}} = assigns) do
    display_pairs = Enum.map(pairs, fn {k, v} -> {k, v, atom_key?(k)} end)

    is_simple_single =
      length(pairs) == 1 and
        (fn [{k, v}] ->
           not TraceLogViewer.TermParser.complex?(v) and
             not TraceLogViewer.TermParser.complex?(k)
         end).(pairs)

    assigns =
      assigns
      |> assign(:name, name)
      |> assign(:display_pairs, display_pairs)
      |> assign(:count, length(pairs))
      |> assign(:open, "{")
      |> assign(:close, "}")
      |> assign(:is_simple_single, is_simple_single)
      |> assign(:auto_collapse, length(pairs) > 3 or (assigns.depth > 0 and length(pairs) > 1))

    ~H"""
    <%= if @is_simple_single do %>
      <span class="text-accent">%{@name}</span><span class="text-base-content/50">{@open}</span>
      <%= for {{k, v, is_atom_key}, _idx} <- Enum.with_index(@display_pairs) do %>
        <%= if is_atom_key do %>
          <span class="text-info">{atom_key_name(k)}:</span>
        <% else %>
          <.term_node node={k} depth={@depth + 1} /> <span class="text-base-content/30">=&gt;</span>
        <% end %>
        <.term_node node={v} depth={@depth + 1} />
      <% end %>
      <span class="text-base-content/50">{@close}</span>
    <% else %>
      <details class="inline" open={!@auto_collapse}>
        <summary class="cursor-pointer select-none inline-flex items-center gap-1 hover:text-primary transition-colors">
          <span class="text-accent">%{@name}</span>
          <span class="text-base-content/50">{@open}</span>
          <span class={["text-base-content/30 text-[10px]", @count == 1 && "hide-when-open"]}>
            {@count} fields
          </span>
          <span class="text-base-content/50 hide-when-open">{@close}</span>
        </summary>
        <div class="ml-4 pl-3 border-l-2 border-accent/20 mt-1 space-y-0.5">
          <%= for {{k, v, is_atom_key}, idx} <- Enum.with_index(@display_pairs) do %>
            <div class="flex items-start gap-1 flex-wrap">
              <%= if is_atom_key do %>
                <span class="text-info">{atom_key_name(k)}:</span>
              <% else %>
                <.term_node node={k} depth={@depth + 1} />
                <span class="text-base-content/30">=&gt;</span>
              <% end %>
              <.term_node node={v} depth={@depth + 1} />
              <%= if idx < @count - 1 do %>
                <span class="text-base-content/20">,</span>
              <% end %>
            </div>
          <% end %>
        </div>
        <span class="text-base-content/50">{@close}</span>
      </details>
    <% end %>
    """
  end

  def term_node(%{node: {:list, []}} = assigns) do
    ~H"""
    <span class="text-base-content/50">[]</span>
    """
  end

  def term_node(%{node: {:list, elements}} = assigns) do
    is_simple_single =
      length(elements) == 1 and not TraceLogViewer.TermParser.complex?(hd(elements))

    assigns =
      assigns
      |> assign(:elements, elements)
      |> assign(:count, length(elements))
      |> assign(:is_simple_single, is_simple_single)
      |> assign(
        :auto_collapse,
        length(elements) > 5 or (assigns.depth > 0 and length(elements) > 1)
      )

    ~H"""
    <%= if @is_simple_single do %>
      <span class="text-base-content/50">[</span>
      <%= for {el, _idx} <- Enum.with_index(@elements) do %>
        <.term_node node={el} depth={@depth + 1} />
      <% end %>
      <span class="text-base-content/50">]</span>
    <% else %>
      <details class="inline" open={!@auto_collapse}>
        <summary class="cursor-pointer select-none inline-flex items-center gap-1 hover:text-primary transition-colors">
          <span class="text-base-content/50">[</span>
          <span class={["text-base-content/30 text-[10px]", @count == 1 && "hide-when-open"]}>
            {@count} items
          </span>
          <span class="text-base-content/50 hide-when-open">]</span>
        </summary>
        <div class="ml-4 pl-3 border-l-2 border-base-300/50 mt-1 space-y-0.5">
          <%= for {el, idx} <- Enum.with_index(@elements) do %>
            <div class="flex items-start gap-1 flex-wrap">
              <span class="text-base-content/20 text-[10px] select-none">{idx}:</span>
              <.term_node node={el} depth={@depth + 1} />
              <%= if idx < @count - 1 do %>
                <span class="text-base-content/20">,</span>
              <% end %>
            </div>
          <% end %>
        </div>
        <span class="text-base-content/50">]</span>
      </details>
    <% end %>
    """
  end

  def term_node(%{node: {:keyword, []}} = assigns) do
    ~H"""
    <span class="text-base-content/50">[]</span>
    """
  end

  def term_node(%{node: {:keyword, pairs}} = assigns) do
    display_pairs =
      Enum.map(pairs, fn {k, v} ->
        {atom_key_name(k), v}
      end)

    is_simple_single =
      length(pairs) == 1 and
        (fn [{_k, v}] -> not TraceLogViewer.TermParser.complex?(v) end).(pairs)

    assigns =
      assigns
      |> assign(:display_pairs, display_pairs)
      |> assign(:count, length(pairs))
      |> assign(:is_simple_single, is_simple_single)
      |> assign(:auto_collapse, length(pairs) > 3 or (assigns.depth > 0 and length(pairs) > 1))

    ~H"""
    <%= if @is_simple_single do %>
      <span class="text-base-content/50">[</span>
      <%= for {{key_name, v}, _idx} <- Enum.with_index(@display_pairs) do %>
        <span class="text-info">{key_name}:</span> <.term_node node={v} depth={@depth + 1} />
      <% end %>
      <span class="text-base-content/50">]</span>
    <% else %>
      <details class="inline" open={!@auto_collapse}>
        <summary class="cursor-pointer select-none inline-flex items-center gap-1 hover:text-primary transition-colors">
          <span class="text-base-content/50">[</span>
          <span class={["text-base-content/30 text-[10px]", @count == 1 && "hide-when-open"]}>
            {@count} items
          </span>
          <span class="text-base-content/50 hide-when-open">]</span>
        </summary>
        <div class="ml-4 pl-3 border-l-2 border-base-300/50 mt-1 space-y-0.5">
          <%= for {{key_name, v}, idx} <- Enum.with_index(@display_pairs) do %>
            <div class="flex items-start gap-1 flex-wrap">
              <span class="text-info">{key_name}:</span>
              <.term_node node={v} depth={@depth + 1} />
              <%= if idx < @count - 1 do %>
                <span class="text-base-content/20">,</span>
              <% end %>
            </div>
          <% end %>
        </div>
        <span class="text-base-content/50">]</span>
      </details>
    <% end %>
    """
  end

  def term_node(%{node: {:tuple, elements}} = assigns) do
    is_complex = Enum.any?(elements, &TraceLogViewer.TermParser.complex?/1)

    assigns =
      assigns
      |> assign(:elements, elements)
      |> assign(:count, length(elements))
      |> assign(:open, "{")
      |> assign(:close, "}")
      |> assign(:is_complex, is_complex)
      |> assign(:auto_collapse, is_complex and assigns.depth > 0)

    ~H"""
    <%= if @is_complex do %>
      <details class="inline" open={!@auto_collapse}>
        <summary class="cursor-pointer select-none inline-flex items-center gap-1 hover:text-primary transition-colors">
          <span class="text-base-content/50">{@open}</span>
          <span class={["text-base-content/30 text-[10px]", @count == 1 && "hide-when-open"]}>
            {@count} elements
          </span>
          <span class="text-base-content/50 hide-when-open">{@close}</span>
        </summary>
        <div class="ml-4 pl-3 border-l-2 border-base-300/50 mt-1 space-y-0.5">
          <%= for {el, idx} <- Enum.with_index(@elements) do %>
            <div class="flex items-start gap-1 flex-wrap">
              <.term_node node={el} depth={@depth + 1} />
              <%= if idx < @count - 1 do %>
                <span class="text-base-content/20">,</span>
              <% end %>
            </div>
          <% end %>
        </div>
        <span class="text-base-content/50">{@close}</span>
      </details>
    <% else %>
      <span class="text-base-content/50">{@open}</span>
      <%= for {el, idx} <- Enum.with_index(@elements) do %>
        <.term_node node={el} depth={@depth + 1} />
        <%= if idx < @count - 1 do %>
          <span class="text-base-content/20">, </span>
        <% end %>
      <% end %>
      <span class="text-base-content/50">{@close}</span>
    <% end %>
    """
  end

  def term_node(%{node: {:binary, content}} = assigns) do
    is_large = String.length(content) > @binary_collapse_threshold

    assigns =
      assigns
      |> assign(:content, content)
      |> assign(:is_large, is_large)
      |> assign(
        :preview,
        if(is_large, do: String.slice(content, 0, 60) <> "…", else: content)
      )

    ~H"""
    <%= if @is_large do %>
      <span
        class="inline-flex items-center gap-1.5 cursor-pointer group/bin rounded px-1 -mx-1 hover:bg-warning/5 transition-colors"
        phx-click="show_binary"
        phx-value-content={@content}
      >
        <span class="text-warning/70">
          &lt;&lt;<span class="group-hover/bin:text-warning transition-colors">{@preview}</span>&gt;&gt;
        </span>
        <span class="text-[10px] text-base-content/30 group-hover/bin:text-primary transition-colors whitespace-nowrap">
          <.icon name="hero-arrows-pointing-out" class="size-3 inline" />
        </span>
      </span>
    <% else %>
      <span class="text-warning/70">&lt;&lt;{@content}&gt;&gt;</span>
    <% end %>
    """
  end

  def term_node(assigns) do
    raw = assigns[:raw] || ""
    assigns = assign(assigns, :display, raw)

    ~H"""
    <span class="text-base-content/70">{@display}</span>
    """
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  @doc false
  def atom_key?({:literal, ":" <> _}), do: true
  def atom_key?(_), do: false

  @doc false
  def atom_key_name({:literal, ":" <> name}), do: name
  def atom_key_name({:literal, name}), do: name
  def atom_key_name(_), do: "?"

  @doc false
  def literal_class(val) do
    cond do
      String.starts_with?(val, ":") -> "text-info"
      String.starts_with?(val, "\"") -> "text-success"
      String.starts_with?(val, "'") -> "text-success"
      String.starts_with?(val, "#") -> "text-warning/70"
      String.starts_with?(val, "~") -> "text-accent"
      val in ["true", "false"] -> "text-error"
      val == "nil" -> "text-error/60"
      String.match?(val, ~r/^\d/) -> "text-primary"
      true -> "text-base-content/80"
    end
  end
end
