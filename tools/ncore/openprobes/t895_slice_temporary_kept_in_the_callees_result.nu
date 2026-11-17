// map: §7.6 | A2 | runs-clean | - | AGORA-895: a slice temporary its callee keeps in its result leaks
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { [i s i n }
@ mk → [i { ^ [i | 7 8 9] }
@ id [i a → [i { ^ a }
@ wrapb [i a → Bag { ^ @ Bag { a 1 } }
@ wrap [i a → ?[i { ^ @ ?[i { T a } }
@ f → [i { ^ ( id ( mk ) ) }
@ main → i { : Bag g ( wrapb ( mk ) ) ( nurl_println_int . . g s 1 ) : ?[i o ( wrap ( mk ) ) ?? o { T q → { ( nurl_println_int . q 1 ) } F → {} } : [i x ( f ) ( nurl_println_int . x 1 ) ^ 0 }
