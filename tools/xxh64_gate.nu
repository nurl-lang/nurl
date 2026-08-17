// tools/xxh64_gate.nu — emit XXH64 digests for a deterministic byte
// sequence so tools/xxh64_gate.sh can check them against an independent
// implementation (python3's `xxhash` module).
//
// XXH64 processes a 32-byte stripe at a time and then takes an 8-byte,
// a 4-byte and a 1-byte tail path, so the interesting lengths are the
// ones straddling those boundaries: every length 0..80 exercises the
// short-input branch and all three tail shapes, and the larger lengths
// prove the striped loop and its accumulator merge. Seeds are varied
// because the seed feeds the accumulators asymmetrically (v4 = seed - P1)
// and a sign slip there is invisible at seed 0.
//
// Output, one record per line:
//   h <len> <seed> <digest-as-signed-decimal>

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hash_xxh64.nu`

@ __vec_of i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i i 0
    ~ < i n {
        ( vec_push [u] v # u & 255 + * i 37 11 )
        = i + i 1
    }
    ^ v
}

@ __emit i n i seed → v {
    : ( Vec u ) v ( __vec_of n )
    : String out ( string_with_cap 48 )
    ( string_push_str out `h ` )
    ( string_push_int out n )
    ( string_push_char out 32 )
    ( string_push_int out seed )
    ( string_push_char out 32 )
    ( string_push_int out ( xxh64_seed v seed ) )
    ( string_push_char out 10 )
    ( nurl_print ( string_data out ) )
    ( string_free out )
    ( vec_free [u] v )
}

@ main → i {
    // Every length through the tail shapes and past the first stripes.
    : ~ i n 0
    ~ <= n 80 { ( __emit n 0 ) = n + n 1 }
    // Larger inputs: the striped loop with a non-trivial tail.
    ( __emit 255 0 ) ( __emit 256 0 ) ( __emit 257 0 )
    ( __emit 1023 0 ) ( __emit 1024 0 ) ( __emit 4096 0 )
    ( __emit 65535 0 ) ( __emit 65536 0 )
    // Seeded, across the same branch boundaries.
    : ~ i s 0
    ~ < s 4 {
        : i seed ? == s 0 1 ? == s 1 42 ? == s 2 -1 0x0123456789ABCDEF
        ( __emit 0 seed ) ( __emit 3 seed ) ( __emit 31 seed )
        ( __emit 32 seed ) ( __emit 33 seed ) ( __emit 1000 seed )
        = s + s 1
    }
    ^ 0
}
