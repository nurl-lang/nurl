// put_safe.nu — writing every element of a Vec, safe, bounds-checked. tools/vec_parity.sh compares the pair.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_zeroed [i] 1000000 )
    : ~ i r 0
    ~ < r 200 { : ~ i k 0 : i n ( vec_len [i] v ) ~ < k n { ( vec_put [i] v k + k r ) = k + k 1 } = r + r 1 }
    ( nurl_println_int ( vec_at [i] v 999 ) )
    ^ 0
}
