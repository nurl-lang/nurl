// get_safe.nu — the sum through vec_get's Option, safe, bounds-checked. tools/vec_parity.sh compares the pair.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k 1000000 { ( vec_push [i] v k ) = k + k 1 }
    : ~ i sum 0
    : ~ i r 0
    ~ < r 200 { = k 0 : i n ( vec_len [i] v ) ~ < k n { ?? ( vec_get [i] v k ) { T x → { = sum + sum x } F → {} } = k + k 1 } = r + r 1 }
    ( nurl_println_int sum )
    ^ 0
}
