$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ~ ( Vec s ) names ( vec_new [s] )
    {
        : s a ( nurl_str_cat `ab` `cd` )
        ( vec_push [s] names a )
    }
    : s x ( vec_at [s] names 0 )
    ( nurl_println x )
    ^ ( vec_len [s] names )
}
