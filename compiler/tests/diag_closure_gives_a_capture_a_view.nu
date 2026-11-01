// A closure cannot give one of its captures, or its own `inout`
// parameter, a value that may hold a view: a closure's type does not say
// what running it stores, so nothing where it runs follows the view, and
// what it points into could be released first (agora #312). The message
// points at a function's `inout` parameter, which every call follows.
// A capture or a parameter of the closure stored whole is named for what
// it holds: the view it is, or the views an owner of views holds (agora
// #331). A value of the target itself is "a value that may hold a view".

$ `stdlib/core/string.nu`

: W { s v }

@ main → i {
    : String a ( string_from `the outer string` )
    : ~ W w @ W { `literal` }
    : ( @ v ) repoint \ → v { = . w v ( string_data a ) }
    ( repoint )
    : ( @ v inout W ) setw \ inout W x → v { = x @ W { ( string_data a ) } }
    ( setw w )
    : ( @ v s ) setv \ s p → v { = w @ W { p } }
    ( setv ( string_data a ) )
    : ~ ( Vec s ) ws ( vec_new [s] )
    : ~ ( Vec s ) other ( vec_new [s] )
    ( vec_push [s] other ( string_data a ) )
    : ( @ v ) swap \ → v { = ws other }
    ( swap )
    : ( @ v ) again \ → v { : s e ( vec_at [s] ws 0 ) ( vec_push [s] ws e ) }
    ( again )
    ( nurl_println . w v )
    ^ 0
}
