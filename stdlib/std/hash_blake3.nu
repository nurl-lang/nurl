// stdlib/std/hash_blake3.nu — BLAKE3 cryptographic hash (pure NURL).
//
// Faithful port of the official BLAKE3 reference (the spec appendix's
// Python `Hasher`): the ChaCha-derived compression function, 1024-byte
// chunks split into 64-byte blocks with CHUNK_START / CHUNK_END flags,
// and the binary Merkle tree of chaining values merged through PARENT
// nodes, with the final root node carrying the ROOT flag.
//
// Unkeyed, default 32-byte output (the `b3sum` default). All-NURL u32
// arithmetic (wraps mod 2^32), little-endian byte order. Binary-clean:
// `( Vec u )` in, exact length, embedded NUL bytes are data.
//
// API:
//   ( blake3_pure ( Vec u ) data ) → ( Vec u )   32-byte digest
//
// Wrapped by stdlib/std/hash.nu as `blake3_bytes` / `blake3_hex`.
//
// Shape: the compression function's sixteen working words, its sixteen
// message words and the eight chaining-value words are scalar locals, never
// a Vec. G and the round take their working words `inout` and are `inline`,
// so after inlining the whole state is SSA values; each of the seven round
// calls passes the message words already in that round's permuted order, so
// the message permutation is resolved at compile time. A chaining value
// travels as eight `inout` words too, and full chunks are compressed straight
// out of the input — nothing on the hot path allocates.

$ `stdlib/std/bytes.nu`

$ `stdlib/core/vec.nu`
$ `stdlib/core/rcbox.nu`

// ── the compression function ──────────────────────────────────────

// G, the quarter-round, on four working words in place.
inline @ __b3_g inout u32 a inout u32 b inout u32 c inout u32 d u32 x u32 y → v {
    = a + + a b x
    = d # u32 ( nurl_rotr32 # u64 ^^ d a 16 )
    = c + c d
    = b # u32 ( nurl_rotr32 # u64 ^^ b c 12 )
    = a + + a b y
    = d # u32 ( nurl_rotr32 # u64 ^^ d a 8 )
    = c + c d
    = b # u32 ( nurl_rotr32 # u64 ^^ b c 7 )
}

// One round: the four column mixes, then the four diagonal mixes. s0..s15 are
// the message words already permuted for this round.
inline @ __b3_round inout u32 v0 inout u32 v1 inout u32 v2 inout u32 v3 inout u32 v4 inout u32 v5 inout u32 v6 inout u32 v7 inout u32 v8 inout u32 v9 inout u32 v10 inout u32 v11 inout u32 v12 inout u32 v13 inout u32 v14 inout u32 v15 u32 s0 u32 s1 u32 s2 u32 s3 u32 s4 u32 s5 u32 s6 u32 s7 u32 s8 u32 s9 u32 s10 u32 s11 u32 s12 u32 s13 u32 s14 u32 s15 → v {
    ( __b3_g v0 v4 v8 v12 s0 s1 )
    ( __b3_g v1 v5 v9 v13 s2 s3 )
    ( __b3_g v2 v6 v10 v14 s4 s5 )
    ( __b3_g v3 v7 v11 v15 s6 s7 )
    ( __b3_g v0 v5 v10 v15 s8 s9 )
    ( __b3_g v1 v6 v11 v12 s10 s11 )
    ( __b3_g v2 v7 v8 v13 s12 s13 )
    ( __b3_g v3 v4 v9 v14 s14 s15 )
}

