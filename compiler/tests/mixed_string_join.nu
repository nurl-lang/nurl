// A borrowed/owned value join retains separate ownership on each branch.
// Count actual frees so the normal corpus catches the leak without LSan.
$ `stdlib/core/string.nu`

& `c` @ nurl_free_count → i

: s borrowed `borrowed`

@ size s text → i { ^ ( nurl_str_len text ) }

@ exercise b choose → v {
    : i a ( size ? choose borrowed ( nurl_str_cat `allocated` ` branch` ) )
    : i b ( size text : ?!choose ( nurl_str_cat `allocated` ` branch` ) borrowed )
    : i c ( size ?? choose { T → borrowed F → ( nurl_str_cat `allocated` ` branch` ) } )
    : i d ( size ? choose borrowed ?? choose { T → borrowed F → ( nurl_str_cat `allocated` ` branch` ) } )
}

@ main → i {
    : i before ( nurl_free_count )
    ( exercise T )
    ( exercise F )
    : b ok == - ( nurl_free_count ) before 4
    ( nurl_println ? ok `mixed_join_cleanup=T` `mixed_join_cleanup=F` )
    ^ ? ok 0 1
}
