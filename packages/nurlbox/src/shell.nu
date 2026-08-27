// nurlbox/shell.nu — the applets a shell script is made of.
//
// test / [ / expr / xargs / timeout / nohup / basename-style plumbing.
//
// `test` and `expr` are where a clone earns its keep: they are called
// once per loop iteration by every script in existence, and their
// grammar is small but exact. Both are implemented as real parsers with
// POSIX precedence, not as flag lists.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/term.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/regex.nu`
$ `bx.nu`

// ── test / [ ──────────────────────────────────────────────────────
//
// Grammar (POSIX):
//   expr  := term ( '-o' term )*
//   term  := factor ( '-a' factor )*
//   factor:= '!' factor | '(' expr ')' | binary | unary | string
//
// A bare string is true when non-empty — which is why `test -n` with no
// operand is true (the string "-n" is non-empty), a quirk POSIX
// mandates and scripts rely on.

: ~ i g_test_pos 0

@ __test_tok ( Vec String ) t i idx → s { ^ ( bx_at t idx ) }

@ __test_left ( Vec String ) t → i { ^ - ( vec_len [String] t ) g_test_pos }

@ __test_is_unary s op → b {
    ? != ( nurl_str_len op ) 2 { ^ F } {}
    ? != ( nurl_str_get op 0 ) 45 { ^ F } {}
    : i c ( nurl_str_get op 1 )
    ^ | | | | | | | | | | | | | | == c 101 == c 102 == c 100 == c 114 == c 119 == c 120 == c 115 == c 76 == c 104 == c 98 == c 99 == c 112 == c 83 == c 116 | == c 122 == c 110
}

@ __test_is_binary s op → b {
    ? | ( bx_streq op `=` ) | ( bx_streq op `!=` ) ( bx_streq op `==` ) { ^ T } {}
    ? | ( bx_streq op `-eq` ) | ( bx_streq op `-ne` ) | ( bx_streq op `-lt` ) | ( bx_streq op `-le` ) | ( bx_streq op `-gt` ) ( bx_streq op `-ge` ) { ^ T } {}
    ? | ( bx_streq op `-nt` ) | ( bx_streq op `-ot` ) ( bx_streq op `-ef` ) { ^ T } {}
    ^ F
}

@ __test_unary s op s arg → b {
    : i c ( nurl_str_get op 1 )
    ? == c 122 { ^ == ( nurl_str_len arg ) 0 } {}
    ? == c 110 { ^ != ( nurl_str_len arg ) 0 } {}
    ? == c 116 { ^ ( term_is_tty ( nurl_str_to_int arg ) ) } {}
    // Everything else asks the filesystem. -h / -L look at the link
    // itself; the rest resolve it, which is what the shell does.
    : !FileStat IoErr r ? | == c 104 == c 76 ( fs_lstat arg ) ( fs_stat arg )
    ?? r {
        F _ → { ^ F }
        T st → {
            ? == c 101 { ^ T } {}
            ? == c 102 { ^ ( stat_is_file st ) } {}
            ? == c 100 { ^ ( stat_is_dir st ) } {}
            ? | == c 104 == c 76 { ^ ( stat_is_symlink st ) } {}
            ? == c 115 { ^ > . st size 0 } {}
            ? == c 98 { ^ == ( stat_kind st ) FS_KIND_BLOCKDEV } {}
            ? == c 99 { ^ == ( stat_kind st ) FS_KIND_CHARDEV } {}
            ? == c 112 { ^ == ( stat_kind st ) FS_KIND_FIFO } {}
            ? == c 83 { ^ == ( stat_kind st ) FS_KIND_SOCKET } {}
            // -r / -w / -x against the caller's own ids. The owner bits
            // apply to the owner, the group bits to a member, otherwise
            // the other bits — the same three-way choice the kernel makes.
            : i m ( stat_mode_bits st )
            : i uid # i ( geteuid )
            : i gid # i ( getegid )
            : ~ i bits & m 7
            ? == . st uid uid { = bits & >> m 6 7 } {
                ? == . st gid gid { = bits & >> m 3 7 } {}
            }
            ? == uid 0 {
                // root reads and writes anything; execute still needs a
                // bit set somewhere.
                ? | == c 114 == c 119 { ^ T } {}
                ? == c 120 { ^ != 0 & m 73 } {}
            } {}
            ? == c 114 { ^ != 0 & bits 4 } {}
            ? == c 119 { ^ != 0 & bits 2 } {}
            ? == c 120 { ^ != 0 & bits 1 } {}
            ^ F
        }
    }
}

