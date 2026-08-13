// simd_scan.nu — the vectorised scanners in stdlib/std/simd.nu must
// agree with a naive scalar reference on EVERY alignment and length,
// not just the ones that happen to be a multiple of the vector width.
//
// The interesting failures of a 16-byte-at-a-time scanner are all at
// the seams: a match that straddles the end of a window, a buffer
// shorter than one window, a match in the scalar tail, and a match that
// does not exist at all. So the test walks every length from 0 to 80
// and every match position within it, comparing against the reference
// each time — the block boundary at 16, 32, 48, 64 is crossed by
// construction rather than by hope.

$ `stdlib/core/vec.nu`
$ `stdlib/std/simd.nu`

// ── scalar references ────────────────────────────────────────────────

@ ref_index_byte * u p i n i c → i {
    : ~ i k 0
    ~ < k n {
        ? == & 255 # i . p k & c 255 { ^ k } {}
        = k + k 1
    }
    ^ -1
}

@ ref_index_crlf * u p i n → i {
    ? < n 2 { ^ -1 } {}
    : ~ i k 0
    ~ < k - n 1 {
        ? & == & 255 # i . p k 13 == & 255 # i . p + k 1 10 { ^ k } {}
        = k + k 1
    }
    ^ -1
}

@ ref_index_head_end * u p i n → i {
    ? < n 4 { ^ -1 } {}
    : ~ i k 0
    ~ <= + k 4 n {
        ? & & & == & 255 # i . p k 13 == & 255 # i . p + k 1 10
        == & 255 # i . p + k 2 13 == & 255 # i . p + k 3 10 { ^ k } {}
        = k + k 1
    }
    ^ -1
}

@ ref_index_ows_end * u p i n → i {
    : ~ i k 0
    ~ < k n {
        : i bb & 255 # i . p k
        ? & != bb 32 != bb 9 { ^ k } {}
        = k + k 1
    }
    ^ n
}

