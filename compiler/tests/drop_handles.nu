// drop_handles.nu — String, Vec and the structs that hold them are
// dropped by the compiler (docs/MEMORY.md §7.6). Nothing below frees by
// hand. Run under LeakSanitizer it is leak-clean; under ASan it is free of
// double-free and use-after-free.

$ `stdlib/core/string.nu`

: Person { String name ( Vec i ) scores }
: Pair { String key i n }

// Builds and returns: the locals move into the struct.
@ mk_person s n i sc → Person {
    : String nm ( string_from n )
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v sc )
    ^ @ Person { nm v }
}

// Appends in place; returns a fresh String.
@ greet String who → String {
    : ~ String out ( string_from `hi ` )
    ( string_push_str out ( string_data who ) )
    ^ out
}

// A field out of a struct this function owns: the caller gets a copy.
@ name_of_new s n → String {
    : Person p ( mk_person n 0 )
    ^ . p name
}

// A borrowed element found and returned inside an Option: lent.
@ find ( Vec String ) v s want → i {
    : ~ i k 0
    ~ < k ( vec_len [String] v ) {
        ?? ( vec_get [String] v k ) {
            T x → { ? ( nurl_str_eq ( string_data x ) want ) { ^ k } {} }
            F → {}
        }
        = k + k 1
    }
    ^ -1
}

// A fresh Option: its payload is owned by the arm that binds it.
@ maybe s x → ?String {
    ? ( nurl_str_eq x `` ) { ^ @ ?String { F } } {}
    ^ @ ?String { T ( string_from x ) }
}

// A join hands over what an arm owns and lends what it borrows; a
// returned binding that only borrows is copied on the way out.
@ pick b c s x → String {
    : String kept ( string_from `outer` )
    : String s ? c ( string_from x ) kept
    ^ s
}

@ main → i {
    : String a ( string_from `alpha` )
    : String g ( greet a )
    ( nurl_println ( string_data g ) )  // hi alpha

    // Moved into a container; still readable through the container.
    : ( Vec String ) names ( vec_new [String] )
    ( vec_push [String] names ( string_from `x` ) )
    ( vec_push [String] names a )
    ( nurl_println_int ( find names `alpha` ) )  // 1

    // A borrowed element stored into a second owner is copied.
    : ( Vec Pair ) pairs ( vec_new [Pair] )
    ?? ( vec_get [String] names 0 ) {
        T s → ( vec_push [Pair] pairs @ Pair { s 7 } )
        F → {}
    }
    ( nurl_println_int ( vec_len [Pair] pairs ) )  // 1

    // Structs: built, read, field returned.
    : Person p ( mk_person `bob` 3 )
    ( nurl_println ( string_data . p name ) )  // bob
    : String nn ( name_of_new `carol` )
    ( nurl_println ( string_data nn ) )  // carol

    // A cursor over a Vec, re-pointed in a loop.
    : ( Vec ( Vec i ) ) rows ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] rows ( vec_new [i] ) )
    : ~ ( Vec i ) cur ( vec_new [i] )
    : ~ i k 0
    ~ < k 3 {
        : ( Vec i ) fresh ( vec_new [i] )
        ( vec_push [i] fresh k )
        = cur fresh
        = k + k 1
    }
    ( nurl_println_int ( vec_len [i] cur ) )  // 1

    // Option payloads: read, moved into a container, released by hand.
    ?? ( maybe `opt` ) { T x → ( nurl_println ( string_data x ) ) F → {} }  // opt
    ?? ( maybe `kept` ) { T x → ( vec_push [String] names x ) F → {} }
    ?? ( maybe `gone` ) { T x → ( string_free x ) F → {} }
    ( nurl_println_int ( vec_len [String] names ) )  // 3
    // An option binding owns its payload; an arm can take it over.
    : ?String ob ( maybe `bound` )
    ?? ob { T x → ( nurl_println ( string_data x ) ) F → {} }  // bound
    : ?String ob2 ( maybe `taken` )
    ?? ob2 { T x → ( vec_push [String] names x ) F → {} }
    : String u ?? ( maybe `joined` ) { T x → x F → ( string_new ) }
    ( nurl_println ( string_data u ) )  // joined
    : String w ( pick F `unused` )
    : String w2 ( pick T `fresh` )
    ( nurl_print ( string_data w ) ) ( nurl_println ( string_data w2 ) )  // outerfresh

    // Rebound and released early by hand (still allowed).
    : ~ String t ( string_from `one` )
    = t ( string_from `two` )
    ( string_free t )
    = t ( string_from `three` )
    ( nurl_println ( string_data t ) )  // three
    ^ 0
}
