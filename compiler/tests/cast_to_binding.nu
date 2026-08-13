// Regression: `# name expr` where `name` is a BINDING, not a type. Unknown
// identifiers lower to the named type `%name`, so this compiled and emitted
// `insertvalue %d undef, …` against a type the module never declares — the
// user met it as an opaque clang error far from the typo. The usual source is
// a mistyped assignment (`# d + d 1` for `= d + d 1`).

@ main → i {
    : ~ i d 2
    ~ < d 5 {
        # d + d 1
    }
    ^ d
}
