// stdlib/core/string.nu — owned growable String, backed by Vec[u].
//
// String is an opaque handle whose underlying storage is a `Vec[u]`
// growable byte buffer. The handle is value-passed; mutations flow
// through the inner Vec's ctl pointer just like Vec[A] itself, so
// aliasing semantics match Vec.
//
// Layout: `String { s ctl }` — same single-i8* shape as `Vec[u]`. The
// `ctl` field points to the same 24-byte control block (`{data, len, cap}`)
// that vec_with_cap[u] allocates. We view it as a Vec[u] inside this
// module via the private `__sbuf` helper; outside this module the type
// is opaque.
//
// Invariants the implementation maintains:
//   1. cap >= len + 1                 (always room for a trailing NUL)
//   2. data[len] == 0  between ops    (so `string_data` returns C-safe s)
//
// `__string_seal` enforces the invariant after every mutation. NUL bytes
// inside [0, len) are stored verbatim (Vec[u] doesn't truncate); only
// `string_data`'s C-string consumers see truncation at the first inner
// NUL, which is the contract of every NUL-terminated API.
//
//   ( string_new )             → String      empty
//   ( string_from raw )        → String      copy of raw i8*
//   ( string_len s )           → i           byte length
//   ( string_data s )          → s           borrowed i8* (null-terminated); do NOT free
//   ( string_get s idx )       → i           byte at index (0 out of range)
//   ( string_push_char s c )   → v           append one byte
//   ( string_push_str s raw )  → v           append raw i8*
//   ( string_push_bytes s src n ) → v        append n raw bytes (no strlen)
//   ( string_push_int s n )    → v           append decimal integer
//   ( string_clear s )         → v           reset to empty
//   ( string_free s )          → v           release buffer, invalidates handle
//   ( string_eq a b )          → b           content equality
//
//   ( string_with_cap n )      → String      empty, cap-preallocated
//   ( string_clone s )         → String      independent deep copy
//   ( string_concat a b )      → String      new owned concatenation
//   ( string_starts_with s p ) → b           prefix check
//   ( string_ends_with s p )   → b           suffix check
//   ( string_contains s n )    → b           substring check
//   ( string_substr s from len ) → String    owned copy of [from, from+len)
//   ( string_to_int s )        → ! i ParseErr  strict decimal parse with sign
//   ( string_to_float s )      → ?f            strict decimal float
//   ( string_index_of s p )    → ?i            byte index of first occurrence
//   ( string_split s sep )     → ( Vec String ) split on sep occurrences

$ `stdlib/core/errors.nu`
$ `stdlib/core/vec.nu`
// Note: do NOT include stdlib/std/bytes.nu here. bytes.nu depends on
// String (e.g. `bytes_to_str → String`); a circular include would force
// the compiler to reference %String before its body is emitted. We keep
// this module self-contained on Vec[u] primitives only.

: String {
    s ctl
}

// ── Internal: view the underlying ctl block as a Vec[u] handle ─────
// All Vec[u] operations on the returned handle mutate the same heap
// control block that `str` references, so they're observable through
// `str` after the call returns. The struct layout `{ s ctl }` matches
// `Vec[A] { s ctl }` so this is a zero-cost view (one i8* copy).
@ __sbuf String str → ( Vec u ) {
    ^ @ ( Vec u ) { . str ctl }
}

// Append the raw NUL-terminated bytes of `raw` onto str's buffer. Caller
// is responsible for the post-mutation `__string_seal`.
@ __string_append_raw String str s raw → v {
    : ( Vec u ) b ( __sbuf str )
    : i n ( nurl_str_len raw )
    ? > n 0 {
        ( vec_reserve [u] b n )
        : *u src # *u raw
        : *u dst ( vec_data [u] b )
        : i len ( vec_len [u] b )
        : *u dst_at # *u + # i dst len
        ( nurl_memcpy dst_at src n )
        ( vec_set_len [u] b + len n )
    } {}
}

