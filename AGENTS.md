# Inkling Agent Guide

Inkling is a focused native macOS app for comparing and editing 2 text files.
Prefer native behavior, predictable review actions, and correctness over adding
surface area.

## Commands

`just` lists the available recipes.

```sh
just test       # Swift tests
just corpus     # Diff coverage, fragmentation, and runtime report
just check      # Tests, signed app build, and launch smoke test
just run        # Build and open build/Inkling.app
CONFIGURATION=release just check
```

Requirements are macOS 14+, Xcode 16+, Swift 6, and `just`.

## Architecture

- SwiftUI owns composition, headers, settings, status, and the center action
  rail.
- AppKit `NSTextView` owns editing, selection, layout, native undo, drag/drop,
  and find indicators.
- `DiffSession` owns loaded files, revisions, dirty state, async recomputation,
  navigation, saving, and block transfer.
- `DiffEngine` produces line, phrase, word, and character differences.
- `DiffConfiguration` controls internal line-pair sensitivity independently
  from semantic word refinement.
- `TextFileService` performs strict supported-encoding decoding and explicit
  file writes.
- `L10n` resolves the String Catalog from the packaged SwiftPM resource bundle.
- `test-files/` contains focused manual comparison fixtures.

## Swift and macOS Practices

- Keep UI state and AppKit interaction `@MainActor`-isolated. Pass immutable
  `Sendable` values across concurrency boundaries.
- Prefer structured, cancellable tasks. Use `Task.detached` only for pure,
  CPU-bound diff work, then validate the captured document revision before
  publishing results.
- Use Observation (`@Observable`) for shared app state and avoid duplicating
  derived state in views.
- Follow native AppKit editing lifecycles instead of mutating `NSTextStorage`
  behind the editor's back.
- Respect the macOS 14 deployment target and verify unfamiliar APIs against the
  installed SDK rather than relying on remembered signatures.
- Avoid force unwraps, silent error fallbacks, and unchecked UTF-16 ranges.
- Use Swift Testing with focused, behavior-named `@Test` cases. Mark UI-facing
  tests `@MainActor`.
- Preserve keyboard access, VoiceOver labels, and non-color diff cues when
  changing interaction or rendering.

## Invariants

- Keep editor panes exactly equal in width side by side and equal in height
  when stacked. Preserve `HSplitView` for horizontal layout and `VSplitView`
  for vertical layout; replacing the horizontal split with an `HStack` has
  broken editor rendering.
- Keep line-number gutters independent from the text view so they cannot cover
  leading glyphs.
- `DiffChange` is the semantic navigation/counting unit. `DiffHunk` is the
  whole-line block-transfer unit.
- Keep matching bounded: full matrices are capped, large regions use ordered
  unique anchors, and unresolved gaps use linear-space matching within a shared
  work budget.
- Navigation centers and emphasizes a change without replacing the user's
  selection.
- Copy Block validates document revisions and ranges, then mutates through the
  target `NSTextView` and its native `UndoManager`.
- File loads clear the replaced editor's undo history. Model-to-view refreshes
  must not register undo operations.
- Never write merely because a file was opened. Preserve dirty-state guards and
  explicit Save/Discard/Cancel behavior.
- Reject malformed or unsupported text instead of silently replacing data.
- Package `Inkling_Inkling.bundle` under
  `Contents/Resources`; the launch smoke test must catch resource regressions.
- Route user-facing text through `L10n` and the String Catalog.

## Change Discipline

- Make surgical changes and preserve native macOS conventions.
- Add focused tests for diff, document-state, or file-I/O behavior changes.
- Run `just corpus` when changing alignment semantics and compare coverage,
  span counts, paired hunks, and runtime across the full fixture set.
- Run the smallest relevant test while iterating; run `just check` before
  landing code that affects the app.
- Keep generated build output and the untracked root `left.txt` out of commits.
- Do not delete or overwrite user files as cleanup.

## Version Control

This is a colocated Jujutsu/Git repository. Use `jj` for local history.

- Keep commits atomic and use Conventional Commits:
  `type(scope): imperative subject`.
- Use `feat`, `fix`, `refactor`, `test`, `docs`, `build`, `perf`, `style`, `ci`,
  `chore`, or `revert`. Omit the scope when it adds no useful context.
- Keep the subject lowercase, under 50 characters, and without a trailing
  period. Use the body to explain why or document tradeoffs.
- Mark breaking changes with `!` and a `BREAKING CHANGE:` footer.
- Never add Copilot co-author or session trailers.
- Move `main` to the completed commit, fetch, push with `jj git push`, and
  verify local and remote `main` match.
- Do not rewrite published history unless the user explicitly requests it.

## Beads

Use `bd` for durable roadmap and issue tracking when its embedded Dolt store is
healthy:

```sh
bd ready
bd show <id>
bd update <id> --claim
bd close <id>
bd dolt push
```

The local embedded store may fail because `.dolt/repo_state.json` is missing.
If it does, report the failure and continue the requested work; do not delete,
reinitialize, import into, or otherwise mutate `.beads` as a workaround.
