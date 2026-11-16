// Loop jumps around a closure literal (agora #871). A closure body is a
// function body: its `break` / `continue` leave a loop written inside it,
// and its `^` returns from the closure. The enclosing loop's labels are
// cut off inside the body and are back after it, so the enclosing loop's
// own `break` after the literal still leaves it.
$ `stdlib/core/vec.nu`

@ app ( @ i ) f → i { ^ ( f ) }

@ main → i {
    : ~ i n 0
    : ~ i last 0
    ~ < n 4 {
        : i r ( app \ → i {
            : ~ i k 0
            ~ T { ? > k 2 { break } {} = k + k 1 }
            ? == k 3 {
                : ~ i j 0
                ~ < j 5 { = j + j 1 ? == j 2 { continue } {} }
                ^ j
            } {}
            ^ 0
        } )
        = last r
        : ( Vec i ) xs ( vec_new [i] )
        ( vec_push [i] xs 4 ) ( vec_push [i] xs 9 )
        : i first ( app \ → i {
            : ~ i got 0
            ~ x xs { ? > x 5 { = got x break } {} }
            ^ got
        } )
        = last + last - first 9
        = n + n 1
        ? == r 5 { break } {}
    }
    ^ + n last
}
