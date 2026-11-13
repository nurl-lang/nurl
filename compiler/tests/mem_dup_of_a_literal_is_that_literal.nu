// mem_dup_of_a_literal_is_that_literal.nu — `( mem_dup @ P1 { … } )`
// (Agora #814): a literal written as mem_dup's operand is a fresh value
// that owns all it holds — as a call's argument it copies what it borrows
// (`. h name`) — so it is the copy. Copied again, the literal itself was
// released by no one (a leak on main for every shape below). Bound, handed
// to a sink, pushed, as a field of a returned literal beside a fresh one;
// a literal over a fresh field too. A literal holding a view is still
// copied as before.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Holder { String name i n }
: P1 { String a }
: O2 { P1 p String b }
: W { s v i n }

@ eat sink P1 p → i { ^ ( string_len . p a ) }

@ f Holder h → O2 { ^ @ O2 { ( mem_dup @ P1 { . h name } ) ( string_from `a fresh field beside the copy, long` ) } }

@ main → i {
    : Holder h @ Holder { ( string_from `the holder's name, long enough for heap` ) 1 }
    : P1 a ( mem_dup @ P1 { . h name } )
    ( nurl_println ( string_data . a a ) )
    : P1 b ( mem_dup @ P1 { ( string_from `a fresh field, long enough for the heap` ) } )
    ( nurl_println ( string_data . b a ) )
    : i k ( eat ( mem_dup @ P1 { . h name } ) )
    : ~ ( Vec P1 ) v ( vec_new [P1] )
    ( vec_push [P1] v ( mem_dup @ P1 { ( string_from `a pushed copy, long enough heap` ) } ) )
    : O2 o ( f h )
    ( nurl_println ( string_data . . o p a ) )
    ( nurl_println ( string_data . o b ) )
    : String src ( string_from `a source string long enough for the heap` )
    : W w ( mem_dup @ W { ( string_data src ) 1 } )
    ( nurl_println . w v )
    ( nurl_println ( string_data . h name ) )
    ^ - + k ( vec_len [P1] v ) 40
}
