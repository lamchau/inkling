# Inkling

**A focused, local-first text comparison and editing app for macOS.**

> **AI disclosure:** Inkling and its documentation were written by AI under
> human direction and review.

Inkling puts 2 files in equal, editable panes and makes the smallest meaningful
changes easy to see. It combines semantic, word, character, and line comparison
with native macOS editing, deliberate navigation, and undoable block transfer.

## Why Inkling

Text comparison tools often optimize for a different job:

- command-line tools are fast, but inspection and editing happen elsewhere;
- IDE diff views are tied to projects, source control, and dense workspaces;
- line-oriented viewers can turn a one-character edit into a full-line change;
- merge tools mix comparison with conflict-resolution machinery;
- hosted tools can require uploading files that should remain local.

Inkling was made for the smaller, frequent task in between: open any 2 local
text files, understand exactly what changed, edit either side, selectively move
content, and save only when you choose.

```mermaid
flowchart LR
    Files[2 local text files] --> Lines[Align stable lines]
    Lines --> Pairs[Pair related edits]
    Pairs --> Meaning[Refine to phrases, words, and characters]
    Meaning --> Review[Review, edit, and transfer blocks]
    Review --> Save[Save explicitly]
```

## What Inkling Aims to Accomplish

- Make a one-character edit visible without losing its word, phrase, or line
  context.
- Make any 2 files easy to compare, even when they live in unrelated
  directories.
- Treat both sides as full, equal editors rather than a source and a preview.
- Keep review precise while making mutation deliberate, disclosed, and
  undoable.
- Preserve native macOS behavior and keep file contents local.
- Stay fast and focused enough to use for a single comparison without project
  setup.

## Comparison Toolkit

| Tool | Purpose |
| --- | --- |
| Semantic diff | Balances readable phrase and word context with exact character refinement |
| Word diff | Emphasizes changed words and punctuation without character detail |
| Character diff | Shows the smallest differing extended grapheme clusters |
| Line diff | Presents complete changed lines when structural review matters most |
| Comparison layout | Switches between equal side-by-side and top-and-bottom editors |
| Ignore whitespace | Removes whitespace from matching decisions for the current comparison |
| Semantic navigation | Counts and visits meaningful changes independently of line hunks |
| Current-change emphasis | Centers, flashes, and underlines the active change without replacing selection |
| Copy Block | Transfers the containing line hunk left or right as one undoable action |
| Foreground/background modes | Switches between colored text and translucent color blocks |
| Category palette | Customizes character, word, phrase, addition, and deletion colors |
| Synchronized scrolling | Keeps both viewports moving together |
| Logical caret sync | Maps the caret to the corresponding line and column in the other pane |
| Line numbers | Adds independent gutters without reducing or covering editor text |

Semantic and character alignment use a grouped edit-cost model so nearby edits
remain coherent instead of fragmenting around ambiguous matches. Large
comparisons first seek stable unique anchors, then use bounded linear-space
matching for difficult gaps.

## Quick Start

### Requirements

- macOS 14 or newer
- Xcode 16 or newer
- Swift 6
- [`just`](https://just.systems/)

Build and open the app:

```sh
just run
```

Run the complete quality gate:

```sh
just check
```

The signed development app is written to `build/Inkling.app`.

For a release build:

```sh
CONFIGURATION=release just run
```

`APP_BUNDLE` can override the output location:

```sh
APP_BUNDLE=build/Inkling-preview.app just app
```

Run `just` with no arguments to list every recipe.

## Using Inkling

1. Drop one file onto each pane, choose each pane independently, or press
   **Command-O** to select 2 files.
2. Choose side-by-side or top-and-bottom layout from the header, then select the
   comparison mode that best matches the review.
3. Move through changes from the center rail or with the configured navigation
   shortcuts.
4. Edit either pane directly. Use the center arrows to copy the current block
   in either direction.
5. Save the focused file with **Command-S** or both files with
   **Command-Shift-S**.

### Default Shortcuts

| Action | Shortcut |
| --- | --- |
| Open comparison | `Command-O` |
| Save focused file | `Command-S` |
| Save both files | `Command-Shift-S` |
| Previous / next change | `Command-Option-Up` / `Command-Option-Down` |
| Copy block right / left | `Command-Option-Right` / `Command-Option-Left` |
| Toggle ignored whitespace | `Command-Option-W` |
| Swap sides | `Command-Option-S` |
| Semantic / word / character / line strategy | `Control-Command-1` through `4` |

Navigation shortcuts and the default comparison layout can be changed in
Settings. Switching layouts preserves the open files, edits, dirty state, and
current comparison.

## File Safety and Supported Text

- Opening or comparing a file never writes to disk.
- Replacing a dirty pane, closing a window, or quitting requires an explicit
  Save, Discard, or Cancel decision.
- Copy Block rejects stale comparisons and invalid editor ranges.
- File loads reject malformed input instead of inserting replacement
  characters.
- UTF-8, UTF-8 with BOM, and UTF-16 little- or big-endian text with a BOM are
  accepted.
- Files containing null bytes and files larger than 5 MiB are rejected.
- Files of 1 MiB or more require confirmation before comparison.
- Saves are atomic and currently write UTF-8.

## Using the Diff Library

`InklingDiff` is a dependency-free Swift library product. Add this package to
another Swift package, depend on the `InklingDiff` product, and compare strings
without importing AppKit or the Inkling application:

```swift
import InklingDiff

let result = DiffEngine.compare(
    left: original,
    right: revised,
    ignoreWhitespace: false,
    strategy: .semantic
)
try result.validate(left: original, right: revised)
```

Results use UTF-16 `NSRange` values so clients can apply highlights directly to
Foundation and AppKit text storage. Each result also reports whether matching
was exact, stable-anchor-assisted, or bounded. Validation rejects malformed
ranges, line hunks, identifiers, references, and navigation offsets before a
client renders or acts on a result.

The trust suite exhaustively checks every pair of short character strings
against an independent LCS oracle, then runs seeded randomized Unicode and
whitespace comparisons for determinism, symmetry, and structural validity.
These tests establish strong evidence for the covered input space; they are not
a claim that every possible input has been formally verified.

## Current Scope

Inkling intentionally focuses on 2 local text files. It does not currently
provide:

- directory, image, binary, or three-way comparison;
- source-control or pull-request integration;
- merge-conflict automation;
- original encoding/BOM preservation when saving;
- external file-change detection;
- session persistence or a change-list sidebar.

Large comparisons use bounded matching fallbacks to protect responsiveness, so
extremely large or highly reordered changes may receive coarser alignment. The
app discloses that outcome in its status text rather than presenting it as an
exact result.

## Development

```sh
just             # List recipes
just build       # Build the Swift executable
just test        # Run Swift Testing suites
just corpus      # Report strategy metrics for every fixture
just app         # Package and ad-hoc sign the app
just verify-app  # Verify resources, signature, and launch
just check       # Run tests and app verification
```

Focused manual fixture pairs live in [`test-files/`](test-files/README.md).

## Project Documentation

- [DESIGN.md](DESIGN.md) - product goals, interaction model, and deliberate
  tradeoffs
- [ARCHITECTURE.md](ARCHITECTURE.md) - runtime structure, diff pipeline,
  document lifecycle, and validation
- [AGENTS.md](AGENTS.md) - concise implementation guidance for coding agents
