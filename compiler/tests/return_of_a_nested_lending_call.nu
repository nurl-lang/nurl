// return_of_a_nested_lending_call.nu — a function that returns what a call
// lends, where that call's argument is itself a call lending a parameter
// (Agora #777): `^ ( id0 ( id0 p ) )`, a field of a struct parameter, a
// join inside the chain, three levels deep, a generic lender, a lender
// defined below its caller, and a temporary argument. The result is a lend
// of the parameter, so the caller keeps the argument it owns and releases
// it once; before, the chain lent nothing in the summary and the caller
// released the argument under the result.

$ `stdlib/core/string.nu`

: O { String name i n }

@ id0 String x → String { ^ x }

@ pick String a String b → String { ^ b }

@ gb [A] A x → A { ^ x }

@ two String p → String { ^ ( id0 ( id0 p ) ) }

@ three String p → String { ^ ( id0 ( id0 ( id0 p ) ) ) }

@ of_field O p → String { ^ ( id0 ( id0 . p name ) ) }

@ through_pick String p String q → String { ^ ( id0 ( pick ( id0 p ) q ) ) }

@ generic String p → String { ^ ( gb [String] ( gb [String] p ) ) }

@ below_first String p → String { ^ ( below ( below p ) ) }

@ below String x → String { ^ x }

@ fresh_inner String p → String { ^ ( id0 ( string_clone p ) ) }

@ main → i {
    : String a ( string_from `the first argument, long enough for the heap` )
    : String b ( string_from `the second argument, long enough for the heap` )
    : O o @ O { ( string_from `the struct's name, long enough for the heap` ) 1 }

    : String r2 ( two a )
    ( nurl_println ( string_data r2 ) )
    : String r3 ( three a )
    ( nurl_println ( string_data r3 ) )
    : String rf ( of_field o )
    ( nurl_println ( string_data rf ) )
    : String rp ( through_pick a b )
    ( nurl_println ( string_data rp ) )
    : String rg ( generic b )
    ( nurl_println ( string_data rg ) )
    : String rb ( below_first a )
    ( nurl_println ( string_data rb ) )
    : String rc ( fresh_inner a )
    ( nurl_println ( string_data rc ) )

    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ( nurl_println ( string_data . o name ) )

    // A temporary argument: the result lends it, so it lives as long as
    // the result does.
    : String rt ( two ( string_from `a temporary argument, long enough heap` ) )
    ( nurl_println ( string_data rt ) )
    ^ 0
}
