// closure_handed_a_binding_it_only_reads.nu — the routes Agora #445's rule
// follows, with closures that only read their capture, and one that gives
// its capture a new value but is handed another binding: each runs clean.
// (A function calling the closure with the binding, a literal passed inline,
// a nested closure, an element, a view and a payload of the binding.)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ run1 ( @ v String ) f String x → v { ( f x ) }

@ app ( @ v String ) f String x → v { ( f x ) }

@ main → i {
    : ~ String o ( string_from `the owner string long enough for the heap` )
    : ~ String q ( string_from `another` )
    : ( @ v String ) rd \ String p → v { ( nurl_println_int + ( string_len o ) ( string_len p ) ) }
    ( run1 rd o )
    ( app \ String p → v { ( nurl_println_int + ( string_len o ) ( string_len p ) ) } o )
    : ( @ v ) inner \ → v { ( nurl_println_int ( string_len o ) ) }
    : ( @ v String ) c1 \ String p → v { ( inner ) ( nurl_println ( string_data p ) ) }
    ( c1 o )
    : ~ ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `the owner string long enough for the heap` ) )
    : ( @ v String ) c2 \ String p → v { ( nurl_println_int + ( vec_len [String] vs ) ( string_len p ) ) }
    ( c2 ( vec_at [String] vs 0 ) )
    : ( @ v s ) c3 \ s p → v { ( nurl_println_int ( string_len o ) ) ( nurl_println p ) }
    ( c3 ( string_data o ) )
    : ~ ? String oo @ ?String { T ( string_from `the owner string long enough for the heap` ) }
    : ( @ v String ) c4 \ String p → v { ?? oo { T z → { ( nurl_println_int ( string_len z ) ) } F → {} } ( nurl_println ( string_data p ) ) }
    ?? oo { T e → { ( c4 e ) } F → {} }
    : ( @ v String ) c5 \ String p → v { = o ( string_from `new` ) ( nurl_println ( string_data p ) ) }
    ( c5 q )
    ( nurl_println ( string_data o ) )
    ^ 0
}
