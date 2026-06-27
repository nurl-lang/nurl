# `nq` — a tiny jq-lite JSON query tool

`nq` is the kind of utility every developer keeps within reach: it reads
JSON from stdin (or a file), applies a small jq-like filter, and prints
the result — pretty by default, compact or raw on request.

It lives in the NURL **registry** (it is *not* part of the core stdlib).
`nq` parses flags with the stdlib `std/args` and leans on the shipped
`stdlib/ext/json` for parsing and printing.

```
nurlpkg install nq
```

## Usage

```
nq [OPTIONS] [FILTER]
```

`FILTER` is a jq-lite path; the default is `.`, the whole document. Input
is read from stdin unless `--file` is given.

| Option | Meaning |
| ------ | ------- |
| `-c`, `--compact` | compact, single-line output |
| `-r`, `--raw`     | raw output for string results (no surrounding quotes) |
| `-f`, `--file F`  | read JSON from file `F` instead of stdin |
| `-h`, `--help`    | show help |

## Filter grammar

```
filter := path [ '|' func ]
func   := keys | length
```

| Filter | Result |
| ------ | ------ |
| `.` | the whole document |
| `.user.name` | navigate objects/arrays (use `.0` for index 0, `[0]` also works) |
| `.items[]` | iterate an array or object — one result per line |
| `.items[].id` | project a field out of each iterated element |
| `. \| keys` | object keys (or array indices) as an array |
| `. \| length` | length of an array / object / string |

A missing path yields `null` (like `jq`). Iterating a scalar, or applying
`keys`/`length` to a value of the wrong type, is an error (exit code 1).

## Examples

```console
$ echo '{"user":{"name":"Ada","age":36},"tags":["x","y","z"]}' | nq .user
{
  "name": "Ada",
  "age": 36
}

$ echo '{"user":{"name":"Ada"}}' | nq -r .user.name
Ada

$ echo '{"items":[{"id":1},{"id":2},{"id":3}]}' | nq '.items[].id'
1
2
3

$ echo '{"a":1,"b":2,"c":3}' | nq -c '. | keys'
["a","b","c"]

$ echo '["x","y","z"]' | nq '. | length'
3
```

## Quality

`nq` is leak-clean under AddressSanitizer / LeakSanitizer across every
code path (navigation, iteration, the `keys`/`length` terminals, and the
error/parse-failure branches). The end-to-end install-and-run loop is
covered by `tools/nurlpkg/test-install-tool.sh`.
