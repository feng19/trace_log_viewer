defmodule TraceLogViewerWeb.TraceLogLive.LogEntryComponent do
  @moduledoc """
  Function component for rendering a single trace log entry
  (call or return) with its arguments / return value displayed
  via the ElixirDataViewer JS hook.
  """

  use TraceLogViewerWeb, :html

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
      <div class="px-4 py-3 space-y-2">
        <%!-- Header row: line | badge | timestamp | module.function | copy --%>
        <div class="flex items-start gap-3">
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

          <%!-- Module.function --%>
          <div class="flex-1 min-w-0 flex items-baseline gap-1 flex-wrap">
            <span class="font-mono text-sm">
              <span class="text-warning/80">{@entry.module}</span><span class="text-base-content/30">.</span><span class="font-semibold text-base-content">{@entry.function}</span>
            </span>
            <%= if @entry.pid do %>
              <span class="text-xs font-mono text-base-content/30 ml-2">{@entry.pid}</span>
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

        <%!-- Call args – argX labels aligned with CALL badge --%>
        <%= if @entry.type == :call && @entry.args_parsed do %>
          <div class="space-y-1.5">
            <%= for {arg, idx} <- Enum.with_index(@entry.args_parsed) do %>
              <div class="group/arg flex items-start gap-3">
                <div class="w-8 shrink-0"></div>
                <span class="shrink-0 text-[10px] font-mono text-base-content/30 bg-base-200 rounded px-1.5 py-0.5 mt-2">
                  {"arg#{idx}"}
                </span>
                <div
                  id={"arg-viewer-#{@entry.id}-#{idx}"}
                  phx-hook="ElixirDataViewer"
                  phx-update="ignore"
                  data-content={format_elixir(arg.raw)}
                  class="edv-wrapper flex-1 min-w-0"
                >
                </div>
              </div>
            <% end %>
          </div>
        <% end %>

        <%!-- Return value – ret label aligned with RETURN badge --%>
        <%= if @entry.type == :return && @entry.return_value do %>
          <div class="group/ret flex items-start gap-3">
            <div class="w-20 shrink-0"></div>
            <div
              id={"ret-viewer-#{@entry.id}"}
              phx-hook="ElixirDataViewer"
              phx-update="ignore"
              data-content={format_elixir(@entry.return_value)}
              class="edv-wrapper flex-1 min-w-0"
            >
            </div>
          </div>
        <% end %>
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

  @doc """
  Formats an Elixir term string using `Code.format_string!/1` for pretty-printing.

  Special inspect-only literals like `#Function<...>`, `#Port<...>`, `#PID<...>`,
  and `#Reference<...>` are temporarily replaced with quoted-string placeholders
  before formatting, then restored afterward. This ensures `Code.format_string!/1`
  can handle the rest of the data structure even when these unparseable literals
  are present.

  Falls back to the original string if formatting still fails after sanitization.
  """
  def format_elixir(nil), do: nil

  def format_elixir(str) when is_binary(str) do
    {sanitized, replacements} = sanitize_special_literals(str)

    formatted =
      sanitized
      |> Code.format_string!()
      |> IO.iodata_to_binary()

    restore_special_literals(formatted, replacements)
  rescue
    _ -> str
  end

  # -------------------------------------------------------------------
  # Special literal sanitization
  # -------------------------------------------------------------------

  @placeholder_prefix "__EDV_PH_"
  @placeholder_suffix "__"

  @doc """
  Scans `str` for inspect-only literals matching `#Name<...>` (e.g.
  `#Function<...>`, `#Port<0,80>`, `#PID<0.123.0>`) and replaces each
  with a unique quoted-string placeholder.

  Returns `{sanitized_string, replacements}` where `replacements` is a
  list of `{index, original}` tuples.
  """
  def sanitize_special_literals(str) do
    {sanitized, replacements, _idx} = do_sanitize(str, [], [], 0)
    {IO.iodata_to_binary(sanitized), replacements}
  end

  # Walk the string; when we hit `#UppercaseName<` we start bracket-balancing
  # to find the matching `>`.
  defp do_sanitize("", acc, replacements, idx) do
    {Enum.reverse(acc), replacements, idx}
  end

  defp do_sanitize(<<"#", rest::binary>> = _full, acc, replacements, idx) do
    case extract_special_literal(rest) do
      {:ok, literal, remaining} ->
        placeholder = "\"#{@placeholder_prefix}#{idx}#{@placeholder_suffix}\""

        do_sanitize(
          remaining,
          [placeholder | acc],
          [{idx, "#" <> literal} | replacements],
          idx + 1
        )

      :error ->
        do_sanitize(rest, ["#" | acc], replacements, idx)
    end
  end

  # Inside a double-quoted string — skip to the closing quote so we don't
  # accidentally match #Name<> inside string content.
  defp do_sanitize(<<"\"", rest::binary>>, acc, replacements, idx) do
    {str_content, remaining} = skip_string(rest, [])
    do_sanitize(remaining, [str_content, "\"" | acc], replacements, idx)
  end

  defp do_sanitize(<<c::utf8, rest::binary>>, acc, replacements, idx) do
    do_sanitize(rest, [<<c::utf8>> | acc], replacements, idx)
  end

  # Skip past a double-quoted string body (handling escape sequences).
  # Returns {string_content_including_closing_quote, remaining}.
  defp skip_string("", acc), do: {Enum.reverse(acc) |> IO.iodata_to_binary(), ""}

  defp skip_string(<<"\\", c::utf8, rest::binary>>, acc) do
    skip_string(rest, [<<c::utf8>>, "\\" | acc])
  end

  defp skip_string(<<"\"", rest::binary>>, acc) do
    {[Enum.reverse(acc) |> IO.iodata_to_binary(), "\""] |> IO.iodata_to_binary(), rest}
  end

  defp skip_string(<<c::utf8, rest::binary>>, acc) do
    skip_string(rest, [<<c::utf8>> | acc])
  end

  # Try to parse `Name<...>` after the `#`. Name must start with an uppercase
  # ASCII letter and can contain word chars and dots (for namespaced structs
  # like `Ecto.Changeset`).
  defp extract_special_literal(str) do
    case Regex.run(~r/\A([A-Z][\w.]*)</, str) do
      [prefix, _name] ->
        rest_after_prefix = String.slice(str, String.length(prefix)..-1//1)

        case balance_angles(rest_after_prefix, 1, [prefix]) do
          {:ok, consumed, remaining} -> {:ok, consumed, remaining}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  # Balance `<` `>` to find where the literal ends, also tracking `[` `]`
  # and `(` `)` to avoid being confused by `>` inside collections.
  defp balance_angles("", _depth, _acc), do: :error

  defp balance_angles(<<"\\", c::utf8, rest::binary>>, depth, acc) do
    balance_angles(rest, depth, [<<c::utf8>>, "\\" | acc])
  end

  # Quoted strings inside the literal
  defp balance_angles(<<"\"", rest::binary>>, depth, acc) do
    {str_content, remaining} = skip_string(rest, [])
    balance_angles(remaining, depth, [str_content, "\"" | acc])
  end

  defp balance_angles(<<">", rest::binary>>, 1, acc) do
    consumed = [">" | acc] |> Enum.reverse() |> IO.iodata_to_binary()
    {:ok, consumed, rest}
  end

  defp balance_angles(<<">", rest::binary>>, depth, acc) when depth > 1 do
    balance_angles(rest, depth - 1, [">" | acc])
  end

  defp balance_angles(<<"<", rest::binary>>, depth, acc) do
    balance_angles(rest, depth + 1, ["<" | acc])
  end

  # Track bracket depth so we don't miscount `>` inside `[...]` or `(...)`
  defp balance_angles(<<c::utf8, rest::binary>>, depth, acc) do
    balance_angles(rest, depth, [<<c::utf8>> | acc])
  end

  @doc """
  Restores the original special literals by replacing their placeholders
  in the formatted string.
  """
  def restore_special_literals(str, []), do: str

  def restore_special_literals(str, replacements) do
    Enum.reduce(replacements, str, fn {idx, original}, s ->
      placeholder = "\"#{@placeholder_prefix}#{idx}#{@placeholder_suffix}\""
      String.replace(s, placeholder, original)
    end)
  end
end
