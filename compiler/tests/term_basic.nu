// term_basic.nu — std/term.nu acceptance (the tty-independent surface).
//
// isatty / raw-enable are checked against a plain file fd (never a
// tty → deterministic F / None in any environment, including CI). The
// ANSI builders are byte-exact-checked via hex (ESC is unprintable).
// The raw-mode toggle and line editor need a real pty — exercised
// manually / by examples, not goldenable here; term_raw_enable's
// not-a-tty None path IS covered, which is the contract callers
// (REPL fallback) rely on.

$ `stdlib/core/string.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/term.nu`

@ phex String v → v {
    : i n ( string_len v )
    : ~ i k 0
    ~ < k n {
        : i b ( string_get v k )
        : i hi / b 16
        : i lo % b 16
        : String c ( string_with_cap 3 )
        ( string_push_char c ? < hi 10 + 48 hi + 87 hi )
        ( string_push_char c ? < lo 10 + 48 lo + 87 lo )
        ( nurl_print ( string_data c ) )
        ( string_free c )
        = k + k 1
    }
}

@ show s label String v → v {
    ( nurl_print label ) ( nurl_print `=` )
    ( phex v )
    ( nurl_print `\n` )
    ( string_free v )
}

@ main → i {
    // ── a regular file fd is never a tty ──
    : i32 fd ( open `/dev/null` # i32 ( posix_const `O_RDONLY` ) # i32 0 )
    ( nurl_print `file_is_tty=` ) ( nurl_print ? ( term_is_tty # i fd ) `T` `F` ) ( nurl_print `\n` )
    : ?TermState rs ( term_raw_enable # i fd )
    ( nurl_print `raw_on_file=` )
    ?? rs { T st → { ( nurl_print `Some(BUG)` ) ( term_raw_disable st ) } F _ → ( nurl_print `none` ) }
    ( nurl_print `\n` )
    : i _c ( close # i fd )

    // ── struct termios is sized (POSIX) ──
    ( nurl_print `termios_sized=` )
    ( nurl_print ? > ( nurl_native_sizeof `struct termios` ) 0 `T` `F` ) ( nurl_print `\n` )

    // ── ANSI builders, byte-exact ──
    ( show `reset` ( ansi_reset ) )  // 1b5b306d
    ( show `bold` ( ansi_sgr 1 ) )  // 1b5b316d
    ( show `fg196` ( ansi_fg 196 ) )  // 1b5b33383b353b3139366d
    ( show `bg21` ( ansi_bg 21 ) )  // 1b5b34383b353b32316d
    ( show `clear` ( ansi_clear ) )  // 1b5b324a 1b5b48
    ( show `clear_line` ( ansi_clear_line ) )  // 1b5b324b0d
    ( show `cursor_to_5_10` ( ansi_cursor_to 5 10 ) )  // 1b5b353b313048
    ( show `up3` ( ansi_cursor_up 3 ) )  // 1b5b3341
    ( show `down2` ( ansi_cursor_down 2 ) )  // 1b5b3242
    ( show `right7` ( ansi_cursor_right 7 ) )  // 1b5b3743
    ( show `left1` ( ansi_cursor_left 1 ) )  // 1b5b3144
    ^ 0
}
