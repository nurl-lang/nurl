// inout_field.nu — `inout` field targets.
//
// An argument of the form `. obj field` at an `inout`
// parameter passes the ADDRESS of that struct field, so the callee
// mutates exactly that field of the caller's struct in place —
// finer-grained than passing the whole struct `inout`.
//
// Exercises a scalar field target, a struct-typed field target
// (the callee then mutates a field of that nested struct), and a
// scalar field of a second struct.

: Counter { i n i max }
: Game { Counter score i turns }

@ add100 inout i x → v {
    = x + x 100
}

@ bump inout Counter c → v {
    = . c n + . c n 1
}

@ main → i {
    : ~ Counter c @ Counter { 5 10 }
    ( add100 . c n )  // scalar field target: c.n = 105
    ( nurl_print `c.n=` ) ( nurl_print ( nurl_str_int . c n ) ) ( nurl_print `\n` )

    : ~ Game g @ Game { @ Counter { 1 99 } 0 }
    ( bump . g score )  // struct field target: g.score.n -> 2
    ( add100 . g turns )  // scalar field target: g.turns = 100
    ( nurl_print `score.n=` ) ( nurl_print ( nurl_str_int . . g score n ) ) ( nurl_print `\n` )
    ( nurl_print `turns=` ) ( nurl_print ( nurl_str_int . g turns ) ) ( nurl_print `\n` )
    ^ 0
}
