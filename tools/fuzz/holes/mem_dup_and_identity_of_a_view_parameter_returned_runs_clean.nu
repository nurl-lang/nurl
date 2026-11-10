// mem_dup_and_identity_of_a_view_parameter_returned_runs_clean: agora #478 — `^ ( mem_dup x )` and `^ ( same x )` of a view parameter: the caller's storage, released by no one here
// Control for agora #478.
// map: §2.10 | A2 | runs-clean | - | agora #478: `^ ( mem_dup x )` and `^ ( same x )` of a view parameter: the caller's storage, released by no one here
$ `stdlib/core/string.nu`

@ pass s x → s { ^ ( mem_dup x ) }

@ same s x → s { ^ x }

@ pass2 s x → s { ^ ( same x ) }

@ main → i {
    : s t ( nurl_str_cat `a caller string, ` `long enough for a heap buffer` )
    ( nurl_println ( pass t ) )
    ( nurl_println ( pass2 t ) )
    ^ 0
}
