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
$ `stdlib/core/slice.nu`
$ `stdlib/core/posix.nu`  // read / write / close / posix_const
$ `stdlib/std/utf8.nu`
$ `stdlib/ext/env.nu`  // $COLUMNS / $LINES fallback for term_width

& `c` @ isatty i32 fd → i32

& `c` @ tcgetattr i32 fd *u buf → i32

& `c` @ tcsetattr i32 fd i32 act in *u buf → i32

& `c` @ cfmakeraw *u buf → v

// `saved` is the termios the terminal had before raw mode, kept as the
// bytes C wrote (the struct is opaque here) and released with the state.
// Only term_raw_enable makes one (`raw`: a literal is unsafe code).
raw : TermState { i fd ( Vec u ) saved }

// The runtime's echo-off line read (stdlib/runtime_core.c): the prompt goes
// to stderr, and the line comes back without its newline, the caller's.
& `c` @ nurl_read_password s prompt → sink s

// A line read from stdin with the terminal's echo off — a password prompt.
// Where echo cannot be turned off (stdin is not a terminal, WASI) the line
// is read as typed.
@ term_read_password s prompt → String {
    : s raw ( nurl_read_password prompt )
    : String out ( string_from raw )
    ^ out
}

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
    : ( Vec u ) saved ( vec_zeroed [u] sz )
    ? == # i ( tcgetattr # i32 fd # *u ( vec_data [u] saved ) ) 0 {} {
        ^ @ ?TermState { F }
    }
    : ( Vec u ) raw ( vec_clone [u] saved )
    ( cfmakeraw # *u ( vec_data [u] raw ) )
    : i32 rc ( tcsetattr # i32 fd # i32 ( posix_const `TCSAFLUSH` ) # *u ( vec_data [u] raw ) )
    ? == # i rc 0 {} {
        ^ @ ?TermState { F }
    }
    ^ @ ?TermState { T @ TermState { fd saved } }
}

