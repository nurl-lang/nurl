// stdlib/std/rng.nu — seedable, deterministic PRNG (xoshiro256**)
//
// Companion to `std/random.nu`'s OS CSPRNG. The CSPRNG draws from the
// kernel entropy pool and *cannot be seeded* — it's the right tool for
// keys, nonces, and tokens, but useless when you need a *reproducible*
// stream: simulations you can replay, property tests with a recorded
// seed, procedural generation, shuffles you can audit. This module fills
// that gap with a small, fast, seedable generator.
//
// Algorithm: xoshiro256** (Blackman & Vigna, 2018) — 256 bits of state,
// 2^256-1 period, passes BigCrush. The seed (a single i64) is expanded
// into the 256-bit state with SplitMix64, the seeding routine the
// xoshiro authors recommend, so even a low-entropy seed like `0` or `1`
// produces a well-distributed state. Same seed → byte-identical stream
// on every platform, every build (NURL's determinism guarantee extends
// here: integer ops only, no float state, no UB).
//
// This is NOT a CSPRNG. Its output is statistically excellent but
// predictable: never use it for anything security-sensitive — reach for
// `std/random.nu` there.
//
//   ( rng_seed seed )            → Rng    seed a generator (any i64 seed)
//   ( rng_next g )               → i       next 64-bit value; the bit
//                                          pattern is uniform over all
//                                          2^64 values, returned in a
//                                          signed i (reinterpret as
//                                          unsigned for hex / packing).
//   ( rng_below g n )            → i       uniform in [0, n); 0 if n <= 0.
//                                          Unbiased (rejection-sampled).
//   ( rng_range g from to )      → i       uniform in [from, to) when
//                                          from < to; otherwise `from`.
//   ( rng_u01 g )                → f       uniform double in [0, 1),
//                                          53-bit mantissa resolution.
//   ( rng_bool g )               → b       fair coin flip.
//   ( rng_free g )               → v       release the generator.
//
// Lifecycle (opaque-handle pattern, same as Arena / Channel / String):
//
//   : Rng g ( rng_seed 0x1234 )
//   : i a ( rng_next g )          // mutates g's state in place
//   : i b ( rng_next g )          // a != b; stream is deterministic
//   ( rng_free g )


// ── State ────────────────────────────────────────────────────────────

// 256-bit xoshiro state. Heap-allocated; `Rng` is a single-pointer
// handle, so passing a Rng by value shares the same stream (every copy
// advances the one underlying state).
: RngImpl {
    u64 s0
    u64 s1
    u64 s2
    u64 s3
}

: Rng { s ctl }

// ── Bit primitives ───────────────────────────────────────────────────

// Rotate a 64-bit word left by `k` bits. `x` is u64, so `>>` lowers to
// a logical (zero-filling) shift — an arithmetic shift would corrupt the
// rotate for words with the high bit set.
@ __rotl u64 x i k → u64 {
    ^ | << x k >> x - 64 k
}

// SplitMix64 finalizing mix (Steele/Lea/Vigna). Given the running
// additive state `z`, produce one well-mixed 64-bit output. Used only to
// expand the seed into the xoshiro state; the increment lives in
// `rng_seed`.
@ __splitmix_mix u64 z → u64 {
    : ~ u64 x z
    = x * ^^ x >> x 30 0xbf58476d1ce4e5b9
    = x * ^^ x >> x 27 0x94d049bb133111eb
    ^ ^^ x >> x 31
}

// ── Construction ─────────────────────────────────────────────────────

// Seed a generator. Any i64 seed is acceptable, including 0: SplitMix64
// diffuses it across all 256 state bits, so adjacent seeds (0, 1, 2 …)
// yield uncorrelated streams. The all-zero xoshiro state is degenerate
// (it would stay zero forever); SplitMix64 never emits it for any seed,
// so no special-case is needed.
@ rng_seed i seed → Rng {
    : *RngImpl st # *RngImpl ( nurl_alloc Z RngImpl )
    : ~ u64 sm # u64 seed
    = sm + sm 0x9e3779b97f4a7c15
    = . st s0 ( __splitmix_mix sm )
    = sm + sm 0x9e3779b97f4a7c15
    = . st s1 ( __splitmix_mix sm )
    = sm + sm 0x9e3779b97f4a7c15
    = . st s2 ( __splitmix_mix sm )
    = sm + sm 0x9e3779b97f4a7c15
    = . st s3 ( __splitmix_mix sm )
    ^ @ Rng { # s st }
}

// ── Core step ────────────────────────────────────────────────────────

// Advance the state and return the next 64-bit output. The bit pattern
// is uniform over all 2^64 values; it's returned reinterpreted as a
// signed i, so the sign is meaningless — feed it through `rng_below` /
// `rng_range` / `rng_u01` for a value in a range, or treat the raw bits
// as unsigned (e.g. `rand_hex_str`-style packing).
// NB: the locals below are named `w*` (not `s*`): a binding named `s0`
// would shadow the field name in `. st s0`, turning the field access
// into a *pointer index* `st[s0]`. Distinct names keep `.` field-typed.
@ rng_next Rng g → i {
    : *RngImpl st # *RngImpl . g ctl
    : u64 w0 . st s0
    : u64 w1 . st s1
    : u64 w2 . st s2
    : u64 w3 . st s3
    // result = rotl(w1 * 5, 7) * 9   (the "**" output scrambler)
    : ~ u64 result ( __rotl * w1 5 7 )
    = result * result 9
    // State update (order matters — the ^= are sequential).
    : u64 t << w1 17
    : ~ u64 n2 ^^ w2 w0
    : ~ u64 n3 ^^ w3 w1
    : u64 n1 ^^ w1 n2
    : u64 n0 ^^ w0 n3
    = n2 ^^ n2 t
    = n3 ( __rotl n3 45 )
    = . st s0 n0
    = . st s1 n1
    = . st s2 n2
    = . st s3 n3
    ^ # i result
}

// ── Range / convenience wrappers ─────────────────────────────────────

// Uniform integer in [0, n). Returns 0 for n <= 0. Unbiased: rejection-
// samples on the smallest power-of-two mask covering n, so there is no
// modulo bias.
@ rng_below Rng g i n → i {
    ? <= n 0 { ^ 0 } {}
    : ~ i mask 1
    ~ < mask n { = mask + * mask 2 1 }
    : ~ i v 0
    : ~ b done F
    ~ ! done {
        = v & ( rng_next g ) mask
        ? < v n { = done T } {}
    }
    ^ v
}

// Uniform integer in [from, to). Returns `from` for an empty / inverted
// range (from >= to).
@ rng_range Rng g i from i to → i {
    ? >= from to { ^ from } {}
    ^ + from ( rng_below g - to from )
}

// Uniform double in [0, 1). Takes the top 53 bits of one output and
// scales by 2^-53, the standard exact construction (every representable
// double multiple of 2^-53 in [0,1) is equally likely; 1.0 never occurs).
@ rng_u01 Rng g → f {
    : u64 r # u64 ( rng_next g )
    : u64 top >> r 11
    ^ / # f top 9007199254740992.0
}

// Fair coin flip. xoshiro256**'s low bits pass the same statistical
// tests as the high bits (the ** scrambler fixes the linear-low-bit
// weakness of plain xoshiro+), so the bottom bit is a sound source.
@ rng_bool Rng g → b {
    ^ == 1 & ( rng_next g ) 1
}

// ── Lifecycle ────────────────────────────────────────────────────────

// Release the generator's state. The handle is dead afterwards.
@ rng_free Rng g → v {
    ( nurl_free # *u . g ctl )
}
