-- registry/migrations/0003_descriptions.sql — searchable descriptions.
--
-- `[package].description` is extracted SERVER-SIDE from the published
-- tarball's nurl.toml on every publish (the latest version's text wins)
-- and recorded here, so /api/v1/search and the catalog can match and
-- show what a package IS — name-only search stops scaling long before
-- a registry reaches thousands of packages. Never trusted from client
-- headers; POST /api/v1/admin/desc-backfill re-extracts for packages
-- published before this column existed.

ALTER TABLE packages ADD COLUMN description TEXT NOT NULL DEFAULT '';
