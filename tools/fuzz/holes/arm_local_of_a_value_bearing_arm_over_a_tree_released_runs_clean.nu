// arm_local_of_a_value_bearing_arm_over_a_tree_released_runs_clean: `: Node { String name ( Vec Node ) kids i n }`; a value-bearing `?` arm binds a String local and yields an element of a `( Vec Node )`
// Closed: the walk that asks whether a value can hold an address marks a struct while it reads it, as it marked enums: a type reached again through its own Vec adds nothing, and no depth budget answers no below six levels (agora #740).
// main 3b63ee3b: accepted — and leaked: the arm's local was never released.
// map: §7.1 | A2 | runs-clean | - | agora #740: an arm local beside a tree element released
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Node { String name ( Vec Node ) kids i n }

@ cond i c → i {
    : ~ ( Vec Node ) v ( vec_new [Node] )
    ( vec_push [Node] v @ Node { ( string_from `an element string long enough for a heap buffer` ) ( vec_new [Node] ) 1 } )
    ( vec_push [Node] v @ Node { ( string_from `another element string long enough for a heap buffer` ) ( vec_new [Node] ) 2 } )
    : Node e ? > c 1 { : String junk ( string_from `a junk string long enough for a heap buffer here` ) ( vec_at [Node] v 0 ) } ( vec_at [Node] v 1 )
    ^ . e n
}

@ main → i {
    ( nurl_println_int ( cond 2 ) )
    ( nurl_println_int ( cond 0 ) )
    ( nurl_println_int ( cond 3 ) )
    ^ 0
}