@ __test_binary s a s op s b → b {
    ? | ( bx_streq op `=` ) ( bx_streq op `==` ) { ^ ( bx_streq a b ) } {}
    ? ( bx_streq op `!=` ) { ^ ! ( bx_streq a b ) } {}
    ? ( bx_streq op `-eq` ) { ^ == ( nurl_str_to_int a ) ( nurl_str_to_int b ) } {}
    ? ( bx_streq op `-ne` ) { ^ != ( nurl_str_to_int a ) ( nurl_str_to_int b ) } {}
    ? ( bx_streq op `-lt` ) { ^ < ( nurl_str_to_int a ) ( nurl_str_to_int b ) } {}
    ? ( bx_streq op `-le` ) { ^ <= ( nurl_str_to_int a ) ( nurl_str_to_int b ) } {}
    ? ( bx_streq op `-gt` ) { ^ > ( nurl_str_to_int a ) ( nurl_str_to_int b ) } {}
    ? ( bx_streq op `-ge` ) { ^ >= ( nurl_str_to_int a ) ( nurl_str_to_int b ) } {}
    ? | | ( bx_streq op `-nt` ) ( bx_streq op `-ot` ) ( bx_streq op `-ef` ) {
        ?? ( fs_stat a ) {
            F _ → { ^ F }
            T sa → {
                ?? ( fs_stat b ) {
                    F _ → { ^ ( bx_streq op `-nt` ) }
                    T sb → {
                        ? ( bx_streq op `-nt` ) { ^ > . sa mtime . sb mtime } {}
                        ? ( bx_streq op `-ot` ) { ^ < . sa mtime . sb mtime } {}
                        ^ & == . sa dev . sb dev == . sa ino . sb ino
                    }
                }
            }
        }
    } {}
    ^ F
}

@ __test_factor ( Vec String ) t → b {
    ? <= ( __test_left t ) 0 { ^ F } {}
    : s tok ( __test_tok t g_test_pos )
    ? ( bx_streq tok `!` ) {
        = g_test_pos + g_test_pos 1
        ^ ! ( __test_factor t )
    } {}
    ? ( bx_streq tok `(` ) {
        = g_test_pos + g_test_pos 1
        : b r ( __test_expr t )
        ? ( bx_streq ( __test_tok t g_test_pos ) `)` ) { = g_test_pos + g_test_pos 1 } {}
        ^ r
    } {}
    // A binary operator two tokens ahead beats a unary one here: POSIX
    // says `test -f = -f` compares two strings, and only the three-token
    // reading gets that right.
    ? >= ( __test_left t ) 3 {
        : s op ( __test_tok t + g_test_pos 1 )
        ? ( __test_is_binary op ) {
            : s a ( __test_tok t g_test_pos )
            : s b ( __test_tok t + g_test_pos 2 )
            = g_test_pos + g_test_pos 3
            ^ ( __test_binary a op b )
        } {}
    } {}
    ? >= ( __test_left t ) 2 {
        ? ( __test_is_unary tok ) {
            : s arg ( __test_tok t + g_test_pos 1 )
            = g_test_pos + g_test_pos 2
            ^ ( __test_unary tok arg )
        } {}
    } {}
    = g_test_pos + g_test_pos 1
    ^ != ( nurl_str_len tok ) 0
}

@ __test_term ( Vec String ) t → b {
    : ~ b acc ( __test_factor t )
    ~ & > ( __test_left t ) 0 ( bx_streq ( __test_tok t g_test_pos ) `-a` ) {
        = g_test_pos + g_test_pos 1
        : b r ( __test_factor t )
        = acc & acc r
    }
    ^ acc
}

@ __test_expr ( Vec String ) t → b {
    : ~ b acc ( __test_term t )
    ~ & > ( __test_left t ) 0 ( bx_streq ( __test_tok t g_test_pos ) `-o` ) {
        = g_test_pos + g_test_pos 1
        : b r ( __test_term t )
        = acc | acc r
    }
    ^ acc
}

