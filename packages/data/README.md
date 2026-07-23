# data — a training DataLoader

Minibatch iteration for training: seeded reproducible shuffle, epoch
reshuffling, drop-last, worker sharding, and disk streaming. The batching
layer the training stack was missing — grad/nn build the graph, this feeds
it.

```
: *DataSet ds   ( data_new x y n d l )        // x: n·d, y: n·l (l may be 0)
: *DataLoader dl ( dl_new ds 32 F 42 )         // batch 32, no drop-last, seed 42
: ( Vec f ) bx ( vec_new [f] )
: ( Vec f ) by ( vec_new [f] )
: ~ i rows ( dl_next dl bx by )                // fills bx/by, returns row count
~ > rows 0 {
    // train on bx (rows·d), by (rows·l)
    = rows ( dl_next dl bx by )
}
( dl_reset dl 43 )                             // next epoch, new permutation
```

## What it does

- **Batching** — `dl_next` gathers the next `batch` rows into caller vectors
  and returns the count (0 at end-of-epoch; the last batch is partial unless
  `drop_last`).
- **Seeded shuffle** — an unbiased Fisher-Yates permutation from `std/rng`.
  The order is a pure function of the seed: `dl_reset dl seed` reproduces it
  regardless of prior state. `seed <= 0` disables shuffling (identity order).
- **Epochs** — `dl_reset` rewinds and reshuffles; pass a fresh seed per epoch.
- **Sharding** — `dl_new_shard ds batch drop_last seed nshards shard`
  partitions `[0,n)` into contiguous, exactly-once slices, one per worker.
- **Disk streaming** — `data_save_ndf` writes the `.ndf` format (magic +
  n/d/l header + little-endian f64 rows); `ndf_open` + `dl_stream` iterate it
  with random-access preads, so a corpus larger than RAM never loads whole —
  `dl_next` reads only the rows a batch needs.

## Verification (`tests/data_test.nu`, 16/16)

Determinism is a gate, not a hope:

- the seeded order is a real permutation, and the same seed reproduces it
  byte-for-byte after `dl_reset`;
- an epoch covers every example **exactly once** (features stay row-aligned
  with labels), and `drop_last` yields exactly `floor(n/batch)·batch` rows;
- `N` shards partition the dataset exactly once (disjoint, complete union);
- a `.ndf` round-trips its header, and **streamed batches equal in-memory
  batches** for the same seed.

## Dependencies

None beyond the standard library (`rng`, `fs`, `bytes`, `floatbits`).

## License

MIT OR Apache-2.0
