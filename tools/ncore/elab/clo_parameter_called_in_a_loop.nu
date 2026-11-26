// A function takes a closure and calls it in a loop.
@ apply_n ( @ i i ) f i n → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k n {
        = acc ( f acc )
        = k + k 1
    }
    ^ acc
}

@ main → i {
    : i step 3
    : ( @ i i ) add \ i x → i { ^ + x step }
    ^ ( apply_n add 4 )
}
