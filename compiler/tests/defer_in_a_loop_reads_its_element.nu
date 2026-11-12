// defer_in_a_loop_reads_its_element.nu — a `;` defer inside a `~ e v`
// body reads the loop's element (Agora #672). The defer runs once, at the
// function's exit, and reads the element of the last round that reached
// it — also with the `~` loop inside another loop, inside another `~`
// loop, and over a field. Only what leaves the elements alone happens
// after the loop (a field of another kind set, the Vec grown elsewhere),
// so every read is good.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) items i n }

@ pr String g → v { ( nurl_println ( string_data g ) ) }

@ mkv → ( Vec String ) {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `first element, long enough for the heap` ) )
    ( vec_push [String] v ( string_from `second element, long enough for the heap` ) )
    ^ v
}

@ plain ( Vec String ) v → i {
    ~ e v { ; { ( pr e ) } }
    ^ 1
}

@ nested ( Vec String ) v i n → i {
    : ~ i k 0
    ~ < k n {
        ~ e v { ; { ( pr e ) } }
        = k + k 1
    }
    ^ k
}

@ inner ( Vec String ) v ( Vec String ) w → i {
    ~ e v { ~ x w { ; { ( pr e ) ( pr x ) } } }
    ^ 2
}

@ field i n → i {
    : ~ H h @ H { ( mkv ) 3 }
    ~ e . h items { ; { ( pr e ) } }
    = . h n 5
    ^ + n . h n
}

@ main → i {
    : ~ ( Vec String ) v ( mkv )
    : ( Vec String ) w ( mkv )
    ( nurl_println_int ( plain v ) )
    ( nurl_println_int ( nested v 2 ) )
    ( nurl_println_int ( inner v w ) )
    ( nurl_println_int ( field 1 ) )
    ( vec_push [String] v ( string_from `third element, long enough for the heap` ) )
    ^ 0
}
