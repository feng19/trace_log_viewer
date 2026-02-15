defmodule TraceLogViewer.TermParserTest do
  use ExUnit.Case, async: true

  alias TraceLogViewer.TermParser

  describe "parse/1" do
    test "parses atom" do
      assert TermParser.parse(":ok") == {:literal, ":ok"}
    end

    test "parses complex atom" do
      assert TermParser.parse(~s(:"hello world")) == {:literal, ~s(:"hello world")}
    end

    test "parses integer" do
      assert TermParser.parse("42") == {:literal, "42"}
    end

    test "parses float" do
      assert TermParser.parse("3.14") == {:literal, "3.14"}
    end

    test "parses negative number" do
      assert TermParser.parse("-42") == {:literal, "-42"}
    end

    test "parses string" do
      assert TermParser.parse(~s("hello")) == {:literal, ~s("hello")}
    end

    test "parses string with escaped quotes" do
      assert TermParser.parse(~s("he\\"llo")) == {:literal, ~s("he\\"llo")}
    end

    test "parses true/false/nil" do
      assert TermParser.parse("true") == {:literal, "true"}
      assert TermParser.parse("false") == {:literal, "false"}
      assert TermParser.parse("nil") == {:literal, "nil"}
    end

    test "parses PID" do
      assert TermParser.parse("#PID<0.123.0>") == {:literal, "#PID<0.123.0>"}
    end

    test "parses reference" do
      assert TermParser.parse("#Reference<0.1.2.3>") == {:literal, "#Reference<0.1.2.3>"}
    end

    test "parses Ecto schema metadata" do
      input = ~s(#Ecto.Schema.Metadata<:loaded, "chat_messages">)
      assert TermParser.parse(input) == {:literal, input}
    end

    test "parses generic hash-angle bracket literal" do
      input = "#Inspect.Error<some content>"
      assert TermParser.parse(input) == {:literal, input}
    end

    test "parses simple map" do
      result = TermParser.parse("%{a: 1, b: 2}")
      assert {:map, pairs} = result
      assert length(pairs) == 2
    end

    test "parses map with arrow syntax" do
      result = TermParser.parse(~s(%{"key" => "value"}))
      assert {:map, [{_key, _value}]} = result
    end

    test "parses nested map" do
      result = TermParser.parse("%{a: %{b: 1}}")
      assert {:map, [{_key, {:map, _inner}}]} = result
    end

    test "parses struct" do
      result = TermParser.parse("%MyApp.User{id: 42, name: \"Alice\"}")
      assert {:struct, "MyApp.User", pairs} = result
      assert length(pairs) == 2
    end

    test "parses list" do
      result = TermParser.parse("[1, 2, 3]")
      assert {:list, elements} = result
      assert length(elements) == 3
    end

    test "parses empty list" do
      result = TermParser.parse("[]")
      assert {:list, []} = result
    end

    test "parses keyword list" do
      result = TermParser.parse("[{:a, 1}, {:b, 2}]")
      assert {:keyword, pairs} = result
      assert length(pairs) == 2
    end

    test "parses keyword list shorthand syntax" do
      result = TermParser.parse("[force_tool_use: true, temperature: 0.3]")
      assert {:keyword, pairs} = result
      assert length(pairs) == 2

      assert [
               {{:literal, ":force_tool_use"}, {:literal, "true"}},
               {{:literal, ":temperature"}, {:literal, "0.3"}}
             ] = pairs
    end

    test "parses keyword list shorthand with complex values" do
      result = TermParser.parse("[name: \"Alice\", tags: [:admin, :user]]")
      assert {:keyword, pairs} = result
      assert length(pairs) == 2
      [{k1, v1}, {k2, v2}] = pairs
      assert k1 == {:literal, ":name"}
      assert v1 == {:literal, "\"Alice\""}
      assert k2 == {:literal, ":tags"}
      assert {:list, [{:literal, ":admin"}, {:literal, ":user"}]} = v2
    end

    test "parses keyword list shorthand with nested map values" do
      result = TermParser.parse("[session_id: \"abc\", tools: [%{type: \"function\"}]]")
      assert {:keyword, pairs} = result
      assert length(pairs) == 2
      [{k1, _v1}, {k2, v2}] = pairs
      assert k1 == {:literal, ":session_id"}
      assert k2 == {:literal, ":tools"}
      assert {:list, [{:map, _}]} = v2
    end

    test "parses keyword list shorthand with nil value" do
      result = TermParser.parse("[llm_model: nil, temperature: 0.3]")
      assert {:keyword, pairs} = result
      assert length(pairs) == 2

      assert [
               {{:literal, ":llm_model"}, {:literal, "nil"}},
               {{:literal, ":temperature"}, {:literal, "0.3"}}
             ] = pairs
    end

    test "parses tuple" do
      result = TermParser.parse("{:ok, 42}")
      assert {:tuple, elements} = result
      assert length(elements) == 2
    end

    test "parses empty map" do
      result = TermParser.parse("%{}")
      assert {:map, []} = result
    end

    test "parses binary" do
      result = TermParser.parse("<<1, 2, 3>>")
      assert {:binary, "1, 2, 3"} = result
    end

    test "parses sigil" do
      result = TermParser.parse("~U[2024-01-15 10:30:00Z]")
      assert {:literal, "~U[2024-01-15 10:30:00Z]"} = result
    end

    test "does not crash on malformed input" do
      # These should not raise — just return some parsed node
      assert is_tuple(TermParser.parse("%{broken"))
      assert is_tuple(TermParser.parse("[unclosed"))
      assert is_tuple(TermParser.parse("{bad"))
      assert is_tuple(TermParser.parse(""))
      assert is_tuple(TermParser.parse("random text"))
    end

    test "parses deeply nested structure" do
      input = "%{a: %{b: %{c: %{d: [1, 2, {:ok, \"deep\"}]}}}}"
      result = TermParser.parse(input)
      assert {:map, _} = result
    end

    test "parses string with escaped newline (literal \\n)" do
      # In trace logs, strings contain literal \n (two characters: backslash + n)
      input = ~S("hello\nworld")
      result = TermParser.parse(input)
      assert {:literal, val} = result
      # The literal \n should be preserved as two characters
      assert val == ~S("hello\nworld")
      assert String.contains?(val, "\\n")
    end

    test "parses string with escaped tab (literal \\t)" do
      input = ~S("hello\tworld")
      result = TermParser.parse(input)
      assert {:literal, val} = result
      assert val == ~S("hello\tworld")
      assert String.contains?(val, "\\t")
    end

    test "parses string with multiple escape sequences" do
      input = ~S("line1\nline2\nline3\ttab")
      result = TermParser.parse(input)
      assert {:literal, val} = result
      assert val == ~S("line1\nline2\nline3\ttab")
    end

    test "parses string with escaped backslash" do
      input = ~S("path\\to\\file")
      result = TermParser.parse(input)
      assert {:literal, val} = result
      assert val == ~S("path\\to\\file")
    end
  end

  describe "complex?/1" do
    test "maps are complex" do
      assert TermParser.complex?({:map, []})
    end

    test "structs are complex" do
      assert TermParser.complex?({:struct, "Mod", []})
    end

    test "lists are complex" do
      assert TermParser.complex?({:list, []})
    end

    test "literals are not complex" do
      refute TermParser.complex?({:literal, ":ok"})
    end

    test "small tuples are not complex" do
      refute TermParser.complex?({:tuple, [{:literal, ":ok"}, {:literal, "42"}]})
    end
  end

  describe "to_string_repr/1" do
    test "literal" do
      assert TermParser.to_string_repr({:literal, ":ok"}) == ":ok"
    end

    test "map with atom keys uses shorthand" do
      node = {:map, [{{:literal, ":a"}, {:literal, "1"}}]}
      assert TermParser.to_string_repr(node) == "%{a: 1}"
    end

    test "map with non-atom keys uses arrow" do
      node = {:map, [{{:literal, "\"key\""}, {:literal, "1"}}]}
      assert TermParser.to_string_repr(node) == ~s(%{"key" => 1})
    end

    test "list" do
      node = {:list, [{:literal, "1"}, {:literal, "2"}]}
      assert TermParser.to_string_repr(node) == "[1, 2]"
    end

    test "tuple" do
      node = {:tuple, [{:literal, ":ok"}, {:literal, "42"}]}
      assert TermParser.to_string_repr(node) == "{:ok, 42}"
    end

    test "struct with atom keys uses shorthand" do
      node = {:struct, "MyMod", [{{:literal, ":id"}, {:literal, "1"}}]}
      assert TermParser.to_string_repr(node) == "%MyMod{id: 1}"
    end

    test "keyword list uses shorthand" do
      node =
        {:keyword, [{{:literal, ":a"}, {:literal, "1"}}, {{:literal, ":b"}, {:literal, "2"}}]}

      assert TermParser.to_string_repr(node) == "[a: 1, b: 2]"
    end

    test "truncation on container types" do
      pairs =
        for i <- 1..20 do
          {{:literal, ":key_#{i}"}, {:literal, "\"#{String.duplicate("v", 50)}\""}}
        end

      node = {:map, pairs}
      result = TermParser.to_string_repr(node, max_length: 50)
      assert String.length(result) <= 53
    end
  end
end
