// nurl-cov/report.nu — the table a person reads, and the lines they act on.
//
// The summary answers "how much of this package do the tests touch"; the
// uncovered listing answers the question that actually changes what
// someone does next: WHICH lines. A percentage alone has never told
// anybody where to write a test, so `--uncovered` prints the line ranges,
// collapsed, in the order they appear in the file.
//
// Colour is used only to rank: red under the floor, yellow near it, green
// above. It is switched off when stdout is not a terminal, and by
// $NO_COLOR, so redirecting the report into a file gives plain text.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/term.nu`
$ `stdlib/ext/env.nu`
$ `model.nu`

: i REP_NAME_W 44

: RepStyle {
    b colour
    i warn_tenths  // below this, a file is flagged
    i floor_tenths  // below this, a file is a failure
}

@ report_style b colour i floor_tenths → RepStyle {
    ^ @ RepStyle { colour ? > floor_tenths 0 floor_tenths 750 floor_tenths }
}

// Colour is a courtesy to a human at a terminal, never something a pipe
// has to strip back out.
@ report_colour_wanted → b {
    ? ! ( term_is_tty 1 ) { ^ F } {}
    ^ ?? ( env_get `NO_COLOR` ) {
        T v → { : b empty == 0 ( string_len v ) ( string_free v ) empty }
        F _ → T
    }
}

@ __rep_tint String out RepStyle st i tenths → v {
    ? ! . st colour { ^ v } {}
    ? < tenths . st floor_tenths { ( string_push_str out `\x1b[31m` ) ^ v } {}
    ? < tenths . st warn_tenths { ( string_push_str out `\x1b[33m` ) ^ v } {}
    ( string_push_str out `\x1b[32m` )
}

@ __rep_untint String out RepStyle st → v {
    ? . st colour { ( string_push_str out `\x1b[0m` ) } {}
}

@ __rep_pad_right String out s text i width → v {
    : i n ( nurl_str_len text )
    ( string_push_str out text )
    : ~ i k n
    ~ < k width { ( string_push_char out 32 ) = k + k 1 }
}

@ __rep_pad_left String out s text i width → v {
    : i n ( nurl_str_len text )
    : ~ i k n
    ~ < k width { ( string_push_char out 32 ) = k + k 1 }
    ( string_push_str out text )
}

@ __rep_ratio String out i hit i found i width → v {
    : String tmp ( string_with_cap 32 )
    ( string_push_int tmp hit )
    ( string_push_char tmp 47 )
    ( string_push_int tmp found )
    ( __rep_pad_left out ( string_data tmp ) width )
    ( string_free tmp )
}

// Tenths of a percent, printed as "87.5%". Keeping the arithmetic in
// integers means the report never disagrees with itself about a boundary.
@ __rep_pct String out i tenths i width → v {
    : String tmp ( string_with_cap 16 )
    ( string_push_int tmp / tenths 10 )
    ( string_push_char tmp 46 )
    ( string_push_int tmp % tenths 10 )
    ( string_push_char tmp 37 )
    ( __rep_pad_left out ( string_data tmp ) width )
    ( string_free tmp )
}

