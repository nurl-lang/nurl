// closure_replacing_the_option_whose_payload_it_is_handed_is_refused: a closure giving its option capture `o` a new value, called with the `T e` payload read in place out of `o`
// Closed: agora #445, a cursor over the replaced binding reaches it: no `=` at the call hands the old value to the cursor.
// main c24c989a: accepted; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #445: a payload of the binding a closure replaces
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owner string long enough for the heap` ) }
    : ( @ v String ) c \ String p → v { = o @ ?String { F } ( nurl_println ( string_data p ) ) }
    ?? o { T e → { ( c e ) } F → {} }
    ^ 0
}
