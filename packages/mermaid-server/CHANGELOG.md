# Changelog

## 0.1.1

`nurlpkg install mermaid-server` installed a binary that could not start:
it builds `src/main.nu` and puts the binary on `$PATH`, and nothing else
in the package comes with it — so the templates the server loads at
startup were never there, and it exited with "no template directory
found".

- **The templates are declared as install assets** (`[install] assets`),
  which stages them to `$NURL_HOME/share/mermaid-server/.templates` — the
  last entry in the resolution chain, so an installed server finds its
  three looks with no further setup. The postinstall hint says what was
  installed instead of asking the user to copy files by hand.
- **`http` is required as `^0`**, the major-only form the rest of the
  registry moved to in #1027, rather than `^0.4.0`.

## 0.1.0

First release.

* **Parser** for the mermaid `graph` / `flowchart` dialect: all five
  directions, all thirteen node shapes, quoted labels, `<br/>` line breaks
  and HTML entities, the solid / dotted / thick line styles with
  arrow / circle / cross heads and bidirectional links, both edge-label
  spellings, chains, `&` node groups, `;` separators and `%%` comments.
  `classDef` / `class` / `style` / `linkStyle` / `click` / accessibility
  statements are skipped with a warning that travels out to the caller;
  `subgraph` is a hard error, because dropping it would change what the
  diagram means.
* **Layered layout** — back-edge-tolerant ranking, dummy-node splitting so
  a link crossing several layers gets its own corridor, barycentre
  crossing reduction, neighbour-pulled placement — in integer arithmetic.
* **SVG renderer** with per-shape geometry, shape-accurate link clipping
  and arrow heads drawn as geometry rather than markers.
* **Templates**: every visual value is read from an external directory of
  TOML files at startup and chosen per request by name, with per-shape and
  per-line-style overrides and a raw-CSS escape hatch. `default`, `dark`
  and `blueprint` ship with the package. The source is a discriminated
  kind, so a non-filesystem loader is one added branch.
* **HTTP**: `POST /render`, `GET /render?src=`, `POST /render.json`,
  `GET /templates`, `GET /healthz`, and a self-contained live playground at
  `/`. Multi-threaded (one worker per CPU by default); permissive CORS.
* **MCP** in the same process: `mermaid_render`, `mermaid_templates` and
  `mermaid_validate`, over Streamable HTTP at `/mcp` or over stdio with
  `--stdio`.
* **CLI**: `render` (stdin or a file, `-o` to a file) and `templates`.
