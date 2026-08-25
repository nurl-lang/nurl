// diag_generic_tparam_bool_name.nu — a generic whose type parameter is named
// `T` and whose body uses the boolean literal `T` says why it failed.
//
// `T` and `F` are the boolean literals, and the lexer is context-free: a bare
// `T` is TT_BOOL wherever it appears, in type position and value position
// alike (see compute_generic_inout_sink, which already documents this).
// Monomorphisation rewrites the type parameter through the body by whole
// word, so a template written `[T]` has its VALUE-position `T`s rewritten
// too — `? T { … }` becomes `? i { … }`, and the instantiation dies on
//
//     error: use of undefined identifier 'i'
//     @ g__i64 i x → i { ? i { ^ 1 } { } ^ 0 }
//
// against source the user never wrote. Renaming the parameter to `A` makes
// the identical program compile, which is not a hint anyone gets from the
// message.
//
// The stdlib avoids the collision by convention — `stdlib/core/vec.nu` names
// its type variable `A` and says why — but nothing warned anyone else, and
// docs/spec.md §4.8 spells its own canonical example `[T]`.
//
// The ambiguity itself is not removed here: doing that means teaching the
// PARSER to resolve `T` by position (types and values are different
// namespaces) instead of rewriting the body textually before it is parsed.
// What is fixed is that the failure now names its cause, which is the
// contract §10.1 sets for every other foot-gun in the language.

@ g [T] T x → i {
    ? T { ^ 1 } {}
    ^ 0
}

@ main → i {
    ^ ( g [i] 1 )
}
