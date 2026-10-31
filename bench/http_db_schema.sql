-- bench/http_db_schema.sql — the database behind bench/run_http.sh's `db`
-- suite (bench/http_server.nu and the Rust peer serve it).
--
--   world    10 000 rows   TechEmpower /db, /queries, /updates
--   fortune  12 rows       TechEmpower /fortunes (its seed, verbatim)
--   items    100 000 rows  HttpArena /async-db: no index on price, so
--                          `price BETWEEN $1 AND $2 LIMIT $3` is a scan
--
-- Deterministic: the random-looking columns are arithmetic on the row id,
-- so every run, on every machine, measures the same data. Idempotent: it
-- drops and recreates its three tables.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f bench/http_db_schema.sql

DROP TABLE IF EXISTS world;
CREATE TABLE world (
    id           integer NOT NULL PRIMARY KEY,
    randomnumber integer NOT NULL DEFAULT 0
);
INSERT INTO world (id, randomnumber)
SELECT g, 1 + (g * 7919) % 10000 FROM generate_series(1, 10000) AS g;

DROP TABLE IF EXISTS fortune;
CREATE TABLE fortune (
    id      integer NOT NULL PRIMARY KEY,
    message varchar(2048) NOT NULL
);
INSERT INTO fortune (id, message) VALUES
    (1, 'fortune: No such file or directory'),
    (2, 'A computer scientist is someone who fixes things that aren''t broken.'),
    (3, 'After enough decimal places, nobody gives a damn.'),
    (4, 'A bad random number generator: 1, 1, 1, 1, 1, 4.33e+67, 1, 1, 1'),
    (5, 'A computer program does what you tell it to do, not what you want it to do.'),
    (6, 'Emacs is a nice operating system, but I prefer UNIX. — Tom Christaensen'),
    (7, 'Any program that runs right is obsolete.'),
    (8, 'A list is only as strong as its weakest link. — Donald Knuth'),
    (9, 'Feature: A bug with seniority.'),
    (10, 'Computers make very fast, very accurate mistakes.'),
    (11, '<script>alert("This should not be displayed in a browser alert box.");</script>'),
    (12, 'フレームワークのベンチマーク');

DROP TABLE IF EXISTS items;
CREATE TABLE items (
    id           integer NOT NULL PRIMARY KEY,
    name         text    NOT NULL,
    category     text    NOT NULL,
    price        integer NOT NULL,
    quantity     integer NOT NULL,
    active       boolean NOT NULL,
    tags         jsonb   NOT NULL,
    rating_score integer NOT NULL,
    rating_count integer NOT NULL
);
INSERT INTO items
SELECT g,
       'Item ' || g,
       (ARRAY['electronics', 'books', 'clothing', 'home', 'sports', 'toys', 'food', 'garden'])[1 + g % 8],
       1 + (g * 7919) % 500,
       (g * 31) % 1000,
       g % 10 <> 0,
       jsonb_build_array('tag' || g % 7, 'tag' || g % 11),
       1 + (g * 13) % 50,
       (g * 17) % 5000
FROM generate_series(1, 100000) AS g;

ANALYZE world;
ANALYZE fortune;
ANALYZE items;
