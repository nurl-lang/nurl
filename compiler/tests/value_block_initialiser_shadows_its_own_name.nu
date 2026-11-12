// agora #631: a value block's binding whose initialiser is a value block
// binding the same name, read in that initialiser — `: String s { : String
// s ( string_concat s s ) s }`. Each name in a block local's source
// expression means the binding visible where it was logged; re-read to a
// fixed point, the outer `s` was taken for the inner one that shadows it,
// every round doubled the text, and nurlc did not terminate. (The runner's
// compile timeout makes a hang a failure.)
$ `stdlib/core/string.nu`

@ main → i {
    : String s ( string_from `ab` )
    : String t { : String s { : String s ( string_concat s s ) s } s }
    ( nurl_println ( string_data t ) )
    : String x ( string_from `x` )
    : String u { : String s { : String s ( string_concat x x ) { : String s ( string_concat s s ) ( string_concat s s ) } } s }
    ( nurl_println ( string_data u ) )
    ^ 0
}