@ ap_test ( Vec String ) argv → i {
    : i n ( vec_len [String] argv )
    : ( Vec String ) t ( vec_new [String] )
    : ~ i last n
    // `[ ... ]` must close; `test ... ` must not.
    ? ( bx_streq ( bx_name ) `[` ) {
        ? | < n 2 ! ( bx_streq ( bx_at argv - n 1 ) `]` ) {
            ( bx_err `missing ]` )
            ( vec_free [String] t )
            ^ 2
        } {}
        = last - n 1
    } {}
    : ~ i i 1
    ~ < i last {
        ( vec_push [String] t ( string_from ( bx_at argv i ) ) )
        = i + i 1
    }
    = g_test_pos 0
    : ~ i rc 1
    ? == ( vec_len [String] t ) 0 { = rc 1 } {
        : b r ( __test_expr t )
        = rc ? r 0 1
    }
    ( vec_free_with [String] t \ String x → v { ( string_free x ) } )
    ^ rc
}

// ── expr ──────────────────────────────────────────────────────────
//
//   expr := or
//   or   := and ( '|' and )*
//   and  := cmp ( '&' cmp )*
//   cmp  := sum ( ('='|'!='|'<'|'<='|'>'|'>=') sum )*
//   sum  := term ( ('+'|'-') term )*
//   term := match ( ('*'|'/'|'%') match )*
//   match:= atom ( ':' atom )*
//   atom := '(' or ')' | 'length' S | 'substr' S P L | 'index' S C | STRING

: ~ i g_expr_pos 0
: ~ b g_expr_err F

@ __expr_tok ( Vec String ) t i idx → s { ^ ( bx_at t idx ) }

@ __expr_left ( Vec String ) t → i { ^ - ( vec_len [String] t ) g_expr_pos }

// expr has no types: every value is a string, and an operator that
// wants a number parses one out. A string that is not a number is 0 for
// arithmetic, which is what every expr does.
@ __expr_num s v → i { ^ ( nurl_str_to_int v ) }

@ __expr_is_num s v → b {
    : i n ( nurl_str_len v )
    ? == n 0 { ^ F } {}
    : ~ i i ? == ( nurl_str_get v 0 ) 45 1 0
    ? >= i n { ^ F } {}
    ~ < i n {
        ? ! ( bx_is_digit ( nurl_str_get v i ) ) { ^ F } {}
        = i + i 1
    }
    ^ T
}

@ __expr_atom ( Vec String ) t → String {
    ? <= ( __expr_left t ) 0 {
        = g_expr_err T
        ^ ( string_new )
    } {}
    : s tok ( __expr_tok t g_expr_pos )
    ? ( bx_streq tok `(` ) {
        = g_expr_pos + g_expr_pos 1
        : String r ( __expr_or t )
        ? & > ( __expr_left t ) 0 ( bx_streq ( __expr_tok t g_expr_pos ) `)` ) { = g_expr_pos + g_expr_pos 1 } { = g_expr_err T }
        ^ r
    } {}
    ? & ( bx_streq tok `length` ) > ( __expr_left t ) 1 {
        = g_expr_pos + g_expr_pos 2
        ^ ( string_from ( nurl_str_int ( nurl_str_len ( __expr_tok t - g_expr_pos 1 ) ) ) )
    } {}
    ? & ( bx_streq tok `substr` ) > ( __expr_left t ) 3 {
        : s src ( __expr_tok t + g_expr_pos 1 )
        : i from ( __expr_num ( __expr_tok t + g_expr_pos 2 ) )
        : i len ( __expr_num ( __expr_tok t + g_expr_pos 3 ) )
        = g_expr_pos + g_expr_pos 4
        : i n ( nurl_str_len src )
        ? | | < from 1 > from n <= len 0 { ^ ( string_new ) } {}
        : i take ? > + - from 1 len n - n - from 1 len
        ^ ( string_from ( nurl_str_slice src - from 1 take ) )
    } {}
    ? & ( bx_streq tok `index` ) > ( __expr_left t ) 2 {
        : s src ( __expr_tok t + g_expr_pos 1 )
        : s set ( __expr_tok t + g_expr_pos 2 )
        = g_expr_pos + g_expr_pos 3
        : i n ( nurl_str_len src )
        : i m ( nurl_str_len set )
        : ~ i i 0
        ~ < i n {
            : ~ i j 0
            ~ < j m {
                ? == ( nurl_str_get src i ) ( nurl_str_get set j ) {
                    ^ ( string_from ( nurl_str_int + i 1 ) )
                } {}
                = j + j 1
            }
            = i + i 1
        }
        ^ ( string_from `0` )
    } {}
    = g_expr_pos + g_expr_pos 1
    ^ ( string_from tok )
}

