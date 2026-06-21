# `md2html` — Markdown → HTML, as a CLI and a library

`md2html` renders Markdown to HTML. It ships both ways:

- an **installable CLI** (`md2html`) that reads Markdown from stdin or a
  file and writes HTML, optionally wrapped in a complete styled page; and
- a **reusable renderer library** (`src/markdown.nu`, one function
  `md_to_html`) that other packages can depend on.

The renderer is the same one that powers the NURL playground's doc viewer,
extracted into the registry so any project can use it.

```
nurlpkg install md2html
md2html < README.md                 # HTML fragment to stdout
md2html -f README.md --full         # complete styled HTML page
md2html -f doc.md -t "My Doc" -F    # full page with a custom <title>
```

## CLI options

| Option | Meaning |
| ------ | ------- |
| `-f`, `--file F`  | read Markdown from file `F` instead of stdin |
| `-F`, `--full`    | emit a complete styled HTML document (not just a fragment) |
| `-t`, `--title T` | document `<title>` when used with `--full` (default `Document`) |
| `-h`, `--help`    | show help |

## Using the renderer as a library

Declare the dependency and import the renderer module:

```toml
[dependencies]
md2html = "^0.1"
```

```
$ `deps/md2html/src/markdown.nu`

: String html ( md_to_html ( string_data my_markdown ) )
// ... use html ...
( string_free html )
```

`md_to_html` takes a Markdown source string and returns an owned HTML
`String` (free it with `string_free`).

## Supported Markdown

- ATX headings (`#` … `######`)
- Fenced code blocks (```` ```lang ````) with a language class
- GitHub-style tables (`| a | b |` + a `|---|---|` delimiter row)
- Blockquotes (`>`)
- Unordered and ordered lists (`-` / `*` / `1.`)
- Horizontal rules (`---`, `***`, `___`)
- Inline: `` `code` ``, `**bold**`, `*em*`, `[text](url)`, `![alt](src)`,
  and `<autolinks>`

Raw text is HTML-escaped; existing entity references are left alone.

Not supported (by design — they don't appear in typical READMEs): nested
lists by indentation, definition lists, footnotes, reference-style links,
setext headings, and raw HTML passthrough.

## Quality

The renderer is a verbatim extraction of the playground's doc renderer,
and the CLI is leak-clean under AddressSanitizer/LeakSanitizer across its
code paths (stdin, `--file`, `--full`, help, and the file-error branch).
The end-to-end install-and-run loop is covered by
`tools/nurlpkg/test-install-tool.sh`.
