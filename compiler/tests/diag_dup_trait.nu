// diag_dup_trait.nu — a supertrait ':' clause written on what was meant
// to be an impl.
//
// This was a silent miscompile, not just a missing message. The ':'
// consumes 'Dog' as a supertrait name, which leaves the lexer on '{',
// so the declaration is read as a re-declaration of the TRAIT rather
// than an impl — and the impl body vanished. No 'speak' was emitted at
// all, and the program still compiled and linked. The
// supertrait-on-impl message can never fire for this shape, because by
// then it is not being read as an impl.
//
// Structs, enums and impls all guarded against a duplicate declaration.
// Traits were the one kind that did not, which is what let this through.
: Dog { i age }

% Speaker [T] { @ speak T self → i }

% Speaker : Dog { @ speak Dog self → i { ^ 1 } }

@ main → i { ^ 0 }
