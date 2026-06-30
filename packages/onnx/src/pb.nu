// packages/onnx/src/pb.nu — a minimal protobuf wire-format decoder.
//
// Just enough proto3 to read an ONNX model: varints, the four wire types,
// and length-delimited regions (sub-messages, strings, bytes, packed
// repeated). Pure NURL over a `( Vec u )` byte buffer — no codegen, no
// schema; the ONNX message shapes live in model.nu, which drives this by
// field number.
//
// A PbR is a cursor: the buffer plus the current read position. Decoders
// advance `pos`; message parsers loop `while pos < end`, where `end` comes
// from the enclosing length-delimited region (or the buffer length at top
// level). A sub-message is parsed by a fresh PbR over the same buffer
// (pb_sub) positioned at the payload — so nested ends never clash.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`

: PbR { ( Vec u ) buf  i pos  i len }

// Wire types (low 3 bits of a field tag).
@ pb_wt_varint → i { ^ 0 }   // int32/64, uint, bool, enum, sint(zigzag)
@ pb_wt_i64    → i { ^ 1 }   // fixed64, sfixed64, double
@ pb_wt_len    → i { ^ 2 }   // string, bytes, embedded message, packed
@ pb_wt_i32    → i { ^ 5 }   // fixed32, sfixed32, float

// New reader over a byte buffer (cursor at 0, end = buffer length).
@ pb_new ( Vec u ) buf → *PbR {
    : *PbR r # *PbR ( nurl_alloc Z PbR )
    = . r buf buf
    = . r pos 0
    = . r len ( vec_len [u] buf )
    ^ r
}

// A reader over the sub-region [start, start+len) of the SAME buffer.
@ pb_sub *PbR r i start i len → *PbR {
    : *PbR s # *PbR ( nurl_alloc Z PbR )
    = . s buf . r buf
    = . s pos start
    = . s len + start len
    ^ s
}

@ pb_pos *PbR r → i { ^ . r pos }
@ pb_set_pos *PbR r i p → v { = . r pos p }
@ pb_end *PbR r → i { ^ . r len }
@ pb_more *PbR r → b { ^ < . r pos . r len }
@ pb_free *PbR r → v { ( nurl_free # *u r ) }

// Byte at absolute offset (0 past end).
@ pb_byte *PbR r i off → i {
    ?? ( vec_get [u] . r buf off ) { T x → ^ # i x F _ → ^ 0 }
}

// Read a base-128 varint at the cursor; advance past it.
@ pb_varint *PbR r → i {
    : ( Vec u ) buf . r buf
    : ~ i p . r pos
    : ~ i result 0
    : ~ i shift 0
    : ~ b more T
    ~ more {
        : i bb ?? ( vec_get [u] buf p ) { T x → # i x F _ → 0 }
        = p + p 1
        = result | result << & bb 127 shift
        = shift + shift 7
        ? == & bb 128 0 { = more F } {}
    }
    = . r pos p
    ^ result
}

// Field tag → field number / wire type.
@ pb_tag *PbR r → i { ^ ( pb_varint r ) }
@ pb_field i tag → i { ^ >> tag 3 }
@ pb_wire i tag → i { ^ & tag 7 }

// Length-delimited: read length, return payload start, advance cursor PAST
// it. Caller reads [start, start+len) (recover len with pb_sub or by math).
@ pb_blob_start *PbR r → i {
    : i len ( pb_varint r )
    : i start . r pos
    = . r pos + start len
    ^ start
}
// Read a length-delimited field and return a bounded sub-reader over its
// payload, advancing the parent cursor past it. The caller loops the
// sub-reader with `pb_more` and frees it with `pb_free`. This is how
// embedded messages (and packed repeated fields) are descended into.
@ pb_submsg *PbR r → *PbR {
    : i len ( pb_varint r )
    : i start . r pos
    : *PbR s ( pb_sub r start len )
    = . r pos + start len
    ^ s
}

// Fixed 32-bit little-endian at cursor; advance 4. (float bits / fixed32)
@ pb_i32 *PbR r → i {
    : ( Vec u ) buf . r buf
    : i p . r pos
    : i b0 ?? ( vec_get [u] buf p )     { T x → # i x F _ → 0 }
    : i b1 ?? ( vec_get [u] buf + p 1 ) { T x → # i x F _ → 0 }
    : i b2 ?? ( vec_get [u] buf + p 2 ) { T x → # i x F _ → 0 }
    : i b3 ?? ( vec_get [u] buf + p 3 ) { T x → # i x F _ → 0 }
    = . r pos + p 4
    ^ | | | b0 << b1 8 << b2 16 << b3 24
}

// Read a length-delimited region as a String.
@ pb_string *PbR r → String {
    : ( Vec u ) buf . r buf
    : i len ( pb_varint r )
    : i start . r pos
    : ( Vec u ) tmp ( vec_new [u] )
    : ~ i k 0
    ~ < k len {
        ?? ( vec_get [u] buf + start k ) { T x → ( vec_push [u] tmp x ) F _ → {} }
        = k + k 1
    }
    = . r pos + start len
    : String out ( bytes_to_str tmp )
    ( vec_free [u] tmp )
    ^ out
}

// Skip a field of the given wire type (cursor at the value).
@ pb_skip *PbR r i wire → v {
    ? == wire 0 { ( pb_varint r ) ^ {} } {}
    ? == wire 1 { = . r pos + . r pos 8 ^ {} } {}
    ? == wire 5 { = . r pos + . r pos 4 ^ {} } {}
    ? == wire 2 { ( pb_blob_start r ) ^ {} } {}
}

// Read `n` little-endian f32 values from the byte region at the cursor
// into the host buffer `dst` (raw *u, 4-byte stride), writing each one's
// exact 32-bit pattern (no float round-trip). Advances the cursor by n*4.
// Used for TensorProto.raw_data → host weights, ready to upload to the GPU.
@ pb_read_f32_into *PbR r *u dst i n → v {
    : ( Vec u ) buf . r buf
    : i base . r pos
    : ~ i k 0
    ~ < k n {
        : i off + base * k 4
        : i b0 ?? ( vec_get [u] buf off )       { T x → # i x F _ → 0 }
        : i b1 ?? ( vec_get [u] buf + off 1 )   { T x → # i x F _ → 0 }
        : i b2 ?? ( vec_get [u] buf + off 2 )   { T x → # i x F _ → 0 }
        : i b3 ?? ( vec_get [u] buf + off 3 )   { T x → # i x F _ → 0 }
        ( nurl_poke_i32 dst k | | | b0 << b1 8 << b2 16 << b3 24 )
        = k + k 1
    }
    = . r pos + base * n 4
}

// Read `n` little-endian int64 values from the byte region at the cursor
// into `dst` (8-byte stride). For TensorProto raw_data of an INT64 tensor
// (shape tensors, split sizes, anchor grids). Advances the cursor by n*8.
@ pb_read_i64_into *PbR r *u dst i n → v {
    : ( Vec u ) buf . r buf
    : i base . r pos
    : ~ i k 0
    ~ < k n {
        : i off + base * k 8
        : ~ i v 0
        : ~ i b 0
        ~ < b 8 {
            : i byte ?? ( vec_get [u] buf + off b ) { T x → # i x F _ → 0 }
            = v | v << byte * b 8
            = b + b 1
        }
        ( nurl_poke dst k v )
        = k + k 1
    }
    = . r pos + base * n 8
}

// 4-byte typed store (runtime.c accessor; runtime.o is always linked).
& `c` @ nurl_poke_i32 *u base i idx i val → v
