// stdlib/std/term.nu — terminal control: raw mode, isatty, ANSI, line editor.
//
// The prerequisite for a REPL (critic C1) and TUI examples. POSIX
// termios via libc FFI (struct termios sized by nurl_native_sizeof, so
// the platform layout never leaks into NURL); ANSI helpers are pure
// string builders; the line editor is a minimal raw-mode loop with
// history + cursor movement.
//
//   ( term_is_tty i fd )            → b
//   ( term_raw_enable i fd )        → ? TermState   None: not a tty / failed
//   ( term_raw_disable TermState )  → v             restore + free
//
//   ( ansi_reset )                  → String  ESC[0m
//   ( ansi_sgr i code )             → String  ESC[<code>m   (1 bold, 4 underline…)
//   ( ansi_fg i color )             → String  ESC[38;5;<n>m (256-color)
//   ( ansi_bg i color )             → String  ESC[48;5;<n>m
//   ( ansi_clear )                  → String  clear screen + home
//   ( ansi_clear_line )             → String  erase line + CR
//   ( ansi_cursor_to i row i col )  → String  1-based
//   ( ansi_cursor_up/down/right/left i n ) → String
//
//   ( term_read_line s prompt ( Vec String ) history ) → ? String
//       Raw-mode line editor on stdin/stdout: printable insert,
//       backspace, ←/→ cursor, ↑/↓ history (borrowed, newest last),
//       Ctrl-A/Ctrl-E home/end, Ctrl-K kill-to-end, Enter → Some(line),
//       Ctrl-C (or Ctrl-D on an empty line) → None. Returns None
//       immediately when stdin is not a tty — callers fall back to
//       plain buffered reads.
//
// Win32/WASI: termios is absent — term_raw_enable returns None and the
// ANSI builders still work (Windows Terminal/ConPTY understands VT).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`  // read / write / close / posix_const
$ `stdlib/ext/env.nu`  // $COLUMNS / $LINES fallback for term_width

& `c` @ isatty i32 fd → i32

& `c` @ tcgetattr i32 fd s buf → i32

& `c` @ tcsetattr i32 fd i32 act s buf → i32

& `c` @ cfmakeraw s buf → v

: TermState { i fd s saved }

@ term_is_tty i fd → b {
    ^ == # i ( isatty # i32 fd ) 1
}

// Save the current termios for `fd`, switch it to raw (cfmakeraw:
// no echo, no canonical buffering, no signal chars). None when fd is
// not a tty, termios is unsupported on this platform, or any call
// fails — the terminal is left untouched in every None case.
@ term_raw_enable i fd → ?TermState {
    ? ( term_is_tty fd ) {} { ^ @ ?TermState { F } }
    : i sz ( nurl_native_sizeof `struct termios` )
    ? <= sz 0 { ^ @ ?TermState { F } } {}
    : s saved ( nurl_zalloc sz )
    ? == # i ( tcgetattr # i32 fd saved ) 0 {} {
        ( nurl_free saved )
        ^ @ ?TermState { F }
    }
    : s raw ( nurl_zalloc sz )
    ( nurl_memcpy # *u raw # *u saved sz )
    ( cfmakeraw raw )
    : i32 rc ( tcsetattr # i32 fd # i32 ( posix_const `TCSAFLUSH` ) raw )
    ( nurl_free raw )
    ? == # i rc 0 {} {
        ( nurl_free saved )
        ^ @ ?TermState { F }
    }
    ^ @ ?TermState { T @ TermState { fd saved } }
}