// Compress one block — sixteen message words — into the chaining value
// h0..h7 in place: h ← the first half of the output state ⊕ the second half,
// which is all a 32-byte digest ever reads. `counter` is the 64-bit node
// counter (chunk index for chunks, 0 for parents).
@ __b3_compress inout u32 h0 inout u32 h1 inout u32 h2 inout u32 h3 inout u32 h4 inout u32 h5 inout u32 h6 inout u32 h7 u32 m0 u32 m1 u32 m2 u32 m3 u32 m4 u32 m5 u32 m6 u32 m7 u32 m8 u32 m9 u32 m10 u32 m11 u32 m12 u32 m13 u32 m14 u32 m15 i counter i blen i flags → v {
    : ~ u32 v0 h0
    : ~ u32 v1 h1
    : ~ u32 v2 h2
    : ~ u32 v3 h3
    : ~ u32 v4 h4
    : ~ u32 v5 h5
    : ~ u32 v6 h6
    : ~ u32 v7 h7
    : ~ u32 v8 # u32 1779033703  // IV[0..4] = 0x6A09E667 0xBB67AE85
    : ~ u32 v9 # u32 3144134277
    : ~ u32 v10 # u32 1013904242  // 0x3C6EF372 0xA54FF53A
    : ~ u32 v11 # u32 2773480762
    : ~ u32 v12 # u32 counter
    : ~ u32 v13 # u32 >> counter 32
    : ~ u32 v14 # u32 blen
    : ~ u32 v15 # u32 flags

    ( __b3_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m0 m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14 m15 )
    ( __b3_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m2 m6 m3 m10 m7 m0 m4 m13 m1 m11 m12 m5 m9 m14 m15 m8 )
    ( __b3_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m3 m4 m10 m12 m13 m2 m7 m14 m6 m5 m9 m0 m11 m15 m8 m1 )
    ( __b3_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m10 m7 m12 m9 m14 m3 m13 m15 m4 m0 m11 m2 m5 m8 m1 m6 )
    ( __b3_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m12 m13 m9 m11 m15 m10 m14 m8 m7 m2 m5 m3 m0 m1 m6 m4 )
    ( __b3_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m9 m14 m11 m5 m8 m12 m15 m1 m13 m3 m0 m10 m2 m6 m4 m7 )
    ( __b3_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m11 m15 m5 m0 m1 m9 m8 m6 m14 m10 m2 m12 m3 m4 m7 m13 )

    = h0 ^^ v0 v8
    = h1 ^^ v1 v9
    = h2 ^^ v2 v10
    = h3 ^^ v3 v11
    = h4 ^^ v4 v12
    = h5 ^^ v5 v13
    = h6 ^^ v6 v14
    = h7 ^^ v7 v15
}

