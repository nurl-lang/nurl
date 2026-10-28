// diag_view_of_call_temporary.nu — a view of a call's temporary argument
// kept past the call that uses it (agora #138).
//
// `( first ( string_from … ) )` makes a String no binding owns; `first`
// hands back a view of it. The String is dropped once a call further out
// is done with the view — `( nurl_println ( first ( … ) ) )` — and a
// binding, a return, an assignment, a closure over it or a callee that
// keeps it consume nothing: the String could never be dropped (it
// leaked), and dropping it at the statement's end would leave the view
// dangling. Each is rejected, naming the call whose result views it;
// binding the argument first (`: String t ( … )`) is the fix.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first String s → s { ^ ( string_data s ) }

@ mk String s → ( @ v ) { ^ \ → v { ( nurl_println ( string_data s ) ) } }

@ keep ( Vec s ) names s x → i { ( vec_push [s] names x ) ^ ( vec_len [s] names ) }

@ bound → i {
    : s v ( first ( string_from `a string long enough to own a heap buffer here` ) )
    ^ ( nurl_str_len v )
}

@ returned → s { ^ ( first ( string_from `a string long enough to own a heap buffer here` ) ) }

@ assigned → i {
    : ~ s outer ``
    {
        = outer ( first ( string_from `a string long enough to own a heap buffer here` ) )
    }
    ^ ( nurl_str_len outer )
}

@ closure → v {
    : ( @ v ) g ( mk ( string_from `a string long enough to own a heap buffer here` ) )
    ( g )
}

@ kept ( Vec s ) names → i { ^ ( keep names ( first ( string_from `a string long enough to own a heap buffer here` ) ) ) }

@ main → i {
    : ( Vec s ) names ( vec_new [s] )
    ( closure )
    ^ + + + ( bound ) ( nurl_str_len ( returned ) ) ( assigned ) ( kept names )
}
