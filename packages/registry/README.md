# registry — the NURL package registry, served by NURL itself

A self-hostable package registry that speaks **exactly the wire protocol
`nurlpkg` already drives** — publish to it, resolve against it, install
from it, with no client changes. It is the NURL re-implementation of
reg.nurl-lang.org (a Cloudflare Worker): the registry that hosts NURL
packages is itself a NURL package, built on three others — [http](../http)
(the server), [template](../template) (the server-rendered pages) and
[md2html](../md2html) (README rendering).

```
nurlpkg install registry            # or build in-tree: nurl.sh src/main.nu registry
                                    # (in-tree: ln -s ../../{http,template,md2html} deps/ first,
                                    #  or just run ./test-e2e.sh which sets them up)

registry token new tero --data ./data       # mint a publish token (printed once)
registry serve --data ./data --port 8914    # serve

export NURL_REGISTRY=http://127.0.0.1:8914/
export NURL_TOKEN=<the token>
nurlpkg publish                     # from any package directory
nurlpkg install <name>              # fetch + verify + build + install
```

## The wire

Read path (static, cacheable):

| Route | Serves |
| --- | --- |
| `GET /index/<name>.json` | the package index — versions, SHA-256 checksums, yank flags, dependency requirements |
| `GET /pkgs/<name>/<name>-<v>.tar.gz` | the tarball, content-addressed and immutable |

Write path (Bearer token):

| Route | Does |
| --- | --- |
| `POST /api/v1/publish` | `X-Nurl-Package` / `X-Nurl-Version` / `X-Nurl-Deps` headers + gzip body. The server recomputes the SHA-256 (a client digest is never trusted), enforces first-publisher name ownership and version immutability (409 on republish). |
| `POST /api/v1/yank` · `/unyank` | owner-only; flips the version's yanked flag (the resolver then skips it) |
| `POST /api/v1/revoke` | deletes the presented token |

Plus `GET /api/v1/search?q=` and `GET /api/v1/stats` (JSON), and a
server-rendered UI: `/` (catalog + search), `/packages/<name>` (owner,
repository from the tarball's manifest, install snippet, versions with
their publish dates, dependencies, and the README rendered straight out
of the published tarball — relative image links rewritten onto the
version-pinned `/files/<name>/<v>/<path>` asset route, images only,
CSP-sandboxed), and `/packages/<name>/<version>/files` (every file in
the published tarball with its size — immutable-cacheable, since
versions are immutable).

## Design

* **SQLite is the single source of truth** (`<data>/registry.db`): users,
  tokens, package ownership, immutable versions, dependency requirements.
  The index JSON is **rendered from the tables on demand** — unlike the
  Worker it replaces, there is no second copy of the version list to
  drift out of sync. Tarballs live on disk under `<data>/pkgs/`, at paths
  **built from validated (name, version) pairs** — no client-supplied
  path segment ever touches the filesystem, so traversal is impossible by
  construction.
* **Connections are per-request** (WAL + busy timeout): every handler is
  thread-safe at any `--workers` count with no shared handle.
* **Tokens** are 32 CSPRNG bytes, shown once; only
  `sha256(pepper ‖ token)` is stored (`REG_TOKEN_PEPPER` is deployment
  config, so a copied database alone can't be brute-forced into live
  tokens). Mint locally with `registry token new`, or configure
  `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` + `REG_BASE_URL` to enable
  the same GitHub-OAuth `/login` flow the public registry uses (the
  outbound GitHub calls ride NURL's pure TLS 1.3 client).
* **TLS**: `--tls-cert` / `--tls-key` serve HTTPS directly (EC or RSA
  leaf; fullchain PEM accepted).

## Commands

```
registry serve [--host H] [--port N] [--data DIR] [--workers N] [--log]
               [--tls-cert PEM --tls-key PEM]
registry token new <login> [--data DIR]
```

Environment: `REG_TOKEN_PEPPER`, `REG_BASE_URL`, `GITHUB_CLIENT_ID`,
`GITHUB_CLIENT_SECRET`.

## Tests

* `nurlpkg test` runs `tests/wire.nu` — the full protocol driven through
  `router_handle` with **no socket**: publish → index → tarball → yank →
  search → stats → revoke, ownership and validation rejections, README
  rendering and asset extraction. ASan/LSan-clean.
* `./test-e2e.sh` is the end-to-end proof: it builds the server, installs
  the toolchain into a throwaway prefix, `nurlpkg publish`es the in-tree
  `md2html` plus a synthesized consumer package, then `nurlpkg install`s
  the consumer from a clean environment — dependency resolution, checksum
  verification and the tarball fetch all served by this package — runs
  the installed binary, and verifies a yanked version is refused.
