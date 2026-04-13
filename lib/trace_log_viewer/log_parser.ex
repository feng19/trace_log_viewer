defmodule TraceLogViewer.LogParser do
  @moduledoc """
  Parses extrace trace log output into structured entries.

  Handles two formats:
  1. Function call:   `04:02:26.664250 Module.function(arg1, arg2, ...)`
  2. Function return:  `04:02:26.664250 Module.function/arity --> return_value`

  Optionally, a PID may appear after the timestamp:
  - `04:02:26.664250 #PID<0.123.0> Module.function(...)`
  """

  defstruct [
    :id,
    :line_number,
    :timestamp,
    :pid,
    :type,
    :module,
    :function,
    :arity,
    :args,
    :args_parsed,
    :return_value,
    :raw
  ]

  @timestamp_re ~r/^(\d{2}:\d{2}:\d{2}\.\d+)\s+/
  @pid_re ~r/^(#PID<[^>]+>|<\d+\.\d+\.\d+>)\s+/
  @return_re ~r/^(.+)\/(\d+)\s+-->\s+(.*)$/s
  @call_re ~r/^(.+?)\.([^.(]+)\((.*)$/s

  @doc """
  Parse a full trace log text into a list of `%TraceLogViewer.LogParser{}` entries.
  """
  def parse(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce([], fn {line, line_number}, acc ->
      case parse_line(String.trim(line), line_number) do
        nil -> acc
        entry -> [entry | acc]
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Parse a single trace log line into a structured entry.
  """
  def parse_line("", _line_number), do: nil

  def parse_line(line, line_number) do
    with {:ok, timestamp, rest} <- extract_timestamp(line),
         {pid, rest} <- extract_pid(rest),
         {:ok, entry} <- parse_content(rest) do
      %__MODULE__{
        id: "log-#{line_number}",
        line_number: line_number,
        timestamp: timestamp,
        pid: pid,
        raw: line
      }
      |> Map.merge(entry)
    else
      _ -> nil
    end
  end

  defp extract_timestamp(line) do
    case Regex.run(@timestamp_re, line) do
      [full_match, timestamp] ->
        rest = String.slice(line, String.length(full_match)..-1//1)
        {:ok, timestamp, rest}

      _ ->
        :error
    end
  end

  defp extract_pid(rest) do
    case Regex.run(@pid_re, rest) do
      [full_match, pid] ->
        rest2 = String.slice(rest, String.length(full_match)..-1//1)
        {pid, rest2}

      _ ->
        {nil, rest}
    end
  end

  defp parse_content(content) do
    cond do
      # Return format: Module.function/arity --> return_value
      match = Regex.run(@return_re, content) ->
        [_, mf, arity, return_value] = match
        {mod, fun} = split_module_function(mf)

        {:ok,
         %{
           type: :return,
           module: mod,
           function: fun,
           arity: String.to_integer(arity),
           args: nil,
           args_parsed: nil,
           return_value: String.trim(return_value)
         }}

      # Call format: Module.function(args...)
      match = Regex.run(@call_re, content) ->
        [_, mod_part, fun, args_with_paren] = match
        # Remove the trailing ) — we need to find the matching one
        args_str = strip_trailing_paren(args_with_paren)

        parsed_args =
          args_str
          |> split_top_level_args()
          |> Enum.map(fn arg ->
            trimmed = String.trim(arg)
            %{raw: trimmed}
          end)

        {:ok,
         %{
           type: :call,
           module: mod_part,
           function: fun,
           arity: length(parsed_args),
           args: args_str,
           args_parsed: parsed_args,
           return_value: nil
         }}

      true ->
        :error
    end
  end

  defp split_module_function(mf) do
    parts = String.split(mf, ".")
    fun = List.last(parts)
    mod = parts |> Enum.drop(-1) |> Enum.join(".")
    {mod, fun}
  end

  defp strip_trailing_paren(str) do
    str = String.trim(str)

    if String.ends_with?(str, ")") do
      String.slice(str, 0..-2//1)
    else
      str
    end
  end

  @doc """
  Split a comma-separated argument string at the top level,
  respecting nesting of brackets, strings, and atoms.
  """
  def split_top_level_args(""), do: []

  def split_top_level_args(str) do
    split_top_level(str, 0, [], [], false, nil)
  end

  # Recursive character-by-character splitter
  defp split_top_level("", _depth, current, acc, _in_string, _string_char) do
    result = current |> Enum.reverse() |> IO.iodata_to_binary()
    Enum.reverse([result | acc])
  end

  # Inside a string literal
  defp split_top_level(<<"\\", c::utf8, rest::binary>>, depth, current, acc, true, sc) do
    split_top_level(rest, depth, [<<c::utf8>>, "\\" | current], acc, true, sc)
  end

  defp split_top_level(<<c::utf8, rest::binary>>, depth, current, acc, true, sc) when c == sc do
    split_top_level(rest, depth, [<<c::utf8>> | current], acc, false, nil)
  end

  defp split_top_level(<<c::utf8, rest::binary>>, depth, current, acc, true, sc) do
    split_top_level(rest, depth, [<<c::utf8>> | current], acc, true, sc)
  end

  # Start of string
  defp split_top_level(<<"\"", rest::binary>>, depth, current, acc, false, _sc) do
    split_top_level(rest, depth, ["\"" | current], acc, true, ?")
  end

  defp split_top_level(<<"'", rest::binary>>, depth, current, acc, false, _sc) do
    split_top_level(rest, depth, ["'" | current], acc, true, ?')
  end

  # Opening brackets
  defp split_top_level(<<c::utf8, rest::binary>>, depth, current, acc, false, _sc)
       when c in [?{, ?[, ?(] do
    split_top_level(rest, depth + 1, [<<c::utf8>> | current], acc, false, nil)
  end

  # Closing brackets
  defp split_top_level(<<c::utf8, rest::binary>>, depth, current, acc, false, _sc)
       when c in [?}, ?], ?)] do
    split_top_level(rest, max(depth - 1, 0), [<<c::utf8>> | current], acc, false, nil)
  end

  # << >>
  defp split_top_level(<<"<<", rest::binary>>, depth, current, acc, false, _sc) do
    split_top_level(rest, depth + 1, ["<<" | current], acc, false, nil)
  end

  defp split_top_level(<<">>", rest::binary>>, depth, current, acc, false, _sc) do
    split_top_level(rest, max(depth - 1, 0), [">>" | current], acc, false, nil)
  end

  # Comma at depth 0 -> split
  defp split_top_level(<<",", rest::binary>>, 0, current, acc, false, _sc) do
    result = current |> Enum.reverse() |> IO.iodata_to_binary()
    split_top_level(String.trim_leading(rest), 0, [], [result | acc], false, nil)
  end

  # Any other character
  defp split_top_level(<<c::utf8, rest::binary>>, depth, current, acc, false, _sc) do
    split_top_level(rest, depth, [<<c::utf8>> | current], acc, false, nil)
  end
end
