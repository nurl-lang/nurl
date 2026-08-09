// enum_nominal_ops.nu — the LEGAL enum operations, now that enums are
// enforced as nominal: '=='/'!=' against a bare variant and between two
// values of the same payload-free enum (tag compare via extractvalue —
// `== c Green` used to emit an icmp on the struct type, invalid IR that
// made the diag_cond_enum cure text uncompilable), a bare variant
// return out of a `→ Color` fn (used to `ret i64` out of a `define
// %Color`), and the `?`-join variant blessing on init, assign and
// return positions (`= c ? cond Green Blue` — both arms proven
// variants of the declared enum).
: | Color { Red Green Blue }

@ pick_ret i n → Color {
    ^ ? > n 3 Green Blue
}

@ flip Color c → Color {
    ? == c Red { ^ Green } {}
    ^ Red
}

@ main → i {
    : Color c Green
    ? == c Green { ( nurl_print `eq_variant\n` ) } {}
    ? != c Red { ( nurl_print `ne_variant\n` ) } {}
    : Color d Green
    ? == c d { ( nurl_print `eq_same_enum\n` ) } {}
    ? == Red ( flip d ) { ( nurl_print `eq_call_lhs_variant\n` ) } {}
    : ~ Color e Red
    = e ? == c d Green Blue
    ? == e Green { ( nurl_print `join_assign\n` ) } {}
    : Color f ? != c d Red Blue
    ? == f Blue { ( nurl_print `join_init\n` ) } {}
    : Color g ( pick_ret 5 )
    ? == g Green { ( nurl_print `join_ret\n` ) } {}
    ?? g {
        Red → { ( nurl_print `match_red\n` ) }
        Green → { ( nurl_print `match_green\n` ) }
        Blue → { ( nurl_print `match_blue\n` ) }
    }
    ^ 0
}
