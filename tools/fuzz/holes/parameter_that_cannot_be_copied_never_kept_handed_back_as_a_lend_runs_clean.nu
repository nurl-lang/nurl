// parameter_that_cannot_be_copied_never_kept_handed_back_as_a_lend_runs_clean: agora #743 — `@ f1 R p → R { ^ ( r0 p ) }` over a parameter of a struct with its own `% Drop` that f1 never keeps: a lend of the caller's own, accepted
// Control: the refusal asks whether the function takes the parameter over (resolve_pfo_lends); a parameter it never keeps is the caller's.
// main 3b63ee3b: accepted, runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #743: `@ f1 R p → R { ^ ( r0 p ) }` over a parameter of a struct with its own `% Drop` that f1 never keeps: a lend of the caller's own, accepted
$ `stdlib/core/string.nu`

: R { String s i n }

% Drop R { @ drop R x → v { ( nurl_println `drop R` ) } }

@ r0 R p → R { ^ p }

@ f1 R p → R { ^ ( r0 p ) }

@ main → i {
    : R x @ R { ( string_from `a string long enough to live on the heap for sure` ) 2 }
    : R s ( f1 x )
    ( nurl_println ( string_data . s s ) )
    ^ 0
}
