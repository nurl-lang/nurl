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
npx wrangler secret put REG_SIGN_KEY             # base64 Ed25519 seed (32B) —
                                                 # signs every published tarball

npx wrangler deploy
```

### Package signing (`REG_SIGN_KEY`)

The registry signs every published tarball with a project Ed25519 key
(minisign legacy `Ed` format — a raw signature over the `.tar.gz` bytes, since
Web Crypto lacks BLAKE2b). `nurlpkg` pins the matching **public** key and
verifies with its pure-NURL minisign implementation, so a compromised R2/CDN
can't substitute tarball bytes. Verification is **mandatory + fail-closed**.

- `REG_SIGN_KEY` is the base64 32-byte Ed25519 **seed**. The pinned public key
  lives in `stdlib/ext/pkg_fetch.nu` (`__pkg_reg_pubkey`) and its keyid is
  hard-coded in `src/index.ts` (`REG_SIGN_KEYID`) — all three must correspond
  to the same key.
- **One-time backfill** — packages published *before* signing was enabled have
  no `.minisig`, so after the first deploy that sets `REG_SIGN_KEY`, sign them
  all (idempotent; auth = presenting the seed itself):

  ```bash
  curl -X POST https://reg.nurl-lang.org/api/v1/admin/sign-backfill \
       -H "X-Reg-Sign-Key: $REG_SIGN_KEY"
  # → {"ok":true,"signed":N,"skipped":M,"failed":0,...}
  ```
- Rotating the key means re-signing everything (`sign-backfill` after clearing
  the old `.minisig` objects) **and** updating the pin in `pkg_fetch.nu` +
  `REG_SIGN_KEYID` in a client release — treat it like a CA rotation.

Point `reg.nurl-lang.org` at the Worker (Workers → custom domain) and the
read path is a cacheable CDN; the write path (`/api/v1/publish`) is the
authenticated Worker route.

## Secrets — where each one lives

| Secret | Home | How |
|---|---|---|
| `GITHUB_CLIENT_SECRET`, `TOKEN_PEPPER`, `REG_SIGN_KEY` | Cloudflare (encrypted) | `wrangler secret put` — never in repo/wrangler.jsonc |
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | GitHub Actions repo secrets | used by the deploy workflow (placeholders pre-created) |
| local dev values | `registry/.dev.vars` | gitignored (`.dev.vars.*`); keys: `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, `TOKEN_PEPPER`, `REGISTRY_URL`, `REG_SIGN_KEY`. `test-local.sh` writes it automatically (with a deterministic test key). |
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
