defmodule TraceLogViewer.TermParser do
  @moduledoc """
  Parses string representations of Elixir terms into a tree structure
  suitable for collapsible rendering in the UI.

  Produces a tree of nodes like:
  - `{:map, [{key_node, value_node}, ...]}` for maps
  - `{:list, [node, ...]}` for lists
  - `{:tuple, [node, ...]}` for tuples
  - `{:keyword, [{key_atom, value_node}, ...]}` for keyword lists
  - `{:struct, name, [{key_node, value_node}, ...]}` for structs
  - `{:binary, content}` for binaries/bitstrings
  - `{:literal, string}` for atoms, numbers, strings, pids, refs, etc.
  """

  @doc """
  Parse a string representation of an Elixir term into a tree structure.
  Returns a node suitable for recursive rendering.
  """
  def parse(str) when is_binary(str) do
    str = String.trim(str)

    try do
      case do_parse(str) do
        {node, ""} -> node
        {node, _rest} -> node
        :error -> {:literal, str}
      end
    rescue
      _ -> {:literal, str}
    end
  end

  defp do_parse(""), do: {{:literal, ""}, ""}

  # Struct: %Module.Name{...}
  defp do_parse("%" <> rest) do
    case parse_struct(rest) do
      :error -> {:error_fallback, "%" <> rest}
      result -> result
    end
  end

  # Map: %{...}
  defp do_parse("%{" <> _ = str) do
    parse_map(str)
  end

  # Tuple: {...}
  defp do_parse("{" <> _ = str) do
    parse_tuple(str)
  end

  # List: [...]
  defp do_parse("[" <> _ = str) do
    parse_list(str)
  end

  # Binary: <<...>>
  defp do_parse("<<" <> _ = str) do
    parse_binary(str)
  end

  # String: "..."
  defp do_parse("\"" <> _ = str) do
    parse_string(str)
  end

  # Charlist: '...'
  defp do_parse("'" <> _ = str) do
    parse_charlist(str)
  end

  # PID: #PID<...>
  defp do_parse("#PID<" <> _ = str) do
    parse_special(str, "#PID<", ">")
  end

  # Reference: #Reference<...>
  defp do_parse("#Reference<" <> _ = str) do
    parse_special(str, "#Reference<", ">")
  end

  # Port: #Port<...>
  defp do_parse("#Port<" <> _ = str) do
    parse_special(str, "#Port<", ">")
  end

  # Function: #Function<...>
  defp do_parse("#Function<" <> _ = str) do
    parse_special(str, "#Function<", ">")
  end

  # Generic #Name<...> (Ecto metadata, Inspect protocol, etc.)
  defp do_parse("#" <> _ = str) do
    parse_hash_literal(str)
  end

  # Sigil: ~...
  defp do_parse("~" <> _ = str) do
    {literal, rest} = take_until_delimiter(str)
    {{:literal, literal}, rest}
  end

  # Negative number
  defp do_parse("-" <> rest) do
    case do_parse(rest) do
      {{:literal, num_str}, rest2} -> {{:literal, "-" <> num_str}, rest2}
      _ -> {{:literal, "-"}, rest}
    end
  end

  # Atom: :atom or :"complex atom"
  defp do_parse(":" <> _ = str) do
    parse_atom(str)
  end

  # true/false/nil
  defp do_parse("true" <> rest), do: {{:literal, "true"}, rest}
  defp do_parse("false" <> rest), do: {{:literal, "false"}, rest}
  defp do_parse("nil" <> rest), do: {{:literal, "nil"}, rest}

  # Number or atom-like identifier
  defp do_parse(str) do
    {token, rest} = take_token(str)

    if token == "" do
      :error
    else
      {{:literal, token}, rest}
    end
  end

  # --- Struct ---
  defp parse_struct(rest) do
    # Could be %{...} (map) or %ModuleName{...} (struct)
    case take_until_char(rest, ?{) do
      {"", _} ->
        # This is %{...}, treat as map
        parse_map("%" <> rest)

      {name, "{" <> inner_rest} ->
        name = String.trim(name)
        {pairs, after_close} = parse_map_pairs(inner_rest)
        {{:struct, name, pairs}, after_close}

      _ ->
        :error
    end
  end

  # --- Map ---
  defp parse_map("%{" <> rest) do
    {pairs, after_close} = parse_map_pairs(rest)
    {{:map, pairs}, after_close}
  end

  defp parse_map(_), do: :error

  defp parse_map_pairs(str) do
    str = String.trim(str)

    case str do
      "}" <> rest ->
        {[], rest}

      _ ->
        parse_map_pairs_loop(str, [])
    end
  end

  defp parse_map_pairs_loop(str, acc) do
    str = String.trim(str)

    case str do
      "}" <> rest ->
        {Enum.reverse(acc), rest}

      "" ->
        {Enum.reverse(acc), ""}

      _ ->
        case parse_map_pair(str) do
          {pair, rest} ->
            rest = String.trim(rest)

            rest =
              case rest do
                "," <> r -> String.trim(r)
                r -> r
              end

            parse_map_pairs_loop(rest, [pair | acc])

          :error ->
            # Fallback: consume until } or end
            {literal, rest} = take_until_char(str, ?})

            rest =
              case rest do
                "}" <> r -> r
                r -> r
              end

            {Enum.reverse([{{:literal, literal}, {:literal, ""}} | acc]), rest}
        end
    end
  end

  defp parse_map_pair(str) do
    # Try atom key shorthand: key: value
    case Regex.run(~r/^([a-z_][a-zA-Z0-9_?!]*):(\s)/, str) do
      [full, key, _] ->
        rest = String.slice(str, String.length(full)..-1//1)

        case do_parse(String.trim(rest)) do
          {value, rest2} -> {{{:literal, ":" <> key}, value}, rest2}
          :error -> :error
        end

      _ ->
        # Try arrow: key => value
        case do_parse(str) do
          {key_node, rest} ->
            rest = String.trim(rest)

            case rest do
              "=>" <> rest2 ->
                rest2 = String.trim(rest2)

                case do_parse(rest2) do
                  {value_node, rest3} -> {{key_node, value_node}, rest3}
                  :error -> :error
                end

              # Could be that key itself consumed the =>
              _ ->
                :error
            end

          :error ->
            :error
        end
    end
  end

  # --- Tuple ---
  defp parse_tuple("{" <> rest) do
    {elements, after_close} = parse_collection_elements(rest, ?})
    {{:tuple, elements}, after_close}
  end

  # --- List ---
  defp parse_list("[" <> rest) do
    rest = String.trim(rest)

    case rest do
      "]" <> after_close ->
        {{:list, []}, after_close}

      _ ->
        {elements, after_close} = parse_list_elements_loop(rest, [])

        # Check if all elements are keyword shorthand pairs
        all_keyword =
          elements != [] and
            Enum.all?(elements, fn
              {:kw_pair, _, _} -> true
              _ -> false
            end)

        if all_keyword do
          kw = Enum.map(elements, fn {:kw_pair, key, value} -> {key, value} end)
          {{:keyword, kw}, after_close}
        else
          # Convert any kw_pairs back to tuples for mixed lists
          regular =
            Enum.map(elements, fn
              {:kw_pair, key, value} -> {:tuple, [key, value]}
              other -> other
            end)

          # Check if it's a keyword list via tuple syntax [{:atom, value}, ...]
          if keyword_list?(regular) do
            kw =
              Enum.map(regular, fn {:tuple, [key, value]} ->
                {key, value}
              end)

            {{:keyword, kw}, after_close}
          else
            {{:list, regular}, after_close}
          end
        end
    end
  end

  # Parse list elements, trying keyword shorthand `key: value` first
  defp parse_list_elements_loop(str, acc) do
    str = String.trim(str)

    case str do
      "]" <> rest ->
        {Enum.reverse(acc), rest}

      "" ->
        {Enum.reverse(acc), ""}

      _ ->
        # Try keyword shorthand first: `key: value`
        case try_keyword_shorthand(str) do
          {:ok, key_atom, value_node, rest} ->
            rest = String.trim(rest)

            rest =
              case rest do
                "," <> r -> String.trim(r)
                r -> r
              end

            parse_list_elements_loop(rest, [{:kw_pair, key_atom, value_node} | acc])

          :not_keyword ->
            # Fall back to regular element parsing
            case do_parse(str) do
              {node, rest} ->
                rest = String.trim(rest)

                rest =
                  case rest do
                    "," <> r -> String.trim(r)
                    r -> r
                  end

                parse_list_elements_loop(rest, [node | acc])

              :error ->
                # Fallback: consume until ] or end
                {literal, rest} = take_until_char(str, ?])

                rest =
                  case rest do
                    "]" <> r -> r
                    r -> r
                  end

                {Enum.reverse([{:literal, literal} | acc]), rest}
            end
        end
    end
  end

  # Try to parse keyword shorthand `key: value` at the start of the string
  defp try_keyword_shorthand(str) do
    case Regex.run(~r/^([a-z_][a-zA-Z0-9_?!]*):\s/, str) do
      [full, key] ->
        rest = String.slice(str, String.length(full)..-1//1)

        case do_parse(String.trim(rest)) do
          {value, rest2} -> {:ok, {:literal, ":" <> key}, value, rest2}
          :error -> :not_keyword
        end

      _ ->
        :not_keyword
    end
  end

  defp keyword_list?([]), do: false

  defp keyword_list?(elements) do
    Enum.all?(elements, fn
      {:tuple, [{:literal, ":" <> _}, _value]} -> true
      _ -> false
    end)
  end

  defp parse_collection_elements(str, close_char) do
    str = String.trim(str)

    case str do
      <<^close_char::utf8, rest::binary>> ->
        {[], rest}

      _ ->
        parse_elements_loop(str, close_char, [])
    end
  end

  defp parse_elements_loop(str, close_char, acc) do
    str = String.trim(str)

    case str do
      <<^close_char::utf8, rest::binary>> ->
        {Enum.reverse(acc), rest}

      "" ->
        {Enum.reverse(acc), ""}

      _ ->
        case do_parse(str) do
          {node, rest} ->
            rest = String.trim(rest)

            rest =
              case rest do
                "," <> r -> String.trim(r)
                r -> r
              end

            parse_elements_loop(rest, close_char, [node | acc])

          :error ->
            # fallback
            {literal, rest} = take_until_char(str, close_char)

            rest =
              case rest do
                <<^close_char::utf8, r::binary>> -> r
                r -> r
              end

            {Enum.reverse([{:literal, literal} | acc]), rest}
        end
    end
  end

  # --- Binary ---
  defp parse_binary("<<" <> rest) do
    {content, after_close} = take_binary_content(rest, 0, [])
    {{:binary, content}, after_close}
  end

  defp take_binary_content(">>" <> rest, 0, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp take_binary_content("<<" <> rest, depth, acc) do
    take_binary_content(rest, depth + 1, ["<<" | acc])
  end

  defp take_binary_content(">>" <> rest, depth, acc) do
    take_binary_content(rest, depth - 1, [">>" | acc])
  end

  defp take_binary_content(<<c::utf8, rest::binary>>, depth, acc) do
    take_binary_content(rest, depth, [<<c::utf8>> | acc])
  end

  defp take_binary_content("", _depth, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), ""}
  end

  # --- String ---
  defp parse_string("\"" <> rest) do
    {content, after_close} = take_string_content(rest, [])
    {{:literal, "\"" <> content <> "\""}, after_close}
  end

  defp take_string_content("\\\"" <> rest, acc) do
    take_string_content(rest, ["\\\"" | acc])
  end

  defp take_string_content("\"" <> rest, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp take_string_content(<<c::utf8, rest::binary>>, acc) do
    take_string_content(rest, [<<c::utf8>> | acc])
  end

  defp take_string_content("", acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), ""}
  end

  # --- Charlist ---
  defp parse_charlist("'" <> rest) do
    {content, after_close} = take_charlist_content(rest, [])
    {{:literal, "'" <> content <> "'"}, after_close}
  end

  defp take_charlist_content("\\'" <> rest, acc) do
    take_charlist_content(rest, ["\\'" | acc])
  end

  defp take_charlist_content("'" <> rest, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp take_charlist_content(<<c::utf8, rest::binary>>, acc) do
    take_charlist_content(rest, [<<c::utf8>> | acc])
  end

  defp take_charlist_content("", acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), ""}
  end

  # --- Special types (#PID, #Reference, etc.) ---
  defp parse_special(str, prefix, suffix) do
    rest = String.slice(str, String.length(prefix)..-1//1)
    {content, after_close} = take_until_string(rest, suffix)

    {{:literal, prefix <> content <> suffix}, after_close}
  end

  # --- Generic #Name<...> (Ecto.Schema.Metadata, etc.) ---
  defp parse_hash_literal("#" <> rest) do
    case Regex.run(~r/^([A-Za-z_][A-Za-z0-9_.]*)<(.*)$/s, rest) do
      [_, name, after_angle] ->
        {content, remaining} = take_angle_content(after_angle, 0, [])
        {{:literal, "#" <> name <> "<" <> content <> ">"}, remaining}

      _ ->
        # Just a # followed by something else, take as token
        {token, remaining} = take_until_delimiter("#" <> rest)
        {{:literal, token}, remaining}
    end
  end

  defp take_angle_content(">" <> rest, 0, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp take_angle_content("<" <> rest, depth, acc) do
    take_angle_content(rest, depth + 1, ["<" | acc])
  end

  defp take_angle_content(">" <> rest, depth, acc) do
    take_angle_content(rest, depth - 1, [">" | acc])
  end

  defp take_angle_content(<<c::utf8, rest::binary>>, depth, acc) do
    take_angle_content(rest, depth, [<<c::utf8>> | acc])
  end

  defp take_angle_content("", _depth, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), ""}
  end

  defp take_until_string(str, target) do
    tlen = String.length(target)
    do_take_until_string(str, target, tlen, [])
  end

  defp do_take_until_string(str, target, tlen, acc) do
    if String.starts_with?(str, target) do
      {acc |> Enum.reverse() |> IO.iodata_to_binary(), String.slice(str, tlen..-1//1)}
    else
      case str do
        <<c::utf8, rest::binary>> ->
          do_take_until_string(rest, target, tlen, [<<c::utf8>> | acc])

        "" ->
          {acc |> Enum.reverse() |> IO.iodata_to_binary(), ""}
      end
    end
  end

  # --- Atom ---
  defp parse_atom(":\"" <> rest) do
    {content, after_close} = take_string_content(rest, [])
    {{:literal, ":\"" <> content <> "\""}, after_close}
  end

  defp parse_atom(":" <> rest) do
    {token, remaining} = take_atom_token(rest)
    {{:literal, ":" <> token}, remaining}
  end

  defp take_atom_token(str) do
    case Regex.run(~r/^([a-zA-Z_][a-zA-Z0-9_?!@]*)(.*)$/s, str) do
      [_, token, rest] -> {token, rest}
      _ -> {"", str}
    end
  end

  # --- Token helpers ---
  defp take_token(str) do
    # Numbers (including floats, scientific notation)
    case Regex.run(~r/^(\d+\.?\d*(?:[eE][+-]?\d+)?)(.*)$/s, str) do
      [_, num, rest] ->
        {num, rest}

      _ ->
        # Elixir-like identifiers (module names, atoms without colon, etc.)
        case Regex.run(~r/^([A-Za-z_][A-Za-z0-9_.]*(?:![A-Za-z0-9_.]*)?)(.*)$/s, str) do
          [_, token, rest] -> {token, rest}
          _ -> {"", str}
        end
    end
  end

  defp take_until_char(str, char) do
    do_take_until_char(str, char, [])
  end

  defp do_take_until_char(<<c::utf8, _::binary>> = str, char, acc) when c == char do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), str}
  end

  defp do_take_until_char(<<c::utf8, rest::binary>>, char, acc) do
    do_take_until_char(rest, char, [<<c::utf8>> | acc])
  end

  defp do_take_until_char("", _char, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), ""}
  end

  defp take_until_delimiter(str) do
    do_take_until_delimiter(str, [], 0, false, nil)
  end

  defp do_take_until_delimiter("", acc, _depth, _in_str, _sc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), ""}
  end

  defp do_take_until_delimiter(<<c::utf8, rest::binary>>, acc, 0, false, _sc)
       when c in [?,, ?), ?], ?}] do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), <<c::utf8, rest::binary>>}
  end

  defp do_take_until_delimiter(<<"\\", c::utf8, rest::binary>>, acc, depth, true, sc) do
    do_take_until_delimiter(rest, [<<c::utf8>>, "\\" | acc], depth, true, sc)
  end

  defp do_take_until_delimiter(<<c::utf8, rest::binary>>, acc, depth, true, sc) when c == sc do
    do_take_until_delimiter(rest, [<<c::utf8>> | acc], depth, false, nil)
  end

  defp do_take_until_delimiter(<<c::utf8, rest::binary>>, acc, depth, true, sc) do
    do_take_until_delimiter(rest, [<<c::utf8>> | acc], depth, true, sc)
  end

  defp do_take_until_delimiter(<<"\"", rest::binary>>, acc, depth, false, _sc) do
    do_take_until_delimiter(rest, ["\"" | acc], depth, true, ?")
  end

  defp do_take_until_delimiter(<<c::utf8, rest::binary>>, acc, depth, false, _sc)
       when c in [?{, ?[, ?(] do
    do_take_until_delimiter(rest, [<<c::utf8>> | acc], depth + 1, false, nil)
  end

  defp do_take_until_delimiter(<<c::utf8, rest::binary>>, acc, depth, false, _sc)
       when c in [?}, ?], ?)] do
    do_take_until_delimiter(rest, [<<c::utf8>> | acc], max(depth - 1, 0), false, nil)
  end

  defp do_take_until_delimiter(<<c::utf8, rest::binary>>, acc, depth, false, _sc) do
    do_take_until_delimiter(rest, [<<c::utf8>> | acc], depth, false, nil)
  end

  @doc """
  Convert a parsed term node back to a string representation.
  """
  def to_string_repr(node, opts \\ [])

  def to_string_repr({:literal, val}, _opts), do: val

  def to_string_repr({:map, pairs}, opts) do
    max_len = Keyword.get(opts, :max_length, :infinity)

    inner =
      Enum.map_join(pairs, ", ", fn {k, v} ->
        kv_pair_repr(k, v, opts)
      end)

    result = "%{" <> inner <> "}"
    maybe_truncate(result, max_len)
  end

  def to_string_repr({:struct, name, pairs}, opts) do
    max_len = Keyword.get(opts, :max_length, :infinity)

    inner =
      Enum.map_join(pairs, ", ", fn {k, v} ->
        kv_pair_repr(k, v, opts)
      end)

    result = "%" <> name <> "{" <> inner <> "}"
    maybe_truncate(result, max_len)
  end

  def to_string_repr({:list, elements}, opts) do
    max_len = Keyword.get(opts, :max_length, :infinity)
    inner = Enum.map_join(elements, ", ", &to_string_repr(&1, opts))
    result = "[" <> inner <> "]"
    maybe_truncate(result, max_len)
  end

  def to_string_repr({:keyword, pairs}, opts) do
    max_len = Keyword.get(opts, :max_length, :infinity)

    inner =
      Enum.map_join(pairs, ", ", fn {k, v} ->
        atom_key_name(k) <> ": " <> to_string_repr(v, opts)
      end)

    result = "[" <> inner <> "]"
    maybe_truncate(result, max_len)
  end

  def to_string_repr({:tuple, elements}, opts) do
    max_len = Keyword.get(opts, :max_length, :infinity)
    inner = Enum.map_join(elements, ", ", &to_string_repr(&1, opts))
    result = "{" <> inner <> "}"
    maybe_truncate(result, max_len)
  end

  def to_string_repr({:binary, content}, opts) do
    max_len = Keyword.get(opts, :max_length, :infinity)
    result = "<<" <> content <> ">>"
    maybe_truncate(result, max_len)
  end

  def to_string_repr(other, _opts) when is_binary(other), do: other
  def to_string_repr(_other, _opts), do: "..."

  defp maybe_truncate(str, :infinity), do: str

  defp maybe_truncate(str, max_len) when byte_size(str) > max_len do
    String.slice(str, 0, max_len) <> "..."
  end

  defp maybe_truncate(str, _max_len), do: str

  # Render a key-value pair, using atom shorthand `key: value` for atom keys
  defp kv_pair_repr({:literal, ":" <> name} = _k, v, opts) do
    name <> ": " <> to_string_repr(v, opts)
  end

  defp kv_pair_repr(k, v, opts) do
    to_string_repr(k, opts) <> " => " <> to_string_repr(v, opts)
  end

  # Extract the atom name from an atom key node, stripping the leading `:`
  defp atom_key_name({:literal, ":" <> name}), do: name
  defp atom_key_name({:literal, name}), do: name
  defp atom_key_name(_), do: "?"

  @doc """
  Check if a parsed node is a complex type (map, list, tuple, struct, keyword).
  """
  def complex?({:map, _}), do: true
  def complex?({:struct, _, _}), do: true
  def complex?({:list, _}), do: true
  def complex?({:keyword, _}), do: true
  def complex?({:tuple, els}) when length(els) > 2, do: true
  def complex?(_), do: false

  @doc """
  Count the approximate character length of a rendered node.
  """
  def approx_size(node) do
    to_string_repr(node) |> String.length()
  end
end
