// should_fail_generic_no_typeargs.nu — a generic function called without
// explicit `[T …]` type arguments must be diagnosed at the call site.
//
// NURL does not infer generic type arguments from value arguments, so
// `( pick 7 9 )` cannot resolve `pick`'s `[T]`. This used to surface the
// MISLEADING "call to unknown function 'pick'" error (the same message a
// genuine typo gets), even though `pick` is defined right above. The
// diagnostic now names the real cause and shows the fix:
// `( pick [T] … )`. (Compile succeeds with explicit args — see the
// frontend probe; this file pins the rejection of the inferred form.)

@ pick [T] T x T y → T { ^ x }

@ main → i {
    ( nurl_print ( nurl_str_int ( pick 7 9 ) ) )
    ^ 0
}
