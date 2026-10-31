// borrow_let_block_view_of_its_local.nu — agora #222 stage 1 (rule (A)). The block's
// tail call lends a `V` out of the block's own local `w`, which ends at the
// block's `}`: a `V` holds a view, so a copy of it would still view `w`. It is
// refused; the message says where to declare `w` instead.

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
