// OPEN in v0.73.0 — a closure holds a view of a Vec it captured across a
// call to one of its own closure PARAMETERS; that parameter, chosen by the
// caller, re-enters the closure and grows the Vec, so the view goes stale
// and is read after the buffer moved. Safe code, no `unsafe`. ASan:
// heap-use-after-free.
//
// Why it is unsound (and distinct from h274–h280): nurlc propagates the
// effect of running a captured closure onto the enclosing closure (h278,
// __clo_effect_note), but a closure PARAMETER is not a capture — it is not
// in g_clo_caps_now — so running it records no effect at all (nurlc.nu
// ~line 23381 skips any root not in g_clo_caps_now). A parameter's captures
// are the caller's to choose: here the caller hands `grow` a closure that
// re-enters `grow`, so running the parameter grows `grow`'s own capture `v`
// while its slice `s` of `v` is live. Neither h274's route check (the
// writer is the opaque parameter, not a known argument or literal) nor
// h279's same-literal check (the writer is not a capture of `grow`) fires.
//
// The fix (not a workaround — the sound modelling of an opaque higher-order
// call): inside a closure body, a call to an opaque closure value — a
// parameter (`__param`), or a closure read from a field or returned, whose
// captures are not a known local literal's — may move the buffer of every
// binding the enclosing closure captured by reference. So views of the
// enclosing closure's captures end at that call, exactly as they end at a
// call that runs a growing closure whose captures ARE known (h280). The
// rule is additive (it ends more borrows, never fewer), so it cannot admit
// a program the checker rejects today; it only rejects this hole and its
// kin. Emit it where a shadowed-callee call is recorded (nurlc.nu ~15580):
// when g_clo_caps_now is non-empty and the callee is opaque, stash a
// realloc effect for each capture root, consumed by the borrow walk's
// pendeff path (bck_borrow_sweep, kc 32) the same way bck_closure_effects_run
// stashes the known-closure case.
//
// main's compiler: compiled; ASan reported heap-use-after-free.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ f ( @ v ( @ v ) ) g → v {
    : ( @ v ) k \ → v {
        : ( @ v ) noop \ → v {}
        ( g noop )
    }
    ( g k )
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( @ v ( @ v ) ) grow \ ( @ v ) h → v {
        : ~ i j 0
        ~ < j 400 { ( vec_push [i] v j ) = j + j 1 }
        : ( Slice i ) s ( slice_from_vec [i] v )
        ( h )
        ( nurl_println_int ( slice_at [i] s 0 ) )
    }
    ( f grow )
    ^ 0
}
