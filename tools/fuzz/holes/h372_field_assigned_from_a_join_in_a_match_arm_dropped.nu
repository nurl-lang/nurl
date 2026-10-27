// H372: as h371, the target a struct field and the statement a `??` whose arm ends in `= . h f ? c ( f ) ( g )`: the field was left holding the string the statement dropped.
// Closed: an assignment's value is lent to whatever reads it, a field store's as a binding's (`__assign_result_lent`, agora #132).
// v0.79.0: accepted; ASan reported heap-use-after-free.
$ `stdlib/core/string.nu`

: Holder { String f }

@ text i n → String {
    : String s ( string_from `a string long enough to own a heap buffer, number ` )
    ( string_push_int s n )
    ^ s
}

@ maybe i c → ?i { ? > c 0 { ^ @ ?i { T c } } {} ^ @ ?i { F } }

@ main → i {
    : ~ Holder h @ Holder { ( text 1 ) }
    : ~ String other ( text 2 )
    ?? ( maybe 7 ) { T v → { = . h f ? > v 6 ( text 3 ) ( text 4 ) } F → { = other ( text 5 ) } }
    ( nurl_println ( string_data . h f ) )
    ^ 0
}
