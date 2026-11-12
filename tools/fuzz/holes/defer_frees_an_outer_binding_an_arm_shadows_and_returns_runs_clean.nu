// defer_frees_an_outer_binding_an_arm_shadows_and_returns_runs_clean: `: String g …  ; { ( string_free g ) }  ? d { : String g …  ^ g } {}`.
// Closed: runs clean, and must stay so. The defer frees the outer `g`; the `^` hands back the arm's own `g`, a binding of its own to the walk (`g'1`). The return's owner was looked up by its bare name, the outer one, and the program was refused as "handed to the caller … a ';' defer releases it" (agora #670 found it in its loop form).
// main 0b3f239: refused (a false positive).
// map: §7.2 | A2 | runs-clean | - | agora #670: a defer frees an outer binding while a `^` hands back an arm's own binding of that name
$ `stdlib/core/string.nu`

@ mk i k → String { : ~ String r ( string_from `g: a string long enough for a heap buffer ` ) ( string_push_int r k ) ^ r }

@ f i n → String {
    : String g ( mk 7 )
    ; { ( string_free g ) ( nurl_println `freed` ) }
    ? == n 1 { : String g ( mk n ) ^ g } {}
    ^ ( string_from `fell off the end of the function` )
}

@ main → i {
    : String a ( f 1 ) ( nurl_println ( string_data a ) )
    : String b ( f 2 ) ( nurl_println ( string_data b ) )
    ^ 0
}
