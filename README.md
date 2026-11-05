# c0fmt

Command-line tool for [C0DATA](https://github.com/c0data): import and export
CSV, JSON, and YAML; convert between compact and pretty forms; validate.
Built on the Crystal reference implementation,
[c0-cr](https://github.com/c0data/c0-cr).

```
c0fmt <command> [options] [file]

Commands:
  import [format] [file]   Import CSV, JSON, or YAML to C0DATA
  export <format> [file]   Export C0DATA to CSV, JSON, or YAML
  pretty [file]            Convert to pretty-printed Unicode form
  compact [file]           Convert to compact binary form
  validate [file]          Check well-formedness

Options:
  -o, --output FILE    Write to file (default: stdout)
  -g, --group NAME     import: group name (default: filename stem)
                       export csv: which group (default: the first)
  -a, --align          pretty: align table columns
  -s, --stream         validate: as a stream log (torn tail, damaged blocks)
  -c, --canonical      validate: also require canonical form
  -h, --help           Show help
```

Reads from a file argument or stdin. Every command accepts either form of
C0DATA as input, compact or pretty, and tells them apart by the glyphs.
The import command auto-detects its format from the file extension
(.csv, .json, .yaml, .yml) or the content.

## Install

Requires [Crystal](https://crystal-lang.org) 1.19 or newer.

```sh
git clone https://github.com/c0data/c0-fmt
cd c0-fmt
shards build --release
cp bin/c0fmt ~/.local/bin/    # or anywhere on your PATH
```

## Shell completion

c0fmt generates its own completion scripts for bash, zsh, and fish. They
complete subcommands, options, formats, and file paths.

```sh
# bash
c0fmt --completions bash > ~/.local/share/bash-completion/completions/c0fmt

# zsh (a directory on your $fpath)
c0fmt --completions zsh > ~/.zfunc/_c0fmt

# fish
c0fmt --completions fish > ~/.config/fish/completions/c0fmt.fish
```

## Examples

`examples/inventory.c0` is a small document in pretty form that uses most
of the format: a SYN heading, a file name, groups at two depths, a header
row, nested lists, a keyed record with a multi-line text value, a note, a
dead record, and references. `cat` it to see the glyphs.
`examples/inventory-compact.c0` is the same document in compact form,
the bytes on the wire; `cat -v` shows the codes as `^A`, `^^` and so
on, and `c0fmt pretty` turns it back into the first file.

Convert a CSV file to pretty-printed C0DATA:

```sh
c0fmt import data.csv | c0fmt pretty
```

```
␖␁version␟1
␝data
  ␁␞name␟amount
  ␞Alice␟100
  ␞Bob␟200
␄
```

Import writes a complete file: the SYN heading naming the spec version,
the data, EOT.

Round-trip through C0DATA and back to CSV:

```sh
c0fmt import csv users.csv | c0fmt export csv
```

Import JSON and view as pretty C0DATA:

```sh
echo '{"users": [{"name": "Alice"}, {"name": "Bob"}]}' | c0fmt import | c0fmt pretty
```

```
␖␁version␟1
␝users
  ␁␞name
  ␞Alice
  ␞Bob
␄
```

Export to JSON or YAML. A header row gives objects; a keyed record gives
an object; a nested level gives a list or table; a reference gives
`{"$ref": "group/record"}`:

```sh
c0fmt export json examples/inventory.c0
```

```json
{
  "inventory": {
    "users": [
      {"id": "1", "name": "Alice", "email": "alice@example.com", "roles": ["admin", "editor"]},
      ...
    ],
    "config": {"host": "localhost", "port": "5432", "motd": "Welcome back.\nSecond line."},
    "links": [{"user": {"$ref": "users/1"}, "tag": {"$ref": "tags/001"}}]
  }
}
```

CSV takes one group, the first unless `-g` names another. A reference is
written as its path; a nested level has no CSV form and is an error:

```sh
c0fmt export csv -g links examples/inventory.c0
```

```
user,tag
users/1,tags/001
```

Validate. The verdict goes to stderr; the exit status is 0 when valid.
Reader warnings (a missing SYN heading, an unknown heading key) are
printed but do not fail the check. `-c` also requires canonical form and
says what is not canonical; `-s` reads a stream log block by block:

```sh
c0fmt validate data.c0
c0fmt validate -c data.c0       # not canonical: comment
c0fmt validate -s claims.c0     # torn: 4 uncommitted byte(s) after 2 committed block(s)
```

Convert between pretty and compact forms; `-a` aligns table columns in
the pretty output, which is layout only and never changes the data:

```sh
c0fmt compact pretty.c0 -o data.c0    # pretty → compact
c0fmt pretty data.c0                   # compact → pretty
c0fmt pretty -a data.c0                # aligned
```

## Development

```sh
shards install
shards build
crystal tool format
```

## License

MIT
