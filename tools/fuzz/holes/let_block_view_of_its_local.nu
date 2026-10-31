// let_block_view_of_its_local: agora #222 — `: V v { : W w ( mkw ) ( view_of w ) }`: the block's tail call lends a value holding a view of the block's own local (let_block_view_of_its_local).
// Closed: rule (A) copies a value lent out of a block's own local only when its type holds no view; a copy of `V` would still view `w`, so it is refused.
// main: accepted; LeakSanitizer reported a leak, and `v.bytes` viewed the freed buffer.
// map: §7.6 | A2 | rejected | - | agora #222: a typed binding of a block whose tail call lends a value holding a view of the block's own local
$ `stdlib/core/string.nu`

: W { String s }
: V { String tag ( Slice u8 ) bytes }

@ view_of W w → V { ^ @ V { ( string_from `tag` ) ( string_bytes . w s ) } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ main → i {
    : V v {
        : W w ( mkw )
        ( view_of w )
    }
    ( nurl_println_int ( slice_len [u8] . v bytes ) )
    ^ 0
}
