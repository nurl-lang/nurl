// closure_param_borrowed.nu — a closure only borrows its parameters
// (docs/MEMORY.md §7.5).
//
// A call through a closure value cannot see what the body does with its
// arguments. So the caller keeps what it passes and drops the temporaries
// it made for the call; what the body stores or hands back — a parameter,
// a field of one, a join over them, the fall-off tail — is a copy; and a
// field handed TO a closure is not "taken". Each shape below used to free
// twice or leak.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ show s label i n → v { ( nurl_print label ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` ) }

: P { String a i n }
: W { String w }

@ shapes → i {
    : String n ( string_from `named` )
    : P p @ P { ( string_from `pa` ) 1 }
    : ( Vec String ) out ( vec_new [String] )
    : ( Vec P ) ps ( vec_new [P] )
    : ( @ String String ) ret \ String s → String { ^ s }
    : ( @ String String ) tail \ String s → String { s }
    : ( @ String P ) field \ P q → String { ^ . q a }
    : ( @ String String ) alias \ String s → String { : String q s ^ q }
    : ( @ String String ) join \ String s → String { ^ ? > ( string_len s ) 0 s ( string_from `e` ) }
    : ( @ v String ) put \ String s → v { ( vec_push [String] out s ) }
    : ( @ v P ) putp \ P q → v { ( vec_push [P] ps q ) }
    : ( @ v P ) putf \ P q → v { ( vec_push [String] out . q a ) }
    : ( @ W String ) wrap \ String s → W { ^ @ W { s } }
    : ( @ i String ) len \ String s → i { ^ ( string_len s ) }
    : String r1 ( ret n )
    : String r2 ( tail n )
    : String r3 ( field p )
    : String r4 ( alias n )
    : String r5 ( join n )
    : String r6 ( ret ( string_from `tmp` ) )
    ( put n )
    ( put ( string_from `tmp2` ) )
    ( putp p )
    ( putf p )
    : W w ( wrap n )
    : i k ( len ( string_from `tmp3` ) )
    ^ + ( vec_len [String] out ) k
}

@ main → i {
    : i b0 ( live )
    ( show `shapes` ( shapes ) )
    // Every *_free_with lends the hook each element and then releases it.
    // (A closure captures a scalar by value: the hook reports through a Vec.)
    : ( Vec i ) seen ( vec_new [i] )
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `x` ) )
    ( vec_push [String] v ( string_from `yy` ) )
    ( vec_free_with [String] v \ String s → v { ( vec_push [i] seen ( string_len s ) ) } )
    ( show `seen` ( vec_len [i] seen ) )
    ( vec_free [i] seen )
    ( show `left` - ( live ) b0 )
    ^ 0
}