// Coverage graphs name their sources absolutely, because the compiler
// wrote them that way. A report read next to the code wants the path the
// reader would type, so the working directory is taken off the front.
@ report_display s path s root → s {
    : i rn ( nurl_str_len root )
    ? == rn 0 { ^ path } {}
    : i pn ( nurl_str_len path )
    ? <= pn rn { ^ path } {}
    : ~ i k 0
    ~ < k rn {
        ? != ( nurl_str_at path pn k ) ( nurl_str_at root rn k ) { ^ path } {}
        = k + k 1
    }
    ? == 47 ( nurl_str_at path pn rn ) { ^ # s + # i path + rn 1 } {}
    ^ path
}

// A long path is cut at the FRONT: the tail is the part that identifies
// the file, and truncating it turns every file in a directory into the
// same row.
@ __rep_name String out s path i width → v {
    : i n ( nurl_str_len path )
    ? <= n width { ( __rep_pad_right out path width ) ^ v } {}
    ( string_push_str out `...` )
    : *u at # *u + # i path - n - width 3
    : String tail ( string_from_bytes at - width 3 )
    ( string_push_str out ( string_data tail ) )
    ( string_free tail )
}

@ report_render * Cov c RepStyle st s root → String {
    : String out ( string_with_cap 16384 )
    ( __rep_pad_right out `File` REP_NAME_W )
    ( __rep_pad_left out `lines` 12 )
    ( __rep_pad_left out `cover` 8 )
    ( __rep_pad_left out `branches` 12 )
    ( __rep_pad_left out `funcs` 10 )
    ( string_push_char out 10 )
    ( __rep_rule out )

    : i n ( cov_file_count c )
    : ~ i i 0
    ~ < i n {
        : CovStat s ( cov_file_stat c i )
        : i tenths ( cov_pct_tenths . s lines_hit . s lines_found )
        ( __rep_name out ( report_display ( cov_file_path c i ) root ) REP_NAME_W )
        ( __rep_ratio out . s lines_hit . s lines_found 12 )
        ( __rep_tint out st tenths )
        ( __rep_pct out tenths 8 )
        ( __rep_untint out st )
        ( __rep_ratio out . s branches_hit . s branches_found 12 )
        ( __rep_ratio out . s funcs_hit . s funcs_found 10 )
        ( string_push_char out 10 )
        = i + i 1
    }

    ( __rep_rule out )
    : CovStat t ( cov_total c )
    : i tt ( cov_pct_tenths . t lines_hit . t lines_found )
    ( __rep_pad_right out `TOTAL` REP_NAME_W )
    ( __rep_ratio out . t lines_hit . t lines_found 12 )
    ( __rep_tint out st tt )
    ( __rep_pct out tt 8 )
    ( __rep_untint out st )
    ( __rep_ratio out . t branches_hit . t branches_found 12 )
    ( __rep_ratio out . t funcs_hit . t funcs_found 10 )
    ( string_push_char out 10 )
    ^ out
}

@ __rep_rule String out → v {
    : ~ i k 0
    ~ < k + REP_NAME_W 42 { ( string_push_char out 45 ) = k + k 1 }
    ( string_push_char out 10 )
}

// The lines nothing ran, collapsed into ranges. This is the part of a
// coverage report that is actionable: it names the work.
@ report_uncovered * Cov c s root → String {
    : String out ( string_with_cap 8192 )
    : i n ( cov_file_count c )
    : ~ i i 0
    ~ < i n {
        : CovStat s ( cov_file_stat c i )
        ? < . s lines_hit . s lines_found {
            ( string_push_str out ( report_display ( cov_file_path c i ) root ) )
            ( string_push_str out `\n  uncovered lines: ` )
            ( __rep_ranges out c i )
            ( string_push_str out `\n` )
            ( __rep_dead_funcs out c i )
        } {}
        = i + i 1
    }
    ? == 0 ( string_len out ) {
        ( string_push_str out `every line with code was executed\n` )
    } {}
    ^ out
}

@ __rep_ranges String out * Cov c i idx → v {
    : i last ( cov_max_line c idx )
    : ~ i start -1
    : ~ i prev -1
    : ~ b first T
    : ~ i l 1
    ~ <= l last {
        : b miss & ( cov_line_exists c idx l ) == 0 ( cov_line_count c idx l )
        ? miss {
            ? < start 0 { = start l } {}
            = prev l
        } {
            ? >= start 0 {
                ( __rep_emit_range out start prev first )
                = first F
                = start -1
            } {}
        }
        = l + l 1
    }
    ? >= start 0 { ( __rep_emit_range out start prev first ) = first F } {}
    ? first { ( string_push_str out `none` ) } {}
}

@ __rep_emit_range String out i from i to b first → v {
    ? ! first { ( string_push_str out `, ` ) } {}
    ( string_push_int out from )
    ? > to from {
        ( string_push_char out 45 )
        ( string_push_int out to )
    } {}
}

// A function nothing called at all is a stronger signal than a run of
// cold lines, and it is worth naming.
@ __rep_dead_funcs String out * Cov c i idx → v {
    : i n ( cov_fn_rows c idx )
    : ~ b any F
    : ~ i k 0
    ~ < k n {
        ? == 0 ( cov_fn_called c idx k ) {
            ? ! any { ( string_push_str out `  never called: ` ) = any T } {
                ( string_push_str out `, ` )
            }
            ( string_push_str out ( cov_fn_name c idx k ) )
        } {}
        = k + k 1
    }
    ? any { ( string_push_char out 10 ) } {}
}
