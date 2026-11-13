// cursor_given_its_own_value_is_handed_on_once.nu — a mutable second name of
// an owner (`: ~ P e p`) given a field value or a whole value of its own, then
// handed on (Agora #781).
//
// `: ~ P e p` makes e a cursor over p: it holds p's value, and p drops it.
// A field stored through e is e's own (a field-owner flag), and what it
// replaced stays p's. Handed back uncopied, e takes its own fields along,
// p drops the values they replaced and nothing else of what went out with
// e. A whole value given to e (`= e …`) is e's own: handed to a `sink`, it
// goes, and p keeps and drops its own. Before, the return dropped e's new
// field under the caller (use after free), p dropped the fields that went
// out with e, and the `sink` cleared p's flag with e's (p's value leaked).

$ `stdlib/core/string.nu`

: P { String name i n }
: Q { String a String b }

@ eat sink String s → i { ^ ( string_len s ) }

@ field → P {
    : ~ P p @ P { ( string_from `orig, a name long enough for a heap buffer` ) 1 }
    : ~ P e p
    = . e name ( string_from `field: replaced, long enough for a heap buffer` )
    ^ e
}

// The second field of two: p must not drop the first, which went out.
@ second → Q {
    : ~ Q p @ Q { ( string_from `second: a, long enough for a heap buffer` ) ( string_from `orig b, long enough for a heap buffer` ) }
    : ~ Q e p
    = . e b ( string_from `second: replaced b, long enough for a heap buffer` )
    ^ e
}

// The store on one path only: the flag answers per run.
@ arm i c → P {
    : ~ P p @ P { ( string_from `arm: orig, long enough for a heap buffer` ) c }
    : ~ P e p
    ? == c 1 { = . e name ( string_from `arm: replaced, long enough for a heap buffer` ) } {}
    ^ e
}

// Twice: the second store drops the first's value, e's own.
@ twice → P {
    : ~ P p @ P { ( string_from `orig, a name long enough for a heap buffer` ) 1 }
    : ~ P e p
    = . e name ( string_from `first, a name long enough for a heap buffer` )
    = . e name ( string_from `twice: second, long enough for a heap buffer` )
    ^ e
}

// p reads its own value beside e's store.
@ beside → P {
    : ~ P p @ P { ( string_from `beside: p keeps its own name, long enough` ) 1 }
    : ~ P e p
    = . e name ( string_from `beside: e's own name, long enough for a heap buffer` )
    ( nurl_println ( string_data . p name ) )
    ^ e
}

// A whole value of e's own handed to a `sink`: s keeps its own.
@ sunk → v {
    : ~ String s ( string_from `sunk: s keeps its own, long enough for a heap buffer` )
    : ~ String e s
    = e ( string_from `sunk: e's own value, long enough for a heap buffer` )
    ( nurl_println_int ( eat e ) )
    ( nurl_println ( string_data s ) )
}

@ main → i {
    : P r1 ( field ) ( nurl_println ( string_data . r1 name ) )
    : Q r2 ( second ) ( nurl_println ( string_data . r2 a ) ) ( nurl_println ( string_data . r2 b ) )
    : P r3 ( arm 1 ) ( nurl_println ( string_data . r3 name ) )
    : P r4 ( arm 0 ) ( nurl_println ( string_data . r4 name ) )
    : P r5 ( twice ) ( nurl_println ( string_data . r5 name ) )
    : P r6 ( beside ) ( nurl_println ( string_data . r6 name ) )
    ( sunk )
    ^ 0
}
