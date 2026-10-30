-- registry/migrations/0005_publish_reservation.sql — atomic publish (agora #162).
--
-- A publish first RESERVES its (name, version) in D1 — the package row
-- (first publisher wins the PRIMARY KEY) and a `pending = 1` version row
-- that only the owner can insert — in one batch, so two concurrent
-- publishers can never both pass the ownership / immutability checks.
-- Only the reservation holder then writes the tarball, signature and index
-- to R2; the commit flips `pending` to 0, and any failure deletes the
-- reservation together with what it wrote. Display and count queries read
-- committed rows only. A reservation its worker died holding (no commit,
-- no rollback) is reclaimable by the same publisher once it is stale.

ALTER TABLE versions ADD COLUMN pending INTEGER NOT NULL DEFAULT 0;
