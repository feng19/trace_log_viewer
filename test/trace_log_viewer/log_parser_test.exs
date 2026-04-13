defmodule TraceLogViewer.LogParserTest do
  use ExUnit.Case, async: true

  alias TraceLogViewer.LogParser

  describe "parse/1" do
    test "parses a function call with simple args" do
      text = ~s[04:02:26.664250 MyApp.Repo.get(MyApp.User, 42)]
      [entry] = LogParser.parse(text)

      assert entry.timestamp == "04:02:26.664250"
      assert entry.type == :call
      assert entry.module == "MyApp.Repo"
      assert entry.function == "get"
      assert entry.arity == 2
      assert entry.pid == nil
      assert length(entry.args_parsed) == 2
      assert Enum.at(entry.args_parsed, 0).raw == "MyApp.User"
      assert Enum.at(entry.args_parsed, 1).raw == "42"
    end

    test "parses a function return" do
      text = ~s[04:02:26.665100 MyApp.Repo.get/2 --> :ok]
      [entry] = LogParser.parse(text)

      assert entry.timestamp == "04:02:26.665100"
      assert entry.type == :return
      assert entry.module == "MyApp.Repo"
      assert entry.function == "get"
      assert entry.arity == 2
      assert entry.return_value == ":ok"
    end

    test "parses entry with Elixir-style PID" do
      text = ~s[04:02:26.664250 #PID<0.123.0> MyApp.Mod.fun(:arg)]
      [entry] = LogParser.parse(text)

      assert entry.pid == "#PID<0.123.0>"
      assert entry.type == :call
      assert entry.module == "MyApp.Mod"
      assert entry.function == "fun"
    end

    test "parses entry with Erlang-style PID" do
      text = ~s[04:02:26.664250 <0.12681.0> MyApp.Mod.fun(:arg)]
      [entry] = LogParser.parse(text)

      assert entry.pid == "<0.12681.0>"
      assert entry.type == :call
      assert entry.module == "MyApp.Mod"
      assert entry.function == "fun"
    end

    test "parses function call with map argument" do
      text = ~s[04:02:26.664250 MyApp.Accounts.get_user(%{id: 42, name: "Alice"})]
      [entry] = LogParser.parse(text)

      assert entry.type == :call
      assert entry.arity == 1
      assert length(entry.args_parsed) == 1

      arg = Enum.at(entry.args_parsed, 0)
      assert arg.raw == ~s[%{id: 42, name: "Alice"}]
    end

    test "parses function return with complex value" do
      text =
        ~s[04:02:26.665200 MyApp.Accounts.get_user/1 --> {:ok, %MyApp.User{id: 42, name: "Alice"}}]

      [entry] = LogParser.parse(text)

      assert entry.type == :return
      assert entry.return_value == ~s[{:ok, %MyApp.User{id: 42, name: "Alice"}}]
    end

    test "parses multiple lines preserving order" do
      text = """
      04:02:26.664250 MyApp.Mod.fun1(:a)
      04:02:26.664350 MyApp.Mod.fun2(:b)
      04:02:26.665100 MyApp.Mod.fun2/1 --> :ok
      04:02:26.665200 MyApp.Mod.fun1/1 --> :error
      """

      entries = LogParser.parse(text)

      assert length(entries) == 4
      assert Enum.at(entries, 0).function == "fun1"
      assert Enum.at(entries, 0).type == :call
      assert Enum.at(entries, 1).function == "fun2"
      assert Enum.at(entries, 1).type == :call
      assert Enum.at(entries, 2).function == "fun2"
      assert Enum.at(entries, 2).type == :return
      assert Enum.at(entries, 3).function == "fun1"
      assert Enum.at(entries, 3).type == :return
    end

    test "ignores empty and non-matching lines" do
      text = """
      some random text
      04:02:26.664250 MyApp.Mod.fun(:a)

      another non-matching line
      """

      entries = LogParser.parse(text)
      assert length(entries) == 1
    end

    test "parses function call with nested map args" do
      text = "04:02:26.664250 MyApp.Mod.fun(%{a: %{b: %{c: 1}}, d: [1, 2, 3]})"

      [entry] = LogParser.parse(text)

      assert entry.type == :call
      assert entry.arity == 1
    end

    test "parses function call with string containing commas" do
      text = ~s[04:02:26.664250 MyApp.Mod.fun("hello, world", 42)]
      [entry] = LogParser.parse(text)

      assert entry.type == :call
      assert entry.arity == 2
      assert Enum.at(entry.args_parsed, 0).raw == ~s["hello, world"]
      assert Enum.at(entry.args_parsed, 1).raw == "42"
    end

    test "parses function call with list argument" do
      text = "04:02:26.664250 MyApp.Mod.fun([:a, :b, :c])"
      [entry] = LogParser.parse(text)

      assert entry.type == :call
      assert entry.arity == 1
      assert Enum.at(entry.args_parsed, 0).raw == "[:a, :b, :c]"
    end

    test "parses function call with tuple argument" do
      text = ~s[04:02:26.664250 MyApp.Mod.fun({:ok, "result"})]
      [entry] = LogParser.parse(text)

      assert entry.type == :call
      assert entry.arity == 1
      assert Enum.at(entry.args_parsed, 0).raw == ~s[{:ok, "result"}]
    end

    test "assigns sequential line numbers" do
      text = """
      04:02:26.664250 MyApp.Mod.fun1(:a)
      04:02:26.664350 MyApp.Mod.fun2(:b)
      """

      entries = LogParser.parse(text)
      assert Enum.at(entries, 0).line_number == 1
      assert Enum.at(entries, 1).line_number == 2
    end

    test "assigns unique ids" do
      text = """
      04:02:26.664250 MyApp.Mod.fun1(:a)
      04:02:26.664350 MyApp.Mod.fun2(:b)
      """

      entries = LogParser.parse(text)
      ids = Enum.map(entries, & &1.id)
      assert ids == Enum.uniq(ids)
    end

    test "parses return with atom value" do
      text = ~s[04:02:26.665400 MyApp.Cache.put/2 --> :ok]
      [entry] = LogParser.parse(text)

      assert entry.type == :return
      assert entry.return_value == ":ok"
    end

    test "handles large string argument without crashing" do
      large_string = String.duplicate("a", 5000)
      text = "04:02:26.664250 MyApp.Mod.fun(\"" <> large_string <> "\")"
      entries = LogParser.parse(text)

      assert length(entries) == 1
      assert Enum.at(entries, 0).type == :call
    end

    test "parses function call with string containing literal \\n" do
      # In trace log output, strings contain literal \n (backslash + n), not actual newlines
      text = ~S[04:02:26.664250 MyApp.Mod.fun("hello\nworld")]
      entries = LogParser.parse(text)

      assert length(entries) == 1
      entry = Enum.at(entries, 0)
      assert entry.type == :call
      assert entry.arity == 1

      arg = Enum.at(entry.args_parsed, 0)
      assert arg.raw == ~S["hello\nworld"]
    end

    test "parses function return with string containing literal \\n" do
      text = ~S[04:02:26.665100 MyApp.Mod.fun/1 --> "hello\nworld"]
      entries = LogParser.parse(text)

      assert length(entries) == 1
      entry = Enum.at(entries, 0)
      assert entry.type == :return
      assert entry.return_value == ~S["hello\nworld"]
    end
  end

  describe "split_top_level_args/1" do
    test "splits simple args" do
      assert LogParser.split_top_level_args("a, b, c") == ["a", "b", "c"]
    end

    test "respects brackets" do
      assert LogParser.split_top_level_args("%{a: 1, b: 2}, :c") == ["%{a: 1, b: 2}", ":c"]
    end

    test "respects strings" do
      assert LogParser.split_top_level_args(~s["hello, world", 42]) == [
               ~s["hello, world"],
               "42"
             ]
    end

    test "respects nested structures" do
      assert LogParser.split_top_level_args("[1, 2], {3, 4}") == ["[1, 2]", "{3, 4}"]
    end

    test "empty string returns empty list" do
      assert LogParser.split_top_level_args("") == []
    end

    test "single arg returns single element list" do
      assert LogParser.split_top_level_args(":atom") == [":atom"]
    end
  end
end
