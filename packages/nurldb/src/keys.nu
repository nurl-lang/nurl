// packages/nurldb/src/keys.nu — index keys as bytes that sort the way the
// values do.
//
// An index compares keys with one memcmp (btree.nu), so a key is encoded
// once, when it is made, into bytes whose order is the values' order:
//
//   NULL    0x00                       (sorts first)
//   INT     0x01, the value with its sign bit flipped, big-endian
//   REAL    0x01, the IEEE bits — all flipped when negative, the sign
//           bit flipped when not — big-endian
//   BOOL    0x01, 0 or 1
//   TEXT    0x01, the bytes with each 0x00 written 0x00 0xFF, then
//           0x00 0x00 (so a prefix sorts before what it prefixes)
//
// A column's values are all of the column's type (the planner converts a
// constant compared with it first), so the encodings of different types
// never meet. An entry's key is its columns' encodings and then the TID
// of the row version it points at, big-endian: entries are unique, and
// the versions of one value lie together in TID order.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/floatbits.nu`
$ `value.nu`

: i MIN_I64 -9223372036854775808

@ __key_be64 ( Vec u ) out i x → v {
    : ~ i sh 56
    ~ >= sh 0 {
        ( vec_push [u] out # u & >> x sh 255 )
        = sh - sh 8
    }
}

// Append the encoding of `v`, a value of column type `ty`.
@ key_put ( Vec u ) out Value v i ty → v {
    ?? v {
        VNull → { ( vec_push [u] out # u 0 ) }
        VInt x → {
            ( vec_push [u] out # u 1 )
            ? == ty TY_REAL { ( __key_real out # f x ) } { ( __key_be64 out ^^ x MIN_I64 ) }
        }
        VReal x → { ( vec_push [u] out # u 1 ) ( __key_real out x ) }
        VBool x → { ( vec_push [u] out # u 1 ) ( vec_push [u] out # u ? x 1 0 ) }
        VText s → {
            ( vec_push [u] out # u 1 )
            : ( Slice u ) b ( string_bytes s )
            : ~ i k 0
            ~ < k ( slice_len [u] b ) {
                : i c ( slice_byte b k )
                ( vec_push [u] out # u c )
                ? == c 0 { ( vec_push [u] out # u 255 ) } {}
                = k + k 1
            }
            ( vec_push [u] out # u 0 ) ( vec_push [u] out # u 0 )
        }
    }
}

@ __key_real ( Vec u ) out f x → v {
    : i bits ( f64_to_bits x )
    ( __key_be64 out ? < bits 0 ^^ bits -1 ^^ bits MIN_I64 )
}

// The key of `row`'s columns `cols` (of types `types`), and then `tid`.
@ key_of_row ( Vec Value ) row ( Vec i ) cols ( Vec i ) types i tid → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] 32 )
    : ~ i k 0
    ~ < k ( vec_len [i] cols ) {
        ( key_put out ( vec_at [Value] row ( vec_at [i] cols k ) ) ( vec_at [i] types k ) )
        = k + k 1
    }
    ( __key_be64 out tid )
    ^ out
}

// The TID a full entry key ends with.
@ key_tid ( Slice u ) key → i {
    : i n ( slice_len [u] key )
    : ~ i t 0
    : ~ i k - n 8
    ~ < k n {
        = t | << t 8 # i ( slice_byte key k )
        = k + k 1
    }
    ^ t
}

// The bounds of every entry whose columns encode as `prefix`: from the
// prefix with the lowest TID to the prefix with the highest (inclusive).
@ key_lo ( Slice u ) prefix → ( Vec u ) {
    : ( Vec u ) out ( slice_to_vec [u] prefix )
    ( __key_be64 out 0 )
    ^ out
}

@ key_hi ( Slice u ) prefix → ( Vec u ) {
    : ( Vec u ) out ( slice_to_vec [u] prefix )
    ( __key_be64 out -1 )
    ^ out
}

// Does `key` start with `prefix`?
@ key_has_prefix ( Slice u ) key ( Slice u ) prefix → b {
    : i n ( slice_len [u] prefix )
    ? > n ( slice_len [u] key ) { ^ F } {}
    ^ == ( slice_bytes_cmp ( slice_prefix [u] key n ) prefix ) 0
}
