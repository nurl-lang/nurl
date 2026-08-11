// ret_falloff_enum.nu — enum values returned by IMPLICIT fall-off.
// Both shapes used to emit invalid IR (`ret %Color %tag` with an i64
// tag) that only the LLVM verifier saw: the bare-variant tail wraps via
// the shared return battery's enum wrap, and the `??` tail exercises
// gen_match's join-variant proof (every value arm a variant of the one
// enum) feeding the same wrap.
//
// Expected output:
//   red
//   green
//   blue

: | Color {
    Red
    Green
    Blue
}

@ pick_bare → Color {
    Red
}

@ pick_match i n → Color {
    ?? n {
        0 → Red
        1 → Green
        _ → Blue
    }
}

@ color_name Color c → s {
    ?? c {
        Red → { ^ `red` }
        Green → { ^ `green` }
        Blue → { ^ `blue` }
    }
}

@ main → i {
    : Color a ( pick_bare )
    : Color b ( pick_match 1 )
    : Color c ( pick_match 7 )
    ( nurl_print ( color_name a ) ) ( nurl_print `\n` )
    ( nurl_print ( color_name b ) ) ( nurl_print `\n` )
    ( nurl_print ( color_name c ) ) ( nurl_print `\n` )
    ^ 0
}
