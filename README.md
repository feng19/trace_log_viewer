# TraceLogViewer

A web-based viewer for Elixir trace logs built with Phoenix LiveView. Upload or paste [extrace](https://hex.pm/packages/extrace) output and explore function calls/returns with collapsible, syntax-highlighted data structures.

## Features

- **Upload or paste** trace log files (up to 50 MB)
- **Structured parsing** of call and return entries with timestamp, PID, module, function, and arguments
- **Collapsible tree rendering** for complex Elixir terms — maps, structs, keyword lists, tuples, lists, binaries, etc.
- **Filter** by call / return type
- **Search** across all log entries
- **Copy to clipboard** for individual values
- **Sample data** included for quick demo

## Supported Log Format

```
# Function call
04:02:26.664250 MyApp.Module.function(arg1, arg2)

# Function return
04:02:26.664350 MyApp.Module.function/2 --> :ok

# With PID
04:02:26.664250 #PID<0.123.0> MyApp.Module.function(arg1)
```

## Getting Started

```bash
mix setup          # Install deps, build assets
mix phx.server     # Start the server
```

Visit [localhost:4000](http://localhost:4000).

## Project Structure

```
lib/
├── trace_log_viewer/
│   ├── log_parser.ex          # Parses raw trace log text into structured entries
│   └── term_parser.ex         # Parses Elixir term strings into a renderable tree
└── trace_log_viewer_web/
    ├── live/
    │   └── trace_log_live.ex              # Main LiveView (upload, paste, filter, search)
    │   └── trace_log_live/
    │       ├── log_entry_component.ex     # Renders individual log entries
    │       └── term_components.ex         # Collapsible tree rendering for parsed terms
    └── components/
        ├── core_components.ex
        └── layouts.ex
```

## Development

```bash
mix precommit     # Compile (warnings-as-errors), format, test
mix test           # Run tests
mix test --failed  # Re-run failed tests
```
