// stdlib/ext/cbor.nu — CBOR (RFC 8949) over the shared Json value.
//
// The IETF-standard binary serialization (used by COSE / WebAuthn / CTAP /
// many IoT protocols), the sibling of MessagePack. Like ext/msgpack.nu it
// works on the `Json` value, so every `json_*` accessor / `json_free` /
// `json_stringify` operates on a decoded document:
//
//   ( cbor_encode Json j )       → !( Vec u ) CborErr
//   ( cbor_decode ( Vec u ) v )  → !Json CborErr
//
// Value mapping (both directions):
//   JNull ↔ 0xf6        JBool ↔ 0xf4/0xf5
//   JNum (integral) ↔ major 0 (unsigned) / major 1 (negative), shortest head
//   JNum (real)     → 0xfb float64 on encode; decode accepts float16/32/64
//   JStr ↔ major 3 (UTF-8 text)
//   JArr ↔ major 4    JObj ↔ major 5 (keys are text strings)
//
// Encode is canonical-ish: integers and lengths use the shortest head, so
// equal documents serialize to equal bytes (no indefinite-length items,
// no float64 where the value is integral). Decode is liberal: it accepts
// every definite-length head and all three float widths.
//
// Out of scope (each → CborUnsupported on decode): byte strings (major 2 —
// no Json mapping), tags (major 6), indefinite-length items, and simple
// values other than false/true/null. CBOR `undefined` (0xf7) decodes to
// JNull.

$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

& `c` @ nurl_f64_bits f x → i
& `c` @ nurl_f64_from_bits i bits → f
& `c` @ nurl_f32_from_bits i bits → f

: | CborErr {
    CborDepth        // nested past CBOR_MAX_DEPTH
    CborTruncated    // ran off the end of the buffer
    CborBadHead      // reserved additional-info (28..30)
    CborUnsupported  // byte string / tag / indefinite / exotic simple
    CborBadType      // non-text map key
    CborTrailing     // bytes left after one complete value
    CborOther
}

: i CBOR_MAX_DEPTH 256

@ cbor_err_name CborErr e → s {
    ^ ?? e {
        CborDepth → `depth-exceeded`
        CborTruncated → `truncated`
        CborBadHead → `bad-head`
        CborUnsupported → `unsupported`
        CborBadType → `bad-map-key`
        CborTrailing → `trailing-bytes`
        CborOther → `other`
    }
}

// ── encoder ─────────────────────────────────────────────────────────