// The little-endian u32 at `blk[off .. off+4]`. Every caller reads inside a
// block it has already sized, so the out-of-range arm never runs.
@ __b3_w ( Vec u ) blk i off → u32 {
    ?? ( bytes_read_u32_le blk off ) { T x → ^ x F → ^ # u32 0 }
}

// Compress the 64-byte block at `blk[off ..]`.
@ __b3_compress_at inout u32 h0 inout u32 h1 inout u32 h2 inout u32 h3 inout u32 h4 inout u32 h5 inout u32 h6 inout u32 h7 ( Vec u ) blk i off i counter i blen i flags → v {
    ( __b3_compress h0 h1 h2 h3 h4 h5 h6 h7 ( __b3_w blk off ) ( __b3_w blk + off 4 ) ( __b3_w blk + off 8 ) ( __b3_w blk + off 12 ) ( __b3_w blk + off 16 ) ( __b3_w blk + off 20 ) ( __b3_w blk + off 24 ) ( __b3_w blk + off 28 ) ( __b3_w blk + off 32 ) ( __b3_w blk + off 36 ) ( __b3_w blk + off 40 ) ( __b3_w blk + off 44 ) ( __b3_w blk + off 48 ) ( __b3_w blk + off 52 ) ( __b3_w blk + off 56 ) ( __b3_w blk + off 60 ) counter blen flags )
}

// ── chunks and parents ────────────────────────────────────────────

// Chaining value of the chunk [off, off+len) (len ≤ 1024) at chunk index
// `counter`, into c0..c7. With `root` set, the final block also carries the
// ROOT flag, so c0..c7 ARE the hash (single-chunk inputs).
@ __b3_chunk_cv inout u32 c0 inout u32 c1 inout u32 c2 inout u32 c3 inout u32 c4 inout u32 c5 inout u32 c6 inout u32 c7 ( Vec u ) data i off i len i counter b root → v {
    // The key words of an unkeyed hash are the IV (the SHA-256 initial
    // hash values 0x6A09E667 … 0x5BE0CD19).
    = c0 # u32 1779033703
    = c1 # u32 3144134277
    = c2 # u32 1013904242
    = c3 # u32 2773480762
    = c4 # u32 1359893119
    = c5 # u32 2600822924
    = c6 # u32 528734635
    = c7 # u32 1541459225
    : i nb ? <= len 0 1 / + len 63 64
    : ~ i bk 0
    ~ < bk - nb 1 {
        // CHUNK_START on the first block only
        ( __b3_compress_at c0 c1 c2 c3 c4 c5 c6 c7 data + off * bk 64 counter 64 ? == bk 0 1 0 )
        = bk + bk 1
    }
    // The last block, zero-padded to 64 bytes when it is partial:
    // CHUNK_END | (CHUNK_START if it is also the first) | (ROOT?)
    : i lb_off + off * - nb 1 64
    : i lb_len - len * - nb 1 64
    : i lflags | 2 | ? == nb 1 1 0 ? root 8 0
    ? == lb_len 64 {
        ( __b3_compress_at c0 c1 c2 c3 c4 c5 c6 c7 data lb_off counter 64 lflags )
    } {
        : ( Vec u ) pad ( vec_zeroed [u] 64 )
        : ~ i j 0
        ~ < j lb_len {
            ( vec_put [u] pad j ( vec_at [u] data + lb_off j ) )
            = j + j 1
        }
        ( __b3_compress_at c0 c1 c2 c3 c4 c5 c6 c7 pad 0 counter lb_len lflags )
    }
}

// Parent node: c0..c7 ← CV(left ‖ right), with c0..c7 holding the right
// child's CV on entry. `flags` is PARENT, plus ROOT for the top node.
@ __b3_parent inout u32 c0 inout u32 c1 inout u32 c2 inout u32 c3 inout u32 c4 inout u32 c5 inout u32 c6 inout u32 c7 u32 l0 u32 l1 u32 l2 u32 l3 u32 l4 u32 l5 u32 l6 u32 l7 i flags → v {
    : ~ u32 h0 # u32 1779033703
    : ~ u32 h1 # u32 3144134277
    : ~ u32 h2 # u32 1013904242
    : ~ u32 h3 # u32 2773480762
    : ~ u32 h4 # u32 1359893119
    : ~ u32 h5 # u32 2600822924
    : ~ u32 h6 # u32 528734635
    : ~ u32 h7 # u32 1541459225
    ( __b3_compress h0 h1 h2 h3 h4 h5 h6 h7 l0 l1 l2 l3 l4 l5 l6 l7 c0 c1 c2 c3 c4 c5 c6 c7 0 64 flags )
    = c0 h0
    = c1 h1
    = c2 h2
    = c3 h3
    = c4 h4
    = c5 h5
    = c6 h6
    = c7 h7
}

// c0..c7 ← CV(stack entry `idx` ‖ c0..c7). The stack is flattened, eight
// words per entry.
@ __b3_parent_with ( Vec u32 ) stack i idx inout u32 c0 inout u32 c1 inout u32 c2 inout u32 c3 inout u32 c4 inout u32 c5 inout u32 c6 inout u32 c7 i flags → v {
    : i base * idx 8
    ( __b3_parent c0 c1 c2 c3 c4 c5 c6 c7 ( vec_at [u32] stack base ) ( vec_at [u32] stack + base 1 ) ( vec_at [u32] stack + base 2 ) ( vec_at [u32] stack + base 3 ) ( vec_at [u32] stack + base 4 ) ( vec_at [u32] stack + base 5 ) ( vec_at [u32] stack + base 6 ) ( vec_at [u32] stack + base 7 ) flags )
}

// ── Incremental (streaming) hashing ────────────────────────────────
//
// BLAKE3's chunk tree, built as the bytes arrive: a 1024-byte chunk
// buffer plus the classic CV stack (one entry per set bit of the
// completed-chunk count). A chunk is only compressed once a LATER byte
// proves it is not the final chunk, so any update pattern produces the
// same tree as the one-shot. blake3_pure below is a thin
// init/update/final composition — the two paths cannot drift.
//
//   ( blake3_init )          → Blake3
//   ( blake3_update h v )    → v          any piece size, any count
//   ( blake3_final h )       → ( Vec u )  32-byte digest; the stream is
//                                          spent after this
//
// A Blake3 is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same stream, and the last owner releases it.

: Blake3Impl {
    ( Vec u32 ) stack
    i scount
    ( Vec u ) cbuf
    i counter
}

: Blake3 { s ctl }

@ Blake3_share Blake3 h → Blake3 { ^ @ Blake3 { # s ( rcbox_share # i . h ctl ) } }

@ Blake3_drop sink Blake3 h → v {
    ( mem_forget h )
    ( rcbox_release [Blake3Impl] # i . h ctl )
}

@ __Blake3_ptr Blake3 h → *Blake3Impl { ^ ( rcbox_ptr [Blake3Impl] # i . h ctl ) }

@ blake3_init → Blake3 {
    ^ @ Blake3 { # s ( rcbox_new [Blake3Impl] @ Blake3Impl { ( vec_new [u32] ) 0 ( vec_new [u] ) 0 } ) }
}

// Let go of `h` now rather than at the end of its owner's scope.
@ blake3_free sink Blake3 h → v {}

// Fold the CV of the completed, non-final chunk [off, off+1024) of `data`
// into the stack, merging one parent per trailing one-bit of the
// completed-chunk count.
@ __b3_absorb_chunk * Blake3Impl h ( Vec u ) data i off → v {
    : ~ u32 c0 0
    : ~ u32 c1 0
    : ~ u32 c2 0
    : ~ u32 c3 0
    : ~ u32 c4 0
    : ~ u32 c5 0
    : ~ u32 c6 0
    : ~ u32 c7 0
    ( __b3_chunk_cv c0 c1 c2 c3 c4 c5 c6 c7 data off 1024 . h counter F )
    : ~ i total + . h counter 1
    ~ == & total 1 0 {
        : i top - . h scount 1
        ( __b3_parent_with . h stack top c0 c1 c2 c3 c4 c5 c6 c7 4 )
        : b _ok ( vec_set_len [u32] . h stack * top 8 )
        = . h scount top
        = total >> total 1
    }
    ( vec_push [u32] . h stack c0 )
    ( vec_push [u32] . h stack c1 )
    ( vec_push [u32] . h stack c2 )
    ( vec_push [u32] . h stack c3 )
    ( vec_push [u32] . h stack c4 )
    ( vec_push [u32] . h stack c5 )
    ( vec_push [u32] . h stack c6 )
    ( vec_push [u32] . h stack c7 )
    = . h scount + . h scount 1
    = . h counter + . h counter 1
}

@ blake3_update Blake3 h__h ( Vec u ) data → v {
    : *Blake3Impl h ( __Blake3_ptr h__h )
    : i n ( vec_len [u] data )
    : ~ i off 0
    ~ < off n {
        // a full buffered chunk is non-final by proof: more bytes exist
        ? == ( vec_len [u] . h cbuf ) 1024 {
            ( __b3_absorb_chunk h . h cbuf 0 )
            ( vec_clear [u] . h cbuf )
        } {}
        // With nothing buffered, every chunk a later byte proves
        // non-final is compressed where it lies — no copy.
        ? == ( vec_len [u] . h cbuf ) 0 {
            ~ > - n off 1024 {
                ( __b3_absorb_chunk h data off )
                = off + off 1024
            }
        } {}
        : i space - 1024 ( vec_len [u] . h cbuf )
        : i left - n off
        : i take ? < left space left space
        ( bytes_extend_raw . h cbuf # s + # i ( vec_data [u] data ) off take )
        = off + off take
    }
}

// Digest: the buffered bytes are the final chunk; fold the stack
// right-to-left, marking the last merge (or lone chunk) as root. The
// stream is spent — its storage goes with its last owner.
@ blake3_final Blake3 h__h → ( Vec u ) {
    : *Blake3Impl h ( __Blake3_ptr h__h )
    : b lone & == . h counter 0 == . h scount 0
    : ~ u32 c0 0
    : ~ u32 c1 0
    : ~ u32 c2 0
    : ~ u32 c3 0
    : ~ u32 c4 0
    : ~ u32 c5 0
    : ~ u32 c6 0
    : ~ u32 c7 0
    ( __b3_chunk_cv c0 c1 c2 c3 c4 c5 c6 c7 . h cbuf 0 ( vec_len [u] . h cbuf ) . h counter lone )
    : ~ i r - . h scount 1
    ~ >= r 0 {
        // PARENT, plus ROOT on the last merge
        ( __b3_parent_with . h stack r c0 c1 c2 c3 c4 c5 c6 c7 ? == r 0 12 4 )
        = r - r 1
    }
    : ( Vec u ) out ( vec_with_cap [u] 32 )
    ( bytes_push_u32_le out c0 )
    ( bytes_push_u32_le out c1 )
    ( bytes_push_u32_le out c2 )
    ( bytes_push_u32_le out c3 )
    ( bytes_push_u32_le out c4 )
    ( bytes_push_u32_le out c5 )
    ( bytes_push_u32_le out c6 )
    ( bytes_push_u32_le out c7 )
    ^ out
}

// ── Public entry ──────────────────────────────────────────────────

// One-shot over the streaming core.
@ blake3_pure ( Vec u ) data → ( Vec u ) {
    : Blake3 h ( blake3_init )
    ( blake3_update h data )
    ^ ( blake3_final h )
}
