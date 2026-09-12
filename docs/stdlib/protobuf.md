# Protocol Buffers

Import `stdlib/ext/protobuf.nu` for the Protocol Buffers binary wire codec.
It reads and writes every scalar wire representation, length-delimited bytes,
UTF-8 strings, embedded messages, packed primitives and deprecated groups.
The codec is pure NURL over the standard byte, slice and float-bit primitives;
it needs no external protobuf library or generated code.

This is the schema-independent layer. Field names, required-field checks,
defaults, enum membership, map keys, oneof selection and application limits
belong to the message parser. It does not parse `.proto` files or generate
message classes. See the [official encoding specification](https://protobuf.dev/programming-guides/encoding/).

## Reading a message

```nurl
$ `stdlib/ext/protobuf.nu`

// Returns the last occurrence of field 1, or the schema's default zero.
@ read_id ( Vec u ) bytes → !u64 ProtoError {
    : ~ ProtoReader r \ ( proto_reader bytes )
    : ~ u64 id # u64 0
    ~ ( proto_more r ) {
        : i offset ( proto_offset r )
        : ProtoTag tag \ ( proto_read_tag r )
        ? == . tag number 1 {
            \ ( proto_expect tag 0 offset )
            = id \ ( proto_read_uint64 r )
        } { \ ( proto_skip r tag ) }
    }
    ^ @ !u64 ProtoError { T id }
}
```

`proto_read_tag` returns `ProtoTag { number, wire }`. Test `proto_more`
before reading the next tag: EOF is a normal message boundary, but attempting
a scalar or tag read at EOF returns `ProtoTruncated`. Always check the known
field's wire type before choosing its reader. Field numbers 1 through
536870911 are accepted. Numbers 19000–19999 are reserved for schema
declarations, but can still be encountered as unknown fields on the wire.

| Protobuf type | Reader suffix | NURL result | Wire |
| --- | --- | --- | --- |
| uint64 | `uint64` | `u64` | 0 |
| int64 | `int64` | `i` | 0 |
| uint32 | `uint32` | `u32` | 0 |
| int32, enum | `int32` | `i32` | 0 |
| sint64 | `sint64` | `i` | 0 |
| sint32 | `sint32` | `i32` | 0 |
| bool | `bool` | `b` | 0 |
| fixed64 | `fixed64` | `u64` | 1 |
| sfixed64 | `sfixed64` | `i` | 1 |
| double | `double` | `f` | 1 |
| fixed32 | `fixed32` | `u32` | 5 |
| sfixed32 | `sfixed32` | `i32` | 5 |
| float | `float` | `f32` | 5 |
| bytes | `bytes` | `( Slice u )` | 2 |
| string | `string` | `String` | 2 |
| embedded message | `message` | `ProtoReader` | 2 |
| packed scalars | `packed` | `ProtoReader` | 2 |

Every reader is named `proto_read_SUFFIX`, takes `inout ProtoReader`, and
returns `!TYPE ProtoError`. `proto_read_message` advances the parent past the
payload and returns a bounded child reader. A child cannot read the parent's
remaining bytes. `proto_read_packed` returns the same bounded view without
increasing message depth; loop over its scalar reader until it is exhausted.
A final partial varint/fixed-width element fails, rather than borrowing bytes
from the next field. Accept both packed and expanded occurrences of repeated
primitives, even in the same message, and append their values in encounter order.

Duplicate scalar/string fields use the last occurrence; duplicate embedded
messages merge; repeated fields concatenate. Maps are repeated embedded entry
messages with fields 1 and 2. Oneof selection and these merge rules are schema
logic: the wire reader retains encounter order and never silently discards
duplicates. Differential tests check that re-encoding preserves the official
runtime's scalar replacement, recursive merging, packed/expanded interleaving
and unknown-field semantics.

`proto_skip(r, tag)` consumes an unknown field after its tag, including an
entire group with matching field-number end tags. A standalone end-group is
an error. For a known group, `proto_read_group(r, tag.number)` starts after its
opening tag, validates the matching end and returns a bounded child over the
contents, without either delimiter. It shares the message depth budget and
leaves the parent at the following field. Finding a group end requires a scan;
parsing the returned view then interprets its fields according to the schema.
`proto_read_raw_field(r)` starts at the tag and returns a borrowed
slice covering the complete encoded field, including group delimiters. This
retains unknown data byte-for-byte, including nonminimal varints.
`proto_validate(bytes)` checks the whole buffer's wire framing. Length-delimited
contents are opaque: only a schema can tell whether they are bytes, a string,
a packed scalar sequence or another message.

## Ownership, errors and limits

Readers are ordinary copyable values; there is no reader allocation or free.
Readers and byte slices borrow backing storage. Keep the original Vec alive
and unchanged until all its readers/slices are finished. Do not mutate reader
fields directly; use constructors and read operations. Raw `Slice` inputs have
the same valid-pointer-and-length contract as `core/slice.nu`. These lifetimes
are a caller obligation, not a compiler-enforced borrow guarantee.

`proto_read_string` validates the complete UTF-8 payload before allocating an
owned String, which the caller releases with `string_free`. Embedded NUL is
preserved; use `string_len`, since a C-string function stops at the first NUL.
Overlong UTF-8, surrogates, invalid continuations and code points above U+10FFFF
are rejected. Byte fields perform no UTF-8 validation.

Errors contain `ProtoCode code` and an absolute byte `offset` relative to the
root input. `proto_error_name(code)` returns a stable diagnostic name. A failed
read/skip leaves its reader unchanged. Earlier successful operations remain
committed; a message parser can copy its reader before a sequence if it needs
to roll the entire sequence back. There is no implicit zero-fill, clipping,
resynchronization or recovery by skipping malformed data.

| Code | Meaning |
| --- | --- |
| `ProtoTruncated` | Required bytes absent inside the current view |
| `ProtoVarintOverflow` | More than 64 bits or continuation on byte ten |
| `ProtoBadTag` | Zero field number or tag wider than 32 bits |
| `ProtoBadWire` | Wire 6/7 or a known field's unexpected wire type |
| `ProtoBadLength` | Length exceeds the signed 31-bit protobuf size limit |
| `ProtoDepth` | Message/group nesting exceeds the configured limit |
| `ProtoGroupMismatch` | Unexpected or incorrectly numbered end-group |
| `ProtoUtf8` | Invalid text at the reported byte |
| `ProtoBadRange` | Invalid constructor limit or supplied slice range |
| `ProtoSize` | Root input or accumulated output exceeds its byte limit |

The default maximum input/output size is 2147483647 bytes; the default nesting
limit is 100. `proto_reader_with_limits(slice, max_bytes, max_depth)` sets a
smaller application byte limit and a depth limit between 0 and 256. The root
has depth zero; each embedded message or open group uses one level. Packed
scalars do not. Constructors reject invalid limits before accessing input.
Length checks use remaining-byte subtraction before cursor arithmetic.

Varints terminate within ten bytes, and byte ten can contain only zero or one.
Nonminimal encodings fitting 64 bits are accepted; overflowing encodings are
rejected even if another runtime truncates them. int32/uint32/sint32 consume
a valid 64-bit varint and keep its low 32 bits, matching common protobuf
runtimes. Any nonzero varint is true. Fixed-width values use little-endian
bits; integer extremes and float bit patterns do not pass through decimal text.

Runtime is linear in bytes actually inspected; strings are validated in one
pass and copied once. Scalar, slice and child-reader results require no heap
allocation. Unknown LEN fields are skipped in constant time. Groups use bounded
stack recursion. Output and owned strings use the existing Vec/String allocation
policy: allocation failure follows the runtime's panic contract, not ProtoError.

## Writing

Create and eventually free the output with `vec_new[u]` and `vec_free[u]`.
For each scalar suffix in the table:

- `proto_put_SUFFIX(out, value)` appends a value without a tag, for packed data.
- `proto_write_SUFFIX(out, field_number, value)` appends tag and value.
- `proto_varint_size(u64)` returns the exact encoded width, 1–10 bytes.

Varints are shortest-form; negative int32/int64 take ten bytes; sint uses
ZigZag. Floats use the standard bitcast primitives. The caller controls field
order, omission of defaults and whether repeated fields are packed.

`proto_write_bytes(out, number, payload_vec)` encodes bytes, an already encoded
embedded message, or a packed buffer. `proto_write_slice` accepts a borrowed
slice, and `proto_write_string` validates and encodes a String. Payloads may
alias the destination's live bytes: the encoder preserves their offsets across
buffer growth. Validation and total-size checks precede mutation, so a reported
error leaves output bytes unchanged. `proto_write_tag(out, number, wire)` also
supports constructing matching start/end group tags; callers must pair them.

```nurl
@ encode_samples → !( Vec u ) ProtoError {
    : ( Vec u ) packed ( vec_new [u] )
    // These fixed small writes cannot fail the output-size limit.
    \ ( proto_put_sint32 packed # i32 -1 )
    \ ( proto_put_sint32 packed # i32 150 )
    : ( Vec u ) out ( vec_new [u] )
    : !v ProtoError result ( proto_write_bytes out 1 packed )
    ( vec_free [u] packed )
    ?? result {
        T → ^ @ !( Vec u ) ProtoError { T out }
        F e → { ( vec_free [u] out ) ^ @ !( Vec u ) ProtoError { F e } }
    }
}
```

For arbitrary sequences of fallible writes, keep ownership outside the function
that propagates errors, or explicitly release owned buffers on each failure.
The caller must enforce application limits on accumulated decoded values too;
a wire byte limit does not prescribe how much a schema parser may allocate.

## Verification and ONNX migration

`compiler/tests/protobuf.nu` pins literal wire vectors, all scalar boundaries,
UTF-8, group/depth validation, aliasing, rollback and nested reader isolation.
`tools/tests/test_protobuf.py` generates all-scalar and nested messages using
the official Python protobuf runtime and compares semantics in both directions.
It also compares malformed/truncated/random framing against an independent
iterative parser. Both run under sanitizers; the latter requires Python
`protobuf==7.36.1`, a test dependency only. CI runs both normal and sanitized
differential checks, with leak detection enabled.

The current `packages/onnx/src/pb.nu` remains in place until the next toolchain
release ships this module. Then migrate `model.nu` to `proto_reader`, checked
tag/scalar operations and bounded children, and propagate ProtoError through
model loading. Replace raw tensor extraction with a checked byte slice followed
by the tensor's dtype/shape validation; preserve float bits when copying.
Accept both packed and expanded tensor metadata. Keep unknown-field skipping
and validate each message's wire types. Remove the old decoder only after ONNX
model/inference regressions and malformed-model tests pass with the released
toolchain. This migration deliberately requires no compatibility wrapper that
converts decode failures into zeros.