// ── Internal: NUL-terminator discipline ─────────────────────────────
// Ensure cap >= len + 1 and write 0 at data[len]. Call after every
// mutation (push, extend, clear, …) so `string_data` returns a C-safe
// pointer.
@ __string_seal String str → v {
    : ( Vec u ) b ( __sbuf str )
    ( vec_reserve [u] b 1 )
    : *u p ( vec_data [u] b )
    : i n ( vec_len [u] b )
    : u zero # u 0
    = . p n zero
}

// ── Constructors ────────────────────────────────────────────────────

@ string_new → String {
    : ( Vec u ) tmp ( vec_with_cap [u] 1 )
    : *u p ( vec_data [u] tmp )
    : u zero # u 0
    = . p 0 zero
    ^ @ String { . tmp ctl }
}

@ string_with_cap i n → String {
    : i want ? > n 0 + n 1 1
    : ( Vec u ) tmp ( vec_with_cap [u] want )
    : *u p ( vec_data [u] tmp )
    : u zero # u 0
    = . p 0 zero
    ^ @ String { . tmp ctl }
}

@ string_from s raw → String {
    : i n ( nurl_str_len raw )
    : ( Vec u ) tmp ( vec_with_cap [u] + n 1 )
    : *u src # *u raw
    : *u dst ( vec_data [u] tmp )
    ( nurl_memcpy dst src n )
    ( vec_set_len [u] tmp n )
    : u zero # u 0
    = . dst n zero
    ^ @ String { . tmp ctl }
}

