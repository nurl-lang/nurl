-- registry/migrations/0001_init.sql — NURL package registry schema (D1).
--
-- Identity comes from GitHub OAuth; a `users` row is created on first
-- login. The CLI authenticates with a registry-issued bearer token whose
-- SHA-256 hash (peppered) is stored in `tokens` — the plaintext is shown
-- once at issuance and never persisted. A package `name` is owned by the
-- user who first published it; versions are immutable.

CREATE TABLE IF NOT EXISTS users (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  github_id   INTEGER NOT NULL UNIQUE,
  login       TEXT    NOT NULL,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS tokens (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id      INTEGER NOT NULL REFERENCES users(id),
  token_hash   TEXT    NOT NULL UNIQUE,   -- hex sha256(pepper || token)
  name         TEXT    NOT NULL,          -- human label
  created_at   INTEGER NOT NULL,
  last_used_at INTEGER
);

CREATE TABLE IF NOT EXISTS packages (
  name          TEXT    PRIMARY KEY,
  owner_user_id INTEGER NOT NULL REFERENCES users(id),
  created_at    INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS versions (
  name         TEXT    NOT NULL REFERENCES packages(name),
  version      TEXT    NOT NULL,
  checksum     TEXT    NOT NULL,          -- hex sha256 of the tarball
  yanked       INTEGER NOT NULL DEFAULT 0,
  published_by INTEGER NOT NULL REFERENCES users(id),
  published_at INTEGER NOT NULL,
  PRIMARY KEY (name, version)
);

CREATE INDEX IF NOT EXISTS idx_tokens_user ON tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_versions_name ON versions(name);
