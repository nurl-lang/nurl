// term_utf8.nu — UTF-8 line editing and display-column cursor math in std/term.nu (Agora #506).
//
// Exercises the pure byte-feed editor (`_term_ed_new` / `_term_feed`), cluster
// boundary stepping (`_term_prev_pos` / `_term_next_pos`) and terminal column
// counting (`_term_cols_from` / `_term_repaint_str`) with no tty dependency so
// the test runs identically on POSIX and Windows.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/utf8.nu`
$ `stdlib/std/term.nu`

@ feed_str _TermEd st String buf s raw ( Vec String ) hist → _TermEd {
    : ( Slice u ) v ( slice_of_str raw )
    : i n ( slice_len [u] v )
    : ~ _TermEd cur st
    : ~ i k 0
    ~ & < k n == . cur done 0 {
        = cur ( _term_feed cur buf ( slice_byte v k ) hist )
        = k + k 1
    }
    ^ cur
}

@ ck inout i fails b ok s name → v {
    ? ok {} {
        = fails + fails 1
        ( nurl_print `FAIL: ` )
        ( nurl_print name )
        ( nurl_print `\n` )
    }
}

@ main → i {
    : ~ i fails 0
    : ( Vec String ) empty_hist ( vec_new [String] )

    // 1. Exact Finnish repro from Agora #506: every ä/ö survives byte for byte.
    : s repro `Juhlissa on 8 ihmistä. Jääkaapissa on 5 litraa mehua. Kustakin juotiin litra. Paljonko juotiin yhteensä kun myös kaikki mehu juotiin?`
    : String b1 ( string_with_cap 160 )
    : ~ _TermEd s1 ( _term_ed_new empty_hist )
    = s1 ( feed_str s1 b1 repro empty_hist )
    = s1 ( _term_feed s1 b1 13 empty_hist )
    ( ck fails == . s1 done 1 `repro accepted on CR` )
    ( ck fails == 1 ( nurl_str_eq ( string_data b1 ) repro ) `Finnish UTF-8 repro preserved intact` )
    ( ck fails ( utf8_valid ( string_data b1 ) ) `repro output is valid UTF-8` )

    // 2. Left/Right/Backspace/Delete/insert-in-middle across 2-, 3-, and 4-byte scalars.
    //    Start: "ääööåå ÄÄÖÖÅÅ"
    //    Left×3 → before "ÖÅÅ"
    //    Backspace×2 → deletes "ÄÖ" → "ääööåå ÄÖÅÅ" (cursor before "ÖÅÅ")
    //    Insert "€🎉" (3B + 4B) → "ääööåå Ä€🎉ÖÅÅ" (cursor before "ÖÅÅ")
    //    Right×1 → past "Ö" (cursor before "ÅÅ")
    //    Delete (ESC [ 3 ~) → deletes first "Å" → "ääööåå Ä€🎉ÖÅ"
    : String b2 ( string_with_cap 64 )
    : ~ _TermEd s2 ( _term_ed_new empty_hist )
    = s2 ( feed_str s2 b2 `ääööåå ÄÄÖÖÅÅ` empty_hist )
    // Left × 3: ESC [ D = 27, 91, 68
    : ~ i k 0
    ~ < k 3 {
        = s2 ( _term_feed s2 b2 27 empty_hist )
        = s2 ( _term_feed s2 b2 91 empty_hist )
        = s2 ( _term_feed s2 b2 68 empty_hist )
        = k + k 1
    }
    // Backspace × 2: 127
    = s2 ( _term_feed s2 b2 127 empty_hist )
    = s2 ( _term_feed s2 b2 127 empty_hist )
    // Insert 3-byte € and 4-byte 🎉 in the middle
    = s2 ( feed_str s2 b2 `€🎉` empty_hist )
    // Right × 1: ESC [ C = 27, 91, 67
    = s2 ( _term_feed s2 b2 27 empty_hist )
    = s2 ( _term_feed s2 b2 91 empty_hist )
    = s2 ( _term_feed s2 b2 67 empty_hist )
    // Forward Delete: ESC [ 3 ~ = 27, 91, 51, 126
    = s2 ( _term_feed s2 b2 27 empty_hist )
    = s2 ( _term_feed s2 b2 91 empty_hist )
    = s2 ( _term_feed s2 b2 51 empty_hist )
    = s2 ( _term_feed s2 b2 126 empty_hist )
    = s2 ( _term_feed s2 b2 10 empty_hist )
    ( ck fails == . s2 done 1 `mid-line edit accepted on LF` )
    ( ck fails == 1 ( nurl_str_eq ( string_data b2 ) `ääööåå Ä€🎉ÖÅ` ) `mid-line UTF-8 edit (Left/Right/BS/Del/3B/4B)` )
    ( ck fails ( utf8_valid ( string_data b2 ) ) `mid-line edit remains valid UTF-8` )

    // 3. Display column counting & repaint cursor-left sequence.
    //    "Jääkaapissa" = 13 bytes, 11 columns; at pos=3 (after "Jä"), tail is
    //    "äkaapissa" = 10 bytes, 9 columns → ESC[9D, not ESC[10D.
    : String b3 ( string_from `Jääkaapissa` )
    ( ck fails == ( string_len b3 ) 13 `Jääkaapissa is 13 UTF-8 bytes` )
    ( ck fails == ( _term_cols_from b3 0 ) 11 `Jääkaapissa is 11 terminal columns` )
    ( ck fails == ( _term_cols_from b3 3 ) 9 `tail after Jä is 9 columns` )
    : String rp ( _term_repaint_str `> ` b3 3 )
    : String want_back ( ansi_cursor_left 9 )
    ( ck fails ( string_ends_with rp ( string_data want_back ) ) `repaint emits ESC[9D for 9-column UTF-8 tail` )

    //    Wide CJK + emoji: "中文🎉a" = 3+3+4+1 = 11 bytes, 2+2+2+1 = 7 columns.
    : String bwide ( string_from `中文🎉a` )
    ( ck fails == ( _term_cols_from bwide 0 ) 7 `CJK + emoji width = 2+2+2+1 = 7 columns` )
    ( ck fails == ( _term_cols_from bwide 3 ) 5 `after first CJK char = 5 columns` )
    ( ck fails == ( _term_cols_from bwide 10 ) 1 `after emoji = 1 column` )

    // 4. Combining mark cluster: 'a' + U+0308 (0xCC 0x88) + 'b' = 4 bytes, 2 columns.
    : String bcomb ( string_with_cap 8 )
    ( string_push_char bcomb 97 )  // 'a'
    ( string_push_char bcomb 204 )  // 0xCC
    ( string_push_char bcomb 136 )  // 0x88 (U+0308 combining diaeresis)
    ( string_push_char bcomb 98 )  // 'b'
    ( ck fails == ( _term_cols_from bcomb 0 ) 2 `decomposed a+U+0308+b is 2 columns` )
    ( ck fails == ( _term_next_pos bcomb 0 ) 3 `next_pos steps over base + combining mark` )
    ( ck fails == ( _term_prev_pos bcomb 3 ) 0 `prev_pos steps back over combining mark + base` )

    // 5. Malformed sequences, C1 controls, stray CSI, and truncated lead recovery.
    : String bbad ( string_with_cap 32 )
    : ~ _TermEd sbad ( _term_ed_new empty_hist )
    // Overlong 0xC0 0xAF
    = sbad ( _term_feed sbad bbad 192 empty_hist )
    = sbad ( _term_feed sbad bbad 175 empty_hist )
    // C1 CSI U+009B = 0xC2 0x9B (must be rejected!)
    = sbad ( _term_feed sbad bbad 194 empty_hist )
    = sbad ( _term_feed sbad bbad 155 empty_hist )
    // Surrogate U+D800 = 0xED 0xA0 0x80
    = sbad ( _term_feed sbad bbad 237 empty_hist )
    = sbad ( _term_feed sbad bbad 160 empty_hist )
    = sbad ( _term_feed sbad bbad 128 empty_hist )
    // Out-of-range U+110000 = 0xF4 0x90 0x80 0x80
    = sbad ( _term_feed sbad bbad 244 empty_hist )
    = sbad ( _term_feed sbad bbad 144 empty_hist )
    = sbad ( _term_feed sbad bbad 128 empty_hist )
    = sbad ( _term_feed sbad bbad 128 empty_hist )
    // Stray continuation 0x80
    = sbad ( _term_feed sbad bbad 128 empty_hist )
    // PageUp ESC [ 5 ~ (must not leak '~')
    = sbad ( _term_feed sbad bbad 27 empty_hist )
    = sbad ( _term_feed sbad bbad 91 empty_hist )
    = sbad ( _term_feed sbad bbad 53 empty_hist )
    = sbad ( _term_feed sbad bbad 126 empty_hist )
    // Truncated 2-byte lead 0xC3 immediately followed by "ok\r"
    = sbad ( _term_feed sbad bbad 195 empty_hist )
    = sbad ( _term_feed sbad bbad 111 empty_hist )  // 'o'
    = sbad ( _term_feed sbad bbad 107 empty_hist )  // 'k'
    = sbad ( _term_feed sbad bbad 13 empty_hist )
    ( ck fails == . sbad done 1 `recovery after truncated lead accepts CR` )
    ( ck fails == 1 ( nurl_str_eq ( string_data bbad ) `ok` ) `invalid UTF-8, C1 and PageUp rejected cleanly` )

    // 6. History recall with UTF-8 + Ctrl-A / Right / Ctrl-K + EOF cancel.
    : ( Vec String ) hist ( vec_new [String] )
    ( vec_push [String] hist ( string_from `ensimmäinen` ) )
    ( vec_push [String] hist ( string_from `toinen 🎉 rivi` ) )
    : String bh ( string_with_cap 32 )
    : ~ _TermEd sh ( _term_ed_new hist )
    // Up × 2 → "ensimmäinen", Down × 1 → "toinen 🎉 rivi"
    = sh ( _term_feed sh bh 27 hist )
    = sh ( _term_feed sh bh 91 hist )
    = sh ( _term_feed sh bh 65 hist )
    = sh ( _term_feed sh bh 27 hist )
    = sh ( _term_feed sh bh 91 hist )
    = sh ( _term_feed sh bh 65 hist )
    ( ck fails == 1 ( nurl_str_eq ( string_data bh ) `ensimmäinen` ) `history Up×2 recalls UTF-8` )
    = sh ( _term_feed sh bh 27 hist )
    = sh ( _term_feed sh bh 91 hist )
    = sh ( _term_feed sh bh 66 hist )
    // Ctrl-A (1), Right×8 (past "toinen 🎉"), Ctrl-K (11) → "toinen 🎉"
    = sh ( _term_feed sh bh 1 hist )
    = k 0
    ~ < k 8 {
        = sh ( _term_feed sh bh 27 hist )
        = sh ( _term_feed sh bh 91 hist )
        = sh ( _term_feed sh bh 67 hist )
        = k + k 1
    }
    = sh ( _term_feed sh bh 11 hist )
    ( ck fails == 1 ( nurl_str_eq ( string_data bh ) `toinen 🎉` ) `Ctrl-A + Right×8 + Ctrl-K stops on UTF-8 boundary` )
    // EOF (-1) cancels cleanly without hanging
    = sh ( _term_feed sh bh -1 hist )
    ( ck fails == . sh done 2 `EOF (-1) cancels cleanly` )

    ? == fails 0 {
        ( nurl_print `term_utf8: all checks passed\n` )
    } {}
    ^ ? == fails 0 0 1
}
