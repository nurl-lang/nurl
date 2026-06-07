// should_fail_bare_pipe_enum.nu — an enum must be declared `: | Name`,
// not with a bare `|` at the top level.
//
// The `:`-less spelling used to fall through the decl loop's silent
// catch-all: the `|` token was skipped and the enum body left to an
// incidental generation path. It only ever "worked" when an enum of the
// same name was also imported (the local decl being effectively dead) —
// otherwise the variants were silently dropped or double-generated. Now
// a bare top-level `|` is a hard error pointing at the correct `: |`
// spelling. Expect COMPILE FAIL.

| Color {
    Red
    Green
}

@ main → i {
    ^ 0
}
