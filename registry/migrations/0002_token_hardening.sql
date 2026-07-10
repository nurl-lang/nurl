-- registry/migrations/0002_token_hardening.sql — M9 hardening.
--
-- Tokens gain an expiry and an optional per-package scope:
--   expires_at  epoch ms; NULL = never (legacy rows are backfilled below so
--               every pre-existing token expires 90 days from this migration
--               rather than living forever)
--   pkgs        NULL = token may act on ALL packages the user owns;
--               else a comma-separated allow-list of package names — a CI
--               token scoped to one package can't touch the others.
--
-- rate_limits backs the fixed-window per-user / per-IP limiter for
-- publish / token-mint / search.

ALTER TABLE tokens ADD COLUMN expires_at INTEGER;
ALTER TABLE tokens ADD COLUMN pkgs TEXT;

UPDATE tokens
   SET expires_at = (strftime('%s','now') + 90*24*3600) * 1000
 WHERE expires_at IS NULL;

CREATE TABLE IF NOT EXISTS rate_limits (
  key          TEXT    PRIMARY KEY,  -- e.g. 'pub:<user_id>', 'search:<ip>'
  window_start INTEGER NOT NULL,     -- epoch ms of the current window
  count        INTEGER NOT NULL
);
