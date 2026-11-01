// A closure cannot give one of its captures, or its own `inout`
// parameter, a value that may hold a view: a closure's type does not say
// what running it stores, so nothing where it runs follows the view, and
// what it points into could be released first (agora #312). The message
// points at a function's `inout` parameter, which every call follows.

$ `stdlib/core/string.nu`

: W { s v }

@ main → i {
    : String a ( string_from `the outer string` )
    : ~ W w @ W { `literal` }
    : ( @ v ) repoint \ → v { = . w v ( string_data a ) }
    ( repoint )
    : ( @ v inout W ) setw \ inout W x → v { = x @ W { ( string_data a ) } }
    ( setw w )
    ( nurl_println . w v )
    ^ 0
}
