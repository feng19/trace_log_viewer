defmodule TraceLogViewerWeb.TraceLogLive.LogEntryComponentTest do
  use ExUnit.Case, async: true

  alias TraceLogViewerWeb.TraceLogLive.LogEntryComponent

  # -------------------------------------------------------------------
  # format_elixir/1
  # -------------------------------------------------------------------

  describe "format_elixir/1" do
    test "returns nil for nil input" do
      assert LogEntryComponent.format_elixir(nil) == nil
    end

    test "formats a simple map" do
      input = ~s(%{a: 1, b: 2})
      result = LogEntryComponent.format_elixir(input)
      assert result =~ "%{a: 1, b: 2}"
    end

    test "formats a string with #PID<...>" do
      input = ~s(%{pid: #PID<0.123.0>, name: "test"})
      result = LogEntryComponent.format_elixir(input)
      assert result =~ "#PID<0.123.0>"
      assert result =~ "name:"
    end

    test "formats a string with #Port<...>" do
      input = ~s(%{port: #Port<0,80>})
      result = LogEntryComponent.format_elixir(input)
      assert result =~ "#Port<0,80>"
    end

    test "formats a string with #Function<...>" do
      input =
        ~s(%{handler: #Function<0.100107238/0 in Lokix.Consumers.Aide.Worker.handle_event/1>})

      result = LogEntryComponent.format_elixir(input)
      assert result =~ "#Function<0.100107238/0 in Lokix.Consumers.Aide.Worker.handle_event/1>"
      assert result =~ "handler:"
    end

    test "formats a string with #Reference<...>" do
      input = ~s(%{ref: #Reference<0.1234.5678.90>})
      result = LogEntryComponent.format_elixir(input)
      assert result =~ "#Reference<0.1234.5678.90>"
    end

    test "formats a string with multiple special literals" do
      input = ~s(%{pid: #PID<0.1.0>, port: #Port<0,80>, ref: #Reference<0.1.2.3>})
      result = LogEntryComponent.format_elixir(input)
      assert result =~ "#PID<0.1.0>"
      assert result =~ "#Port<0,80>"
      assert result =~ "#Reference<0.1.2.3>"
    end

    test "formats a standalone special literal" do
      assert LogEntryComponent.format_elixir("#PID<0.123.0>") == "#PID<0.123.0>"
    end

    test "formats a standalone Function literal" do
      input = "#Function<0.100107238/0 in Lokix.Consumers.Aide.Worker.handle_event/1>"
      assert LogEntryComponent.format_elixir(input) == input
    end

    test "formats a standalone Port literal" do
      input = "#Port<0,80>"
      assert LogEntryComponent.format_elixir(input) == input
    end

    test "preserves normal strings without special literals" do
      input = ~s(%{name: "hello", count: 42})
      result = LogEntryComponent.format_elixir(input)
      assert result =~ "hello"
      assert result =~ "42"
    end

    test "handles #MapSet<[...]> with nested brackets" do
      input = ~s(%{set: #MapSet<[1, 2, 3]>})
      result = LogEntryComponent.format_elixir(input)
      assert result =~ "#MapSet<[1, 2, 3]>"
    end

    test "handles nested angle brackets" do
      input = ~s(%{val: #Inspect.Error<inspecting raised #Port<0,1>>})
      result = LogEntryComponent.format_elixir(input)
      assert result =~ "#Inspect.Error<inspecting raised #Port<0,1>>"
    end

    test "does not replace # inside quoted strings" do
      input = ~s(%{msg: "#PID<fake>"})
      result = LogEntryComponent.format_elixir(input)
      # The #PID<fake> is inside a string literal, should stay as-is in the string
      assert result =~ ~s("#PID<fake>")
    end

    test "handles deeply nested map with special literals" do
      input = ~s(%{outer: %{inner: #PID<0.5.0>, list: [#Port<0,1>, #Port<0,2>]}})
      result = LogEntryComponent.format_elixir(input)
      assert result =~ "#PID<0.5.0>"
      assert result =~ "#Port<0,1>"
      assert result =~ "#Port<0,2>"
    end
  end

  # -------------------------------------------------------------------
  # sanitize_special_literals/1
  # -------------------------------------------------------------------

  describe "sanitize_special_literals/1" do
    test "returns original string and empty list when no special literals" do
      {sanitized, replacements} = LogEntryComponent.sanitize_special_literals(~s(%{a: 1}))
      assert sanitized == ~s(%{a: 1})
      assert replacements == []
    end

    test "replaces #PID<...> with a placeholder" do
      {sanitized, replacements} = LogEntryComponent.sanitize_special_literals(~s(#PID<0.1.0>))
      assert sanitized =~ "__EDV_PH_0__"
      assert length(replacements) == 1
      assert {0, "#PID<0.1.0>"} in replacements
    end

    test "replaces multiple literals with unique placeholders" do
      input = ~s(#PID<0.1.0>, #Port<0,80>)
      {sanitized, replacements} = LogEntryComponent.sanitize_special_literals(input)
      assert length(replacements) == 2
      assert {0, "#PID<0.1.0>"} in replacements
      assert {1, "#Port<0,80>"} in replacements
      refute sanitized =~ "#PID"
      refute sanitized =~ "#Port"
    end

    test "does not touch # that is not followed by UppercaseName<" do
      {sanitized, replacements} = LogEntryComponent.sanitize_special_literals(~s(%{a: "#hello"}))
      assert replacements == []
      assert sanitized == ~s(%{a: "#hello"})
    end
  end

  # -------------------------------------------------------------------
  # restore_special_literals/2
  # -------------------------------------------------------------------

  describe "restore_special_literals/2" do
    test "returns string unchanged with empty replacements" do
      assert LogEntryComponent.restore_special_literals("hello", []) == "hello"
    end

    test "restores a single placeholder" do
      str = ~s("__EDV_PH_0__")
      result = LogEntryComponent.restore_special_literals(str, [{0, "#PID<0.1.0>"}])
      assert result == "#PID<0.1.0>"
    end

    test "restores multiple placeholders" do
      str = ~s(%{a: "__EDV_PH_0__", b: "__EDV_PH_1__"})
      replacements = [{0, "#PID<0.1.0>"}, {1, "#Port<0,80>"}]
      result = LogEntryComponent.restore_special_literals(str, replacements)
      assert result =~ "#PID<0.1.0>"
      assert result =~ "#Port<0,80>"
    end
  end
end
