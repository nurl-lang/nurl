// Passing a value of one named struct type where a DIFFERENT named struct
// is declared by-value compiles (clang coerces, reading the foreign
// struct's leading fields) — a silent miscompile. Must be a call-site
// error. Only by-value named aggregates are checked, so scalars / enums
// (i64) / pointers are untouched.
$ `stdlib/core/string.nu`

: A { i x i y }
: B { i p i q i r }

@ takes_a A a → i { ^ . a x }

@ main → i {
    : B b @ B { 1 2 3 }
    ^ ( takes_a b )
}
