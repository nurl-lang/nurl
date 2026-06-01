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

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── word helpers ──────────────────────────────────────────────────

@ __b3_get ( Vec u32 ) v i idx → u32 {
    : ?u32 o ( vec_get [u32] v idx )
    ?? o { T x → { ^ x } F → { ^ # u32 0 } }
}

@ __b3_set ( Vec u32 ) v i idx u32 x → v {
    : b _r ( vec_set [u32] v idx x )
}

// Right-rotate a u32 by c bits (0 < c < 32).
@ __b3_rotr u32 x i c → u32 {
    : u32 cu # u32 c
    : u32 inv # u32 - 32 c
    ^ | >> x cu << x inv
}

// BLAKE3 IV = the SHA-256 initial hash values.
@ __b3_iv → ( Vec u32 ) {
    : ( Vec u32 ) v ( vec_with_cap [u32] 8 )
    ( vec_push [u32] v # u32 1779033703 )  // 0x6A09E667
    ( vec_push [u32] v # u32 3144134277 )  // 0xBB67AE85
    ( vec_push [u32] v # u32 1013904242 )  // 0x3C6EF372
    ( vec_push [u32] v # u32 2773480762 )  // 0xA54FF53A
    ( vec_push [u32] v # u32 1359893119 )  // 0x510E527F
    ( vec_push [u32] v # u32 2600822924 )  // 0x9B05688C
    ( vec_push [u32] v # u32 528734635 )   // 0x1F83D9AB
    ( vec_push [u32] v # u32 1541459225 )  // 0x5BE0CD19
    ^ v
}

@ __b3_copy ( Vec u32 ) src i n → ( Vec u32 ) {
    : ( Vec u32 ) d ( vec_with_cap [u32] n )
    : ~ i i 0
    ~ < i n { ( vec_push [u32] d ( __b3_get src i ) ) = i + i 1 }
    ^ d
}

// One byte of the 64-byte block at [base, base+blen); 0 past blen
// (zero-padding for a partial final block).
@ __b3_byte ( Vec u ) data i base i blen i p → i {
    ? >= p blen { ^ 0 } {}
    : ?u o ( vec_get [u] data + base p )
    ?? o { T x → { ^ # i x } F → { ^ 0 } }
}

// 16 little-endian u32 words from the 64-byte block at `base`, with the
// bytes from blen..64 treated as zero.
@ __b3_block_words ( Vec u ) data i base i blen → ( Vec u32 ) {
    : ( Vec u32 ) w ( vec_with_cap [u32] 16 )
    : ~ i wi 0
    ~ < wi 16 {
        : i p * wi 4
        : i b0 ( __b3_byte data base blen + p 0 )
        : i b1 ( __b3_byte data base blen + p 1 )
        : i b2 ( __b3_byte data base blen + p 2 )
        : i b3 ( __b3_byte data base blen + p 3 )
        : i word | b0 | << b1 8 | << b2 16 << b3 24
        ( vec_push [u32] w # u32 word )
        = wi + wi 1
    }
    ^ w
}

// m[i] = m[MSG_PERMUTATION[i]];  PERM = 2 6 3 10 7 0 4 13 1 11 12 5 9 14 15 8
@ __b3_permute ( Vec u32 ) m → ( Vec u32 ) {
    : ( Vec u32 ) p ( vec_with_cap [u32] 16 )
    ( vec_push [u32] p ( __b3_get m 2 ) )
    ( vec_push [u32] p ( __b3_get m 6 ) )
    ( vec_push [u32] p ( __b3_get m 3 ) )
    ( vec_push [u32] p ( __b3_get m 10 ) )
    ( vec_push [u32] p ( __b3_get m 7 ) )
    ( vec_push [u32] p ( __b3_get m 0 ) )
    ( vec_push [u32] p ( __b3_get m 4 ) )
    ( vec_push [u32] p ( __b3_get m 13 ) )
    ( vec_push [u32] p ( __b3_get m 1 ) )
    ( vec_push [u32] p ( __b3_get m 11 ) )
    ( vec_push [u32] p ( __b3_get m 12 ) )
    ( vec_push [u32] p ( __b3_get m 5 ) )
    ( vec_push [u32] p ( __b3_get m 9 ) )
    ( vec_push [u32] p ( __b3_get m 14 ) )
    ( vec_push [u32] p ( __b3_get m 15 ) )
    ( vec_push [u32] p ( __b3_get m 8 ) )
    ^ p
}

// The G mixing function, in place on the 16-word state.
@ __b3_g ( Vec u32 ) s i a i b i c i d u32 mx u32 my → v {
    : ~ u32 sa ( __b3_get s a )
    : ~ u32 sb ( __b3_get s b )
    : ~ u32 sc ( __b3_get s c )
    : ~ u32 sd ( __b3_get s d )
    = sa # u32 + + sa sb mx
    = sd ( __b3_rotr ^^ sd sa 16 )
    = sc # u32 + sc sd
    = sb ( __b3_rotr ^^ sb sc 12 )
    = sa # u32 + + sa sb my
    = sd ( __b3_rotr ^^ sd sa 8 )
    = sc # u32 + sc sd
    = sb ( __b3_rotr ^^ sb sc 7 )
    ( __b3_set s a sa )
    ( __b3_set s b sb )
    ( __b3_set s c sc )
    ( __b3_set s d sd )
}

// One round: 4 column mixes then 4 diagonal mixes.
@ __b3_round ( Vec u32 ) s ( Vec u32 ) m → v {
    ( __b3_g s 0 4 8 12 ( __b3_get m 0 ) ( __b3_get m 1 ) )
    ( __b3_g s 1 5 9 13 ( __b3_get m 2 ) ( __b3_get m 3 ) )
    ( __b3_g s 2 6 10 14 ( __b3_get m 4 ) ( __b3_get m 5 ) )
    ( __b3_g s 3 7 11 15 ( __b3_get m 6 ) ( __b3_get m 7 ) )
    ( __b3_g s 0 5 10 15 ( __b3_get m 8 ) ( __b3_get m 9 ) )
    ( __b3_g s 1 6 11 12 ( __b3_get m 10 ) ( __b3_get m 11 ) )
    ( __b3_g s 2 7 8 13 ( __b3_get m 12 ) ( __b3_get m 13 ) )
    ( __b3_g s 3 4 9 14 ( __b3_get m 14 ) ( __b3_get m 15 ) )
}

// The compression function. Returns the full 16-word output state; the
// caller takes words 0..8 as a chaining value (or, for a ROOT node,
// as the first 32 bytes of output). `counter` is the 64-bit node
// counter (chunk index for chunks, 0 for parents).
@ __b3_compress ( Vec u32 ) cv ( Vec u32 ) block i counter i blen i flags → ( Vec u32 ) {
    : ( Vec u32 ) iv ( __b3_iv )
    : ( Vec u32 ) s ( vec_with_cap [u32] 16 )
    : ~ i i 0
    ~ < i 8 { ( vec_push [u32] s ( __b3_get cv i ) ) = i + i 1 }
    ( vec_push [u32] s ( __b3_get iv 0 ) )
    ( vec_push [u32] s ( __b3_get iv 1 ) )
    ( vec_push [u32] s ( __b3_get iv 2 ) )
    ( vec_push [u32] s ( __b3_get iv 3 ) )
    ( vec_push [u32] s # u32 & counter 0xFFFFFFFF )
    ( vec_push [u32] s # u32 & >> counter 32 0xFFFFFFFF )
    ( vec_push [u32] s # u32 blen )
    ( vec_push [u32] s # u32 flags )
    ( vec_free [u32] iv )

    : ~ ( Vec u32 ) m ( __b3_copy block 16 )
    : ~ i rd 0
    ~ < rd 7 {
        ? > rd 0 {
            : ( Vec u32 ) mp ( __b3_permute m )
            ( vec_free [u32] m )
            = m mp
        } {}
        ( __b3_round s m )
        = rd + rd 1
    }
    ( vec_free [u32] m )

    // Feed-forward: s[i] ^= s[i+8]; s[i+8] ^= cv[i].
    : ~ i j 0
    ~ < j 8 {
        : u32 lo ^^ ( __b3_get s j ) ( __b3_get s + j 8 )
        : u32 hi ^^ ( __b3_get s + j 8 ) ( __b3_get cv j )
        ( __b3_set s j lo )
        ( __b3_set s + j 8 hi )
        = j + j 1
    }
    ^ s
}

// Chaining value of a chunk [off, off+len) at index `counter`. With
// `root` set, the final block also carries the ROOT flag, so words 0..8
// of the result ARE the 32-byte hash (single-chunk inputs).
@ __b3_chunk_cv ( Vec u ) data i off i len i counter b root → ( Vec u32 ) {
    : ~ ( Vec u32 ) cv ( __b3_iv )
    : i nb ? <= len 0 1 / + len 63 64
    : ~ i bk 0
    ~ < bk - nb 1 {
        : ( Vec u32 ) bw ( __b3_block_words data + off * bk 64 64 )
        : i fl ? == bk 0 1 0  // CHUNK_START on the first block only
        : ( Vec u32 ) out ( __b3_compress cv bw counter 64 fl )
        ( vec_free [u32] bw )
        ( vec_free [u32] cv )
        = cv ( __b3_copy out 8 )
        ( vec_free [u32] out )
        = bk + bk 1
    }
    : i lb_off + off * - nb 1 64
    : i lb_len - len * - nb 1 64
    : ( Vec u32 ) lbw ( __b3_block_words data lb_off lb_len )
    : i lflags | 2 | ? == nb 1 1 0 ? root 8 0  // CHUNK_END | (CHUNK_START if 1 block) | (ROOT?)
    : ( Vec u32 ) st ( __b3_compress cv lbw counter lb_len lflags )
    : ( Vec u32 ) result ( __b3_copy st 8 )
    ( vec_free [u32] cv )
    ( vec_free [u32] lbw )
    ( vec_free [u32] st )
    ^ result
}

// Parent node CV from two child CVs. ROOT flag for the top node.
@ __b3_parent ( Vec u32 ) left ( Vec u32 ) right b root → ( Vec u32 ) {
    : ( Vec u32 ) iv ( __b3_iv )
    : ( Vec u32 ) block ( vec_with_cap [u32] 16 )
    : ~ i i 0
    ~ < i 8 { ( vec_push [u32] block ( __b3_get left i ) ) = i + i 1 }
    : ~ i j 0
    ~ < j 8 { ( vec_push [u32] block ( __b3_get right j ) ) = j + j 1 }
    : i flags | 4 ? root 8 0  // PARENT | (ROOT?)
    : ( Vec u32 ) st ( __b3_compress iv block 0 64 flags )
    : ( Vec u32 ) result ( __b3_copy st 8 )
    ( vec_free [u32] iv )
    ( vec_free [u32] block )
    ( vec_free [u32] st )
    ^ result
}

// ── CV stack (flattened: 8 u32 per entry) ─────────────────────────

@ __b3_stack_push ( Vec u32 ) stack ( Vec u32 ) cv8 → v {
    : ~ i i 0
    ~ < i 8 { ( vec_push [u32] stack ( __b3_get cv8 i ) ) = i + i 1 }
}

@ __b3_stack_pop ( Vec u32 ) stack → ( Vec u32 ) {
    : i base - ( vec_len [u32] stack ) 8
    : ( Vec u32 ) cv ( vec_with_cap [u32] 8 )
    : ~ i i 0
    ~ < i 8 { ( vec_push [u32] cv ( __b3_get stack + base i ) ) = i + i 1 }
    : b _ok ( vec_set_len [u32] stack base )
    ^ cv
}

@ __b3_stack_get ( Vec u32 ) stack i idx → ( Vec u32 ) {
    : i base * idx 8
    : ( Vec u32 ) cv ( vec_with_cap [u32] 8 )
    : ~ i i 0
    ~ < i 8 { ( vec_push [u32] cv ( __b3_get stack + base i ) ) = i + i 1 }
    ^ cv
}

// Root chaining value for a multi-chunk (> 1024 byte) input.
@ __b3_root_multi ( Vec u ) data i n i num_chunks → ( Vec u32 ) {
    : ( Vec u32 ) stack ( vec_new [u32] )
    : ~ i scount 0
    : ~ i ci 0
    ~ < ci - num_chunks 1 {
        : ~ ( Vec u32 ) ncv ( __b3_chunk_cv data * ci 1024 1024 ci F )
        : ~ i total + ci 1
        ~ == & total 1 0 {
            : ( Vec u32 ) popped ( __b3_stack_pop stack )
            = scount - scount 1
            : ( Vec u32 ) merged ( __b3_parent popped ncv F )
            ( vec_free [u32] popped )
            ( vec_free [u32] ncv )
            = ncv merged
            = total >> total 1
        }
        ( __b3_stack_push stack ncv )
        ( vec_free [u32] ncv )
        = scount + scount 1
        = ci + ci 1
    }
    : i last_off * - num_chunks 1 1024
    : i last_len - n last_off
    : ~ ( Vec u32 ) cur ( __b3_chunk_cv data last_off last_len - num_chunks 1 F )
    : ~ i r - scount 1
    ~ >= r 0 {
        : ( Vec u32 ) left ( __b3_stack_get stack r )
        : ( Vec u32 ) merged ( __b3_parent left cur == r 0 )
        ( vec_free [u32] left )
        ( vec_free [u32] cur )
        = cur merged
        = r - r 1
    }
    ( vec_free [u32] stack )
    ^ cur
}

// ── Public entry ──────────────────────────────────────────────────

@ blake3_pure ( Vec u ) data → ( Vec u ) {
    : i n ( vec_len [u] data )
    : i nc / + n 1023 1024
    : i num_chunks ? < nc 1 1 nc
    : ( Vec u32 ) root8 ? == num_chunks 1
    ( __b3_chunk_cv data 0 n 0 T )
    ( __b3_root_multi data n num_chunks )

    : ( Vec u ) out ( vec_with_cap [u] 32 )
    : ~ i i 0
    ~ < i 8 {
        : i w # i ( __b3_get root8 i )
        ( vec_push [u] out # u & w 255 )
        ( vec_push [u] out # u & >> w 8 255 )
        ( vec_push [u] out # u & >> w 16 255 )
        ( vec_push [u] out # u & >> w 24 255 )
        = i + i 1
    }
    ( vec_free [u32] root8 )
    ^ out
}
