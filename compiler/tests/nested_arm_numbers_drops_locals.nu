// nested_arm_numbers_drops_locals.nu — an arm whose value is made of numbers
// drops its locals, even when it ends in another `??`.
//
// `^ ?? r { T _ → { : ( Vec u ) t … ?? r2 { T p → @ !i i { … } … } } … }`:
// the inner `??` handed its drops up to the outer arm, which kept them for
// a value that might point into them — but a `!i i` holds no address.
// `t` and the payload `p` leaked per call (stdlib noise handshakes).

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ mk → ( Vec u ) { ^ ( bytes_from_str `abc` ) }

@ mkr → !( Vec u ) i { ^ @ !( Vec u ) i { T ( mk ) } }

@ nested ! v i r → !i i {
    ^ ?? r {
        T _ → {
            : ( Vec u ) t ( mk )
            : !( Vec u ) i r2 ( mkr )
            ?? r2 {
                T p → { @ !i i { T + ( vec_len [u] t ) ( vec_len [u] p ) } }
                F e → @ !i i { F e }
            }
        }
        F e → @ !i i { F e }
    }
}

// …and an error that is an enum of bare tags is a number too
: | Bad { BadA BadB }

@ nested_enum ! v i r → !i Bad {
    ^ ?? r {
        T _ → {
            : ( Vec u ) t ( mk )
            : !( Vec u ) i r2 ( mkr )
            ?? r2 {
                T p → { @ !i Bad { T + ( vec_len [u] t ) ( vec_len [u] p ) } }
                F _ → @ !i Bad { F BadA }
            }
        }
        F _ → @ !i Bad { F BadB }
    }
}

@ main → i {
    : i l0 ( live )
    : !v i ok @ !v i { T 0 }
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 { ?? ( nested ok ) { T n → { = acc + acc n } F _ → {} } = k + k 1 }
    = k 0
    ~ < k 10 { ?? ( nested_enum ok ) { T n → { = acc + acc n } F _ → {} } = k + k 1 }
    ( nurl_print_int acc ) ( nurl_print `\n` )
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}
