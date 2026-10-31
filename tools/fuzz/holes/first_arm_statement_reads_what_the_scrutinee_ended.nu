// first_arm_statement_reads_what_the_scrutinee_ended: what a match's scrutinee call does to its arguments was recorded after the first statement of an arm, not before the arms: that statement could read a borrow the call had already ended. `clr_and` clears the Vec `e` borrows an element of, and the arm printed `e`.
// Closed: the scrutinee call's pending rows follow the `match` row (gen_match), and the walk applies them before it forks into the arms (bck_handle_match). The same order keeps a borrow of the payload the call lent from being ended by that call's own effect (`?? ( lru_get c k ) { T v → { … v … } }`).
// v0.76.0: accepted; the arm printed the cleared String's bytes (an empty line), AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | h315 | a match scrutinee call's effects were recorded after the first arm statement, which read a borrow the call had ended
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clr_and ( Vec String ) v → ?i { ( vec_clear [String] v ) ^ @ ?i { T 1 } }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a long enough heap string` ) )
    ?? ( vec_get [String] v 0 ) {
        T e → {
            ?? ( clr_and v ) {
                T x → { ( nurl_println ( string_data e ) ) }
                F → {}
            }
        }
        F → {}
    }
    ^ 0
}
