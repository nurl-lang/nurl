# NURL package registry — deployment

A Cloudflare Worker (`registry/src/index.ts`) backed by **R2** (the static
read path: `index/*.json` + `pkgs/**/*.tar.gz`) and **D1** (users, tokens,
package ownership, versions). The NURL client (`nurlpkg install` /
`nurlpkg publish`) drives this exact contract.

**Status: LIVE in production at https://reg.nurl-lang.org.** It serves real
packages today (e.g. `nq` and `md2html`, published 2026-06-20), and the
default `nurlpkg install <name>` resolves against it. The sections below are
the reference for *reproducing* or re-provisioning that deployment — the
production instance is already wired.

## Provisioning an instance (reference — production is already live)

1. **A GitHub OAuth App** (https://github.com/settings/developers → *New OAuth App*)
   - Homepage URL: `https://reg.nurl-lang.org`
   - Authorization callback URL: `https://reg.nurl-lang.org/auth/callback`
   - Note the **Client ID** (public) and generate a **Client Secret**.

2. **A Cloudflare account** with Workers + R2 + D1 enabled.

## One-time setup

```bash
cd registry
npm install

# R2 bucket (static read path)
npx wrangler r2 bucket create nurl-registry

# D1 database — paste the printed database_id into wrangler.jsonc
npx wrangler d1 create nurl-registry
npx wrangler d1 migrations apply REG_DB --remote

# Public config
#   edit wrangler.jsonc: set GITHUB_CLIENT_ID + REGISTRY_URL

# Secrets — stored encrypted in Cloudflare, NEVER in the repo:
npx wrangler secret put GITHUB_CLIENT_SECRET     # from the OAuth app
npx wrangler secret put TOKEN_PEPPER             # any long random string

npx wrangler deploy
```

Point `reg.nurl-lang.org` at the Worker (Workers → custom domain) and the
read path is a cacheable CDN; the write path (`/api/v1/publish`) is the
authenticated Worker route.

## Secrets — where each one lives

| Secret | Home | How |
|---|---|---|
| `GITHUB_CLIENT_SECRET`, `TOKEN_PEPPER` | Cloudflare (encrypted) | `wrangler secret put` — never in repo/wrangler.jsonc |
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | GitHub Actions repo secrets | used by the deploy workflow (placeholders pre-created) |
| local dev values | `registry/.dev.vars` | gitignored (`.dev.vars.*`); keys: `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, `TOKEN_PEPPER`, `REGISTRY_URL`. `test-local.sh` writes it automatically. |
| `GITHUB_CLIENT_ID` | `wrangler.jsonc` `vars` | public, fine to commit |

The `CLOUDFLARE_API_TOKEN` for CI: Cloudflare dashboard → My Profile → API
Tokens → *Edit Cloudflare Workers* template (add R2 + D1 edit). Put it (and
your account id) into the repo's GitHub Actions secrets; the
`.github/workflows/registry-deploy.yml` workflow deploys on push to `main`
that touches `registry/`.

## Publishing flow (end users)

```bash
# 1. Get a token: open https://reg.nurl-lang.org/login, sign in with GitHub,
#    copy the one-time token it shows.
export NURL_TOKEN=<token>
# 2. From a package dir (has nurl.toml):
nurlpkg publish
# 3. Consumers depend on it (foo = "^1.0" in [dependencies]) and:
nurlpkg install
```

`$NURL_REGISTRY` overrides the registry URL (defaults to the built-in /
`[package].registry`). The registry recomputes each tarball's SHA-256
server-side, enforces first-publisher name ownership, and treats published
versions as immutable.

## Local testing (no account)

`registry/test-local.sh` runs the Worker under `wrangler dev` (miniflare
simulates R2 + D1), seeds a token into the local D1, and drives the real
`nurlpkg` binary through a full publish → install round-trip plus
immutability (409) and bad-token (401) rejections:

```bash
./build.sh                 # build/nurlpkg
cd registry && npm install
./test-local.sh            # prints PASS / FAIL
```
