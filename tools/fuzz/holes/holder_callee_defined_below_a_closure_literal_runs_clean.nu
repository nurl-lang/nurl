// holder_callee_defined_below_a_closure_literal_runs_clean: a function calls a holder callee defined below it, which hands back only a literal, then builds a closure literal; the String it held is released before the holder is read.
// Closed: a closure literal's own walk set-up no longer empties the enclosing function's `rvcallees`: the function is still walked after the callee it waits for, which answers "views nothing" (__gen_closure_expr).
// main 4f15689: accepted; ran clean.
// map: §6.2 | A2 | runs-clean | - | agora #422: a holder callee defined below, then a closure literal: the answer is the callee's, not "may"
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f → i {
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : String t ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( g t )
    }
    : ( @ i ) c \ → i { ^ 1 }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ ( c )
}

@ g String t → ( Vec s ) { ^ ( h t ) }

@ h String t → ( Vec s ) {
    : ( Vec s ) v ( vec_new [s] )
    ( vec_push [s] v `a static literal` )
    ^ v
}

@ main → i { ^ - ( f ) 1 }
