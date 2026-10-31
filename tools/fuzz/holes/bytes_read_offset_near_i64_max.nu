// bytes_read_offset_near_i64_max: `( bytes_read_u64_le v 9223372036854775806 )`: the range test
// computed `off + 8`, which wraps negative, so the read went to
// `data + off` — any address. All six bytes_read_* readers.
// Closed: the offset is tested against `len - width`.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
// map: §3.3d | B | runs-clean | h442 | `( bytes_read_u64_le v 9223372036854775806 )`: the range test computed `off + 8`, which wraps negative, so the read went to `data + off` — any address. All six bytes_read_* readers.
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

@ main → i {
    : ( Vec u ) v ( bytes_from_str `abcdefgh` )
    ?? ( bytes_read_u64_le v 9223372036854775806 ) {
        T x → { ( nurl_println_int # i x ) }
        F → { ( nurl_println `none` ) }
    }
    ^ 0
}