// `S : REGEX` — an anchored match; the result is the match length (or
// the first captured group, which this engine does not offer, so the
// length is what it always returns).
@ __expr_match ( Vec String ) t → String {
    : ~ String acc ( __expr_atom t )
    ~ & > ( __expr_left t ) 0 ( bx_streq ( __expr_tok t g_expr_pos ) `:` ) {
        = g_expr_pos + g_expr_pos 1
        : String pat ( __expr_atom t )
        : String anchored ( string_from `^` )
        ( string_push_bytes anchored # *u ( string_data pat ) ( string_len pat ) )
        : String bre ( _bre_to_ere ( string_data anchored ) )
        : ~ i len 0
        ?? ( regex_compile ( string_data bre ) ) {
            T r → {
                ?? ( regex_find r ( string_data acc ) ) {
                    T m → { ? == . m start 0 { = len . m len } {} }
                    F _ → {}
                }
                ( regex_free r )
            }
            F _ → { = g_expr_err T }
        }
        ( string_free bre )
        ( string_free anchored )
        ( string_free pat )
        ( string_free acc )
        = acc ( string_from ( nurl_str_int len ) )
    }
    ^ acc
}

@ __expr_arith String a s op String b → String {
    : i x ( __expr_num ( string_data a ) )
    : i y ( __expr_num ( string_data b ) )
    : ~ i r 0
    ? ( bx_streq op `+` ) { = r + x y } {}
    ? ( bx_streq op `-` ) { = r - x y } {}
    ? ( bx_streq op `*` ) { = r * x y } {}
    ? ( bx_streq op `/` ) {
        ? == y 0 { = g_expr_err T } { = r / x y }
    } {}
    ? ( bx_streq op `%` ) {
        ? == y 0 { = g_expr_err T } { = r - x * y / x y }
    } {}
    ^ ( string_from ( nurl_str_int r ) )
}

@ __expr_term ( Vec String ) t → String {
    : ~ String acc ( __expr_match t )
    ~ & > ( __expr_left t ) 0 | ( bx_streq ( __expr_tok t g_expr_pos ) `*` ) | ( bx_streq ( __expr_tok t g_expr_pos ) `/` ) ( bx_streq ( __expr_tok t g_expr_pos ) `%` ) {
        : s op ( __expr_tok t g_expr_pos )
        = g_expr_pos + g_expr_pos 1
        : String b ( __expr_match t )
        : String r ( __expr_arith acc op b )
        ( string_free acc )
        ( string_free b )
        = acc r
    }
    ^ acc
}

@ __expr_sum ( Vec String ) t → String {
    : ~ String acc ( __expr_term t )
    ~ & > ( __expr_left t ) 0 | ( bx_streq ( __expr_tok t g_expr_pos ) `+` ) ( bx_streq ( __expr_tok t g_expr_pos ) `-` ) {
        : s op ( __expr_tok t g_expr_pos )
        = g_expr_pos + g_expr_pos 1
        : String b ( __expr_term t )
        : String r ( __expr_arith acc op b )
        ( string_free acc )
        ( string_free b )
        = acc r
    }
    ^ acc
}

@ __expr_cmp_op s op → b {
    ^ | | ( bx_streq op `=` ) | ( bx_streq op `!=` ) ( bx_streq op `<` ) | ( bx_streq op `<=` ) | ( bx_streq op `>` ) ( bx_streq op `>=` )
}

@ __expr_cmp ( Vec String ) t → String {
    : ~ String acc ( __expr_sum t )
    ~ & > ( __expr_left t ) 0 ( __expr_cmp_op ( __expr_tok t g_expr_pos ) ) {
        : s op ( __expr_tok t g_expr_pos )
        = g_expr_pos + g_expr_pos 1
        : String b ( __expr_sum t )
        // Two numbers compare numerically, anything else compares as
        // text — POSIX's rule, and the reason `expr 10 '>' 9` is 1 while
        // `expr a10 '>' a9` is 0.
        : b numeric & ( __expr_is_num ( string_data acc ) ) ( __expr_is_num ( string_data b ) )
        : ~ i c 0
        ? numeric {
            : i x ( __expr_num ( string_data acc ) )
            : i y ( __expr_num ( string_data b ) )
            = c ? < x y -1 ? > x y 1 0
        } { = c ( nurl_str_cmp ( string_data acc ) ( string_data b ) ) }
        : ~ b r F
        ? ( bx_streq op `=` ) { = r == c 0 } {}
        ? ( bx_streq op `!=` ) { = r != c 0 } {}
        ? ( bx_streq op `<` ) { = r < c 0 } {}
        ? ( bx_streq op `<=` ) { = r <= c 0 } {}
        ? ( bx_streq op `>` ) { = r > c 0 } {}
        ? ( bx_streq op `>=` ) { = r >= c 0 } {}
        ( string_free acc )
        ( string_free b )
        = acc ( string_from ? r `1` `0` )
    }
    ^ acc
}

@ __expr_truthy String v → b {
    ? == ( string_len v ) 0 { ^ F } {}
    ? ( bx_streq ( string_data v ) `0` ) { ^ F } {}
    ^ T
}

@ __expr_and ( Vec String ) t → String {
    : ~ String acc ( __expr_cmp t )
    ~ & > ( __expr_left t ) 0 ( bx_streq ( __expr_tok t g_expr_pos ) `&` ) {
        = g_expr_pos + g_expr_pos 1
        : String b ( __expr_cmp t )
        : b both & ( __expr_truthy acc ) ( __expr_truthy b )
        ? ! both {
            ( string_free acc )
            = acc ( string_from `0` )
        } {}
        ( string_free b )
    }
    ^ acc
}

@ __expr_or ( Vec String ) t → String {
    : ~ String acc ( __expr_and t )
    ~ & > ( __expr_left t ) 0 ( bx_streq ( __expr_tok t g_expr_pos ) `|` ) {
        = g_expr_pos + g_expr_pos 1
        : String b ( __expr_and t )
        ? ! ( __expr_truthy acc ) {
            ( string_free acc )
            = acc ( string_clone b )
        } {}
        ( string_free b )
    }
    ^ acc
}

@ ap_expr ( Vec String ) argv → i {
    : i n ( vec_len [String] argv )
    ? < n 2 {
        ( bx_err `missing operand` )
        ^ 2
    } {}
    : ( Vec String ) t ( vec_new [String] )
    : ~ i i 1
    ~ < i n {
        ( vec_push [String] t ( string_from ( bx_at argv i ) ) )
        = i + i 1
    }
    = g_expr_pos 0
    = g_expr_err F
    : String r ( __expr_or t )
    : ~ i rc 0
    ? g_expr_err {
        ( bx_err `syntax error` )
        = rc 2
    } {
        ( nurl_print ( string_data r ) )
        ( nurl_print `\n` )
        = rc ? ( __expr_truthy r ) 0 1
    }
    ( string_free r )
    ( vec_free_with [String] t \ String x → v { ( string_free x ) } )
    ^ rc
}

// ── xargs ─────────────────────────────────────────────────────────

@ __xargs_run ( Vec String ) cmd b trace → i {
    : i n ( vec_len [String] cmd )
    ? == n 0 { ^ 0 } {}
    ? trace {
        : ~ i k 0
        ~ < k n {
            ? > k 0 { ( nurl_eprint ` ` ) } {}
            ( nurl_eprint ( bx_at cmd k ) )
            = k + k 1
        }
        ( nurl_eprint `\n` )
    } {}
    ( flush )
    : i32 pid ( fork )
    ? == # i pid 0 {
        : s argvbuf ( nurl_zalloc * 8 + n 1 )
        : ~ i k 0
        ~ < k n {
            ( nurl_poke argvbuf k # i ( bx_at cmd k ) )
            = k + k 1
        }
        : i32 _r ( execvp ( bx_at cmd 0 ) # *u argvbuf )
        ( _exit # i32 127 )
        ^ 127
    } {}
    ? < # i pid 0 { ^ 127 } {}
    : s statusbuf ( nurl_zalloc 8 )
    : i32 _w ( waitpid pid # *u statusbuf # i32 0 )
    : i raw ( nurl_peek statusbuf 0 )
    ( nurl_free statusbuf )
    ^ ( nurl_wait_exit_status & raw 65535 )
}

// Split stdin into items: whitespace-separated, or NUL-separated with
// -0. Quoting is honoured for the whitespace form, because `xargs` is
// most often fed `ls` output and a quoted name must survive.
@ __xargs_items b nul ( Vec String ) out → v {
    : ( Vec u ) data ( read_all_stdin_bytes )
    : i n ( vec_len [u] data )
    : *u p ( vec_data [u] data )
    : String cur ( string_new )
    : ~ b any F
    : ~ i quote 0
    : ~ i i 0
    ~ < i n {
        : i c & 255 # i . p i
        ? nul {
            ? == c 0 {
                ( vec_push [String] out ( string_clone cur ) )
                ( string_clear cur )
                = any F
            } {
                ( string_push_char cur c )
                = any T
            }
        } {
            ? != quote 0 {
                ? == c quote { = quote 0 } { ( string_push_char cur c ) = any T }
            } {
                ? | == c 34 == c 39 { = quote c = any T } {
                    ? | | == c 32 == c 9 | == c 10 == c 13 {
                        ? any {
                            ( vec_push [String] out ( string_clone cur ) )
                            ( string_clear cur )
                            = any F
                        } {}
                    } {
                        ( string_push_char cur c )
                        = any T
                    }
                }
            }
        }
        = i + i 1
    }
    ? any { ( vec_push [String] out ( string_clone cur ) ) } {}
    ( string_free cur )
    ( vec_free [u] data )
}

@ ap_xargs ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `0n:I:rtes:` `null=0,max-args=n,replace=I,no-run-if-empty=r,verbose=t` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ( Vec String ) items ( vec_new [String] )
        ( __xargs_items ( bx_has o `0` ) items )
        : i ni ( vec_len [String] items )
        : i nops ( bx_operand_count o )
        // With no command, xargs runs `echo`.
        : ( Vec String ) base ( vec_new [String] )
        ? == nops 0 {
            ( vec_push [String] base ( string_from `echo` ) )
        } {
            : ~ i k 0
            ~ < k nops {
                ( vec_push [String] base ( string_from ( bx_operand o k ) ) )
                = k + k 1
            }
        }
        : b trace ( bx_has o `t` )
        ? & == ni 0 ( bx_has o `r` ) {} {
            ? ( bx_has o `I` ) {
                : s repl ( bx_val o `I` )
                : ~ i k 0
                ~ < k ni {
                    : ( Vec String ) cmd ( vec_new [String] )
                    : i nb ( vec_len [String] base )
                    : ~ i j 0
                    ~ < j nb {
                        : s piece ( bx_at base j )
                        : i at ( nurl_str_find piece repl )
                        ? >= at 0 {
                            : String sub ( string_from ( nurl_str_slice piece 0 at ) )
                            ( string_push_str sub ( bx_at items k ) )
                            ( string_push_str sub ( nurl_str_slice piece + at ( nurl_str_len repl ) - ( nurl_str_len piece ) + at ( nurl_str_len repl ) ) )
                            ( vec_push [String] cmd sub )
                        } { ( vec_push [String] cmd ( string_from piece ) ) }
                        = j + j 1
                    }
                    : i one ( __xargs_run cmd trace )
                    ? != one 0 { = rc one } {}
                    ( vec_free_with [String] cmd \ String x → v { ( string_free x ) } )
                    = k + k 1
                }
            } {
                : i batch ? ( bx_has o `n` ) ( nurl_str_to_int ( bx_val o `n` ) ) 0
                : ~ i k 0
                : ~ b once F
                ~ | < k ni & ! once == ni 0 {
                    = once T
                    : ( Vec String ) cmd ( vec_new [String] )
                    : i nb ( vec_len [String] base )
                    : ~ i j 0
                    ~ < j nb {
                        ( vec_push [String] cmd ( string_from ( bx_at base j ) ) )
                        = j + j 1
                    }
                    : ~ i taken 0
                    ~ & < k ni | <= batch 0 < taken batch {
                        ( vec_push [String] cmd ( string_from ( bx_at items k ) ) )
                        = k + k 1
                        = taken + taken 1
                    }
                    : i one ( __xargs_run cmd trace )
                    ? != one 0 { = rc one } {}
                    ( vec_free_with [String] cmd \ String x → v { ( string_free x ) } )
                }
            }
        }
        ( vec_free_with [String] base \ String x → v { ( string_free x ) } )
        ( vec_free_with [String] items \ String x → v { ( string_free x ) } )
    }
    ( bx_opts_free o )
    ^ rc
}
