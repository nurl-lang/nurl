// A Vec of raw strings filled with owned text and with a view, then read.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_from `abc` )
    : s a ( nurl_str_cat `x` `y` )
    : ~ ( Vec s ) names ( vec_new [s] )
    ( vec_push [s] names a )
    ( vec_push [s] names ( string_data t ) )
    : ~ i k 0
    : ~ i acc 0
    ~ < k ( vec_len [s] names ) {
        : s x ( vec_at [s] names k )
        = acc + acc ( nurl_str_len x )
        = k + k 1
    }
    ^ acc
}
