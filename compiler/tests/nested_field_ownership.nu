// nested_field_ownership.nu — a field of a struct held by value inside a
// binding (`. . o b name`) is that binding's own storage, owned exactly as
// a direct field (`. o tag`) is.
//
// Moving one into a `sink` parameter empties it in place, so the outer
// struct does not drop it again (it did: a double free). Replacing one
// (`= . . o b items …`) drops the value it held — through an `inout`
// parameter the caller's — and a binding that only borrows its value (a
// copy of a Vec element) owns the field it is given from there (each of
// those leaked). Run under ASan / LSan by the sanitizer suite.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bag { ( Vec String ) items String name }
: Outer { Bag b String tag }
: Outer2 { Outer x i k }

@ fresh_outer → Outer {
    : Bag b @ Bag { ( vec_new [String] ) ( string_from `bag name on the heap, long enough` ) }
    ( vec_push [String] . b items ( string_from `an element string on the heap` ) )
    ^ @ Outer { b ( string_from `tag on the heap, long enough` ) }
}

@ eat sink String x → i { ^ ( string_len x ) }

@ eatv sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ reset inout Outer o → v { = . . o b name ( string_from `replacement name, long enough` ) }

@ main → i {
    // moved into a sink: whole field, a Vec field, and through a binding
    : ~ Outer a ( fresh_outer )
    ( nurl_println_int ( eat . . a b name ) )
    ( nurl_println_int ( eatv . . a b items ) )
    : ~ Outer c ( fresh_outer )
    : String t . . c b name
    ( nurl_println_int ( eat t ) )

    // replaced: a Vec field, a String field, a whole nested struct, three
    // levels down, and through an inout parameter
    : ~ Outer o ( fresh_outer )
    = . . o b items ( vec_new [String] )
    = . . o b name ( string_from `a new name` )
    ( nurl_println_int + ( vec_len [String] . . o b items ) ( string_len . . o b name ) )
    : ~ Outer2 p @ Outer2 { ( fresh_outer ) 1 }
    = . . . p x b items ( vec_new [String] )
    = . . p x tag ( string_from `x` )
    ( nurl_println_int + ( vec_len [String] . . . p x b items ) ( string_len . . p x tag ) )
    : ~ Outer q ( fresh_outer )
    ( reset q )
    ( nurl_println_int ( string_len . . q b name ) )

    // taken out, then replaced: the binding keeps the old value
    : ~ Outer w ( fresh_outer )
    : String old . . w b name
    ( mem_take old )
    = . . w b name ( string_from `newer` )
    ( nurl_println_int + ( string_len old ) ( string_len . . w b name ) )

    // a borrowing copy: the field it is given is its own
    : ( Vec Outer ) os ( vec_new [Outer] )
    ( vec_push [Outer] os ( fresh_outer ) )
    ?? ( vec_get [Outer] os 0 ) {
        T r0 → {
            : ~ Outer r r0
            = . . r b name ( string_from `replaced name, long enough to be heap` )
            ( nurl_println_int ( string_len . . r b name ) )
        }
        F → {}
    }
    ?? ( vec_get [Outer] os 0 ) { T r1 → { ( nurl_println_int ( string_len . . r1 b name ) ) } F → {} }
    ^ 0
}
