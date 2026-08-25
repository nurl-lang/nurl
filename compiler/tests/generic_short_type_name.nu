// generic_short_type_name.nu — a CONCRETE type whose name is spelled like a
// type parameter is still a concrete type argument.
//
// `is_tparam_like` answers a question about spelling: one uppercase letter,
// optionally followed by a digit — the project's tparam convention (`[A]`,
// `[K V]`, `[T1 T2]`). `ensure_struct_instantiated` used that answer to skip
// "still abstract" instantiations, so a user struct named `P` or `Q3` — both
// perfectly legal names — was mistaken for a type parameter and its
// instantiation was never materialised. `( Vec P )` then referenced a
// `%Vec__P` nothing defined, and the program died with
//
//     stdlib/core/vec.nu:201: type 'Vec__P' has no field 'ctl'
//
// pointing into the stdlib, with the real cause (the length of the user's own
// struct name) nowhere in the message. A one-character rename made it work.
//
// The fix is to ask scope instead of spelling: `is_abstract_tparam` treats a
// tparam-shaped token as abstract only when it is NOT a type in `syms`, which
// required moving the purely-lexical `scan_type_names` pass ahead of
// `scan_generic_structs` so the names are registered before the instantiation
// scan consults them.
//
// Covered here: a short-named struct as the argument of a stdlib generic
// (Vec), of a user generic struct, and of a user generic function.

$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: P { i8 a u16 b }
: Q3 { i v }

: Box [T] { T inner }

@ mkbox [T] T x → ( Box T ) { ^ @ ( Box T ) { x } }

@ psum P p → i { ^ + # i . p a # i . p b }

@ main → i {
    // A generic struct from the stdlib, instantiated at `P`.
    : ( Vec P ) v ( vec_new [P] )
    ( vec_push [P] v @ P { # i8 200 # u16 60000 } )
    ( vec_push [P] v @ P { # i8 -1 # u16 7 } )
    ( nurl_print `len=` )
    ( nurl_print ( nurl_str_int ( vec_len [P] v ) ) )
    ( nurl_print `\n` )

    : ~ i k 0
    : ~ i total 0
    ~ < k ( vec_len [P] v ) {
        : P e ( opt_unwrap [P] ( vec_get [P] v k ) )
        = total + total ( psum e )
        = k + k 1
    }
    ( nurl_print `total=` )
    ( nurl_print ( nurl_str_int total ) )
    ( nurl_print `\n` )
    ( vec_free [P] v )

    // A user generic struct + generic function, instantiated at `Q3`.
    : ( Box Q3 ) b ( mkbox [Q3] @ Q3 { 41 } )
    ( nurl_print `box=` )
    ( nurl_print ( nurl_str_int . . b inner v ) )
    ( nurl_print `\n` )

    // …and at `P`, so the two short names do not share a monomorph.
    : ( Box P ) b2 ( mkbox [P] @ P { # i8 3 # u16 4 } )
    ( nurl_print `box2=` )
    ( nurl_print ( nurl_str_int ( psum . b2 inner ) ) )
    ( nurl_print `\n` )

    ( nurl_print `done\n` )
    ^ 0
}
