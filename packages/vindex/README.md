# vindex — a vector index

The retrieval middle between embeddings and generation — the RAG piece.
`embed` turns text into vectors, `nurllama` turns a prompt into an answer;
`vindex` is what finds the right vectors in between.

```
: *VIndex ix ( vx_build_ivf vecs n dim VX_COSINE 256 20 42 )  // k-means, 256 lists
: ( Vec i ) ids ( vec_new [i] )
: ( Vec f ) dists ( vec_new [f] )
: i found ( vx_search ix query 10 8 ids dists )               // top-10, probe 8 lists
// ids[0..found) are the nearest document rows, dists ascending
```

## Two indexes, one search

- **Exact** (`vx_build_exact`) — brute force over every vector. The ground
  truth, and fine up to tens of thousands of vectors.
- **IVF-flat** (`vx_build_ivf`) — a k-means coarse quantiser (`nlist`
  centroids) with inverted lists. A query scores only the `nprobe` nearest
  clusters, trading recall for speed on a knob.

Both search by **cosine** (`VX_COSINE`) or **L2** (`VX_L2`); cosine
precomputes each vector's norm, so a candidate costs one dot product.
`vx_search` fills caller vectors with the top-k ids and (ascending)
distances. An index serialises to one `.vix` blob (`vx_save` / `vx_load`)
that loads back to identical results.

## Verification (`tests/vindex_test.nu`, 8/8)

- cosine and L2 **top-1 of a corpus vector is itself** (self-distance ~0);
- **IVF recall@10 vs the exact index** on a fixed clustered corpus is 1.0 at
  `nprobe=4/10` (recall is a measured gate, not a hope — turn `nprobe` down
  and it drops, which is the tradeoff);
- a `.vix` round-trips its header and returns **identical search results**
  after load.

## RAG, end to end

`vindex` is the middle of a three-package pipeline (each shipped and tested
on its own):

```
// 1. embed a corpus  (embed)      → one vector per document
// 2. build an index  (vindex)     → vx_build_ivf over those vectors
// 3. embed the query (embed)      → one vector
// 4. retrieve         (vindex)    → vx_search → top-k document rows
// 5. answer grounded  (nurllama)  → prompt = retrieved docs + question
```

The retrieval steps (2, 4) are this package; the embedding (1, 3) is
`embed`'s cosine-1.0-verified vectors and the generation (5) is `nurllama`.

## Dependencies

None beyond the standard library. (HNSW is a natural follow-up to IVF-flat
for larger corpora; the exact index is the recall reference either way.)

## License

MIT OR Apache-2.0
