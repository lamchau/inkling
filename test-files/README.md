# Test files

Each directory contains a `left.txt` and `right.txt` pair for manual Inkling
testing.

Run `just corpus` to report highlight coverage, span counts, change counts,
hunks, and runtime for every Inkling algorithm and fixture.

| Pair | Exercises |
| --- | --- |
| `a-vs-b` | The original `../a.txt` and `../b.txt`, preserved byte-for-byte |
| `single-character` | One changed character inside an otherwise matching word |
| `semantic-phrases` | Several word and phrase edits on matching prose lines |
| `line-insertion` | Added and removed lines for navigation and pane alignment |
| `whitespace` | Tabs, spaces, and blank-line differences |
| `unicode` | Accents, emoji modifiers, CJK text, and right-to-left text |
