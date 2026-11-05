// packages/nurldb/src/value.nu — SQL values, and a row's bytes.
//
// A value is NULL or one of four types. A row is a ( Vec Value ); on a
// page it is encoded after the tuple header (heap.nu) as a null bitmap
// and the non-null columns in order:
//
//   INT   8 bytes, little-endian two's complement
//   REAL  8 bytes, the IEEE 754 bits
//   BOOL  1 byte
//   TEXT  u32 length, then the bytes — or, for a value kept out of line
//         on overflow pages (ovf.nu), u32 length | 2^31 and the u32
//         number of its first page
//
// Values compare the way SQL orders them within one type (NULL sorts
// first, and = with NULL is decided by the caller: SQL's three-valued
// logic lives in the expression evaluator, expr.nu).

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/float.nu`

: i TY_INT 1
: i TY_REAL 2
: i TY_TEXT 3
: i TY_BOOL 4

: | Value {
    VNull
    VInt i
    VReal f
    VText String
    VBool b
}

@ ty_name i t → s {
    ? == t TY_INT { ^ `INT` } {}
    ? == t TY_REAL { ^ `REAL` } {}
    ? == t TY_TEXT { ^ `TEXT` } {}
    ? == t TY_BOOL { ^ `BOOL` } {}
    ^ `?`
}

@ val_is_null Value v → b { ^ ?? v { VNull → T _ → F } }

@ val_type Value v → i {
    ^ ?? v { VNull → 0 VInt _ → TY_INT VReal _ → TY_REAL VText _ → TY_TEXT VBool _ → TY_BOOL }
}

// Three-way order of two non-null values of one type (or an INT and a
// REAL, compared numerically). -2: the types cannot be compared.
@ val_cmp Value a Value b → i {
    ^ ?? a {
        VInt x → ?? b {
            VInt y → ? < x y -1 ? > x y 1 0
            VReal y → ( __cmp_f # f x y )
            _ → -2
        }
        VReal x → ?? b {
            VReal y → ( __cmp_f x y )
            VInt y → ( __cmp_f x # f y )
            _ → -2
        }
        VText x → ?? b {
            VText y → ( slice_bytes_cmp ( string_bytes x ) ( string_bytes y ) )
            _ → -2
        }
        VBool x → ?? b {
            VBool y → ? == x y 0 ? x 1 -1
            _ → -2
        }
        VNull → -2
    }
}

@ __cmp_f f x f y → i { ^ ? < x y -1 ? > x y 1 0 }

// The order a sort and an index use: NULL first, then by value; values of
// types that do not compare order by their type tag.
@ val_order Value a Value b → i {
    : b an ( val_is_null a )
    : b bn ( val_is_null b )
    ? & an bn { ^ 0 } {}
    ? an { ^ -1 } {}
    ? bn { ^ 1 } {}
    : i c ( val_cmp a b )
    ? == c -2 {
        : i ta ( val_type a )
        : i tb ( val_type b )
        ^ ? < ta tb -1 1
    } {}
    ^ c
}

@ val_eq Value a Value b → b { ^ == ( val_order a b ) 0 }

@ val_clone Value v → Value { ^ ( mem_dup v ) }

// A 64-bit hash, equal for values val_eq calls equal (an INT and the
// equal REAL included).
@ val_hash Value v → i {
    ^ ?? v {
        VNull → 0
        VInt x → ( __mix x )
        VReal x → ( __hash_real x )
        VText s → ( __hash_bytes ( string_bytes s ) )
        VBool x → ? x 1 2
    }
}

// A REAL holding a whole number hashes as that INT (they compare equal).
@ __hash_real f x → i {
    ? & & == x ( float_trunc x ) < ( float_abs x ) 9.0e18 ! ( float_is_nan x ) { ^ ( __mix # i x ) } {}
    ^ ( __mix ( f64_to_bits x ) )
}

@ __mix i x → i {
    : i a * ^^ x >> x 31 -7046029254386353131
    : i b * ^^ a >> a 29 -4658895280553007687
    ^ ^^ b >> b 32
}

@ __hash_bytes ( Slice u ) b → i {
    : ~ i h -3750763034362895579
    : ~ i k 0
    ~ < k ( slice_len [u] b ) {
        = h * ^^ h ( slice_byte b k ) 1099511628211
        = k + k 1
    }
    ^ ( __mix h )
}

// The value as text (what the shell prints).
@ val_text Value v → String {
    ^ ?? v {
        VNull → ( string_from `NULL` )
        VInt x → ( string_from ( nurl_str_int x ) )
        VReal x → ( string_from ( nurl_str_float x ) )
        VText s → ( string_clone s )
        VBool x → ( string_from ? x `true` `false` )
    }
}

// ── row bytes ──────────────────────────────────────────────────────────

// A TEXT length with this bit set names a value kept out of line.
: i TEXT_OUT 2147483648

// The bytes a value kept out of line takes in its row: its length and
// its first overflow page.
: i TEXT_OUT_SIZE 8

// Column `k`'s first overflow page, or 0 when it is in the row (`ext` is
// empty when every column is).
@ __ext_at ( Vec i ) ext i k → i { ^ ? < k ( vec_len [i] ext ) ( vec_at [i] ext k ) 0 }

// The encoded size of `row`'s columns (bitmap included).
@ row_size ( Vec Value ) row → i { ^ ( row_size_ext row ( vec_new [i] ) ) }

// The same, with the TEXT columns `ext` names kept out of line.
@ row_size_ext ( Vec Value ) row ( Vec i ) ext → i {
    : i n ( vec_len [Value] row )
    : ~ i size / + n 7 8
    : ~ i k 0
    ~ c row {
        : i out ( __ext_at ext k )
        = size + size ?? c { VNull → 0 VInt _ → 8 VReal _ → 8 VBool _ → 1 VText s → ? > out 0 TEXT_OUT_SIZE + 4 ( string_len s ) }
        = k + k 1
    }
    ^ size
}

// Encode `row` at `off` of `dst` (which holds row_size bytes from there).
@ row_encode ( Vec Value ) row ( Slice u ) dst i off → v { ( row_encode_ext row ( vec_new [i] ) dst off ) }

// The same, with the TEXT columns `ext` names kept out of line: column k,
// when ext[k] > 0, is stored as its length and ext[k], the first of the
// overflow pages that hold its bytes.
@ row_encode_ext ( Vec Value ) row ( Vec i ) ext ( Slice u ) dst i off → v {
    : i n ( vec_len [Value] row )
    : i nb / + n 7 8
    : ~ i k 0
    ~ < k nb { ( slice_put [u] dst + off k # u 0 ) = k + k 1 }
    : ~ i at + off nb
    = k 0
    ~ c row {
        ?? c {
            VNull → {
                : i bi + off / k 8
                ( slice_put [u] dst bi # u | # i ( slice_at [u] dst bi ) << 1 % k 8 )
            }
            VInt x → { ( slice_put_u64_le dst at x ) = at + at 8 }
            VReal x → { ( slice_put_u64_le dst at ( f64_to_bits x ) ) = at + at 8 }
            VBool x → { ( slice_put [u] dst at # u ? x 1 0 ) = at + at 1 }
            VText s → {
                : i len ( string_len s )
                : i out ( __ext_at ext k )
                ? > out 0 {
                    ( slice_put_u32_le dst at | len TEXT_OUT )
                    ( slice_put_u32_le dst + at 4 out )
                    = at + at TEXT_OUT_SIZE
                } {
                    ( slice_put_u32_le dst at len )
                    ( slice_copy [u] ( slice_window [u] dst + at 4 len ) ( string_bytes s ) )
                    = at + + at 4 len
                }
            }
        }
        = k + k 1
    }
}

// Decode `ncols` columns of the types `types` from `src` at `off`. A TEXT
// column kept out of line decodes as NULL, and its column, length and
// first overflow page are appended to `outs` (three entries each): the
// caller reads the value from its pages (ovf.nu's tuple_row_full).
@ row_decode ( Slice u ) src i off ( Vec i ) types inout ( Vec i ) outs → ( Vec Value ) {
    : i n ( vec_len [i] types )
    : i nb / + n 7 8
    : ( Vec Value ) row ( vec_with_cap [Value] n )
    : ~ i at + off nb
    : ~ i k 0
    ~ < k n {
        : b null != 0 & >> # i ( slice_at [u] src + off / k 8 ) % k 8 1
        ? null { ( vec_push [Value] row @ Value { VNull } ) } {
            : i t ( vec_at [i] types k )
            ? == t TY_INT { ( vec_push [Value] row @ Value { VInt ( slice_u64_le src at ) } ) = at + at 8 } {}
            ? == t TY_REAL { ( vec_push [Value] row @ Value { VReal ( bits_to_f64 ( slice_u64_le src at ) ) } ) = at + at 8 } {}
            ? == t TY_BOOL { ( vec_push [Value] row @ Value { VBool != 0 # i ( slice_at [u] src at ) } ) = at + at 1 } {}
            ? == t TY_TEXT {
                : i len ( slice_u32_le src at )
                ? != 0 & len TEXT_OUT {
                    ( vec_push [i] outs k )
                    ( vec_push [i] outs & len - TEXT_OUT 1 )
                    ( vec_push [i] outs ( slice_u32_le src + at 4 ) )
                    ( vec_push [Value] row @ Value { VNull } )
                    = at + at TEXT_OUT_SIZE
                } {
                    : String s ( string_new )
                    ( string_push_window s src + at 4 len )
                    ( vec_push [Value] row @ Value { VText s } )
                    = at + + at 4 len
                }
            } {}
        }
        = k + k 1
    }
    ^ row
}
