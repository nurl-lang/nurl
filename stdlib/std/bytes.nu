// stdlib/std/bytes.nu — byte buffers built on Vec[u]
//
// `( Vec u )` is the canonical NURL byte buffer. All Vec[A] operations
// already work with `[u]`-instantiation (push/pop/get/set/len/cap/data
// /clear/extend/each/fold/free); this module adds byte-specific
// helpers that don't exist on the generic Vec.
//
//   ( bytes_from_str raw )     → ( Vec u )         copy NUL-terminated
//                                                  string (excluding the
//                                                  NUL); for an owned
//                                                  String pass
//                                                  `( string_data str )`.
//   ( bytes_to_str v )         → String            copy bytes into a
//                                                  String (the SB appends
//                                                  the NUL terminator).
//   ( bytes_to_hex v )         → String            lowercase 2 chars/byte
//   ( bytes_from_hex raw )     → ! ( Vec u ) ParseErr
//   ( bytes_eq a b )           → b                 byte-by-byte equality
//   ( bytes_find_byte v t )    → ? i               first index of byte t
//   ( bytes_extend_str v raw ) → v                 append from NUL string
//
// Memory model: byte buffers are owned heap allocations; free with
// `( vec_free [u] v )`. Borrowed pointers (e.g. `bytes_data`) must not
// outlive the Vec.
//
// Example — read a file, hex-encode, write the digest back out:
//   : ! ( Vec u ) IoErr r ( read_file_bytes `input.bin` )
//   ?? r {
//     T v → {
//       : String hex ( bytes_to_hex v )
//       ( println ( string_data hex ) )
//       ( string_free hex )
//       ( vec_free [u] v )
//     }
//     F e → ( eprintln ( io_err_msg # IoErr e ) )
//   }

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/errors.nu`

// ── Construction from raw / String ─────────────────────────────────

@ bytes_from_str s raw → ( Vec u ) {
  : i n ( nurl_str_len raw )
  : ( Vec u ) v ( vec_with_cap [u] n )
  : ~ i k 0
  ~ < k n {
    ( vec_push [u] v # u ( nurl_str_get raw k ) )
    = k + k 1
  }
  ^ v
}

// Append the bytes of `raw` (NUL-terminated, excluding NUL) onto `v`.
@ bytes_extend_str ( Vec u ) v s raw → v {
  : i n ( nurl_str_len raw )
  ( vec_reserve [u] v n )
  : ~ i k 0
  ~ < k n {
    ( vec_push [u] v # u ( nurl_str_get raw k ) )
    = k + k 1
  }
}

// Append the decimal-text bytes of `n` onto `v` (no leading zeros, '-' for
// negatives). Convenience over `bytes_extend_str ( nurl_str_int n )` —
// hides the malloc'd intermediate from caller-side accounting.
@ bytes_push_int ( Vec u ) v i n → v {
  ( bytes_extend_str v ( nurl_str_int n ) )
}

// Append the default float formatting (`%g`) of `x` onto `v`.
@ bytes_push_float ( Vec u ) v f x → v {
  ( bytes_extend_str v ( nurl_str_float x ) )
}

// Copy the bytes of `v` into a fresh owned String. The SB appends a
// trailing NUL automatically. NUL bytes inside `v` are stored verbatim
// — `string_data` returns the buffer up to the first NUL, so if you
// want the full contents iterate the bytes manually.
@ bytes_to_str ( Vec u ) v → String {
  : i n ( vec_len [u] v )
  : String out ( string_with_cap n )
  : ~ i k 0
  ~ < k n {
    : ? u got ( vec_get [u] v k )
    ?? got {
      T b → ( string_push_char out # i b )
      F _ → {}
    }
    = k + k 1
  }
  ^ out
}

// ── Hex round-trip ─────────────────────────────────────────────────

@ __byte_hex_hi i b → i {
  : i n & 15 / b 16
  ? < n 10 { ^ + 48 n } {}
  ^ + 87 n
}

@ __byte_hex_lo i b → i {
  : i n & b 15
  ? < n 10 { ^ + 48 n } {}
  ^ + 87 n
}

@ bytes_to_hex ( Vec u ) v → String {
  : i n ( vec_len [u] v )
  : String out ( string_with_cap * n 2 )
  : ~ i k 0
  ~ < k n {
    : ? u got ( vec_get [u] v k )
    ?? got {
      T b → {
        : i ib # i b
        ( string_push_char out ( __byte_hex_hi ib ) )
        ( string_push_char out ( __byte_hex_lo ib ) )
      }
      F _ → {}
    }
    = k + k 1
  }
  ^ out
}

@ __hex_byte_value i c → i {
  ? & >= c 48 <= c 57  { ^ - c 48 } {}
  ? & >= c 97 <= c 102 { ^ + 10 - c 97 } {}
  ? & >= c 65 <= c 70  { ^ + 10 - c 65 } {}
  ^ -1
}

@ bytes_from_hex s raw → ! ( Vec u ) ParseErr {
  : i n ( nurl_str_len raw )
  ? == n 0 { ^ @ ! ( Vec u ) ParseErr { F @ ParseErr { Empty } } } {}
  ? != 0 & n 1 {
    ^ @ ! ( Vec u ) ParseErr { F @ ParseErr { BadFormat } }
  } {}
  : ( Vec u ) v ( vec_with_cap [u] / n 2 )
  : ~ i k 0
  ~ < k n {
    : i hi ( __hex_byte_value ( nurl_str_get raw k ) )
    : i lo ( __hex_byte_value ( nurl_str_get raw + k 1 ) )
    ? | < hi 0 < lo 0 {
      ( vec_free [u] v )
      ^ @ ! ( Vec u ) ParseErr { F @ ParseErr { BadFormat } }
    } {}
    ( vec_push [u] v # u + lo * hi 16 )
    = k + k 2
  }
  ^ @ ! ( Vec u ) ParseErr { T v }
}

// ── Equality ────────────────────────────────────────────────────────

@ bytes_eq ( Vec u ) a ( Vec u ) b → b {
  : i la ( vec_len [u] a )
  : i lb ( vec_len [u] b )
  ? != la lb { ^ F } {}
  : *u pa ( vec_data [u] a )
  : *u pb ( vec_data [u] b )
  : ~ i k 0
  ~ < k la {
    : u xa . pa k
    : u xb . pb k
    ? != xa xb { ^ F } {}
    = k + k 1
  }
  ^ T
}

// ── Search ──────────────────────────────────────────────────────────

@ bytes_find_byte ( Vec u ) v u target → ? i {
  : i n ( vec_len [u] v )
  : *u p ( vec_data [u] v )
  : ~ i k 0
  ~ < k n {
    : u x . p k
    ? == x target { ^ @ ? i { T k } } {}
    = k + k 1
  }
  ^ @ ? i { F 0 }
}

// First index where `needle` starts inside `v`. Empty needle → 0
// (mirrors `string_index_of`'s convention). Returns None if no match.
@ bytes_index_of ( Vec u ) v ( Vec u ) needle → ? i {
  : i n ( vec_len [u] v )
  : i m ( vec_len [u] needle )
  ? == m 0 { ^ @ ? i { T 0 } } {}
  ? > m n { ^ @ ? i { F 0 } } {}
  : *u p ( vec_data [u] v )
  : *u q ( vec_data [u] needle )
  : i last + - n m 1
  : ~ i k 0
  ~ < k last {
    : ~ i j 0
    : ~ b ok T
    ~ < j m {
      : u x . p + k j
      : u y . q j
      ? != x y { = ok F = j m } { = j + j 1 }
    }
    ? ok { ^ @ ? i { T k } } {}
    = k + k 1
  }
  ^ @ ? i { F 0 }
}

// ── Prefix / suffix ────────────────────────────────────────────────

@ bytes_starts_with ( Vec u ) v ( Vec u ) prefix → b {
  : i n ( vec_len [u] v )
  : i m ( vec_len [u] prefix )
  ? > m n { ^ F } {}
  : *u p ( vec_data [u] v )
  : *u q ( vec_data [u] prefix )
  : ~ i k 0
  ~ < k m {
    : u x . p k
    : u y . q k
    ? != x y { ^ F } {}
    = k + k 1
  }
  ^ T
}

@ bytes_ends_with ( Vec u ) v ( Vec u ) suffix → b {
  : i n ( vec_len [u] v )
  : i m ( vec_len [u] suffix )
  ? > m n { ^ F } {}
  : *u p ( vec_data [u] v )
  : *u q ( vec_data [u] suffix )
  : i base - n m
  : ~ i k 0
  ~ < k m {
    : u x . p + base k
    : u y . q k
    ? != x y { ^ F } {}
    = k + k 1
  }
  ^ T
}

// ── Slice (copy) ───────────────────────────────────────────────────

// Copy the half-open range [from, to) of `v` into a fresh owned Vec[u].
// Both bounds are clamped to [0, len]; if the resulting range is empty
// (or inverted) the returned Vec has len 0. Caller owns the result and
// must `( vec_free [u] out )`.
@ bytes_slice ( Vec u ) v i from i to → ( Vec u ) {
  : i n ( vec_len [u] v )
  : ~ i lo from
  : ~ i hi to
  ? < lo 0 { = lo 0 } {}
  ? > lo n { = lo n } {}
  ? < hi lo { = hi lo } {}
  ? > hi n { = hi n } {}
  : i len - hi lo
  : ( Vec u ) out ( vec_with_cap [u] len )
  ? > len 0 {
    : *u p ( vec_data [u] v )
    : ~ i k 0
    ~ < k len {
      ( vec_push [u] out . p + lo k )
      = k + k 1
    }
  } {}
  ^ out
}
