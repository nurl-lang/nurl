// diag_bool_literal_words.nu — `true` and `false` written as words.
//
// The reverse of diag_bind_bool_literal_name.nu, and the one that gets
// written first: every other language spells the boolean literals
// `true` / `false`, and NURL spells them `T` / `F`. The words are not
// near-misses of any identifier, so the "did you mean" suggester had
// nothing to offer and the reader got the generic "no binding,
// parameter, constant, enum variant, or function with this name is in
// scope" — which sends them looking for a missing declaration.
//
// A file that writes TOML or JSON has just seen `true` as data a line
// earlier, which is what makes this the common mistake rather than a
// rare one.
$ `stdlib/core/io.nu`

@ main → i {
    : b flag true
    ? flag { ( nurl_println `yes` ) } {}
    ^ 0
}
