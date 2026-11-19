// copied_slice_parameter_of_a_temporary_runs_clean: `( wrapb ( mk ) )` with wrapb `^ @ Bag { t 3 }` of a `[i` parameter, the same of an option `@ ?[i { T a }`, of a join `? c ( mk ) a`, and of a binding: the literal copies the parameter's slice
// Closed (agora #895): a slice parameter a literal copies into a field it owns by type, of elements that hold no view, is a value of its own: no keep, no lend, `-` to the borrow walk and `__nurl_slice_copy` to the engine, so the caller releases its temporary at the statement's end.
// main 85a31ca: LeakSanitizer: the temporary's buffer leaked (the caller took the result for a view of it and released it nowhere).
// map: §7.6 | A2 | runs-clean | - | agora #895: a copied slice parameter holds nothing of its argument, of a temporary, an option's payload, a join and a binding
: Bag { [i t i n }

@ mk → [i { ^ [i | 1 2 3] }
@ wrapb [i t → Bag { ^ @ Bag { t 3 } }
@ wrapo [i a → ?[i { ^ @ ?[i { T a } }

@ main → i {
    : Bag b ( wrapb ( mk ) )
    ~ x . b t { ( nurl_println_int x ) }
    : ?[i o ( wrapo ( mk ) )
    ?? o { T s → { ~ x s { ( nurl_println_int x ) } } F → {} }
    : [i a [i | 4 5]
    : i c 1
    : Bag d ( wrapb ? > c 0 ( mk ) a )
    : Bag e ( wrapb ? > c 5 ( mk ) a )
    ~ x . d t { ( nurl_println_int x ) }
    ~ x . e t { ( nurl_println_int x ) }
    : [i f ( mk )
    : Bag g ( wrapb f )
    ~ x . g t { ( nurl_println_int x ) }
    ~ x a { ( nurl_println_int x ) }
    ^ 0
}
