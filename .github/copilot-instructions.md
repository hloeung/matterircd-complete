# Copilot Instructions — matterircd-complete

## Environment & Formatting

- Language: Perl 5 (targeting embedded Perl in Irssi).
- Indentation: Strictly 4 spaces per indentation level. Do not use hard tabs.
- Pragmas: Always respect and maintain `use strict;` and `use warnings;`.
- Dependencies: Rely strictly on standard Perl core modules (e.g., `POSIX`, `File::Spec`, `Encode`, `JSON::PP` where applicable) and the embedded `Irssi` API (`Irssi`, `Irssi::Irc`, `Irssi::TextUI`). Avoid introducing external CPAN dependencies that break standalone `~/.irssi/scripts/` deployments.

## Irssi Script Architecture & Conventions

- Signals & Handlers: Follow existing Irssi idioms for signal registration (`Irssi::signal_add`, `Irssi::signal_add_priority`) and signal flow control (`Irssi::signal_continue`, `Irssi::signal_stop`).
- Context Safety: Always check and safely handle optional or undefined contexts (e.g., when `$server` or `$witem` is `undef` in status windows or background signals).
- Settings & Commands: Use standard `Irssi::settings_add_*` and `Irssi::settings_get_*` conventions for configuration. Use `Irssi::command_bind` for script commands.
- Naming & Structure: Follow established `snake_case` subroutines and variable naming conventions consistent with the existing script (e.g., `$server`, `$witem`, `$target`, `$data`).

## Diff Hygiene & Scope

- Keep changes minimal, surgical, and scoped strictly to the task.
- Match existing structural flow and indentation. Do not add, remove, or reformat blank lines or whitespace on untouched lines.
- Preserve existing comments unless they are invalidated by the change.
- Avoid excessive defensive over-engineering, unnecessary abstraction layers, or speculative helpers when direct procedural Perl fits the surrounding code.
- Do not add or suggest test suites or unit test frameworks unless explicitly requested.

## Memory, Regex & Performance

- Long-Running Session Hygiene: The script runs continuously inside Irssi for weeks or months. Ensure hash caches, message thread tables, and completion rings do not grow unbounded (enforce size limits / TTL eviction).
- Regex Performance: Precompile regular expressions where appropriate (`qr//`). Avoid expensive, unanchored regexes in high-frequency signal hooks like `message public` or completion triggers.
- Safe I/O & TOCTOU: Prevent time-of-check to time-of-use (TOCTOU) race conditions during cache read/write operations. When persisting cache or state to disk, use atomic writes (write to temporary file and `rename`) with explicit open modes.
- Comments: Document only non-obvious Irssi quirks, edge cases, protocol handling, and intent. Do not write self-evident comments that restate the code.