@ ref_bytes_eq * u a * u b i n → b {
    : ~ i k 0
    ~ < k n {
        ? != & 255 # i . a k & 255 # i . b k { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ ref_bytes_eq_ci * u a * u b i n → b {
    : ~ i k 0
    ~ < k n {
        ? != ( simd_ascii_lower & 255 # i . a k ) ( simd_ascii_lower & 255 # i . b k ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

// ── harness ──────────────────────────────────────────────────────────

: ~ i g_fail 0

@ chk s what i want i got → v {
    ? != want got {
        = g_fail + g_fail 1
        ? < g_fail 12 {
            ( nurl_print `FAIL ` ) ( nurl_print what )
            ( nurl_print ` want=` ) ( nurl_print_int want )
            ( nurl_print ` got=` ) ( nurl_print_int got )
            ( nurl_println `` )
        } {}
    } {}
}

@ fill * u p i n i c → v {
    : ~ i k 0
    ~ < k n { = . p k # u c = k + k 1 }
}

@ main → i {
    : i cap 128
    : ( Vec u ) buf ( vec_with_cap [u] cap )
    : b _l1 ( vec_set_len [u] buf cap )
    : ( Vec u ) buf2 ( vec_with_cap [u] cap )
    : b _l2 ( vec_set_len [u] buf2 cap )
    : *u p ( vec_data [u] buf )
    : *u q ( vec_data [u] buf2 )

    // ── single-byte search, every (length, position) pair ────────────
    : ~ i n 0
    ~ <= n 80 {
        : ~ i pos 0
        ~ <= pos n {
            ( fill p cap 65 )
            ? < pos n { = . p pos # u 90 } {}
            ( chk `index_byte` ( ref_index_byte p n 90 ) ( simd_index_byte p n 90 ) )
            = pos + pos 1
        }
        // absent
        ( fill p cap 65 )
        ( chk `index_byte/absent` ( ref_index_byte p n 90 ) ( simd_index_byte p n 90 ) )
        = n + n 1
    }

    // ── CRLF, every (length, position) pair ──────────────────────────
    = n 0
    ~ <= n 80 {
        : ~ i pos 0
        ~ <= pos n {
            ( fill p cap 65 )
            ? <= + pos 2 n { = . p pos # u 13 = . p + pos 1 # u 10 } {}
            ( chk `index_crlf` ( ref_index_crlf p n ) ( simd_index_crlf p n ) )
            = pos + pos 1
        }
        // a lone CR and a lone LF must NOT match
        ( fill p cap 65 )
        ? > n 3 { = . p - n 2 # u 13 = . p 1 # u 10 } {}
        ( chk `index_crlf/lone` ( ref_index_crlf p n ) ( simd_index_crlf p n ) )
        = n + n 1
    }

    // ── head terminator, every (length, position) pair ───────────────
    = n 0
    ~ <= n 80 {
        : ~ i pos 0
        ~ <= pos n {
            ( fill p cap 65 )
            ? <= + pos 4 n {
                = . p pos # u 13 = . p + pos 1 # u 10
                = . p + pos 2 # u 13 = . p + pos 3 # u 10
            } {}
            ( chk `index_head_end` ( ref_index_head_end p n ) ( simd_index_head_end p n ) )
            = pos + pos 1
        }
        // CRLF CR X — a near miss that must not be reported
        ( fill p cap 65 )
        ? > n 8 { = . p 3 # u 13 = . p 4 # u 10 = . p 5 # u 13 } {}
        ( chk `index_head_end/near` ( ref_index_head_end p n ) ( simd_index_head_end p n ) )
        = n + n 1
    }

    // ── OWS run length ───────────────────────────────────────────────
    = n 0
    ~ <= n 80 {
        : ~ i pos 0
        ~ <= pos n {
            ( fill p cap 32 )
            ? > pos 0 { = . p - pos 1 # u 9 } {}
            ? < pos n { = . p pos # u 65 } {}
            ( chk `index_ows_end` ( ref_index_ows_end p n ) ( simd_index_ows_end p n ) )
            = pos + pos 1
        }
        = n + n 1
    }

    // ── equality, plain and case-insensitive ─────────────────────────
    = n 0
    ~ <= n 80 {
        : ~ i pos 0
        ~ <= pos n {
            ( fill p cap 97 )  // 'a'
            ( fill q cap 65 )  // 'A' — equal only case-insensitively
            ( chk `bytes_eq_ci` ? ( ref_bytes_eq_ci p q n ) 1 0 ? ( simd_bytes_eq_ci p q n ) 1 0 )
            ( chk `bytes_eq` ? ( ref_bytes_eq p q n ) 1 0 ? ( simd_bytes_eq p q n ) 1 0 )
            // one differing byte at `pos`
            ( fill q cap 97 )
            ? < pos n { = . q pos # u 98 } {}
            ( chk `bytes_eq/diff` ? ( ref_bytes_eq p q n ) 1 0 ? ( simd_bytes_eq p q n ) 1 0 )
            ( chk `bytes_eq_ci/diff` ? ( ref_bytes_eq_ci p q n ) 1 0 ? ( simd_bytes_eq_ci p q n ) 1 0 )
            = pos + pos 1
        }
        = n + n 1
    }

    // ── the case-folding trap: '^' (0x5E) and '~' (0x7E) differ only
    //    in bit 5, so `x | 32` would call them equal. Both are legal
    //    HTTP token characters, so that would merge two header names.
    ( fill p cap 94 )
    ( fill q cap 126 )
    ( chk `fold/caret-vs-tilde` 0 ? ( simd_bytes_eq_ci p q 40 ) 1 0 )
    ( fill p cap 64 )  // '@'
    ( fill q cap 96 )  // '`'
    ( chk `fold/at-vs-backtick` 0 ? ( simd_bytes_eq_ci p q 40 ) 1 0 )

    // ── bulk XOR against a scalar reference ──────────────────────────
    = n 0
    ~ <= n 80 {
        : ~ i k 0
        ~ < k cap { = . p k # u & 255 * k 7 = . q k # u & 255 + k 3 = k + k 1 }
        ( simd_xor_into p q n )
        : ~ i bad 0
        = k 0
        ~ < k n {
            ? != & 255 # i . p k & 255 ^^ & 255 * k 7 & 255 + k 3 { = bad + bad 1 } {}
            = k + k 1
        }
        // bytes past n must be untouched
        ~ < k cap {
            ? != & 255 # i . p k & 255 * k 7 { = bad + bad 1 } {}
            = k + k 1
        }
        ( chk `xor_into` 0 bad )
        = n + n 1
    }

    ( vec_free [u] buf )
    ( vec_free [u] buf2 )
    ? == g_fail 0 { ( nurl_println `simd: all scans agree with the scalar reference` ) }
    { ( nurl_print `simd: ` ) ( nurl_print_int g_fail ) ( nurl_println ` mismatches` ) }
    ^ 0
}
