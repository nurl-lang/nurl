$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_with_cap [i] 4 )
    ( vec_push [i] v 10 )
    ( vec_push [i] v 20 )
    ( vec_push [i] v 30 )
    ( vec_push [i] v 40 )

    : ( Slice i ) s ( slice_from_vec [i] v )
    ( nurl_print `len=` ) ( nurl_print ( nurl_str_int ( slice_len [i] s ) ) ) ( nurl_print `\n` )

    : *i p ( slice_data [i] s )
    ( nurl_print `first via ptr=` ) ( nurl_print ( nurl_str_int . p 0 ) ) ( nurl_print `\n` )

    : ?i g0 ( slice_get [i] s 0 )
    ?? g0 {
        T x → { ( nurl_print `get(0)=` ) ( nurl_print ( nurl_str_int x ) ) ( nurl_print `\n` ) }
        F → ( nurl_print `get(0)=none\n` )
    }
    : ?i g99 ( slice_get [i] s 99 )
    ?? g99 {
        T x → { ( nurl_print `oob hit\n` ) }
        F → ( nurl_print `oob ok\n` )
    }

    : ?( Slice i ) sub_o ( slice_sub [i] s 1 3 )
    ?? sub_o {
        T sub → {
            ( nurl_print `sub_len=` ) ( nurl_print ( nurl_str_int ( slice_len [i] sub ) ) ) ( nurl_print `\n` )
            : *i sp ( slice_data [i] sub )
            ( nurl_print `sub[0]=` ) ( nurl_print ( nurl_str_int . sp 0 ) ) ( nurl_print `\n` )
            ( nurl_print `sub[1]=` ) ( nurl_print ( nurl_str_int . sp 1 ) ) ( nurl_print `\n` )
        }
        F → ( nurl_print `sub none\n` )
    }

    : ?i first ( slice_first [i] s )
    ?? first { T x → { ( nurl_print `first=` ) ( nurl_print ( nurl_str_int x ) ) ( nurl_print `\n` ) } F → {} }
    : ?i last ( slice_last [i] s )
    ?? last { T x → { ( nurl_print `last=` ) ( nurl_print ( nurl_str_int x ) ) ( nurl_print `\n` ) } F → {} }

    ( vec_free [i] v )
    ^ 0
}