@ term_raw_disable TermState st → v {
    // tcsetattr reads a whole struct termios: `saved` must still hold one
    // (a callee can empty a sealed struct's Vec field, agora #159).
    ? < ( vec_len [u] . st saved ) ( nurl_native_sizeof `struct termios` ) { ^ } {}
    : i32 _rc ( tcsetattr # i32 . st fd # i32 ( posix_const `TCSAFLUSH` ) # *u ( vec_data [u] . st saved ) )
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
    : ~ u b 0
    : i n ( __term_read_byte b )
    ^ ? > n 0 # i b -1
}

// read(2) of one byte into the caller's `b` (its place, for the call).
@ __term_read_byte inout u b → i {
    ^ ( read 0 # *u ( mem_addr b ) 1 )
}

// Terminal display width of one Unicode scalar (0 for controls and combining
// marks, 2 for East Asian Wide / Fullwidth / emoji blocks, 1 otherwise).
@ __term_cp_width i cp → i {
    ? | < cp 32 & >= cp 127 < cp 160 { ^ 0 } {}
    ? < cp 768 { ^ 1 } {}
    ? | & >= cp 768 <= cp 879
    | & >= cp 1155 <= cp 1161
    | & >= cp 1425 <= cp 1469
    | == cp 1471
    | & >= cp 1473 <= cp 1474
    | & >= cp 1476 <= cp 1477
    | == cp 1479
    | & >= cp 1552 <= cp 1562
    | & >= cp 1611 <= cp 1631
    | == cp 1648
    | & >= cp 1750 <= cp 1773
    | == cp 3633
    | & >= cp 3636 <= cp 3642
    | & >= cp 3655 <= cp 3662
    | & >= cp 4448 <= cp 4607
    | & >= cp 6832 <= cp 6911
    | & >= cp 7616 <= cp 7679
    | & >= cp 8203 <= cp 8207
    | & >= cp 8288 <= cp 8292
    | & >= cp 8400 <= cp 8447
    | & >= cp 12441 <= cp 12442
    | & >= cp 65024 <= cp 65039
    | & >= cp 65056 <= cp 65071
    == cp 65279 { ^ 0 } {}
    ? | & >= cp 4352 <= cp 4447
    | & >= cp 9001 <= cp 9002
    | & >= cp 11904 <= cp 12350
    | & >= cp 12352 <= cp 42191
    | & >= cp 44032 <= cp 55203
    | & >= cp 63744 <= cp 64255
    | & >= cp 65040 <= cp 65049
    | & >= cp 65072 <= cp 65135
    | & >= cp 65280 <= cp 65376
    | & >= cp 65504 <= cp 65510
    | & >= cp 127744 <= cp 128591
    | & >= cp 128640 <= cp 128767
    | & >= cp 129280 <= cp 129535
    | & >= cp 129648 <= cp 129791
    | & >= cp 131072 <= cp 196605
    & >= cp 196608 <= cp 262141 { ^ 2 } {}
    ^ 1
}

// Terminal columns occupied by `buf[pos .. len)`.
@ _term_cols_from String buf i pos → i {
    : ( Slice u ) v ( slice_of_str ( string_data buf ) )
    : i n ( slice_len [u] v )
    : ~ i p ? < pos 0 0 pos
    : ~ i cols 0
    ~ < p n {
        : Utf8Dec d ( utf8_decode_at v p )
        : i step ? > . d width 0 . d width 1
        = cols + cols ( __term_cp_width . d cp )
        = p + p step
    }
    ^ cols
}

@ __term_is_cont i b → b {
    ^ & >= b 128 < b 192
}

// Step back one UTF-8 scalar boundary in `v` from `pos > 0`.
@ __term_prev_scalar ( Slice u ) v i pos → i {
    ? <= pos 0 { ^ 0 } {}
    : ~ i p - pos 1
    : ~ i steps 0
    ~ & > p 0 & < steps 3 ( __term_is_cont ( slice_byte v p ) ) {
        = p - p 1
        = steps + steps 1
    }
    : Utf8Dec d ( utf8_decode_at v p )
    ? & == . d ok 1 == + p . d width pos { ^ p } {}
    ^ - pos 1
}

// Previous cursor boundary before byte `pos` (steps across any trailing
// zero-width combining marks onto their base character).
@ _term_prev_pos String buf i pos → i {
    ? <= pos 0 { ^ 0 } {}
    : ( Slice u ) v ( slice_of_str ( string_data buf ) )
    : ~ i p ( __term_prev_scalar v pos )
    : ~ b more T
    ~ & > p 0 more {
        : Utf8Dec d ( utf8_decode_at v p )
        ? & == . d ok 1 == ( __term_cp_width . d cp ) 0 {
            = p ( __term_prev_scalar v p )
        } {
            = more F
        }
    }
    ^ p
}

// Next cursor boundary after byte `pos` (advances past one character and any
// zero-width combining marks attached to it).
@ _term_next_pos String buf i pos → i {
    : ( Slice u ) v ( slice_of_str ( string_data buf ) )
    : i n ( slice_len [u] v )
    ? >= pos n { ^ n } {}
    : Utf8Dec d0 ( utf8_decode_at v pos )
    : ~ i p + pos ? > . d0 width 0 . d0 width 1
    : ~ b more T
    ~ & < p n more {
        : Utf8Dec d ( utf8_decode_at v p )
        ? & == . d ok 1 == ( __term_cp_width . d cp ) 0 {
            = p + p . d width
        } {
            = more F
        }
    }
    ^ p
}

// Build the repaint frame: erase line + CR + prompt + buffer, then walk the
// cursor left by the display columns of `buf[pos .. len)`.
@ _term_repaint_str s prompt String buf i pos → String {
    : String out ( ansi_clear_line )
    ( string_push_str out prompt )
    ( string_append out buf )
    : i tail ( _term_cols_from buf pos )
    ? > tail 0 {
        : String back ( ansi_cursor_left tail )
        ( string_append out back )
    } {}
    ^ out
}

// Repaint: CR + erase line + prompt + buffer, then walk the cursor
// back to `pos`.
@ __term_repaint s prompt String buf i pos → v {
    : String frame ( _term_repaint_str prompt buf pos )
    ( nurl_print ( string_data frame ) )
    ( nurl_flush_stdout )
}

// Replace buf's contents with `src` (used by history recall).
@ __term_setbuf String buf s src → v {
    ( string_clear buf )
    ( string_push_str buf src )
}

// Remove bytes `[from, to)` from `buf` (rebuild via substr — lines are short).
@ __term_delete_range String buf i from i to → v {
    : i n ( string_len buf )
    ? | < from 0 | >= from to > to n { ^ } {}
    : String head ( string_substr buf 0 from )
    : String tail ( string_substr buf to - n to )
    ( string_clear buf )
    ( string_append buf head )
    ( string_append buf tail )
}

// Insert byte `c` at `idx`.
@ __term_insert_at String buf i idx i c → v {
    : i n ( string_len buf )
    : String head ( string_substr buf 0 idx )
    : String tail ( string_substr buf idx - n idx )
    ( string_clear buf )
    ( string_append buf head )
    ( string_push_char buf c )
    ( string_append buf tail )
}

// Insert `ins` at byte `idx`.
@ __term_insert_str String buf i idx String ins → v {
    : i n ( string_len buf )
    : String head ( string_substr buf 0 idx )
    : String tail ( string_substr buf idx - n idx )
    ( string_clear buf )
    ( string_append buf head )
    ( string_append buf ins )
    ( string_append buf tail )
}

// Drop everything from `keep` onward (Ctrl-K).
@ __term_truncate String buf i keep → v {
    : String head ( string_substr buf 0 keep )
    ( string_clear buf )
    ( string_append buf head )
}

// Pure scalar state for one `term_read_line` session:
//   done: 0 = editing, 1 = accepted, 2 = cancelled / EOF
//   esc:  0 = ground, 1 = after ESC, 2 = CSI (`ESC [`), 3 = SS3 (`ESC O`)
: _TermEd {
    i pos
    i hidx
    i done
    i esc
    i csi_param
    i utf8_need
    i utf8_cp
    i utf8_min
}

@ _term_ed_new ( Vec String ) history → _TermEd {
    ^ @ _TermEd { 0 ( vec_len [String] history ) 0 0 0 0 0 0 }
}

// Feed one raw input byte `c` (-1 on EOF) into `(st, buf)`.
@ _term_feed _TermEd st String buf i c ( Vec String ) history → _TermEd {
    : ~ i pos . st pos
    : ~ i hidx . st hidx
    : ~ i done . st done
    : ~ i esc . st esc
    : ~ i csi . st csi_param
    : ~ i need . st utf8_need
    : ~ i cp . st utf8_cp
    : ~ i umin . st utf8_min

    ? < c 0 {
        ^ @ _TermEd { pos hidx 2 0 0 0 0 0 }
    } {}

    ? > need 0 {
        ? & >= c 128 < c 192 {
            = cp | << cp 6 & c 63
            = need - need 1
            ? == need 0 {
                ? & >= cp umin & <= cp 1114111 ! & >= cp 55296 <= cp 57343 {
                    : String ins ( utf8_encode_cp cp )
                    : i w ( string_len ins )
                    ( __term_insert_str buf pos ins )
                    = pos + pos w
                } {}
                = cp 0
                = umin 0
            } {}
            ^ @ _TermEd { pos hidx done esc csi need cp umin }
        } {
            = need 0
            = cp 0
            = umin 0
        }
    } {}

    ? != esc 0 {
        ? == c 3 {
            ^ @ _TermEd { pos hidx 2 0 0 0 0 0 }
        } {}
        ? == esc 1 {
            ? == c 91 { ^ @ _TermEd { pos hidx done 2 0 0 0 0 } } {}
            ? == c 79 { ^ @ _TermEd { pos hidx done 3 0 0 0 0 } } {}
            ? == c 27 { ^ @ _TermEd { pos hidx done 1 0 0 0 0 } } {}
            ^ @ _TermEd { pos hidx done 0 0 0 0 0 }
        } {}
        ? == esc 3 {
            ? == c 72 { = pos 0 } {}
            ? == c 70 { = pos ( string_len buf ) } {}
            ? == c 68 { = pos ( _term_prev_pos buf pos ) } {}
            ? == c 67 { = pos ( _term_next_pos buf pos ) } {}
            ^ @ _TermEd { pos hidx done 0 0 0 0 0 }
        } {}
        ? == esc 2 {
            ? & >= c 48 <= c 57 {
                ? >= csi 0 { = csi + * csi 10 - c 48 } {}
                ^ @ _TermEd { pos hidx done 2 csi 0 0 0 }
            } {}
            ? & >= c 32 <= c 63 {
                ? == c 59 { = csi -1 } {}
                ^ @ _TermEd { pos hidx done 2 csi 0 0 0 }
            } {}
            ? & >= c 64 <= c 126 {
                ? == c 68 { = pos ( _term_prev_pos buf pos ) } {}
                ? == c 67 { = pos ( _term_next_pos buf pos ) } {}
                ? == c 72 { = pos 0 } {}
                ? == c 70 { = pos ( string_len buf ) } {}
                ? & == c 65 > hidx 0 {
                    = hidx - hidx 1
                    ?? ( vec_get [String] history hidx ) {
                        T h → { ( __term_setbuf buf ( string_data h ) ) = pos ( string_len buf ) }
                        F _ → {}
                    }
                } {}
                ? & == c 66 < hidx ( vec_len [String] history ) {
                    = hidx + hidx 1
                    ? == hidx ( vec_len [String] history ) {
                        ( __term_setbuf buf `` )
                        = pos 0
                    } {
                        ?? ( vec_get [String] history hidx ) {
                            T h → { ( __term_setbuf buf ( string_data h ) ) = pos ( string_len buf ) }
                            F _ → {}
                        }
                    }
                } {}
                ? == c 126 {
                    ? | == csi 1 == csi 7 { = pos 0 } {}
                    ? | == csi 4 == csi 8 { = pos ( string_len buf ) } {}
                    ? == csi 3 {
                        : i nx ( _term_next_pos buf pos )
                        ( __term_delete_range buf pos nx )
                    } {}
                } {}
                ^ @ _TermEd { pos hidx done 0 0 0 0 0 }
            } {}
            ? == c 27 { ^ @ _TermEd { pos hidx done 1 0 0 0 0 } } {}
            ^ @ _TermEd { pos hidx done 0 0 0 0 0 }
        } {}
    } {}

    ? | == c 13 == c 10 {
        = done 1
    } {
        ? | == c 3 & == c 4 == ( string_len buf ) 0 {
            = done 2
        } {
            ? == c 4 {
                : i nx ( _term_next_pos buf pos )
                ( __term_delete_range buf pos nx )
            } {
                ? | == c 127 == c 8 {
                    ? > pos 0 {
                        : i pv ( _term_prev_pos buf pos )
                        ( __term_delete_range buf pv pos )
                        = pos pv
                    } {}
                } {
                    ? == c 1 {
                        = pos 0
                    } {
                        ? == c 5 {
                            = pos ( string_len buf )
                        } {
                            ? == c 11 {
                                ( __term_truncate buf pos )
                            } {
                                ? == c 27 {
                                    = esc 1
                                } {
                                    ? & >= c 32 < c 127 {
                                        ( __term_insert_at buf pos c )
                                        = pos + pos 1
                                    } {
                                        ? & >= c 194 < c 224 {
                                            = cp & c 31
                                            = need 1
                                            = umin 160
                                        } {
                                            ? & >= c 224 < c 240 {
                                                = cp & c 15
                                                = need 2
                                                = umin 2048
                                            } {
                                                ? & >= c 240 < c 245 {
                                                    = cp & c 7
                                                    = need 3
                                                    = umin 65536
                                                } {}
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    ^ @ _TermEd { pos hidx done esc csi need cp umin }
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
    : ~ _TermEd ed ( _term_ed_new history )
    ( __term_repaint prompt buf . ed pos )
    ~ == . ed done 0 {
        : i c ( __term_getb )
        = ed ( _term_feed ed buf c history )
        ? & == . ed done 0 & == . ed utf8_need 0 == . ed esc 0 {
            ( __term_repaint prompt buf . ed pos )
        } {}
    }
    ( term_raw_disable st )
    ( nurl_print `\n` )
    ? == . ed done 1 { ^ @ ?String { T buf } } {}
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
unsafe & `c` @ ioctl i32 fd i req ... → i32

@ __term_ioctl_word i fd i req inout i w → i32 {
    ^ ( ioctl # i32 fd req # *u ( mem_addr w ) )
}

@ __term_winsz i fd i idx → i {
    : i req ( posix_const `TIOCGWINSZ` )
    ? < req 0 { ^ -1 } {}
    // struct winsize: four little-endian u16s (rows, cols, xpixel,
    // ypixel), written into the caller's word.
    : ~ i ws 0
    : i32 rc ( __term_ioctl_word fd req ws )
    : ~ i out -1
    ? == # i rc 0 {
        = out & >> ws * idx 16 0xffff
    } {}
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
