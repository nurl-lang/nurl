// sum_raw.nu — the sum of a Vec's elements, raw pointer (the baseline). tools/vec_parity.sh compares the pair.
$ `stdlib/core/vec.nu`

unsafe @ main → i {
    : ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k 1000000 { ( vec_push [i] v k ) = k + k 1 }
    : ~ i sum 0
    : ~ i r 0
    ~ < r 200 { = k 0 : i n ( vec_len [i] v ) : *i p ( vec_data [i] v ) ~ < k n { = sum + sum . p k = k + k 1 } = r + r 1 }
    ( nurl_println_int sum )
    ^ 0
}
