// Protocol Buffers wire codec. No schema, code generation, or C dependency.
// See docs/stdlib/protobuf.md for ownership, error, limit and schema contracts.
// Readers and returned Slice[u] values borrow immutable backing storage.
// Every fallible read is transactional: an error leaves the cursor unchanged.

$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/utf8.nu`

: i PROTO_MAX_BYTES 2147483647
: i PROTO_MAX_FIELD 536870911
: i PROTO_DEFAULT_DEPTH 100
: i PROTO_DEPTH_LIMIT 256

: | ProtoCode {
    ProtoTruncated
    ProtoVarintOverflow
    ProtoBadTag
    ProtoBadWire
    ProtoBadLength
    ProtoDepth
    ProtoGroupMismatch
    ProtoUtf8
    ProtoBadRange
    ProtoSize
}
: ProtoError { ProtoCode code i offset }
: ProtoTag { i number i wire }
: ProtoReader { ( Slice u ) bytes i pos i base i depth i max_depth }

@ proto_error_name ProtoCode code → s {
    ^ ?? code {
        ProtoTruncated → `truncated`
        ProtoVarintOverflow → `varint-overflow`
        ProtoBadTag → `bad-tag`
        ProtoBadWire → `bad-wire`
        ProtoBadLength → `bad-length`
        ProtoDepth → `depth-exceeded`
        ProtoGroupMismatch → `group-mismatch`
        ProtoUtf8 → `invalid-utf8`
        ProtoBadRange → `bad-range`
        ProtoSize → `size-limit`
    }
}

// Explicit limits apply before any input access. Raw slices have the same
// caller lifetime/storage contract as core/slice.nu; prefer proto_reader.
@ proto_reader_with_limits ( Slice u ) bytes i max_bytes i max_depth → !ProtoReader ProtoError {
    ? | | < . bytes len 0 < max_bytes 0 > max_bytes PROTO_MAX_BYTES {
        ^ @ !ProtoReader ProtoError { F @ ProtoError { ProtoBadRange 0 } }
    } {}
    ? | < max_depth 0 > max_depth PROTO_DEPTH_LIMIT {
        ^ @ !ProtoReader ProtoError { F @ ProtoError { ProtoBadRange 0 } }
    } {}
    ? > . bytes len max_bytes {
        ^ @ !ProtoReader ProtoError { F @ ProtoError { ProtoSize 0 } }
    } {}
    ? & > . bytes len 0 == # i . bytes data 0 {
        ^ @ !ProtoReader ProtoError { F @ ProtoError { ProtoBadRange 0 } }
    } {}
    ^ @ !ProtoReader ProtoError { T @ ProtoReader { bytes 0 0 0 max_depth } }
}

@ proto_reader ( Vec u ) bytes → !ProtoReader ProtoError {
    ^ ( proto_reader_with_limits ( slice_from_vec [u] bytes ) PROTO_MAX_BYTES PROTO_DEFAULT_DEPTH )
}

@ proto_remaining ProtoReader r → i { ^ - . . r bytes len . r pos }

@ proto_more ProtoReader r → b { ^ > ( proto_remaining r ) 0 }

@ proto_offset ProtoReader r → i { ^ + . r base . r pos }

@ __proto_error ProtoReader r ProtoCode code → ProtoError {
    ^ @ ProtoError { code ( proto_offset r ) }
}

// A varint is at most ten bytes; the tenth can carry only bit 63.
// Non-minimal, non-overflowing encodings are accepted for interoperability.
@ proto_read_uint64 inout ProtoReader r → !u64 ProtoError {
    : *u data . . r bytes data
    : i end . . r bytes len
    : ~ i p . r pos
    : ~ u64 value # u64 0
    : ~ i k 0
    ~ < k 10 {
        ? >= p end { ^ @ !u64 ProtoError { F @ ProtoError { ProtoTruncated + . r base p } } } {}
        : i byte # i . data p
        ? & == k 9 > byte 1 {
            ^ @ !u64 ProtoError { F @ ProtoError { ProtoVarintOverflow + . r base p } }
        } {}
        = value | value << # u64 & byte 127 * k 7
        = p + p 1
        ? < byte 128 {
            = . r pos p
            ^ @ !u64 ProtoError { T value }
        } {}
        = k + k 1
    }
    ^ @ !u64 ProtoError { F ( __proto_error r ProtoVarintOverflow ) }
}

@ proto_read_tag inout ProtoReader r → !ProtoTag ProtoError {
    : ~ ProtoReader next r
    : u64 bits \ ( proto_read_uint64 next )
    ? | == bits # u64 0 > bits # u64 4294967295 {
        ^ @ !ProtoTag ProtoError { F ( __proto_error r ProtoBadTag ) }
    } {}
    : i number # i >> bits 3
    : i wire # i & bits # u64 7
    ? == number 0 { ^ @ !ProtoTag ProtoError { F ( __proto_error r ProtoBadTag ) } } {}
    ? > wire 5 { ^ @ !ProtoTag ProtoError { F ( __proto_error r ProtoBadWire ) } } {}
    = r next
    ^ @ !ProtoTag ProtoError { T @ ProtoTag { number wire } }
}

// Check the schema's expected wire type before interpreting a known field.
@ proto_expect ProtoTag tag i wire i offset → !v ProtoError {
    ? != . tag wire wire { ^ @ !v ProtoError { F @ ProtoError { ProtoBadWire offset } } } {}
    ^ @ !v ProtoError { T }
}

@ __proto_take inout ProtoReader r i n → !( Slice u ) ProtoError {
    ? < n 0 { ^ @ !( Slice u ) ProtoError { F ( __proto_error r ProtoBadRange ) } } {}
    ? > n ( proto_remaining r ) { ^ @ !( Slice u ) ProtoError { F ( __proto_error r ProtoTruncated ) } } {}
    : *u start # *u + # i . . r bytes data . r pos
    = . r pos + . r pos n
    ^ @ !( Slice u ) ProtoError { T @ ( Slice u ) { start n } }
}

// Zero-copy payload. No allocation, even for a multi-gigabyte field.
@ proto_read_bytes inout ProtoReader r → !( Slice u ) ProtoError {
    : ~ ProtoReader next r
    : u64 n \ ( proto_read_uint64 next )
    ? > n # u64 PROTO_MAX_BYTES {
        ^ @ !( Slice u ) ProtoError { F ( __proto_error r ProtoBadLength ) }
    } {}
    : ( Slice u ) bytes \ ( __proto_take next # i n )
    = r next
    ^ @ !( Slice u ) ProtoError { T bytes }
}

@ proto_read_message inout ProtoReader r → !ProtoReader ProtoError {
    ? >= . r depth . r max_depth { ^ @ !ProtoReader ProtoError { F ( __proto_error r ProtoDepth ) } } {}
    : ~ ProtoReader next r
    : ( Slice u ) bytes \ ( proto_read_bytes next )
    : i base - ( proto_offset next ) . bytes len
    : ProtoReader child @ ProtoReader { bytes 0 base + . r depth 1 . r max_depth }
    = r next
    ^ @ !ProtoReader ProtoError { T child }
}

// Packed primitives are not recursive messages and use no depth budget.
// Read scalar values until !proto_more; partial final elements are errors.
@ proto_read_packed inout ProtoReader r → !ProtoReader ProtoError {
    : ~ ProtoReader next r
    : ( Slice u ) bytes \ ( proto_read_bytes next )
    : i base - ( proto_offset next ) . bytes len
    : ProtoReader child @ ProtoReader { bytes 0 base . r depth . r max_depth }
    = r next
    ^ @ !ProtoReader ProtoError { T child }
}

@ __proto_utf8 ( Slice u ) bytes i base → !v ProtoError {
    : ~ i p 0
    ~ < p . bytes len {
        : Utf8Dec decoded ( utf8_decode_n # s . bytes data . bytes len p )
        ? == . decoded ok 0 { ^ @ !v ProtoError { F @ ProtoError { ProtoUtf8 + base p } } } {}
        = p + p . decoded width
    }
    ^ @ !v ProtoError { T }
}

// Owned String, including embedded NUL bytes. Validate before allocating.
@ proto_read_string inout ProtoReader r → !String ProtoError {
    : ~ ProtoReader next r
    : ( Slice u ) bytes \ ( proto_read_bytes next )
    \ ( __proto_utf8 bytes - ( proto_offset next ) . bytes len )
    : String value ( string_from_bytes_packed . bytes data . bytes len )
    = r next
    ^ @ !String ProtoError { T value }
}

@ __proto_fixed inout ProtoReader r i width → !u64 ProtoError {
    : ( Slice u ) bytes \ ( __proto_take r width )
    : *u data . bytes data
    : ~ u64 value # u64 0
    : ~ i k 0
    ~ < k width {
        = value | value << # u64 . data k * k 8
        = k + k 1
    }
    ^ @ !u64 ProtoError { T value }
}

@ proto_read_fixed64 inout ProtoReader r → !u64 ProtoError { ^ ( __proto_fixed r 8 ) }

@ proto_read_fixed32 inout ProtoReader r → !u32 ProtoError {
    : u64 bits \ ( __proto_fixed r 4 )
    ^ @ !u32 ProtoError { T # u32 bits }
}

// Unknown fields, including deprecated groups, are fully bounds checked.
// The entire skip rolls back on malformed data, mismatched ends or depth.
@ proto_skip inout ProtoReader r ProtoTag tag → !v ProtoError {
    ? | < . tag number 1 > . tag number PROTO_MAX_FIELD {
        ^ @ !v ProtoError { F ( __proto_error r ProtoBadTag ) }
    } {}
    : ~ ProtoReader next r
    ?? . tag wire {
        0 → { \ ( proto_read_uint64 next ) }
        1 → { \ ( __proto_take next 8 ) }
        2 → { \ ( proto_read_bytes next ) }
        3 → { \ ( proto_read_group next . tag number ) }
        4 → { ^ @ !v ProtoError { F ( __proto_error r ProtoGroupMismatch ) } }
        5 → { \ ( __proto_take next 4 ) }
        _ → { ^ @ !v ProtoError { F ( __proto_error r ProtoBadWire ) } }
    }
    = r next
    ^ @ !v ProtoError { T }
}

// Cursor is immediately after the start-group tag. Validate the complete
// group, then return a child over its contents (excluding both delimiters).
// Locating a group's end requires scanning; the returned view borrows input.
@ proto_read_group inout ProtoReader r i number → !ProtoReader ProtoError {
    ? | < number 1 > number PROTO_MAX_FIELD {
        ^ @ !ProtoReader ProtoError { F ( __proto_error r ProtoBadTag ) }
    } {}
    ? >= . r depth . r max_depth { ^ @ !ProtoReader ProtoError { F ( __proto_error r ProtoDepth ) } } {}
    : ~ ProtoReader next r
    = . next depth + . next depth 1
    : ~ b ended F
    : ~ i end . r pos
    ~ ! ended {
        = end . next pos
        : i offset ( proto_offset next )
        : ProtoTag tag \ ( proto_read_tag next )
        ? == . tag wire 4 {
            ? != . tag number number {
                ^ @ !ProtoReader ProtoError { F @ ProtoError { ProtoGroupMismatch offset } }
            } {}
            = ended T
        } { \ ( proto_skip next tag ) }
    }
    : *u start # *u + # i . . r bytes data . r pos
    : ( Slice u ) bytes @ ( Slice u ) { start - end . r pos }
    : ProtoReader child @ ProtoReader { bytes 0 ( proto_offset r ) . next depth . r max_depth }
    = . next depth . r depth
    = r next
    ^ @ !ProtoReader ProtoError { T child }
}

// Validate framing, not the schema of opaque LEN payloads.
@ proto_validate ( Vec u ) bytes → !v ProtoError {
    : ~ ProtoReader r \ ( proto_reader bytes )
    ~ ( proto_more r ) {
        : ProtoTag tag \ ( proto_read_tag r )
        \ ( proto_skip r tag )
    }
    ^ @ !v ProtoError { T }
}

// Typed scalar accessors. uint32/int32 consume a full varint then retain
// its low 32 bits, as protobuf runtimes do (including ten-byte negatives).
@ proto_read_int64 inout ProtoReader r → !i ProtoError {
    : u64 bits \ ( proto_read_uint64 r )
    ^ @ !i ProtoError { T # i bits }
}

@ proto_read_uint32 inout ProtoReader r → !u32 ProtoError {
    : u64 bits \ ( proto_read_uint64 r )
    ^ @ !u32 ProtoError { T # u32 bits }
}

@ proto_read_int32 inout ProtoReader r → !i32 ProtoError {
    : u64 bits \ ( proto_read_uint64 r )
    ^ @ !i32 ProtoError { T # i32 bits }
}

@ proto_read_bool inout ProtoReader r → !b ProtoError {
    : u64 bits \ ( proto_read_uint64 r )
    ^ @ !b ProtoError { T != bits # u64 0 }
}

@ proto_read_sint64 inout ProtoReader r → !i ProtoError {
    : u64 bits \ ( proto_read_uint64 r )
    ^ @ !i ProtoError { T # i ^^ >> bits 1 # u64 - 0 # i & bits # u64 1 }
}

@ proto_read_sint32 inout ProtoReader r → !i32 ProtoError {
    : u32 bits \ ( proto_read_uint32 r )
    ^ @ !i32 ProtoError { T # i32 ^^ >> bits 1 # u32 - 0 # i & bits # u32 1 }
}

@ proto_read_sfixed64 inout ProtoReader r → !i ProtoError {
    : u64 bits \ ( proto_read_fixed64 r )
    ^ @ !i ProtoError { T # i bits }
}

@ proto_read_sfixed32 inout ProtoReader r → !i32 ProtoError {
    : u32 bits \ ( proto_read_fixed32 r )
    ^ @ !i32 ProtoError { T # i32 bits }
}

@ proto_read_double inout ProtoReader r → !f ProtoError {
    : u64 bits \ ( proto_read_fixed64 r )
    ^ @ !f ProtoError { T ( bits_to_f64 # i bits ) }
}

@ proto_read_float inout ProtoReader r → !f32 ProtoError {
    : u32 bits \ ( proto_read_fixed32 r )
    ^ @ !f32 ProtoError { T ( bits_to_f32 # i bits ) }
}

// Return an entire unknown record verbatim, including tag and group end.
@ proto_read_raw_field inout ProtoReader r → !( Slice u ) ProtoError {
    : ~ ProtoReader next r
    : ProtoTag tag \ ( proto_read_tag next )
    \ ( proto_skip next tag )
    : *u start # *u + # i . . r bytes data . r pos
    : i n - . next pos . r pos
    = r next
    ^ @ !( Slice u ) ProtoError { T @ ( Slice u ) { start n } }
}

// Writers append to a caller-owned Vec[u]. Fallible validation happens
// before mutation. Allocation failure follows Vec's normal panic contract.
@ proto_varint_size u64 value → i {
    : ~ u64 n value
    : ~ i size 1
    ~ >= n # u64 128 { = n >> n 7 = size + size 1 }
    ^ size
}

@ __proto_room ( Vec u ) out i size → !v ProtoError {
    : i n ( vec_len [u] out )
    ? | < size 0 > size - PROTO_MAX_BYTES n {
        ^ @ !v ProtoError { F @ ProtoError { ProtoSize n } }
    } {}
    ( vec_reserve [u] out size )
    ^ @ !v ProtoError { T }
}

@ __proto_emit_varint ( Vec u ) out u64 value → v {
    : ~ u64 n value
    ~ >= n # u64 128 {
        ( vec_push [u] out # u | & n # u64 127 # u64 128 )
        = n >> n 7
    }
    ( vec_push [u] out # u n )
}

@ __proto_emit_fixed ( Vec u ) out u64 value i width → v {
    : ~ i k 0
    ~ < k width {
        ( vec_push [u] out # u >> value * k 8 )
        = k + k 1
    }
}

@ __proto_tag_bits i number i wire i offset → !u64 ProtoError {
    ? | < number 1 > number PROTO_MAX_FIELD {
        ^ @ !u64 ProtoError { F @ ProtoError { ProtoBadTag offset } }
    } {}
    ? | < wire 0 > wire 5 {
        ^ @ !u64 ProtoError { F @ ProtoError { ProtoBadWire offset } }
    } {}
    ^ @ !u64 ProtoError { T # u64 | << number 3 wire }
}

// A low-level tag writer also permits paired start/end group tags.
@ proto_write_tag ( Vec u ) out i number i wire → !v ProtoError {
    : u64 tag \ ( __proto_tag_bits number wire ( vec_len [u] out ) )
    \ ( __proto_room out ( proto_varint_size tag ) )
    ( __proto_emit_varint out tag )
    ^ @ !v ProtoError { T }
}

@ proto_put_uint64 ( Vec u ) out u64 value → !v ProtoError {
    \ ( __proto_room out ( proto_varint_size # u64 value ) )
    ( __proto_emit_varint out # u64 value )
    ^ @ !v ProtoError { T }
}

@ proto_write_uint64 ( Vec u ) out i number u64 value → !v ProtoError {
    : u64 tag \ ( __proto_tag_bits number 0 ( vec_len [u] out ) )
    \ ( __proto_room out + ( proto_varint_size tag ) ( proto_varint_size # u64 value ) )
    ( __proto_emit_varint out tag )
    ( __proto_emit_varint out # u64 value )
    ^ @ !v ProtoError { T }
}

@ proto_put_fixed64 ( Vec u ) out u64 value → !v ProtoError {
    \ ( __proto_room out 8 )
    ( __proto_emit_fixed out # u64 value 8 )
    ^ @ !v ProtoError { T }
}

@ proto_write_fixed64 ( Vec u ) out i number u64 value → !v ProtoError {
    : u64 tag \ ( __proto_tag_bits number 1 ( vec_len [u] out ) )
    \ ( __proto_room out + ( proto_varint_size tag ) 8 )
    ( __proto_emit_varint out tag )
    ( __proto_emit_fixed out # u64 value 8 )
    ^ @ !v ProtoError { T }
}

@ proto_put_fixed32 ( Vec u ) out u32 value → !v ProtoError {
    \ ( __proto_room out 4 )
    ( __proto_emit_fixed out # u64 value 4 )
    ^ @ !v ProtoError { T }
}

@ proto_write_fixed32 ( Vec u ) out i number u32 value → !v ProtoError {
    : u64 tag \ ( __proto_tag_bits number 5 ( vec_len [u] out ) )
    \ ( __proto_room out + ( proto_varint_size tag ) 4 )
    ( __proto_emit_varint out tag )
    ( __proto_emit_fixed out # u64 value 4 )
    ^ @ !v ProtoError { T }
}

@ proto_put_int64 ( Vec u ) out i value → !v ProtoError {
    ^ ( proto_put_uint64 out # u64 value )
}

@ proto_write_int64 ( Vec u ) out i number i value → !v ProtoError {
    ^ ( proto_write_uint64 out number # u64 value )
}

@ proto_put_uint32 ( Vec u ) out u32 value → !v ProtoError {
    ^ ( proto_put_uint64 out # u64 value )
}

@ proto_write_uint32 ( Vec u ) out i number u32 value → !v ProtoError {
    ^ ( proto_write_uint64 out number # u64 value )
}

@ proto_put_int32 ( Vec u ) out i32 value → !v ProtoError {
    ^ ( proto_put_uint64 out # u64 # i value )
}

@ proto_write_int32 ( Vec u ) out i number i32 value → !v ProtoError {
    ^ ( proto_write_uint64 out number # u64 # i value )
}

@ proto_put_bool ( Vec u ) out b value → !v ProtoError {
    ^ ( proto_put_uint64 out # u64 ? value 1 0 )
}

@ proto_write_bool ( Vec u ) out i number b value → !v ProtoError {
    ^ ( proto_write_uint64 out number # u64 ? value 1 0 )
}

@ proto_put_sint64 ( Vec u ) out i value → !v ProtoError {
    ^ ( proto_put_uint64 out ^^ << # u64 value 1 # u64 >> value 63 )
}

@ proto_write_sint64 ( Vec u ) out i number i value → !v ProtoError {
    ^ ( proto_write_uint64 out number ^^ << # u64 value 1 # u64 >> value 63 )
}

@ proto_put_sint32 ( Vec u ) out i32 value → !v ProtoError {
    ^ ( proto_put_uint64 out # u64 # u32 ^^ << # u32 value 1 # u32 >> value 31 )
}

@ proto_write_sint32 ( Vec u ) out i number i32 value → !v ProtoError {
    ^ ( proto_write_uint64 out number # u64 # u32 ^^ << # u32 value 1 # u32 >> value 31 )
}

@ proto_put_sfixed64 ( Vec u ) out i value → !v ProtoError {
    ^ ( proto_put_fixed64 out # u64 value )
}

@ proto_write_sfixed64 ( Vec u ) out i number i value → !v ProtoError {
    ^ ( proto_write_fixed64 out number # u64 value )
}

@ proto_put_sfixed32 ( Vec u ) out i32 value → !v ProtoError {
    ^ ( proto_put_fixed32 out # u32 value )
}

@ proto_write_sfixed32 ( Vec u ) out i number i32 value → !v ProtoError {
    ^ ( proto_write_fixed32 out number # u32 value )
}

@ proto_put_double ( Vec u ) out f value → !v ProtoError {
    ^ ( proto_put_fixed64 out # u64 ( f64_to_bits value ) )
}

@ proto_write_double ( Vec u ) out i number f value → !v ProtoError {
    ^ ( proto_write_fixed64 out number # u64 ( f64_to_bits value ) )
}

@ proto_put_float ( Vec u ) out f32 value → !v ProtoError {
    ^ ( proto_put_fixed32 out # u32 ( f32_to_bits value ) )
}

@ proto_write_float ( Vec u ) out i number f32 value → !v ProtoError {
    ^ ( proto_write_fixed32 out number # u32 ( f32_to_bits value ) )
}

// Borrowed slices may refer to out itself: preserve their offset across
// reserve/reallocation. A source alias must lie within out's live bytes.
@ proto_write_slice ( Vec u ) out i number ( Slice u ) bytes → !v ProtoError {
    : i offset ( vec_len [u] out )
    : u64 tag \ ( __proto_tag_bits number 2 offset )
    : i n . bytes len
    ? | < n 0 > n PROTO_MAX_BYTES {
        ^ @ !v ProtoError { F @ ProtoError { ProtoBadLength offset } }
    } {}
    ? & > n 0 == # i . bytes data 0 {
        ^ @ !v ProtoError { F @ ProtoError { ProtoBadRange offset } }
    } {}
    : u64 start # u64 . bytes data
    : u64 dst # u64 ( vec_data [u] out )
    : ~ i alias -1
    ? & >= start dst <= - start dst # u64 offset {
        = alias # i - start dst
        ? > n - offset alias {
            ^ @ !v ProtoError { F @ ProtoError { ProtoBadRange offset } }
        } {}
    } {}
    : i header + ( proto_varint_size tag ) ( proto_varint_size # u64 n )
    \ ( __proto_room out + header n )
    ( __proto_emit_varint out tag )
    ( __proto_emit_varint out # u64 n )
    ? > n 0 {
        : ~ * u source . bytes data
        ? >= alias 0 { = source # *u + # i ( vec_data [u] out ) alias } {}
        : *u target # *u + # i ( vec_data [u] out ) + offset header
        ( nurl_memcpy target source n )
        ( vec_set_len [u] out + + offset header n )
    } {}
    ^ @ !v ProtoError { T }
}

// Also encodes embedded messages and packed scalar buffers.
@ proto_write_bytes ( Vec u ) out i number ( Vec u ) bytes → !v ProtoError {
    ^ ( proto_write_slice out number ( slice_from_vec [u] bytes ) )
}

@ proto_write_string ( Vec u ) out i number String value → !v ProtoError {
    : ( Slice u ) bytes @ ( Slice u ) { # *u ( string_data value ) ( string_len value ) }
    \ ( __proto_utf8 bytes ( vec_len [u] out ) )
    ^ ( proto_write_slice out number bytes )
}
