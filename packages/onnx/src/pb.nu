// packages/onnx/src/pb.nu — the protobuf seam between ONNX and the stdlib.
//
// The wire format itself lives in `stdlib/ext/protobuf.nu` now: varints,
// tags, length-delimited regions, packed repeated fields, groups, bounds
// and depth limits, all checked. This file is the adapter that lets
// model.nu keep reading a message as a flat loop over fields.
//
// A PReader is a checked stdlib reader plus a STICKY error. Every read
// below is infallible at the call site and returns a neutral value once
// the reader has failed, so a parser stays a straight `while more { ... }`
// loop with no per-field error plumbing — but nothing is silently
// mis-read: the first failure latches, every later read is a no-op, the
// enclosing loop stops on `pb_more`, and `pb_err` reports what went wrong
// and where. A sub-message reader carries its failure back to its parent
// through `pb_absorb`.
//
// Also here: turning a little-endian byte block into a host buffer of f32
// or int64 values. That part was never protobuf — it is what
// TensorProto.raw_data and the tools' plain `.f32` files both need.

$ `stdlib/core/slice.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/protobuf.nu`

: PReader { ProtoReader r b failed ProtoError err }

// ── construction ──────────────────────────────────────────────────

// A reader that has already failed — the neutral value a construction
// failure degrades to, so `pb_new` needs no error branch at its call site.
@ pb_empty ProtoError e → PReader {
    ^ @ PReader { @ ProtoReader { @ ( Slice u ) { # *u 0 0 } 0 0 0 PROTO_DEFAULT_DEPTH } T e }
}

@ pb_new ( Vec u ) bytes → PReader {
    ?? ( proto_reader bytes ) {
        T r → ^ @ PReader { r F @ ProtoError { ProtoTruncated 0 } }
        F e → ^ ( pb_empty e )
    }
}

// ── error state ───────────────────────────────────────────────────

@ pb_failed PReader p → b { ^ . p failed }

@ pb_err PReader p → ProtoError { ^ . p err }

// Latch the first failure; later ones do not overwrite it.
@ __pb_fail inout PReader p ProtoError e → v {
    ? . p failed {} { = . p failed T = . p err e }
}

// Carry a sub-reader's failure into its parent.
@ pb_absorb inout PReader p PReader sub → v {
    ? . sub failed { ( __pb_fail p . sub err ) } {}
}

// More fields to read? False once the reader has failed, so every
// message loop stops at the first bad field instead of spinning.
@ pb_more inout PReader p → b {
    ? . p failed { ^ F } {}
    ^ ( proto_more . p r )
}

// ── field reads ───────────────────────────────────────────────────

// Next field tag. Returns field 0 / wire 0 once failed.
@ pb_tag inout PReader p → ProtoTag {
    ? . p failed { ^ @ ProtoTag { 0 0 } } {}
    ?? ( proto_read_tag . p r ) {
        T t → ^ t
        F e → { ( __pb_fail p e ) ^ @ ProtoTag { 0 0 } }
    }
}

// A varint field as i64 (int32/int64/uint/bool/enum all arrive here).
@ pb_varint inout PReader p → i {
    ? . p failed { ^ 0 } {}
    ?? ( proto_read_int64 . p r ) {
        T v → ^ v
        F e → { ( __pb_fail p e ) ^ 0 }
    }
}

// A fixed 32-bit field as its raw bit pattern (float bits / fixed32).
@ pb_i32 inout PReader p → i {
    ? . p failed { ^ 0 } {}
    ?? ( proto_read_fixed32 . p r ) {
        T v → ^ # i v
        F e → { ( __pb_fail p e ) ^ 0 }
    }
}

// A length-delimited field as an owned String. ONNX name/op_type fields
// are proto3 `string`, but a STRING attribute's value is `bytes` and is
// not required to be UTF-8, so this does NOT validate — it takes the
// bytes as they are, which is what the previous reader did.
@ pb_string inout PReader p → String {
    ? . p failed { ^ ( string_new ) } {}
    ?? ( proto_read_bytes . p r ) {
        T s → ^ ( __pb_slice_str s )
        F e → { ( __pb_fail p e ) ^ ( string_new ) }
    }
}

@ __pb_slice_str ( Slice u ) s → String {
    : ( Vec u ) tmp ( vec_new [u] )
    : ~ i k 0
    ~ < k ( slice_len [u] s ) {
        ?? ( slice_get [u] s k ) { T x → ( vec_push [u] tmp x ) F _ → {} }
        = k + k 1
    }
    : String out ( bytes_to_str tmp )
    ( vec_free [u] tmp )
    ^ out
}

// A length-delimited field's raw payload, borrowed in place. The slice
// borrows the caller's model buffer — valid as long as that buffer is.
@ pb_bytes inout PReader p → ( Slice u ) {
    ? . p failed { ^ @ ( Slice u ) { # *u 0 0 } } {}
    ?? ( proto_read_bytes . p r ) {
        T s → ^ s
        F e → { ( __pb_fail p e ) ^ @ ( Slice u ) { # *u 0 0 } }
    }
}

// An embedded message as its own bounded reader.
@ pb_submsg inout PReader p → PReader {
    ? . p failed { ^ @ PReader { . p r T . p err } } {}
    ?? ( proto_read_message . p r ) {
        T sub → ^ @ PReader { sub F @ ProtoError { ProtoTruncated 0 } }
        F e → { ( __pb_fail p e ) ^ @ PReader { . p r T e } }
    }
}

// A packed repeated field as a bounded reader over its payload.
@ pb_packed inout PReader p → PReader {
    ? . p failed { ^ @ PReader { . p r T . p err } } {}
    ?? ( proto_read_packed . p r ) {
        T sub → ^ @ PReader { sub F @ ProtoError { ProtoTruncated 0 } }
        F e → { ( __pb_fail p e ) ^ @ PReader { . p r T e } }
    }
}

// Skip a field whose tag was already read (groups included).
@ pb_skip inout PReader p ProtoTag tag → v {
    ? . p failed { ^ {} } {}
    ?? ( proto_skip . p r tag ) {
        T _ → {}
        F e → ( __pb_fail p e )
    }
}

// ── raw little-endian blocks (not protobuf) ───────────────────────

& `c` @ nurl_poke_i32 *u base i idx i32 val → v

@ __byte ( Slice u ) s i off → i {
    ?? ( slice_get [u] s off ) { T x → ^ # i x F _ → ^ 0 }
}

// `n` little-endian f32 values from `s` into `dst` (raw *u, 4-byte
// stride), writing each one's exact 32-bit pattern — no float
// round-trip. Elements past the end of the slice read as zero.
@ slice_f32_into ( Slice u ) s * u dst i n → v {
    : ~ i k 0
    ~ < k n {
        : i off * k 4
        : i b0 ( __byte s off )
        : i b1 ( __byte s + off 1 )
        : i b2 ( __byte s + off 2 )
        : i b3 ( __byte s + off 3 )
        ( nurl_poke_i32 dst k # i32 | | | b0 << b1 8 << b2 16 << b3 24 )
        = k + k 1
    }
}

// `n` little-endian int64 values from `s` into `dst` (8-byte stride).
@ slice_i64_into ( Slice u ) s * u dst i n → v {
    : ~ i k 0
    ~ < k n {
        : i off * k 8
        : ~ i value 0
        : ~ i b 0
        ~ < b 8 {
            = value | value << ( __byte s + off b ) * b 8
            = b + b 1
        }
        ( nurl_poke dst k value )
        = k + k 1
    }
}

// The same two over a whole byte vector — how the tools read a plain
// little-endian `.f32` file.
@ vec_f32_into ( Vec u ) bytes * u dst i n → v {
    ( slice_f32_into ( slice_from_vec [u] bytes ) dst n )
}

@ vec_i64_into ( Vec u ) bytes * u dst i n → v {
    ( slice_i64_into ( slice_from_vec [u] bytes ) dst n )
}
