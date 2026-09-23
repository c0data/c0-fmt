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
  -g, --group NAME     Group name for import (default: filename stem)
  -h, --help           Show help
```

Reads from a file argument or stdin. The import command auto-detects
format from file extension (.csv, .json, .yaml, .yml) or content.

## Install

Requires [Crystal](https://crystal-lang.org) 1.19 or newer.

```sh
git clone https://github.com/c0data/c0-fmt
cd c0-fmt
shards build --release
cp bin/c0fmt ~/.local/bin/    # or anywhere on your PATH
```

## Examples

Convert a CSV file to pretty-printed C0DATA:

```sh
c0fmt import data.csv | c0fmt pretty
```

```
␝data
  ␁name␟amount
  ␞Alice␟100
  ␞Bob␟200
```

Round-trip through C0DATA and back to CSV:

```sh
c0fmt import csv users.csv | c0fmt export csv
```

Import JSON and view as pretty C0DATA:

```sh
echo '{"users": [{"name": "Alice"}, {"name": "Bob"}]}' | c0fmt import | c0fmt pretty
```

```
␝users
  ␁name
  ␞Alice
  ␞Bob
```

Export to JSON or YAML:

```sh
c0fmt import users.csv | c0fmt export json
```

```json
{
  "users": [
    {"name": "Alice", "amount": "100"},
    {"name": "Bob", "amount": "200"}
  ]
}
```

```sh
c0fmt import users.csv | c0fmt export yaml
```

```yaml
---
users:
- name: Alice
  amount: "100"
- name: Bob
  amount: "200"
```

Validate a C0DATA file (`-s` validates a stream log block by block):

```sh
c0fmt validate data.c0
c0fmt validate -s claims.c0
```

Convert between pretty and compact forms:

```sh
c0fmt compact pretty.c0 -o data.c0    # pretty → compact
c0fmt pretty data.c0                   # compact → pretty
```

## Development

```sh
shards install
shards build
crystal tool format
```

## License

MIT
