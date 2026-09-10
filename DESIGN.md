# Inkling Design

## Product Intent

Inkling is a purpose-built environment for understanding and editing the
difference between 2 text files. It is not a source-control browser, a merge
suite, or a general-purpose editor with a diff panel attached.

The core job is:

> Show exactly what changed, preserve enough surrounding context to understand
> it, and make the next safe action obvious.

## The Problem

Most diff presentations begin with lines because lines are stable, cheap to
compare, and easy to render. That is useful for structure, but often too coarse
for prose, configuration, generated text, and small code edits. A single
character may be the only meaningful difference while the interface emphasizes
an entire line.

Finer-grained tools can fail in the opposite direction. Raw character diffs
fragment text into visual noise, lose word boundaries, and make related edits
look unrelated. Review then becomes a choice between too much highlighting and
too little meaning.

Inkling treats line alignment as structure, not as the final presentation.
Changed lines are paired, stable words become anchors, related edits become
phrases, and similar words are refined down to their exact character changes.

## Design Principles

### Make the smallest meaningful change visible

Character changes should remain visible inside their word and phrase context.
The semantic mode is the default because it balances precision with readable
grouping; word, character, and line modes remain available when a different
question needs answering.

### Keep both sides equally important

Neither file is a privileged source or destination. The panes remain exactly
equal in width, both are editable, and every side-specific action has a mirrored
equivalent. Direction becomes explicit only when the user copies a block.

### Separate review units from mutation units

A reviewer navigates semantic changes, which may be a character, word, phrase,
addition, or deletion. A transfer operation acts on a complete line hunk so the
result remains structurally coherent. Navigation precision must not imply an
unsafe partial mutation.

### Preserve user agency

Opening is not saving. Navigating is not selecting. Comparing is not merging.
Copying is undoable. Dirty files cannot be silently replaced or discarded.
These boundaries keep review actions predictable.

### Be native where behavior matters

Text editing, selection, wrapping, undo, keyboard commands, file panels, and
accessibility should behave like macOS. Custom UI is reserved for the comparison
model: highlights, change navigation, side-specific drop targets, and the center
action rail.

### Customize signal, not structure

Foreground/background modes and per-category colors let users adapt contrast
and emphasis. They do not change what an operation means. Character, word,
phrase, addition, and deletion remain stable categories regardless of palette.

### Stay focused and fast

The interface should open directly into a 2-file task, avoid project setup,
and keep controls close to the comparison. Expensive matching is bounded and
performed away from the main actor; stale results are discarded.

## Interaction Model

### Setup

The empty state presents one drop well per side. A user may fill the 2 slots
from unrelated directories, drop 2 files together, or use the native 2-file
selection panel.

### Review

The center rail provides previous/next navigation and communicates the current
position. Navigation centers and briefly flashes the semantic range while a
persistent underline retains orientation. The user's text selection remains
untouched.

### Edit and transfer

Both panes are ordinary editable text views. Direct edits immediately mark that
side dirty and schedule a new comparison. Copy Block moves the current line
hunk toward the chosen side and registers one named native undo operation.

### Save and exit

Command-S saves the focused dirty pane; Save Both handles both sides and reports
partial failures. Replacing files, closing, and quitting use the same explicit
Save/Discard/Cancel model.

## Visual Language

- **Character** identifies the exact local edit and receives the strongest
  nested emphasis.
- **Word** identifies a changed lexical unit.
- **Phrase** groups a larger unmatched region.
- **Addition** and **deletion** identify unpaired lines.
- **Current change** uses a separate accent underline so navigation state does
  not overwrite category color.
- **Drop state** uses a dashed boundary and translucent fill, preserving the
  side that will receive the file.

Color is useful but should not be the only long-term cue. Keyboard access,
labels, shape, underline, and position must continue to carry meaning.

## Deliberate Boundaries

Inkling currently avoids directory comparison, version-control hosting,
three-way merge workflows, binary formats, and automated conflict resolution.
Those features would change the product from a focused comparison tool into a
workspace.

Future additions should earn their place by improving the 2-file loop without
obscuring it. A feature that needs persistent project state, a repository model,
or a second navigation hierarchy should be treated with particular skepticism.
