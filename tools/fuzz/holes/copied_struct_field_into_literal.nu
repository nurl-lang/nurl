// copied_struct_field_into_literal: a struct binding copied from another (`: E b a`, or `: E m m0` over a `??` payload) is a cursor over that binding's value, which still drops it; a returned literal that took a handle field of the copy (`^ @ !( Vec u ) String { T . b out }`, or a binding read from it) took it without a copy and without emptying the owner's slot, so the owner freed the Vec the caller got. audio's MP3 encoder hit it: mp3_encode returned an empty stream.
// Closed: the literal's take also empties that field in each binding the struct is a cursor over, where it holds the very same handle (gen_agg_lit).
// main (before this PR): heap-use-after-free in main reading the returned Vec.
// map: §7.6 | A2 | runs-clean | h191 | returned literal takes Vec field of struct cursor copy; owner frees it too
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: E { i n ( Vec u ) out }

@ mk → !E String { ^ @ !E String { T @ E { 1 ( vec_new [u] ) } } }

@ fill inout E e → v { ( vec_push [u] . e out 7 ) }

@ from_payload → !( Vec u ) String {
    ?? ( mk ) {
        T m0 → {
            : ~ E m m0
            ( fill m )
            ( fill m )
            ^ @ !( Vec u ) String { T . m out }
        }
        F e → { ^ @ !( Vec u ) String { F e } }
    }
}

@ from_copy → ?( Vec u ) {
    : E a @ E { 2 ( vec_new [u] ) }
    : ~ E b a
    ( fill b )
    : ( Vec u ) o . b out
    ^ @ ?( Vec u ) { T o }
}

@ main → i {
    ?? ( from_payload ) { T v → { ( nurl_println_int ( vec_len [u] v ) ) } F e → {} }
    ?? ( from_copy ) { T v → { ( nurl_println_int ( vec_len [u] v ) ) } F → {} }
    ^ 0
}
