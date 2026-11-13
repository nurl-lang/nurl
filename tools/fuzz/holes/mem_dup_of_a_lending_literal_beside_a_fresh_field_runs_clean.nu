// mem_dup_of_a_lending_literal_beside_a_fresh_field_runs_clean: `^ @ O2 { ( mem_dup @ P1 { . h name } ) ( string_from … ) }` with h a borrowed parameter; the caller reads both fields.
// Agora #814: mem_dup copied the literal that already owned the copy of h's field, and the literal was released by no one; a literal operand of mem_dup is now the copy (gen_mem_dup, where it lends nothing and holds no view).
// map: §7.6 | A2 | runs-clean | - | agora #814: mem_dup of a literal is that literal, released once
$ `stdlib/core/string.nu`

: Holder { String name i n }
: P1 { String a }
: O2 { P1 p String b }

@ f Holder h → O2 { ^ @ O2 { ( mem_dup @ P1 { . h name } ) ( string_from `a fresh field string, long enough for heap` ) } }

@ main → i {
    : Holder h @ Holder { ( string_from `the holder name string, long enough heap` ) 1 }
    : O2 o ( f h )
    ( nurl_println ( string_data . . o p a ) )
    ( nurl_println ( string_data . o b ) )
    ^ 0
}