@ term_raw_disable TermState st → v {
    : i32 _rc ( tcsetattr # i32 . st fd # i32 ( posix_const `TCSAFLUSH` ) . st saved )
    ( nurl_free . st saved )
}

// ── ANSI builders (ESC = 0x1b cannot ride in a backtick literal) ────

@ __ansi_csi → String {
    : String s ( string_with_cap 8 )
    ( string_push_char s 27 )
    ( string_push_char s 91 )  // '['
    ^ s
}

@ ansi_reset → String {
    : String s ( __ansi_csi )
    ( string_push_str s `0m` )
    ^ s
}

@ ansi_sgr i code → String {
    : String s ( __ansi_csi )
    ( string_push_str s ( nurl_str_int code ) )
    ( string_push_char s 109 )  // 'm'
    ^ s
}

@ ansi_fg i color → String {
    : String s ( __ansi_csi )
    ( string_push_str s `38;5;` )
    ( string_push_str s ( nurl_str_int color ) )
    ( string_push_char s 109 )
    ^ s
}

@ ansi_bg i color → String {
    : String s ( __ansi_csi )
    ( string_push_str s `48;5;` )
    ( string_push_str s ( nurl_str_int color ) )
    ( string_push_char s 109 )
    ^ s
}

@ ansi_clear → String {
    : String s ( __ansi_csi )
    ( string_push_str s `2J` )
    : String h ( __ansi_csi )
    ( string_push_str h `H` )
    ( string_push_str s ( string_data h ) )
    ( string_free h )
    ^ s
}

@ ansi_clear_line → String {
    : String s ( __ansi_csi )
    ( string_push_str s `2K` )
    ( string_push_char s 13 )  // CR
    ^ s
}

@ ansi_cursor_to i row i col → String {
    : String s ( __ansi_csi )
    ( string_push_str s ( nurl_str_int row ) )
    ( string_push_char s 59 )  // ';'
    ( string_push_str s ( nurl_str_int col ) )
    ( string_push_char s 72 )  // 'H'
    ^ s
}

@ __ansi_move i n i letter → String {
    : String s ( __ansi_csi )
    ( string_push_str s ( nurl_str_int n ) )
    ( string_push_char s letter )
    ^ s
}

@ ansi_cursor_up i n → String { ^ ( __ansi_move n 65 ) }  // 'A'
@ ansi_cursor_down i n → String { ^ ( __ansi_move n 66 ) }  // 'B'
@ ansi_cursor_right i n → String { ^ ( __ansi_move n 67 ) }  // 'C'
@ ansi_cursor_left i n → String { ^ ( __ansi_move n 68 ) }  // 'D'

// ── minimal line editor ─────────────────────────────────────────────

// Read one byte from stdin; -1 on EOF/error.
@ __term_getb → i {
    : s buf ( nurl_zalloc 1 )
    : i n ( read 0 # *u buf 1 )
    : i c ? > n 0 ( nurl_peek buf 0 ) -1
    ( nurl_free buf )
    ^ & c 255
}

// Repaint: CR + erase line + prompt + buffer, then walk the cursor
// back to `pos`.
@ __term_repaint s prompt String buf i pos → v {
    : String cl ( ansi_clear_line )
    ( nurl_print ( string_data cl ) )
    ( string_free cl )
    ( nurl_print prompt )
    ( nurl_print ( string_data buf ) )
    : i tail - ( string_len buf ) pos
    ? > tail 0 {
        : String back ( ansi_cursor_left tail )
        ( nurl_print ( string_data back ) )
        ( string_free back )
    } {}
    ( nurl_flush_stdout )
}

// Replace buf's contents with `src` (used by history recall).
@ __term_setbuf String buf s src → v {
    ( string_clear buf )
    ( string_push_str buf src )
}

// Remove the byte at `idx` (rebuild via substr — lines are short).
@ __term_delete_at String buf i idx → v {
    : i n ( string_len buf )
    : String head ( string_substr buf 0 idx )
    : String tail ( string_substr buf + idx 1 - n + idx 1 )
    ( string_clear buf )
    ( string_push_str buf ( string_data head ) )
    ( string_push_str buf ( string_data tail ) )
    ( string_free head )
    ( string_free tail )
}

// Insert byte `c` at `idx`.
@ __term_insert_at String buf i idx i c → v {
    : i n ( string_len buf )
    : String head ( string_substr buf 0 idx )
    : String tail ( string_substr buf idx - n idx )
    ( string_clear buf )
    ( string_push_str buf ( string_data head ) )
    ( string_push_char buf c )
    ( string_push_str buf ( string_data tail ) )
    ( string_free head )
    ( string_free tail )
}

// Drop everything from `keep` onward (Ctrl-K).
@ __term_truncate String buf i keep → v {
    : String head ( string_substr buf 0 keep )
    ( string_clear buf )
    ( string_push_str buf ( string_data head ) )
    ( string_free head )
}

@ term_read_line s prompt ( Vec String ) history → ?String {
    : ?TermState rawst ( term_raw_enable 0 )
    ^ ?? rawst {
        T st → ( __term_edit st prompt history )
        F _ → @ ?String { F }
    }
}

// The raw-mode editing loop proper (st is consumed: disabled before
// returning on every path).
@ __term_edit TermState st s prompt ( Vec String ) history → ?String {
    : String buf ( string_with_cap 64 )
    : ~ i pos 0
    : ~ i hidx ( vec_len [String] history )  // one past newest
    : ~ i done 0  // 0 = editing, 1 = accepted, 2 = cancelled
    ( __term_repaint prompt buf pos )
    ~ == done 0 {
        : i c ( __term_getb )
        ? | == c 13 == c 10 { = done 1 } {
            ? | == c 3 & == c 4 == ( string_len buf ) 0 { = done 2 } {
                ? | == c 127 == c 8 {
                    ? > pos 0 {
                        ( __term_delete_at buf - pos 1 )
                        = pos - pos 1
                    } {}
                } {
                    ? == c 1 { = pos 0 } {  // Ctrl-A
                        ? == c 5 { = pos ( string_len buf ) } {  // Ctrl-E
                            ? == c 11 {  // Ctrl-K
                                ( __term_truncate buf pos )
                            } {
                                ? == c 27 {  // ESC [ ...
                                    : i c1 ( __term_getb )
                                    ? == c1 91 {
                                        : i c2 ( __term_getb )
                                        ? & == c2 68 > pos 0 { = pos - pos 1 } {}  // left
                                        ? & == c2 67 < pos ( string_len buf ) { = pos + pos 1 } {}  // right
                                        ? & == c2 65 > hidx 0 {  // up
                                            = hidx - hidx 1
                                            ?? ( vec_get [String] history hidx ) {
                                                T h → { ( __term_setbuf buf ( string_data h ) ) = pos ( string_len buf ) ( string_free h ) }
                                                F _ → {}
                                            }
                                        } {}
                                        ? & == c2 66 < hidx ( vec_len [String] history ) {  // down
                                            = hidx + hidx 1
                                            ? == hidx ( vec_len [String] history ) {
                                                ( __term_setbuf buf `` )
                                                = pos 0
                                            } {
                                                ?? ( vec_get [String] history hidx ) {
                                                    T h → { ( __term_setbuf buf ( string_data h ) ) = pos ( string_len buf ) ( string_free h ) }
                                                    F _ → {}
                                                }
                                            }
                                        } {}
                                    } {}
                                } {
                                    ? & >= c 32 < c 127 {  // printable insert
                                        ( __term_insert_at buf pos c )
                                        = pos + pos 1
                                    } {}
                                } } } } } } }
        ? == done 0 { ( __term_repaint prompt buf pos ) } {}
    }
    ( term_raw_disable st )
    ( nurl_print `\n` )
    ? == done 1 { ^ @ ?String { T buf } } {}
    ( string_free buf )
    ^ @ ?String { F }
}

// ── Terminal size ───────────────────────────────────────────────────
//
// TIOCGWINSZ on the requested fd; when that fails (not a tty, wasm,
// win32 console without the ioctl) fall back to $COLUMNS / $LINES,
// then to the classic 80×24. struct winsize is four u16s (row, col,
// xpixel, ypixel) on every POSIX platform; the ioctl request value
// differs per OS and is surfaced through nurl_native_constant.

// ioctl(2) is `int ioctl(int, unsigned long, ...)` — variadic, so the
// argp pointer must go through the variadic ABI. See the note on fcntl
// in core/posix.nu for why a fixed-arity spelling is silently wrong on
// Apple arm64 and silently fine everywhere else.
& `c` @ ioctl i32 fd i req ... → i32

@ __term_winsz i fd i idx → i {
    : i req ( posix_const `TIOCGWINSZ` )
    ? < req 0 { ^ -1 } {}
    : *u ws # *u ( nurl_alloc 8 )
    : i32 rc ( ioctl # i32 fd req ws )
    : ~ i out -1
    ? == # i rc 0 {
        : i lo # i . ws * idx 2
        : i hi # i . ws + * idx 2 1
        = out | lo << hi 8
    } {}
    ( nurl_free # s ws )
    ^ ? > out 0 out -1
}

@ __term_env_dim s name i def → i {
    : ?String ev ( env_get name )
    ?? ev {
        T v → {
            : ~ i out def
            ?? ( string_to_int v ) {
                T n → { ? > n 0 { = out n } {} }
                F _ → {}
            }
            ( string_free v )
            ^ out
        }
        F → { ^ def }
    }
}

// Columns of the terminal on stdout: ioctl → $COLUMNS → 80.
@ term_width → i {
    : i w ( __term_winsz 1 1 )
    ? > w 0 { ^ w } {}
    ^ ( __term_env_dim `COLUMNS` 80 )
}

// Rows of the terminal on stdout: ioctl → $LINES → 24.
@ term_height → i {
    : i hh ( __term_winsz 1 0 )
    ? > hh 0 { ^ hh } {}
    ^ ( __term_env_dim `LINES` 24 )
}
