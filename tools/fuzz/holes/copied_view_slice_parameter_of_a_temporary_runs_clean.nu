// copied_view_slice_parameter_of_a_temporary_runs_clean: `( wraps ( mks ) )` with `@ wraps [s t → SBag { ^ @ SBag { t 2 } }` (a `[s` of literals), the same of a call that lends a String's views, and of a binding: the literal copies a slice of views
// Closed (agora #935): a slice parameter a literal copies, of elements that hold views, is a buffer of its own holding copies of them: `^0` to the walk (`__nurl_slice_copy`: what the elements view, not the slice the parameter views) and the `mem_dup` primitive to the engine, and a `^k` answer views nothing of a temporary whose elements own nothing (`__rv_views_arg`) - the caller releases it.
// main 08e56f54: LeakSanitizer: the temporary's buffer leaked (the caller took the result for a view of it).
// map: §7.6 | A2 | runs-clean | - | agora #935: a copied slice of views holds what its elements view, of a temporary, a lending call's temporary and a binding
$ `stdlib/core/string.nu`

: SBag { [s t i n }

@ mks → [s { ^ [s | `a` `b`] }
@ viewsof String a → [s { ^ [s | ( string_data a )] }
@ wraps [s t → SBag { ^ @ SBag { t 2 } }

@ main → i {
    : SBag b ( wraps ( mks ) )
    ~ x . b t { ( nurl_println x ) }
    : String a ( string_from `xy` )
    : SBag c ( wraps ( viewsof a ) )
    ~ x . c t { ( nurl_println x ) }
    : [s v ( mks )
    : SBag d ( wraps v )
    ~ x . d t { ( nurl_println x ) }
    ^ 0
}