// Emit a head: (major << 5) | argument, with the shortest length form.
@ __cbor_head ( Vec u ) out i major i arg → v {
    : i m << major 5
    ? < arg 24 { ( vec_push [u] out # u | m arg ) } {
        ? <= arg 255 {
            ( vec_push [u] out # u | m 24 )
            ( vec_push [u] out # u arg )
        } {
            ? <= arg 65535 {
                ( vec_push [u] out # u | m 25 )
                ( bytes_push_u16_be out # u16 arg )
            } {
                ? <= arg 4294967295 {
                    ( vec_push [u] out # u | m 26 )
                    ( bytes_push_u32_be out # u32 arg )
                } {
                    ( vec_push [u] out # u | m 27 )
                    ( bytes_push_u64_be out # u64 arg )
                }
            }
        }
    }
}

@ cbor_encode Json j → !( Vec u ) CborErr {
    : ( Vec u ) out ( vec_new [u] )
    : i rc ( __cbor_enc j out 0 )
    ? != rc 0 {
        ( vec_free [u] out )
        ^ @ !( Vec u ) CborErr { F @ CborErr { CborDepth } }
    } {}
    ^ @ !( Vec u ) CborErr { T out }
}

// Append the encoding of `j`. Returns 0 on success, 1 on depth overflow.
@ __cbor_enc Json j ( Vec u ) out i depth → i {
    ? > depth CBOR_MAX_DEPTH { ^ 1 } {}
    ^ ?? j {
        JNull → { ( vec_push [u] out # u 246 ) 0 }      // 0xf6
        JBool bv → {
            ? bv { ( vec_push [u] out # u 245 ) } { ( vec_push [u] out # u 244 ) }  // f5 / f4
            0
        }
        JNum s → { ( __cbor_enc_num s out ) 0 }
        JStr s → {
            : i len ( string_len s )
            ( __cbor_head out 3 len )
            ( __cbor_push_bytes out ( string_data s ) len )
            0
        }
        JArr v → {
            ( __cbor_head out 4 ( vec_len [Json] v ) )
            ( __cbor_enc_elems v out depth )
        }
        JObj v → {
            ( __cbor_head out 5 / ( vec_len [Json] v ) 2 )
            ( __cbor_enc_elems v out depth )
        }
    }
}

@ __cbor_push_bytes ( Vec u ) out s data i len → v {
    : *u bp # *u data
    : ~ i k 0
    ~ < k len { ( vec_push [u] out . bp k ) = k + k 1 }
}

@ __cbor_enc_elems ( Vec Json ) v ( Vec u ) out i depth → i {
    : i n ( vec_len [Json] v )
    : ~ i k 0
    : ~ i rc 0
    ~ & < k n == rc 0 {
        ?? ( vec_get [Json] v k ) { T e → { = rc ( __cbor_enc e out + depth 1 ) } F → {} }
        = k + k 1
    }
    ^ rc
}

// A JNum carries the number as decimal text — integral → major 0/1,
// otherwise a float64.
@ __cbor_enc_num String s ( Vec u ) out → v {
    ? ( __cbor_num_is_int s ) {
        ?? ( string_to_int s ) {
            T n → {
                ? >= n 0 { ( __cbor_head out 0 n ) }
                { ( __cbor_head out 1 - - 0 n 1 ) }     // major 1, arg = -1-n
            }
            F → ( __cbor_enc_f64_str s out )
        }
    } {
        ( __cbor_enc_f64_str s out )
    }
}

@ __cbor_num_is_int String s → b {
    : i n ( string_len s )
    : ~ i k 0
    : ~ b isint T
    ~ & < k n isint {
        : i c ( string_get s k )
        ? | | == c 46 == c 101 == c 69 { = isint F } {}   // . e E
        = k + k 1
    }
    ^ isint
}

@ __cbor_enc_f64_str String s ( Vec u ) out → v {
    : f x ?? ( string_to_float s ) { T fv → fv F → 0.0 }
    ( vec_push [u] out # u 251 )                         // 0xfb float64
    ( bytes_push_u64_be out # u64 ( nurl_f64_bits x ) )
}

// ── decoder ─────────────────────────────────────────────────────────

: CborDec { s data i len i pos }

@ __cd_new ( Vec u ) v → *CborDec {
    : *CborDec p # *CborDec ( nurl_alloc Z CborDec )
    = . p data # s ( vec_data [u] v )
    = . p len ( vec_len [u] v )
    = . p pos 0
    ^ p
}

@ __cd_free * CborDec p → v { ( nurl_free # s p ) }
@ __cd_remaining * CborDec p → i { ^ - . p len . p pos }

@ __cd_u8 * CborDec p → i {
    : *u d # *u . p data
    : i idx . p pos
    : i bb & 255 # i . d idx
    = . p pos + idx 1
    ^ bb
}

// Read `nbytes` big-endian into an unsigned i64 accumulator.
@ __cd_be * CborDec p i nbytes → i {
    : ~ i val 0
    : ~ i k 0
    ~ < k nbytes { = val + * val 256 ( __cd_u8 p ) = k + k 1 }
    ^ val
}

// Decode the head argument for additional-info `ai` (majors 0–5). 24→1,
// 25→2, 26→4, 27→8 length bytes; 28–30 reserved; 31 indefinite.
@ __cd_arg * CborDec p i ai → !i CborErr {
    ? < ai 24 { ^ @ !i CborErr { T ai } } {}
    : i nbytes ? == ai 24 1 ? == ai 25 2 ? == ai 26 4 ? == ai 27 8 -1
    ? < nbytes 0 {
        ? == ai 31 { ^ @ !i CborErr { F @ CborErr { CborUnsupported } } } {}
        ^ @ !i CborErr { F @ CborErr { CborBadHead } }
    } {}
    ? < ( __cd_remaining p ) nbytes { ^ @ !i CborErr { F @ CborErr { CborTruncated } } } {}
    ^ @ !i CborErr { T ( __cd_be p nbytes ) }
}

@ cbor_decode ( Vec u ) v → !Json CborErr {
    : *CborDec p ( __cd_new v )
    : !Json CborErr r ( __cd_value p 0 )
    ?? r {
        T jv → {
            ? > ( __cd_remaining p ) 0 {
                ( json_free jv ) ( __cd_free p )
                ^ @ !Json CborErr { F @ CborErr { CborTrailing } }
            } {}
            ( __cd_free p )
            ^ @ !Json CborErr { T jv }
        }
        F e → { ( __cd_free p ) ^ @ !Json CborErr { F e } }
    }
}

@ __cd_value * CborDec p i depth → !Json CborErr {
    ? > depth CBOR_MAX_DEPTH { ^ @ !Json CborErr { F @ CborErr { CborDepth } } } {}
    ? < ( __cd_remaining p ) 1 { ^ @ !Json CborErr { F @ CborErr { CborTruncated } } } {}
    : i b ( __cd_u8 p )
    : i major / b 32
    : i ai & b 31
    ? == major 7 { ^ ( __cd_simple p ai ) } {}
    : !i CborErr ar ( __cd_arg p ai )
    ?? ar {
        T arg → {
            ? == major 0 { ^ @ !Json CborErr { T ( json_int arg ) } } {}
            ? == major 1 { ^ @ !Json CborErr { T ( json_int - - 0 arg 1 ) } } {}
            ? == major 3 { ^ ( __cd_text p arg ) } {}
            ? == major 4 { ^ ( __cd_array p arg depth ) } {}
            ? == major 5 { ^ ( __cd_map p arg depth ) } {}
            // major 2 (byte string) and 6 (tag) have no Json mapping.
            ^ @ !Json CborErr { F @ CborErr { CborUnsupported } }
        }
        F e → { ^ @ !Json CborErr { F e } }
    }
}

// Read `n` UTF-8 bytes as a JStr.
@ __cd_text * CborDec p i n → !Json CborErr {
    ? < ( __cd_remaining p ) n { ^ @ !Json CborErr { F @ CborErr { CborTruncated } } } {}
    : String s ( string_with_cap + n 1 )
    : ~ i k 0
    ~ < k n { ( string_push_char s ( __cd_u8 p ) ) = k + k 1 }
    : Json j ( json_str_lit ( string_data s ) )
    ( string_free s )
    ^ @ !Json CborErr { T j }
}

@ __cd_array * CborDec p i n i depth → !Json CborErr {
    : Json arr ( json_arr_new )
    : ~ i k 0
    ~ < k n {
        : !Json CborErr ev ( __cd_value p + depth 1 )
        ?? ev {
            T e → { : b _ok ( json_arr_push arr e ) }
            F er → { ( json_free arr ) ^ @ !Json CborErr { F er } }
        }
        = k + k 1
    }
    ^ @ !Json CborErr { T arr }
}

@ __cd_map * CborDec p i n i depth → !Json CborErr {
    : Json obj ( json_obj_new )
    : ~ i k 0
    ~ < k n {
        : !Json CborErr kv ( __cd_value p + depth 1 )
        ?? kv {
            T key → {
                ? ( json_is_str key ) {} {
                    ( json_free key ) ( json_free obj )
                    ^ @ !Json CborErr { F @ CborErr { CborBadType } }
                }
                : !Json CborErr vv ( __cd_value p + depth 1 )
                ?? vv {
                    T val → { : b _ok ( json_obj_set obj ( json_str_data key ) val ) ( json_free key ) }
                    F er → { ( json_free key ) ( json_free obj ) ^ @ !Json CborErr { F er } }
                }
            }
            F er → { ( json_free obj ) ^ @ !Json CborErr { F er } }
        }
        = k + k 1
    }
    ^ @ !Json CborErr { T obj }
}

// Major 7: false/true/null, undefined→null, and float16/32/64.
@ __cd_simple * CborDec p i ai → !Json CborErr {
    ? == ai 20 { ^ @ !Json CborErr { T ( json_bool F ) } } {}
    ? == ai 21 { ^ @ !Json CborErr { T ( json_bool T ) } } {}
    ? == ai 22 { ^ @ !Json CborErr { T ( json_null ) } } {}
    ? == ai 23 { ^ @ !Json CborErr { T ( json_null ) } } {}   // undefined → null
    ? == ai 25 {
        ? < ( __cd_remaining p ) 2 { ^ @ !Json CborErr { F @ CborErr { CborTruncated } } } {}
        ^ @ !Json CborErr { T ( json_float ( __cbor_half_to_f64 ( __cd_be p 2 ) ) ) }
    } {}
    ? == ai 26 {
        ? < ( __cd_remaining p ) 4 { ^ @ !Json CborErr { F @ CborErr { CborTruncated } } } {}
        ^ @ !Json CborErr { T ( json_float ( nurl_f32_from_bits ( __cd_be p 4 ) ) ) }
    } {}
    ? == ai 27 {
        ? < ( __cd_remaining p ) 8 { ^ @ !Json CborErr { F @ CborErr { CborTruncated } } } {}
        ^ @ !Json CborErr { T ( json_float ( nurl_f64_from_bits ( __cd_be p 8 ) ) ) }
    } {}
    // simple value 0..19 / 24 / break (31) — no Json mapping
    ^ @ !Json CborErr { F @ CborErr { CborUnsupported } }
}

// IEEE half (16-bit) → f64, via the f32 bit pattern (handles zero,
// subnormal, normal, inf, NaN).
@ __cbor_half_to_f64 i h → f {
    : i sign << & / h 32768 1 31           // f32 sign bit
    : i exp & / h 1024 31
    : i mant & h 1023
    : ~ i bits 0
    ? == exp 0 {
        ? == mant 0 { = bits sign } {
            // subnormal half → normalize into an f32 normal
            : ~ i e -1
            : ~ i m mant
            ~ == 0 & m 1024 { = m << m 1 = e - e 1 }
            = m & m 1023
            = bits | sign | << + e 127 23 << m 13
        }
    } {
        ? == exp 31 {
            = bits | sign | << 255 23 << mant 13          // inf / NaN
        } {
            = bits | sign | << + - exp 15 127 23 << mant 13   // normal
        }
    }
    ^ ( nurl_f32_from_bits bits )
}
