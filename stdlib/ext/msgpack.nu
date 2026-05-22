// stdlib/ext/msgpack.nu — MessagePack codec
//
// A faithful binary codec between the `Json` value from stdlib/ext/json.nu
// and the MessagePack wire format (https://msgpack.org/). MessagePack is
// a compact, schemaless binary form of the same data model as JSON, so a
// `Json` tree round-trips through it losslessly (within the limits noted
// below).
//
//   ( msgpack_encode j )      → ! ( Vec u ) MsgpackErr   Json → bytes
//   ( msgpack_decode bytes )  → ! Json MsgpackErr         bytes → Json
//   ( msgpack_err_name e )    → s                          render an error
//
// Mapping:
//   JNull            ↔ nil
//   JBool            ↔ true / false
//   JNum (integer)   ↔ int   (smallest of fixint / int8 / int16 / int32 /
//                              int64 on encode; every int format decoded)
//   JNum (real)      ↔ float64 on encode; float32 AND float64 decoded
//   JStr             ↔ str   (fixstr / str8 / str16 / str32)
//   JArr             ↔ array (fixarray / array16 / array32)
//   JObj             ↔ map   (fixmap / map16 / map32), string keys only
//
// Encoding is exact and the encoder never fails except `MsgpackDepth` on
// a pathologically deep tree (cap 256). The decoder accepts every format
// above in any size. Limits, all surfaced as `MsgpackErr`:
//   * `bin` / `ext` / `fixext` have no faithful `Json` representation —
//     `MsgpackUnsupported`.
//   * a map key that is not a string is `MsgpackUnsupported` (JSON
//     objects are string-keyed).
//   * a truncated input is `MsgpackTruncated`; the reserved byte 0xc1
//     `MsgpackBadType`; trailing bytes after a complete value
//     `MsgpackOther`.
//   * a `uint64` whose value is >= 2^63 decodes to its signed-i64
//     reinterpretation — NURL has no unsigned JSON number type.
//
// Ownership: msgpack_encode returns an owned `Vec[u]`; msgpack_decode
// returns an owned `Json` (free with json_free). Both BORROW their input.

$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/std/bytes.nu`

// IEEE-754 bit access (runtime.c) — `#` casts convert numeric value, not
// bit pattern, so float wire encoding needs these.
& `c` @ nurl_f64_bits      f x    → i
& `c` @ nurl_f64_from_bits i bits → f
& `c` @ nurl_f32_from_bits i bits → f

: | MsgpackErr {
    MsgpackTruncated
    MsgpackBadType
    MsgpackUnsupported
    MsgpackDepth
    MsgpackOther
}

@ msgpack_err_name MsgpackErr e → s {
    ^ ?? e {
        MsgpackTruncated → `truncated input`
        MsgpackBadType → `invalid type byte`
        MsgpackUnsupported → `unsupported type (bin / ext / non-string map key)`
        MsgpackDepth → `nesting too deep`
        MsgpackOther → `malformed msgpack`
    }
}

// Recursion cap — guards both directions against a stack-exhausting
// adversarial tree. JSON nesting beyond this is pathological.
: i MP_MAX_DEPTH 256

// ── Encoder ─────────────────────────────────────────────────────────

@ msgpack_encode Json j → !( Vec u ) MsgpackErr {
    : ( Vec u ) out ( vec_new [u] )
    : i rc ( __mp_enc j out 0 )
    ? != rc 0 {
        ( vec_free [u] out )
        ^ @ !( Vec u ) MsgpackErr { F @ MsgpackErr { MsgpackDepth } }
    } {}
    ^ @ !( Vec u ) MsgpackErr { T out }
}

