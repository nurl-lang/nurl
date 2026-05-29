// borrow_strict_field_alias.nu — strict-mode extension of the
// N-readers-XOR-1-writer check.
//
// The default check fires only when both aliasing arguments are BARE
// identifiers; under `--strict-borrowck` it also fires when one or
// both arguments reach the same binding through a `. obj field`
// projection.
//
// This file compiles cleanly under default `--borrowck` (the bare-
// identifier check does not see `. c n` as aliasing `c`) and only
// errors out when the test runner adds `--strict-borrowck`.
//
// One positive case + one negative control.

: Counter { i n i tag }

@ swap_field_and_self inout Counter a i b → v {
    = . a n b
}

@ bump_tag inout Counter a → v {
    = . a tag + . a tag 1
}

@ main → i {
    : ~ Counter c @ Counter { 3 7 }
    : ~ Counter d @ Counter { 0 1 }

    // POSITIVE — `c` handed `inout` AND its own field `c.n` read by
    // the same call. Default --borrowck misses this because the
    // second argument's first token is `.`, not the identifier `c`.
    ( swap_field_and_self c . c n )

    // CONTROL — `c` is `inout`, `d.n` is the by-value second arg.
    // Strict mode reads the root of the field-access (`d`) and sees
    // no aliasing.
    ( swap_field_and_self c . d n )

    ( bump_tag d )

    ^ 0
}
