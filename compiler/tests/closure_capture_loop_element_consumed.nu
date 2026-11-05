// closure_capture_loop_element_consumed.nu — a closure that hands a
// captured `~` loop element to a callee that keeps it.
//
// A `~` loop element handed to a consumer leaves its container: the
// element's slot is emptied (`__eslot`). The closure body inherited that
// slot for a capture of the element. The slot is the enclosing function's
// element pointer, a register the body does not have, and emptying it was
// IR clang rejected ("use of undefined value"). nurldb's ParAgg had this
// shape, and no build saw it until every package entry was lowered to IR.
// In the body the capture is its own snapshot: the callee keeps a copy of
// it, and the container keeps every element.

$ `stdlib/core/vec.nu`

// Keeps its argument in an owner that drops it.
@ keep ( Vec i ) row → i {
    : ( Vec ( Vec i ) ) h ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] h row )
    ^ ( vec_len [i] ( vec_at [( Vec i )] h 0 ) )
}

@ call_with ( @ i ) f → i { ^ ( f ) }

@ main → i {
    : ( Vec ( Vec i ) ) rows ( vec_new [( Vec i )] )
    : ~ i r 0
    ~ < r 3 {
        : ( Vec i ) row ( vec_new [i] )
        : ~ i k 0
        ~ <= k r { ( vec_push [i] row + * r 10 k ) = k + k 1 }
        ( vec_push [( Vec i )] rows row )
        = r + r 1
    }
    : ~ i kept 0
    ~ row rows {
        = kept + kept ( call_with \ → i { ^ ( keep row ) } )
    }
    ( nurl_print `kept: ` ) ( nurl_println_int kept )
    : ~ i n 0
    : ~ i sum 0
    ~ row rows {
        = n + n ( vec_len [i] row )
        ~ x row { = sum + sum x }
    }
    ( nurl_print `left: ` ) ( nurl_print_int n ) ( nurl_print `, sum ` ) ( nurl_println_int sum )
    ^ 0
}
