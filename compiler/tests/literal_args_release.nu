// literal_args_release.nu — a struct / option / result literal built as a
// call's argument releases what it made or copied once the call is done,
// unless the callee keeps or consumes the argument.
//
// `( use @ P { ( string_from `x` ) 1 } )`, `( api `PUT` @ ?Json { T a } )`:
// the literal's fresh fields (and copies of borrowed ones) had no owner
// after the call — every call leaked them (the anomaly package's MCP edit
// path leaked its patch body this way). A field that IS a binding's value
// stays that binding's when the callee only borrows the argument, and goes
// with the argument when the callee keeps it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: P { String s i n }

@ use P p → i { ^ ( string_len . p s ) }

@ use_opt ? String o → i { ^ ?? o { T s → ( string_len s ) F → 0 } }

@ use_res ! String i r → i { ^ ?? r { T s → ( string_len s ) F e → e } }

@ keep ( Vec P ) v P p → v { ( vec_push [P] v p ) }

@ round → i {
    : String mine ( string_from `mine` )
    : ~ i t 0
    = t + t ( use @ P { ( string_from `fresh` ) 1 } )
    = t + t ( use @ P { mine 2 } )
    = t + t ( use_opt @ ?String { T ( string_from `opt` ) } )
    = t + t ( use_opt @ ?String { T mine } )
    = t + t ( use_res @ !String i { T ( string_from `ok` ) } )
    : ( Vec P ) kept ( vec_new [P] )
    ( keep kept @ P { ( string_from `kept` ) 3 } )
    : i mine_len ( string_len mine )
    ( keep kept @ P { mine 4 } )  // moves `mine` into the kept P
    ^ + + t ( vec_len [P] kept ) mine_len
}

@ main → i {
    : i r ( round )
    : i l0 ( live )
    : ~ i k 0
    ~ < k 20 { : i x ( round ) = k + k 1 }
    ( nurl_println ( nurl_str_cat `result ` ( nurl_str_int r ) ) )
    ( nurl_println ? == l0 ( live ) `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - ( live ) l0 ) ) )
    ^ 0
}
