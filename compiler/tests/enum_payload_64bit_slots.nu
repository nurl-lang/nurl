// enum_payload_64bit_slots.nu — regression for the wasm32 payload-slot
// truncation. Enum payload slots used to be `ptr`-typed and every payload
// rode them through inttoptr/ptrtoint. On 64-bit targets that is lossless,
// but wasm32 pointers are 32 bits wide, so an f64 bit-pattern or an
// integer ≥ 2^32 silently lost its upper half (the chaotic-showcase
// autodiff computed garbage on wasm while passing natively). The slots are
// now uniformly i64 — bit-complete on every target — and pointers are the
// ones that convert (ptrtoint/inttoptr, lossless everywhere).
//
// This test pins the 64-bit-exact round-trip for every payload kind whose
// bits used to transit a pointer: f64 (incl. values whose bit-pattern has
// BOTH halves non-zero), i64 above 2^32, negative i64 (sign bits live in
// the upper half), an f64 in a non-zero slot index, and a genuine pointer
// payload. Natively this always passed — the golden guards the IR shape
// staying bit-complete; the wasm twin is exercised by
// packages/wasmbuilder/tests/build_test.sh, where the same program must
// print the same bytes under a wasm runtime.

: | W {
    Big i
    D f
    Mix i f i
    Ptr * W
    Nil
}

@ ck b ok s label → v {
    ( nurl_print label ) ( nurl_print ? ok ` ok\n` ` FAIL\n` )
}

@ main → i {
    // i64 payload with high bits set (> 2^32) — upper half must survive.
    : W a @ W { Big 81985529216486895 }  // 0x0123456789ABCDEF
    ?? a {
        Big v → { ( ck == v 81985529216486895 `big_i64` ) }
        D _ → {}
        Mix _ _ _ → {}
        Ptr _ → {}
        Nil → {}
    }

    // negative i64 — the sign lives in the upper half.
    : W n @ W { Big - 0 4294967297 }  // -(2^32 + 1)
    ?? n {
        Big v → { ( ck == v - 0 4294967297 `neg_i64` ) }
        D _ → {}
        Mix _ _ _ → {}
        Ptr _ → {}
        Nil → {}
    }

    // f64 payload whose bit-pattern fills both 32-bit halves.
    : W d @ W { D 10.9093 }
    ?? d {
        Big _ → {}
        D v → { ( ck & > v 10.9092 < v 10.9094 `f64_slot0` ) }
        Mix _ _ _ → {}
        Ptr _ → {}
        Nil → {}
    }

    // mixed slots: big int, f64, big int — slots 0/1/2 all 64-bit-exact.
    : W m @ W { Mix 4294967296 6.58385 8589934592 }
    ?? m {
        Big _ → {}
        D _ → {}
        Mix x v y → {
            ( ck == x 4294967296 `mix_slot0` )
            ( ck & > v 6.58384 < v 6.58386 `mix_slot1_f64` )
            ( ck == y 8589934592 `mix_slot2` )
        }
        Ptr _ → {}
        Nil → {}
    }

    // pointer payload still round-trips through the i64 slot.
    : *W p # *W ( nurl_alloc Z W )
    = . p 0 @ W { Big 1311768467463790320 }  // 0x1234567890ABCDF0
    : W w @ W { Ptr p }
    ?? w {
        Big _ → {}
        D _ → {}
        Mix _ _ _ → {}
        Ptr q → {
            : W inner . q 0
            ?? inner {
                Big v → { ( ck == v 1311768467463790320 `ptr_payload_i64` ) }
                D _ → {}
                Mix _ _ _ → {}
                Ptr _ → {}
                Nil → {}
            }
        }
        Nil → {}
    }
    ( nurl_free # s p )
    ^ 0
}
