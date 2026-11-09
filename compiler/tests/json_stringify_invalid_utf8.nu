// json_stringify_invalid_utf8.nu — the writer's output is UTF-8 whatever
// bytes a string held (RFC 8259 §8.1, agora #516).
//
// __json_str copied every byte of 0x80 and up as it was, so a String of
// bytes from outside (a model's sampled tokens, a file, a socket) came out
// as a JSON text a strict reader rejects. Now a well-formed sequence goes
// out as it is and each byte that is not part of one is U+FFFD (EF BF BD),
// one per byte, as std/utf8's decoder recovers. Each case prints the bytes
// json_stringify wrote between the quotes, in hex, and whether they are
// UTF-8 (utf8_valid). The long cases cross the writer's 16-byte steps.

$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/utf8.nu`

@ __hex1 i v → i { ^ ? < v 10 + 48 v + 55 v }

@ show s label ( Vec u ) raw → v {
    : String text ( bytes_to_str raw )
    : String out ( json_stringify ( json_str_lit ( string_data text ) ) )
    : s o ( string_data out )
    : ( Slice u ) ov ( slice_of_str o )
    : String hex ( string_with_cap 64 )
    : ~ i k 1
    ~ < k - ( nurl_str_len o ) 1 {
        : i b ( slice_byte ov k )
        ( string_push_char hex 32 )
        ( string_push_char hex ( __hex1 & >> b 4 15 ) )
        ( string_push_char hex ( __hex1 & b 15 ) )
        = k + k 1
    }
    ( nurl_print label ) ( nurl_print `:` ) ( nurl_print ( string_data hex ) )
    ( nurl_print ? ( utf8_valid o ) ` (utf8)\n` ` (NOT utf8)\n` )
}

@ bytes1 i a → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) ( vec_push [u] v # u a ) ^ v }

@ main → i {
    // 'A' E2 'A': a 3-byte sequence cut short by an ASCII byte.
    : ( Vec u ) t ( vec_new [u] ) ( vec_push [u] t 65 ) ( vec_push [u] t 226 ) ( vec_push [u] t 65 )
    ( show `truncated` t )
    // C0 80: an overlong NUL.
    : ( Vec u ) o ( vec_new [u] ) ( vec_push [u] o 192 ) ( vec_push [u] o 128 )
    ( show `overlong` o )
    // ED A0 80: U+D800 encoded as if it were a scalar.
    : ( Vec u ) g ( vec_new [u] ) ( vec_push [u] g 237 ) ( vec_push [u] g 160 ) ( vec_push [u] g 128 )
    ( show `surrogate` g )
    // 80 BF: continuation bytes with no leader.
    : ( Vec u ) c ( vec_new [u] ) ( vec_push [u] c 128 ) ( vec_push [u] c 191 )
    ( show `stray continuation` c )
    // F0 9F 98: a 4-byte sequence cut off at the end.
    : ( Vec u ) e ( vec_new [u] ) ( vec_push [u] e 240 ) ( vec_push [u] e 159 ) ( vec_push [u] e 152 )
    ( show `truncated at end` e )
    // FF: a byte no sequence starts with.
    ( show `invalid leader` ( bytes1 255 ) )
    // Well-formed text is unchanged: é, €, 😀.
    : ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w 195 ) ( vec_push [u] w 169 )
    ( vec_push [u] w 226 ) ( vec_push [u] w 130 ) ( vec_push [u] w 172 )
    ( vec_push [u] w 240 ) ( vec_push [u] w 159 ) ( vec_push [u] w 152 ) ( vec_push [u] w 128 )
    ( show `well-formed` w )
    // Across 16-byte steps: 14 ASCII bytes, then € straddling the block
    // edge, then a bad byte, then an escape and more ASCII.
    : ( Vec u ) x ( vec_new [u] )
    : ~ i i 0
    ~ < i 14 { ( vec_push [u] x 97 ) = i + i 1 }
    ( vec_push [u] x 226 ) ( vec_push [u] x 130 ) ( vec_push [u] x 172 )
    ( vec_push [u] x 254 ) ( vec_push [u] x 34 )
    = i 0
    ~ < i 18 { ( vec_push [u] x 98 ) = i + i 1 }
    ( show `across blocks` x )
    ^ 0
}