// Take ownership of an already-malloc'd, NUL-terminated buffer and
// wrap it as a String WITHOUT copying. The caller must NOT touch
// `raw` after the call — the returned String now owns the buffer
// and will `nurl_free` it on `string_free`.
//
// `raw_cap` is the actual malloc'd size (bytes), typically
// `nurl_str_len raw + 1` for a freshly-read file buffer. Must be
// >= len + 1 so the trailing NUL fits.
//
// Used by fast file I/O paths (CSV / arena loaders) to avoid the
// `nurl_memcpy` over the full content — for a 100 MB CSV that's
// ~33 ms saved per load.
@ string_from_take s raw i raw_cap → String {
    : i n ( nurl_str_len raw )
    : s ctl ( nurl_zalloc 24 )
    ( nurl_poke ctl 0 # i raw )
    ( nurl_poke ctl 1 n )
    ( nurl_poke ctl 2 raw_cap )
    ^ @ String { ctl }
}

// Build an owned String from a raw byte range. `src` is a borrowed
// pointer into another buffer; `n` bytes are copied verbatim and a NUL
// terminator is written at offset n. Faster than building a temporary
// raw `s` and calling `string_from`, because it avoids a strlen scan
// and an extra malloc/free pair.
@ string_from_bytes * u src i n → String {
    : i len ? > n 0 n 0
    : ( Vec u ) tmp ( vec_with_cap [u] + len 1 )
    : *u dst ( vec_data [u] tmp )
    ? > len 0 {
        ( nurl_memcpy dst src len )
        ( vec_set_len [u] tmp len )
    } {}
    : u zero # u 0
    = . dst len zero
    ^ @ String { . tmp ctl }
}

// Deep copy of `str` into a fresh owned String. The two Strings share
// no storage — mutating or freeing one never affects the other. Embedded
// NUL bytes in [0, len) are preserved verbatim.
//
// This is the stock element-clone for owned-String containers: pass it
// to `vec_clone_with` / `map_clone_with` wrapped in a `\`-closure (NURL
// hands closure values, not @-function names, to higher-order params):
//
//   ( vec_clone_with [String] src \ String s → String { ^ ( string_clone s ) } )
@ string_clone String str → String {
    : ( Vec u ) b ( __sbuf str )
    : i n ( vec_len [u] b )
    : *u src ( vec_data [u] b )
    ^ ( string_from_bytes src n )
}

// ── Inspectors ──────────────────────────────────────────────────────

@ string_len String str → i {
    ^ ( vec_len [u] ( __sbuf str ) )
}

@ string_data String str → s {
    ^ # s ( vec_data [u] ( __sbuf str ) )
}

@ string_get String str i idx → i {
    : ?u got ( vec_get [u] ( __sbuf str ) idx )
    ?? got {
        T x → { ^ # i x }
        F _ → { ^ 0 }
    }
}

@ string_eq String a String b → b {
    : ( Vec u ) ba ( __sbuf a )
    : ( Vec u ) bb ( __sbuf b )
    : i la ( vec_len [u] ba )
    : i lb ( vec_len [u] bb )
    ? != la lb { ^ F } {}
    : *u pa ( vec_data [u] ba )
    : *u pb ( vec_data [u] bb )
    ^ == ( nurl_str_eq # s pa # s pb ) 1
}

// ── Mutators ────────────────────────────────────────────────────────

@ string_push_char String str i c → v {
    : ( Vec u ) b ( __sbuf str )
    ( vec_push [u] b # u c )
    ( __string_seal str )
}

@ string_push_str String str s raw → v {
    ( __string_append_raw str raw )
    ( __string_seal str )
}

// Append exactly `n` raw bytes from `src` onto str's buffer. Unlike
// string_push_str this needs no strlen scan and preserves embedded NUL
// bytes verbatim — the range-append a streaming reader wants when it
// already knows the line length. `src` is borrowed; the bytes are
// copied, str keeps no reference.
@ string_push_bytes String str * u src i n → v {
    ? > n 0 {
        : ( Vec u ) b ( __sbuf str )
        : i len ( vec_len [u] b )
        ( vec_reserve [u] b + n 1 )
        : *u dst ( vec_data [u] b )
        : *u dst_at # *u + # i dst len
        ( nurl_memcpy dst_at src n )
        : b _ok ( vec_set_len [u] b + len n )
    } {}
    ( __string_seal str )
}

@ string_push_int String str i n → v {
    : s raw ( nurl_str_int n )
    ( __string_append_raw str raw )
    ( __string_seal str )
}

@ string_push_float String str f x → v {
    : s raw ( nurl_str_float x )
    ( __string_append_raw str raw )
    ( __string_seal str )
}

@ string_clear String str → v {
    : ( Vec u ) b ( __sbuf str )
    ( vec_clear [u] b )
    ( __string_seal str )
}

@ string_free String str → v {
    ( vec_free [u] ( __sbuf str ) )
}

// ── Concat ──────────────────────────────────────────────────────────

@ string_concat String a String b → String {
    : i la ( string_len a )
    : i lb ( string_len b )
    : String out ( string_with_cap + la lb )
    ( string_push_str out ( string_data a ) )
    ( string_push_str out ( string_data b ) )
    ^ out
}

// ── Predicates / search (delegate to nurl_str_* on string_data) ────

@ string_starts_with String str s prefix → b {
    ^ != 0 ( nurl_str_starts ( string_data str ) prefix )
}

@ string_ends_with String str s suffix → b {
    ^ != 0 ( nurl_str_ends ( string_data str ) suffix )
}

@ string_contains String str s needle → b {
    ^ >= ( nurl_str_find ( string_data str ) needle ) 0
}

// Strict decimal parse. Accepts optional leading '-' or '+', then one
// or more decimal digits, and nothing else. Empty input (or just a sign
// with no digits) → Empty. Any non-digit byte after the optional sign →
// BadFormat. Overflow is not currently detected (atoll wraps silently);
// a future revision may return Overflow for > i64 magnitude.
@ string_to_int String str → !i ParseErr {
    : i len ( string_len str )
    ? == len 0 { ^ @ !i ParseErr { F @ ParseErr { Empty } } } {}

    : ~ i idx 0
    : i first ( string_get str 0 )
    // '-' = 45, '+' = 43
    ? | == first 45 == first 43 { = idx 1 } {}

    // bare sign with no digits
    ? == idx len { ^ @ !i ParseErr { F @ ParseErr { Empty } } } {}

    ~ < idx len {
        : i c ( string_get str idx )
        ? == ( nurl_is_digit c ) 0 {
            ^ @ !i ParseErr { F @ ParseErr { BadFormat } }
        } {}
        = idx + idx 1
    }

    : s buf ( string_data str )
    ^ @ !i ParseErr { T ( nurl_str_to_int buf ) }
}

// First byte index at which `needle` occurs in `str`. Empty needle
// matches at 0 (same as nurl_str_find / strstr). Result is None if
// the needle is not present.
@ string_index_of String str s needle → ?i {
    : i n ( nurl_str_find ( string_data str ) needle )
    ? < n 0 { ^ @ ?i { F 0 } } {}
    ^ @ ?i { T n }
}

// Strict decimal float. Either int or fractional part may be empty
// (`.5` and `1.` both accepted) but at least one mantissa digit is
// required overall. Optional exponent must have at least one digit.
@ string_to_float String str → ?f {
    : i len ( string_len str )
    ? == len 0 { ^ @ ?f { F 0.0 } } {}

    : ~ i idx 0
    : i first ( string_get str 0 )
    ? | == first 45 == first 43 { = idx 1 } {}
    ? == idx len { ^ @ ?f { F 0.0 } } {}

    : ~ i int_digits 0
    : ~ b going T
    ~ going {
        ? == idx len { = going F } {
            : i c ( string_get str idx )
            ? == ( nurl_is_digit c ) 0 { = going F } {
                = idx + idx 1
                = int_digits + int_digits 1
            }
        }
    }

    : ~ i frac_digits 0
    ? & < idx len == ( string_get str idx ) 46 {
        = idx + idx 1
        = going T
        ~ going {
            ? == idx len { = going F } {
                : i c ( string_get str idx )
                ? == ( nurl_is_digit c ) 0 { = going F } {
                    = idx + idx 1
                    = frac_digits + frac_digits 1
                }
            }
        }
    } {}

    ? & == int_digits 0 == frac_digits 0 {
        ^ @ ?f { F 0.0 }
    } {}

    ? < idx len {
        : i c ( string_get str idx )
        ? | == c 101 == c 69 {
            = idx + idx 1
            ? < idx len {
                : i esgn ( string_get str idx )
                ? | == esgn 45 == esgn 43 { = idx + idx 1 } {}
            } {}
            : ~ i exp_digits 0
            = going T
            ~ going {
                ? == idx len { = going F } {
                    : i ec ( string_get str idx )
                    ? == ( nurl_is_digit ec ) 0 { = going F } {
                        = idx + idx 1
                        = exp_digits + exp_digits 1
                    }
                }
            }
            ? == exp_digits 0 {
                ^ @ ?f { F 0.0 }
            } {}
        } {}
    } {}

    ? != idx len { ^ @ ?f { F 0.0 } } {}

    : s buf ( string_data str )
    ^ @ ?f { T ( nurl_str_to_float buf ) }
}

// ── Owned-returning transforms ──────────────────────────────────────

@ string_substr String str i from i len → String {
    : i slen ( string_len str )
    : i start from
    ? < start 0 { = start 0 } {}
    ? > start slen { = start slen } {}
    : i n len
    ? < n 0 { = n 0 } {}
    ? > + start n slen { = n - slen start } {}

    : ( Vec u ) tmp ( vec_with_cap [u] + n 1 )
    : *u dst ( vec_data [u] tmp )
    ? > n 0 {
        : *u src # *u ( string_data str )
        : *u src_at # *u + # i src start
        ( nurl_memcpy dst src_at n )
        ( vec_set_len [u] tmp n )
    } {}
    : u zero # u 0
    = . dst n zero
    ^ @ String { . tmp ctl }
}

// Copy all bytes with ASCII 'A'..'Z' mapped to 'a'..'z'.
@ string_to_lower String str → String {
    : i n ( string_len str )
    : String out ( string_with_cap n )
    : ~ i i 0
    ~ < i n {
        : ~ i c ( string_get str i )
        ? & >= c 65 <= c 90 { = c + c 32 } {}
        ( string_push_char out c )
        = i + i 1
    }
    ^ out
}

// Copy all bytes with ASCII 'a'..'z' mapped to 'A'..'Z'.
@ string_to_upper String str → String {
    : i n ( string_len str )
    : String out ( string_with_cap n )
    : ~ i i 0
    ~ < i n {
        : ~ i c ( string_get str i )
        ? & >= c 97 <= c 122 { = c - c 32 } {}
        ( string_push_char out c )
        = i + i 1
    }
    ^ out
}

// Bytewise reverse. Safe for ASCII; reverses code units, not UTF-8 scalars.
@ string_reverse String str → String {
    : i n ( string_len str )
    : String out ( string_with_cap n )
    : ~ i i - n 1
    ~ >= i 0 {
        ( string_push_char out ( string_get str i ) )
        = i - i 1
    }
    ^ out
}

// Concatenate `str` with itself `times` times. times ≤ 0 yields empty.
@ string_repeat String str i times → String {
    : i n ( string_len str )
    : i want ? > times 0 * n times 0
    : String out ( string_with_cap want )
    : ~ i k 0
    ~ < k times {
        ( string_push_str out ( string_data str ) )
        = k + k 1
    }
    ^ out
}

// Strip leading whitespace bytes (nurl_is_space).
@ string_trim_start String str → String {
    : i n ( string_len str )
    : ~ i start 0
    : ~ b more T
    ~ more {
        ? >= start n { = more F } {
            ? == ( nurl_is_space ( string_get str start ) ) 0 { = more F } {
                = start + start 1
            }
        }
    }
    ^ ( string_substr str start - n start )
}

// Strip trailing whitespace bytes.
@ string_trim_end String str → String {
    : i n ( string_len str )
    : ~ i end n
    : ~ b more T
    ~ more {
        ? <= end 0 { = more F } {
            ? == ( nurl_is_space ( string_get str - end 1 ) ) 0 { = more F } {
                = end - end 1
            }
        }
    }
    ^ ( string_substr str 0 end )
}

// Strip both leading and trailing whitespace.
@ string_trim String str → String {
    : i n ( string_len str )
    : ~ i start 0
    : ~ b more T
    ~ more {
        ? >= start n { = more F } {
            ? == ( nurl_is_space ( string_get str start ) ) 0 { = more F } {
                = start + start 1
            }
        }
    }
    : ~ i end n
    = more T
    ~ more {
        ? <= end start { = more F } {
            ? == ( nurl_is_space ( string_get str - end 1 ) ) 0 { = more F } {
                = end - end 1
            }
        }
    }
    ^ ( string_substr str start - end start )
}

// Split `str` on every non-overlapping occurrence of `sep` (raw `s`).
// Always returns at least one element. Empty separator → single-element
// Vec containing a copy of the whole string. Adjacent separators and
// separators at the boundaries produce empty String elements, mirroring
// Rust's `str::split` semantics.
@ string_split String str s sep → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( string_len str )
    : i slen ( nurl_str_len sep )
    ? == slen 0 {
        ( vec_push [String] out ( string_from ( string_data str ) ) )
        ^ out
    } {}

    : ~ i start 0
    : ~ b going T
    ~ going {
        : s cur # s + # i ( string_data str ) start
        : i found ( nurl_str_find cur sep )
        ? < found 0 {
            ( vec_push [String] out ( string_substr str start - n start ) )
            = going F
        } {
            ( vec_push [String] out ( string_substr str start found ) )
            = start + start + found slen
        }
    }
    ^ out
}

// Replace every non-overlapping occurrence of `from` in `str` with `to`.
// Empty `from` is a no-op (returns a copy of `str`); matching stops at
// byte boundaries, no regex.
@ string_replace String str s from s to → String {
    : i flen ( nurl_str_len from )
    ? == flen 0 { ^ ( string_from ( string_data str ) ) } {}

    : i n ( string_len str )
    : String out ( string_with_cap n )
    : ~ i start 0
    : ~ b going T
    ~ going {
        : s cur # s + # i ( string_data str ) start
        : i found ( nurl_str_find cur from )
        ? < found 0 {
            ( string_push_str out cur )
            = going F
        } {
            ? > found 0 {
                : s chunk ( nurl_str_slice cur 0 found )
                ( string_push_str out chunk )
            } {}
            ( string_push_str out to )
            = start + start + found flen
        }
    }
    ^ out
}
