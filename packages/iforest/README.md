# `iforest` — Isolation Forest anomaly detection

`iforest` finds the odd points in a dataset. It implements the **Isolation
Forest** (Liu, Ting & Zhou, 2008): instead of modelling what "normal"
looks like, it builds an ensemble of random binary trees that recursively
split the data at random features and thresholds. Anomalies are *few and
different*, so they get isolated near the root of each tree — their average
path length is short — while normal points sit deep in crowded regions. The
forest turns that path length into a score in `(0, 1]`.

It ships both ways:

- an **installable CLI** (`iforest`) that scores the rows of a numeric CSV;
  and
- a **reusable library** (`src/iforest.nu`) that trains a forest and scores
  points from your own NURL code.

```
nurlpkg install iforest
iforest < data.csv                 # one anomaly score per row, in order
iforest -f data.csv --top 10       # the 10 most anomalous rows
iforest -f data.csv -H -t 200 -S 7 # skip header, 200 trees, seed 7
```

## Scores

The score `s(x)` maps a point's mean path length over the forest to `(0, 1]`:

| Score        | Reading                                                 |
| ------------ | ------------------------------------------------------- |
| `≈ 1.0`      | almost certainly an anomaly (isolated very quickly)     |
| `≈ 0.5`      | no clear signal — path length close to the average      |
| `< 0.5`      | a normal, "crowded" point, isolated only deep in a tree |

There is no universal cutoff; rank the rows (`--top`) or threshold on the
score distribution for your data.

## CLI options

| Option | Meaning |
| ------ | ------- |
| `-f`, `--file F`   | read CSV from file `F` instead of stdin |
| `-H`, `--header`   | skip the first line (treat it as a header) |
| `-t`, `--trees N`  | number of trees in the forest (default `100`) |
| `-s`, `--sample N` | subsample size per tree, ψ (default `256`) |
| `-S`, `--seed N`   | PRNG seed for reproducible forests (default `42`) |
| `-k`, `--top K`    | print only the K most anomalous rows as `index⇥score`, highest first |
| `-d`, `--delim C`  | field delimiter (default `,`) |
| `-h`, `--help`     | show help |

Input is a numeric CSV: rows are samples, columns are features. The first
data row fixes the column count; rows whose numeric-field count differs are
skipped to keep the matrix rectangular. By default the tool prints one
score per line in input order (paste it back as a new column); `--top K`
prints the ranked anomalies instead.

The forest is fully deterministic: a fixed `--seed` produces a
byte-identical forest, and hence identical scores, on every platform and
build.

A node splits only on a column that varies over its subsample. A constant
column (a stuck sensor, a one-hot category nobody sent) is redrawn rather
than ending the subtree in one big leaf, so carrying such columns costs
nothing; only rows that agree on every column stop a subtree early.

## Using the trainer as a library

The library depends only on the standard library (`vec`, `float`, `rng`) —
declare the dependency and import the module:

```toml
[dependencies]
iforest = "^0.1"
```

```
$ `deps/iforest/src/iforest.nu`

// data is a row-major ( Vec f ) of n_rows * n_cols values.
: IForest fo ( iforest_train data n_rows n_cols 100 256 42 )
: f s ( iforest_score_row fo data 0 )   // score row 0 in place
// ... or score an arbitrary point:
: f s2 ( iforest_score fo my_point )     // my_point is a ( Vec f ) of n_cols
( iforest_free fo )
```

### Surface

| Function | Result |
| -------- | ------ |
| `( iforest_train data n_rows n_cols n_trees sample_size seed )` | `IForest` (caller owns it) |
| `( iforest_score forest point )` | `f` — score of a `( Vec f )` of length `n_cols` |
| `( iforest_score_row forest data row )` | `f` — score row `row` of a row-major matrix, no copy |
| `( iforest_avg_path n )` | `f` — `c(n)`, the path-length normaliser (for custom thresholds) |
| `( iforest_n_trees forest )` / `( iforest_sample_size forest )` | `i` |
| `( iforest_free forest )` | `v` |

`sample_size` (ψ) is clamped to `n_rows`; the per-tree height limit is
`ceil(log2 ψ)`, the standard Isolation Forest setting.

## Implementation notes

All nodes of all trees live in one flat struct-of-arrays shared across the
forest (a node arena plus a root index per tree): no recursive ADTs, no
Vec-of-Vec, and scoring walks raw pointers. Random splits are driven by
`std/rng`'s seedable xoshiro256\*\* generator, which is what makes the
forest reproducible.

## Quality

The CLI is leak-clean under AddressSanitizer/LeakSanitizer across its code
paths (stdin, `--file`, `--top`, help, the file-error branch, and empty
input), and the end-to-end install-and-run loop is covered by
`tools/nurlpkg/test-install-tool.sh`.
