// mem_dup_inside_a_lending_call_that_is_a_join_arm_runs_clean: `? c ( pick o ( mem_dup x ) ) ( mks … )` over a struct owning a String — the arm is a call that lends `o`; the `mem_dup` copy inside it is only its argument.
// Control for agora #688: an arm owns a copy only where it is the `mem_dup` call itself, one call below the join; a copy made inside a call the arm makes leaves the arm answering by that call. Taken for the arm's own, `o`'s buffer was released under its owner.
// map: §7.6 | A2 | runs-clean | - | agora #688: a mem_dup copy inside a lending call that is a ? arm (struct)
$ `stdlib/core/string.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ pick S a S b → S { ^ a }

@ f S o S x b c → S { ^ ? c ( pick o ( mem_dup x ) ) ( mks `a fresh one long enough for the heap buffer` ) }

@ main → i {
    : S o ( mks `the owner's string, long enough for the heap` )
    : S x ( mks `another string, long enough for the heap ok` )
    : S r ( f o x T )
    ^ - . r n . o n
}
