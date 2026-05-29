// generic_nested_struct.nu — regression for nested generic struct
// instantiation through a generic function.
//
// Before the 2026-05-17 fix to emit_one_instantiation +
// ensure_struct_instantiated, defining two generic structs A[T] and
// B[T] and writing a generic function that returned (B T) but
// internally allocated *(A T) and wrote its fields failed at parse
// with "unknown field or variable: m" — the inner struct's field
// metadata was never materialised. The fix re-scans the substituted
// body of both monomorphised generic fns and of every generic struct
// instantiation, so nested concrete uses (A i) inside (B i) emit
// their named types + field tables before any consumer reads them.
//
// This test also covers the deeper transitive case: a "Wrap[A]"
// struct whose body contains "( Vec A )" — when Wrap[s] is
// instantiated, Vec[s] must be emitted first so the outer struct is
// a sized aggregate at GEP time (otherwise LLVM rejects with
// "base element of getelementptr must be sized").

$ `stdlib/core/vec.nu`

: Inner [A] {
    A value
    i count
}

: Outer [A] { s ctl }

@ mk_outer [A] A v → ( Outer A ) {
    : *( Inner A ) imp # *( Inner A ) ( nurl_alloc Z ( Inner A ) )
    = . imp value v
    = . imp count 1
    ^ @ ( Outer A ) { # s imp }
}

@ outer_count [A] ( Outer A ) o → i {
    : *( Inner A ) imp # *( Inner A ) . o ctl
    ^ . imp count
}

@ outer_free [A] ( Outer A ) o → v {
    : *( Inner A ) imp # *( Inner A ) . o ctl
    ( nurl_free # s imp )
}

: Wrap [A] {
    ( Vec A ) items
    i flag
}

@ wrap_new [A] → *( Wrap A ) {
    : *( Wrap A ) w # *( Wrap A ) ( nurl_alloc Z ( Wrap A ) )
    = . w items ( vec_new [A] )
    = . w flag 7
    ^ w
}

@ wrap_push [A] * ( Wrap A ) w A x → v {
    ( vec_push [A] . w items x )
}

@ wrap_len [A] * ( Wrap A ) w → i {
    ^ ( vec_len [A] . w items )
}

@ wrap_free [A] * ( Wrap A ) w → v {
    ( vec_free [A] . w items )
    ( nurl_free # s w )
}

@ main → i {
    // ── Case 1: nested generic structs (Inner inside Outer) ─────
    : ( Outer i ) oi ( mk_outer [i] 42 )
    ( nurl_print `i_count=` )
    ( nurl_print ( nurl_str_int ( outer_count [i] oi ) ) )
    ( nurl_print `\n` )
    ( outer_free [i] oi )

    : ( Outer s ) os ( mk_outer [s] `hello` )
    ( nurl_print `s_count=` )
    ( nurl_print ( nurl_str_int ( outer_count [s] os ) ) )
    ( nurl_print `\n` )
    ( outer_free [s] os )

    // ── Case 2: transitive (Wrap[A] contains Vec[A]) ────────────
    : *( Wrap i ) wi ( wrap_new [i] )
    ( wrap_push [i] wi 10 )
    ( wrap_push [i] wi 20 )
    ( wrap_push [i] wi 30 )
    ( nurl_print `wi_len=` )
    ( nurl_print ( nurl_str_int ( wrap_len [i] wi ) ) )
    ( nurl_print `\n` )
    ( wrap_free [i] wi )

    : *( Wrap s ) ws ( wrap_new [s] )
    ( wrap_push [s] ws `a` )
    ( wrap_push [s] ws `b` )
    ( nurl_print `ws_len=` )
    ( nurl_print ( nurl_str_int ( wrap_len [s] ws ) ) )
    ( nurl_print `\n` )
    ( wrap_free [s] ws )

    ( nurl_print `done\n` )
    ^ 0
}
