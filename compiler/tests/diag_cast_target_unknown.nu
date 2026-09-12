// diag_cast_target_unknown.nu — a cast to a type nothing declares.
//
// A cast's TARGET is a type position, and every other one runs the
// declared-type check — `Z NoSuchType` and `%NoTrait` were closed in the
// same sweep. This one did not, so `# * g 1` emitted
// `inttoptr i64 1 to %g*`, a reference to a type the module never
// defines. The BARE form (`# NoSuchTy 1`) is caught downstream by
// whatever consumes the value, which is why only the POINTER form
// reached clang.
//
// `g` here is a function, which is the spelling the token-deletion
// sweep produced: `# *u fiber_a 1` with the `u` deleted. The
// cast-to-a-BINDING case keeps its own, better message ("did you mean to
// ASSIGN to it") — see cast_to_binding.nu; this is the backstop for
// every other name.

@ g → i {
    ^ 1
}

@ main → i {
    : *i p # *g 1
    ^ 0
}