// Append the encoding of `j` to `out`. Returns 0 on success, 1 when the
// tree is nested past MP_MAX_DEPTH.
@ __mp_enc Json j ( Vec u ) out i depth → i {
    ? > depth MP_MAX_DEPTH { ^ 1 } {}
    ^ ?? j {
        JNull → { ( vec_push [u] out # u 192 ) 0 }
        JBool bv → {
            ? bv { ( vec_push [u] out # u 195 ) } { ( vec_push [u] out # u 194 ) }
            0
        }
        JNum s → { ( __mp_enc_num s out ) 0 }
        JStr s → { ( __mp_enc_str s out ) 0 }
        JArr v → {
            ( __mp_enc_arr_header ( vec_len [Json] v ) out )
            ( __mp_enc_elems v out depth )
        }
        JObj v → {
            ( __mp_enc_map_header / ( vec_len [Json] v ) 2 out )
            ( __mp_enc_elems v out depth )
        }
    }
}

// Encode every element of `v` in order. For a JObj the Vec already
// alternates key, value, key, value — exactly a msgpack map body.
@ __mp_enc_elems ( Vec Json ) v ( Vec u ) out i depth → i {
    : i n ( vec_len [Json] v )
    : ~ i k 0
    : ~ i rc 0
    ~ & < k n == rc 0 {
        ?? ( vec_get [Json] v k ) {
            T e → { = rc ( __mp_enc e out + depth 1 ) }
            F → {}
        }
        = k + k 1
    }
    ^ rc
}

@ __mp_enc_str String s ( Vec u ) out → v {
    : i len ( string_len s )
    ? <= len 31 {
        ( vec_push [u] out # u + 160 len )
    } {
        ? <= len 255 {
            ( vec_push [u] out # u 217 )
            ( vec_push [u] out # u len )
        } {
            ? <= len 65535 {
                ( vec_push [u] out # u 218 )
                ( bytes_push_u16_be out # u16 len )
            } {
                ( vec_push [u] out # u 219 )
                ( bytes_push_u32_be out # u32 len )
            }
        }
    }
    : *u bp # *u ( string_data s )
    : ~ i k 0
    ~ < k len {
        ( vec_push [u] out . bp k )
        = k + k 1
    }
}

// A JNum carries its number as decimal text — classify it, then encode
// as a msgpack integer or a float64.
@ __mp_enc_num String s ( Vec u ) out → v {
    ? ( __mp_num_is_int s ) {
        ?? ( string_to_int s ) {
            T n → ( __mp_enc_int n out )
            F → ( __mp_enc_f64_str s out )
        }
    } {
        ( __mp_enc_f64_str s out )
    }
}

// T unless the text carries a '.', 'e' or 'E' — i.e. it looks integral.
@ __mp_num_is_int String s → b {
    : i n ( string_len s )
    : ~ i k 0
    : ~ b isint T
    ~ & < k n isint {
        : i c ( string_get s k )
        ? | | == c 46 == c 101 == c 69 { = isint F } {}
        = k + k 1
    }
    ^ isint
}

@ __mp_enc_f64_str String s ( Vec u ) out → v {
    : f x ?? ( string_to_float s ) { T fv → fv F → 0.0 }
    ( __mp_enc_f64 x out )
}

@ __mp_enc_f64 f x ( Vec u ) out → v {
    ( vec_push [u] out # u 203 )
    ( bytes_push_u64_be out # u64 ( nurl_f64_bits x ) )
}

// Smallest signed format that holds `n`: positive / negative fixint,
// then int8 / int16 / int32 / int64.
@ __mp_enc_int i n ( Vec u ) out → v {
    ? & >= n 0 <= n 127 {
        ( vec_push [u] out # u n )
    } {
        ? & >= n -32 < n 0 {
            ( vec_push [u] out # u & n 255 )
        } {
            ? & >= n -128 <= n 127 {
                ( vec_push [u] out # u 208 )
                ( vec_push [u] out # u & n 255 )
            } {
                ? & >= n -32768 <= n 32767 {
                    ( vec_push [u] out # u 209 )
                    ( bytes_push_u16_be out # u16 n )
                } {
                    ? & >= n -2147483648 <= n 2147483647 {
                        ( vec_push [u] out # u 210 )
                        ( bytes_push_u32_be out # u32 n )
                    } {
                        ( vec_push [u] out # u 211 )
                        ( bytes_push_u64_be out # u64 n )
                    }
                }
            }
        }
    }
}

@ __mp_enc_arr_header i n ( Vec u ) out → v {
    ? <= n 15 {
        ( vec_push [u] out # u + 144 n )
    } {
        ? <= n 65535 {
            ( vec_push [u] out # u 220 )
            ( bytes_push_u16_be out # u16 n )
        } {
            ( vec_push [u] out # u 221 )
            ( bytes_push_u32_be out # u32 n )
        }
    }
}

@ __mp_enc_map_header i n ( Vec u ) out → v {
    ? <= n 15 {
        ( vec_push [u] out # u + 128 n )
    } {
        ? <= n 65535 {
            ( vec_push [u] out # u 222 )
            ( bytes_push_u16_be out # u16 n )
        } {
            ( vec_push [u] out # u 223 )
            ( bytes_push_u32_be out # u32 n )
        }
    }
}

// ── Decoder ─────────────────────────────────────────────────────────

// Cursor over the input buffer. `data` is a borrowed pointer into the
// caller's Vec — valid for the whole msgpack_decode call.
: MsgpackDec { s data i len i pos }

@ __md_new ( Vec u ) v → *MsgpackDec {
    : *MsgpackDec p # *MsgpackDec ( nurl_alloc Z MsgpackDec )
    = . p data # s ( vec_data [u] v )
    = . p len ( vec_len [u] v )
    = . p pos 0
    ^ p
}

@ __md_free *MsgpackDec p → v {
    ( nurl_free # s p )
}

@ __md_remaining *MsgpackDec p → i {
    ^ - . p len . p pos
}

// Read one byte (0..255) and advance. Caller has checked availability.
@ __md_u8 *MsgpackDec p → i {
    : *u d # *u . p data
    : i idx . p pos
    : i bb & 255 # i . d idx
    = . p pos + idx 1
    ^ bb
}

// Read `nbytes` big-endian into an unsigned accumulator. Caller has
// checked availability.
@ __md_read_len *MsgpackDec p i nbytes → i {
    : ~ i val 0
    : ~ i k 0
    ~ < k nbytes {
        = val + * val 256 ( __md_u8 p )
        = k + k 1
    }
    ^ val
}

@ msgpack_decode ( Vec u ) v → !Json MsgpackErr {
    : *MsgpackDec p ( __md_new v )
    : !Json MsgpackErr r ( __md_value p 0 )
    ?? r {
        T jv → {
            // A msgpack document is exactly one value — trailing bytes
            // mean a malformed input.
            ? > ( __md_remaining p ) 0 {
                ( json_free jv )
                ( __md_free p )
                ^ @ !Json MsgpackErr { F @ MsgpackErr { MsgpackOther } }
            } {}
            ( __md_free p )
            ^ @ !Json MsgpackErr { T jv }
        }
        F e → {
            ( __md_free p )
            ^ @ !Json MsgpackErr { F e }
        }
    }
}

@ __md_value *MsgpackDec p i depth → !Json MsgpackErr {
    ? > depth MP_MAX_DEPTH {
        ^ @ !Json MsgpackErr { F @ MsgpackErr { MsgpackDepth } }
    } {}
    ? < ( __md_remaining p ) 1 {
        ^ @ !Json MsgpackErr { F @ MsgpackErr { MsgpackTruncated } }
    } {}
    : i t ( __md_u8 p )
    // Range-encoded headers: positive / negative fixint, fixstr,
    // fixarray, fixmap.
    ? <= t 127 { ^ @ !Json MsgpackErr { T ( json_int t ) } } {}
    ? >= t 224 { ^ @ !Json MsgpackErr { T ( json_int - t 256 ) } } {}
    ? & >= t 160 <= t 191 { ^ ( __md_read_str p - t 160 ) } {}
    ? & >= t 144 <= t 159 { ^ ( __md_read_arr p - t 144 depth ) } {}
    ? & >= t 128 <= t 143 { ^ ( __md_read_map p - t 128 depth ) } {}
    // Fixed type bytes.
    ^ ?? t {
        192 → @ !Json MsgpackErr { T ( json_null ) }
        194 → @ !Json MsgpackErr { T ( json_bool F ) }
        195 → @ !Json MsgpackErr { T ( json_bool T ) }
        202 → ( __md_read_f32 p )
        203 → ( __md_read_f64 p )
        204 → ( __md_read_uint p 1 )
        205 → ( __md_read_uint p 2 )
        206 → ( __md_read_uint p 4 )
        207 → ( __md_read_uint p 8 )
        208 → ( __md_read_int p 1 )
        209 → ( __md_read_int p 2 )
        210 → ( __md_read_int p 4 )
        211 → ( __md_read_int p 8 )
        217 → ( __md_read_str_n p 1 )
        218 → ( __md_read_str_n p 2 )
        219 → ( __md_read_str_n p 4 )
        220 → ( __md_read_arr_n p 2 depth )
        221 → ( __md_read_arr_n p 4 depth )
        222 → ( __md_read_map_n p 2 depth )
        223 → ( __md_read_map_n p 4 depth )
        _ → @ !Json MsgpackErr { F ( __md_classify_bad t ) }
    }
}

// bin8/16/32 (196-198), ext8/16/32 (199-201) and fixext1..16 (212-216)
// have no Json mapping; 0xc1 (193) is reserved/never-used.
@ __md_classify_bad i t → MsgpackErr {
    ? & >= t 196 <= t 201 { ^ @ MsgpackErr { MsgpackUnsupported } } {}
    ? & >= t 212 <= t 216 { ^ @ MsgpackErr { MsgpackUnsupported } } {}
    ^ @ MsgpackErr { MsgpackBadType }
}

@ __md_read_uint *MsgpackDec p i nbytes → !Json MsgpackErr {
    ? < ( __md_remaining p ) nbytes {
        ^ @ !Json MsgpackErr { F @ MsgpackErr { MsgpackTruncated } }
    } {}
    ^ @ !Json MsgpackErr { T ( json_int ( __md_read_len p nbytes ) ) }
}

@ __md_read_int *MsgpackDec p i nbytes → !Json MsgpackErr {
    ? < ( __md_remaining p ) nbytes {
        ^ @ !Json MsgpackErr { F @ MsgpackErr { MsgpackTruncated } }
    } {}
    : ~ i val ( __md_read_len p nbytes )
    // Sign-extend from an nbytes*8-bit field. For nbytes == 8 the
    // accumulator already holds the signed i64 bit-for-bit.
    ? < nbytes 8 {
        : i bits * nbytes 8
        ? != 0 & val << 1 - bits 1 {
            = val - val << 1 bits
        } {}
    } {}
    ^ @ !Json MsgpackErr { T ( json_int val ) }
}

@ __md_read_f32 *MsgpackDec p → !Json MsgpackErr {
    ? < ( __md_remaining p ) 4 {
        ^ @ !Json MsgpackErr { F @ MsgpackErr { MsgpackTruncated } }
    } {}
    ^ @ !Json MsgpackErr { T ( json_float ( nurl_f32_from_bits ( __md_read_len p 4 ) ) ) }
}

@ __md_read_f64 *MsgpackDec p → !Json MsgpackErr {
    ? < ( __md_remaining p ) 8 {
        ^ @ !Json MsgpackErr { F @ MsgpackErr { MsgpackTruncated } }
    } {}
    ^ @ !Json MsgpackErr { T ( json_float ( nurl_f64_from_bits ( __md_read_len p 8 ) ) ) }
}

@ __md_read_str *MsgpackDec p i len → !Json MsgpackErr {
    ? < ( __md_remaining p ) len {
        ^ @ !Json MsgpackErr { F @ MsgpackErr { MsgpackTruncated } }
    } {}
    : String s ( string_with_cap + len 1 )
    : ~ i k 0
    ~ < k len {
        ( string_push_char s ( __md_u8 p ) )
        = k + k 1
    }
    ^ @ !Json MsgpackErr { T @ Json { JStr s } }
}

@ __md_read_str_n *MsgpackDec p i lenbytes → !Json MsgpackErr {
    ? < ( __md_remaining p ) lenbytes {
        ^ @ !Json MsgpackErr { F @ MsgpackErr { MsgpackTruncated } }
    } {}
    ^ ( __md_read_str p ( __md_read_len p lenbytes ) )
}

@ __md_read_arr *MsgpackDec p i count i depth → !Json MsgpackErr {
    : ( Vec Json ) elems ( vec_new [Json] )
    : ~ i k 0
    : ~ b failed F
    : ~ MsgpackErr err MsgpackOther
    ~ & < k count == failed F {
        ?? ( __md_value p + depth 1 ) {
            T jv → ( vec_push [Json] elems jv )
            F e → { = failed T = err e }
        }
        = k + k 1
    }
    ? failed {
        ( __mp_free_json_vec elems )
        ^ @ !Json MsgpackErr { F err }
    } {}
    ^ @ !Json MsgpackErr { T @ Json { JArr elems } }
}

@ __md_read_arr_n *MsgpackDec p i lenbytes i depth → !Json MsgpackErr {
    ? < ( __md_remaining p ) lenbytes {
        ^ @ !Json MsgpackErr { F @ MsgpackErr { MsgpackTruncated } }
    } {}
    ^ ( __md_read_arr p ( __md_read_len p lenbytes ) depth )
}

@ __md_read_map *MsgpackDec p i count i depth → !Json MsgpackErr {
    : ( Vec Json ) elems ( vec_new [Json] )
    : ~ i k 0
    : ~ b failed F
    : ~ MsgpackErr err MsgpackOther
    ~ & < k count == failed F {
        ?? ( __md_value p + depth 1 ) {
            T jk → {
                ? ( json_is_str jk ) {
                    ?? ( __md_value p + depth 1 ) {
                        T jv → {
                            ( vec_push [Json] elems jk )
                            ( vec_push [Json] elems jv )
                        }
                        F e → {
                            = failed T
                            = err e
                            ( json_free jk )
                        }
                    }
                } {
                    = failed T
                    = err @ MsgpackErr { MsgpackUnsupported }
                    ( json_free jk )
                }
            }
            F e → { = failed T = err e }
        }
        = k + k 1
    }
    ? failed {
        ( __mp_free_json_vec elems )
        ^ @ !Json MsgpackErr { F err }
    } {}
    ^ @ !Json MsgpackErr { T @ Json { JObj elems } }
}

@ __md_read_map_n *MsgpackDec p i lenbytes i depth → !Json MsgpackErr {
    ? < ( __md_remaining p ) lenbytes {
        ^ @ !Json MsgpackErr { F @ MsgpackErr { MsgpackTruncated } }
    } {}
    ^ ( __md_read_map p ( __md_read_len p lenbytes ) depth )
}

@ __mp_free_json_vec ( Vec Json ) v → v {
    : ( @ v Json ) drop \ Json e → v { ( json_free e ) }
    ( vec_free_with [Json] v drop )
}
