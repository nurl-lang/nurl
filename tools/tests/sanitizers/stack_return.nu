// Deliberately return a closure referring to the callee's stack.
: Counter { i n i max }

@ make → ( @ i ) {
    : ~ Counter c @ Counter { 41 100 }
    ^ \ → i { = . c n + . c n 1 ^ . c n }
}

@ main → i {
    : ( @ i ) f ( make )
    ( nurl_println_int ( f ) )
    ^ 0
}
