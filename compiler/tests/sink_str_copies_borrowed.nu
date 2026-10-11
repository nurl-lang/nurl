// A raw string handed to a parameter that takes it over: in safe code only
// a declared `sink s` does, and its callee releases it. A caller hands over
// a string it owns — its own binding's, or a fresh temporary — and a copy
// of anything else: a literal, a view of a String, a borrowed parameter, a
// field, a result owned on only some paths. A safe function handing its own
// borrowed parameter to `string_adopt` passes a copy, and the caller keeps
// its string. A closure value is handed fresh temporaries it only borrows.
$ `stdlib/core/string.nu`
$ `stdlib/core/option.nu`

: Rec { s name i n }

@ take sink s x → i { ^ ( strlen x ) }

@ via s p → i { ^ ( string_len ( string_adopt p ) ) }

@ mk b c → s { ? c { ^ ( nurl_str_cat `fr` `esh` ) } {} ^ `lit` }

@ pick s a → s { ^ a }

@ back → s { : s x ( nurl_str_cat `ret` `urned` ) ^ ( pick x ) }

@ main → i {
    : s m ( nurl_str_cat `ab` `cd` )
    : String b ( string_from `hello` )
    : Rec r @ Rec { `field` 1 }
    : s lit `bound literal`
    : ~ i t 0
    = t + t ( take m )
    = t + t ( take `direct` )
    = t + t ( take lit )
    = t + t ( take ( string_data b ) )
    = t + t ( take . r name )
    = t + t ( take ( nurl_str_cat `x` `y` ) )
    = t + t ( take ( mk T ) )
    = t + t ( take ( mk F ) )
    : s mm ( nurl_str_cat `keep` `me` )
    = t + t ( via mm )
    = t + t ( via `lit` )
    ( nurl_println mm )
    : String a ( string_adopt `adopted literal` )
    : ?s o @ ?s { F }
    : s d ( nurl_str_cat `def` `ault` )
    ( nurl_println ( opt_unwrap_or [s] o d ) )
    ( nurl_println ( opt_unwrap_or [s] o `literal default` ) )
    : ( @ i s ) f \ s x → i { ^ ( strlen x ) }
    = t + t ( f ( nurl_str_cat `tm` `p` ) )
    ( nurl_println ( back ) )
    ( nurl_println_int + t ( string_len a ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
