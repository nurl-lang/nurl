// unit_variant_local_owns.nu — a local holding a unit variant owns its
// value: returning it in a result literal does not make the function lend.
//
// `: ~ ResolveErr failure ResolveConflict … ^ @ !( Vec LockPkg ) ResolveErr {
// F failure }` (resolve_registry): the bare variant name read like a global,
// so the binding counted as borrowing it, the literal holding it as lending,
// and the function as returning a borrow on every path — no caller dropped
// the Ok payload either. Written in place (`{ F EA }`) it never leaked.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

: Pay { String a }
: | E { EP Pay EA EB }

// A: a mutable local holding a unit variant, returned on the failure path.
@ mk_a b fail → !( Vec String ) E {
    : ~ E failure EA
    ? fail { ^ @ !( Vec String ) E { F failure } } {}
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `x` ) )
    ^ @ !( Vec String ) E { T v }
}

// B: the same with an immutable local.
@ mk_b b fail → !( Vec String ) E {
    : E failure EA
    ? fail { ^ @ !( Vec String ) E { F failure } } {}
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `x` ) )
    ^ @ !( Vec String ) E { T v }
}

// C: the variant written in place — dropped correctly.
@ mk_c b fail → !( Vec String ) E {
    ? fail { ^ @ !( Vec String ) E { F EA } } {}
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `x` ) )
    ^ @ !( Vec String ) E { T v }
}

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ main → i {
    : ~ i base ( live )
    : ~ i k 0
    ~ < k 20 { : !( Vec String ) E r ( mk_a F ) = k + k 1 }
    ( nurl_print `A live delta: ` ) ( nurl_print_int - ( live ) base ) ( nurl_print `\n` )
    = base ( live ) = k 0
    ~ < k 20 { : !( Vec String ) E r ( mk_b F ) = k + k 1 }
    ( nurl_print `B live delta: ` ) ( nurl_print_int - ( live ) base ) ( nurl_print `\n` )
    = base ( live ) = k 0
    ~ < k 20 { : !( Vec String ) E r ( mk_c F ) = k + k 1 }
    ( nurl_print `C live delta: ` ) ( nurl_print_int - ( live ) base ) ( nurl_print `\n` )
    ^ 0
}
