// bare_view_of_a_loop_elements_storage_or_held_view_kept_while_the_container_grows_runs_clean: agora #471 — `pick` hands back, from inside `~ x p` over a `( Vec Item )` parameter, either `( string_data . x label )` or `. x tag` (a view the element holds); the caller grows its Vec, then reads the answer (the shape the fix must keep)
// Closed: the walk answers `^0 %0`, both as they are (__rv_ask's 4): the element's own storage through an element, which growth spares, and what the element holds, which ends with what it views — not the whole argument (agora #471's adversarial pass).
// main 9d2e7cd: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #471: a bare view of a loop element's storage or of a view it holds, kept while the caller's container grows
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Item { String label s tag }

@ pick ( Vec Item ) p b own → s {
    ~ x p { ? own { ^ ( string_data . x label ) } { ^ . x tag } }
    ^ `none`
}

@ main → i {
    : String line ( string_from `a tag text that outlives the items` )
    : ( Vec Item ) t ( vec_new [Item] )
    ( vec_push [Item] t @ Item { ( string_from `a label that stays put` ) ( string_data line ) } )
    : s v ( pick t T )
    ( vec_push [Item] t @ Item { ( string_from `grown` ) ( string_data line ) } )
    ( nurl_println v )
    ^ 0
}
