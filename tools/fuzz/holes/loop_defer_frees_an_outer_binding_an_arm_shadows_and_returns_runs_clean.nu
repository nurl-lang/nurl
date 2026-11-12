// loop_defer_frees_an_outer_binding_an_arm_shadows_and_returns_runs_clean: `: String g …  ~ c { ? d { : String g …  ^ g } {}  ; { ( string_free g ) } }`.
// Closed: runs clean, and must stay so. A `^` above a loop body's `;` runs that defer from the second round on (agora #670); it frees the outer `g`, and the `^` hands back the arm's own `g`, a binding of its own to the walk (`g'1`). The return's owner was looked up by its bare name, the outer one: refused as "handed to the caller … a ';' defer releases it".
// main 0b3f239: accepted (the `^` skipped the defer, #670's wrong output: the outer `g` was never freed on that way out).
// map: §7.2 | A2 | runs-clean | - | agora #670: a loop defer frees an outer binding while a `^` above it hands back an arm's own binding of that name
$ `stdlib/core/string.nu`

@ mk i k → String { : ~ String r ( string_from `g: a loop string long enough for a heap buffer ` ) ( string_push_int r k ) ^ r }

@ f i n → String {
    : String g ( mk 7 )
    : ~ i k 0
    ~ < k 3 {
        ? == k n { : String g ( mk k ) ^ g } {}
        ; { ( string_free g ) ( nurl_println `freed` ) }
        = k + k 1
    }
    ^ ( string_from `fell off the end of the function` )
}

@ main → i {
    : String a ( f 1 ) ( nurl_println ( string_data a ) )
    : String b ( f 9 ) ( nurl_println ( string_data b ) )
    ^ 0
}
