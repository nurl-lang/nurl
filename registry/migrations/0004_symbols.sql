-- registry/migrations/0004_symbols.sql — searchable symbol index.
--
-- The public symbol NAMES a package exposes (function/type/trait names,
-- from nurldoc over its published src/*.nu) are extracted SERVER-SIDE on
-- every publish and recorded here, so /api/v1/search matches a package by
-- a symbol whose name the caller could not otherwise guess (e.g. searching
-- "gqa attention" finds `nn` because it exports nn_gqa_attention). Name and
-- description alone can't do that — the API surface is the missing index.
-- Never trusted from client headers; POST /api/v1/admin/symbols-backfill
-- re-extracts for packages published before this column existed.

ALTER TABLE packages ADD COLUMN symbols TEXT NOT NULL DEFAULT '';
