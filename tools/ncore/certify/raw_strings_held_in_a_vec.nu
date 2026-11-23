$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : s a ( nurl_str_cat `ab` `cd` )
    : s b ( nurl_str_cat `ef` `` )
    : ~ ( Vec s ) names ( vec_new [s] )
    ( vec_push [s] names a )
    ( vec_push [s] names b )
    : s x ( vec_at [s] names 1 )
    ( nurl_println x )
    ^ ( vec_len [s] names )
}
