// md2html — a small Markdown → HTML renderer for NURL.
//
// Ported from the renderer that powers the NURL playground's doc viewer
// (nurlapi's `/readme`, `/stdlib-docs`, …), extracted here as a reusable,
// dependency-light registry library. Pure text → text: `md_to_html` takes
// Markdown source and returns an owned HTML String.
//
// Supported:
//   * ATX headings (# .. ######)
//   * Fenced code blocks (```lang … ```) with a language class
//   * GitHub-style tables (`| a | b |` + a `|---|---|` delimiter row)
//   * Blockquotes (>)
//   * Unordered + ordered lists (- / *  /  1. 2. …)
//   * Horizontal rules (---, ***, ___)
//   * Inline: `code`, **bold**, *em*, [text](url), ![alt](src), <autolink>
//   * Raw text is HTML-escaped; entity refs are left alone.
//
// Not supported (by design — they don't appear in typical READMEs):
//   nested lists by indent, definition lists, footnotes, reference-style
//   links, setext headings, raw HTML passthrough.
//
// Surface:
//   ( md_to_html s src )  → String   rendered HTML (caller owns it)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ __html_escape_char String out i c → v {
    ? == c 38 { ( string_push_str out `&amp;` ) } {
        ? == c 60 { ( string_push_str out `&lt;` ) } {
            ? == c 62 { ( string_push_str out `&gt;` ) } {
                ? == c 34 { ( string_push_str out `&quot;` ) } {
                    ( string_push_char out c )
                }
            }
        }
    }
}

@ _html_escape_into s src String out → v {
    : i n ( nurl_str_len src )
    : ~ i k 0
    ~ < k n {
        ( __html_escape_char out ( nurl_str_get src k ) )
        = k + k 1
    }
}

// Helper: get byte from a string buffer at idx (0 if past end).
@ __md_byte s buf i n i idx → i {
    ? | < idx 0 >= idx n { ^ 0 } {}
    ^ ( nurl_str_get buf idx )
}

// Render inline elements from `buf[from..to)` into `out`. Inline grammar
// is recursion-free: walks left→right, handles `` ` `` (code spans),
// `**` (bold), `*` (em), `[txt](url)`, `<url>` autolinks. `to` is the
// exclusive upper bound; `buf` is the underlying NUL-terminated buffer.
@ __md_inline s buf i from i to String out → v {
    : ~ i i from
    ~ < i to {
        : i c ( nurl_str_get buf i )
        : i c1 ( __md_byte buf to + i 1 )

        // Backslash-escape: consume next char verbatim.
        ? == c 92 {
            ? > c1 0 {
                ( __html_escape_char out c1 )
                = i + i 2
            } {
                ( string_push_char out c )
                = i + i 1
            }
        } {

            // Code span: `…`
            ? == c 96 {
                : ~ i end - 0 1
                : ~ i j + i 1
                ~ < j to {
                    ? == ( nurl_str_get buf j ) 96 { = end j = j to } { = j + j 1 }
                }
                ? >= end 0 {
                    ( string_push_str out `<code>` )
                    : ~ i k + i 1
                    ~ < k end {
                        ( __html_escape_char out ( nurl_str_get buf k ) )
                        = k + k 1
                    }
                    ( string_push_str out `</code>` )
                    = i + end 1
                } {
                    ( __html_escape_char out c )
                    = i + i 1
                }
            } {

                // Bold: **…**
                ? & == c 42 == c1 42 {
                    : ~ i end - 0 1
                    : ~ i j + i 2
                    ~ < j - to 1 {
                        ? & == ( nurl_str_get buf j ) 42 == ( nurl_str_get buf + j 1 ) 42 {
                            = end j = j to
                        } { = j + j 1 }
                    }
                    ? >= end 0 {
                        ( string_push_str out `<strong>` )
                        ( __md_inline buf + i 2 end out )
                        ( string_push_str out `</strong>` )
                        = i + end 2
                    } {
                        ( __html_escape_char out c )
                        = i + i 1
                    }
                } {

                    // Em: *…* (single, no nesting)
                    ? == c 42 {
                        : ~ i end - 0 1
                        : ~ i j + i 1
                        ~ < j to {
                            ? == ( nurl_str_get buf j ) 42 { = end j = j to } { = j + j 1 }
                        }
                        ? >= end 0 {
                            ( string_push_str out `<em>` )
                            : ~ i k + i 1
                            ~ < k end {
                                ( __html_escape_char out ( nurl_str_get buf k ) )
                                = k + k 1
                            }
                            ( string_push_str out `</em>` )
                            = i + end 1
                        } {
                            ( __html_escape_char out c )
                            = i + i 1
                        }
                    } {

                        // Image: ![alt](url)
                        ? & == c 33 == c1 91 {
                            : ~ i mid - 0 1
                            : ~ i close - 0 1
                            : ~ i j + i 2
                            ~ < j to {
                                ? == ( nurl_str_get buf j ) 93 {
                                    ? == ( __md_byte buf to + j 1 ) 40 { = mid j = close mid = j to } { = j to }
                                } { = j + j 1 }
                            }
                            ? >= mid 0 {
                                : ~ i k + mid 2
                                ~ < k to {
                                    ? == ( nurl_str_get buf k ) 41 { = close k = k to } { = k + k 1 }
                                }
                            } {}
                            ? & >= mid 0 > close mid {
                                ( string_push_str out `<img alt="` )
                                : ~ i a + i 2
                                ~ < a mid {
                                    ( __html_escape_char out ( nurl_str_get buf a ) )
                                    = a + a 1
                                }
                                ( string_push_str out `" src="` )
                                : ~ i b + mid 2
                                ~ < b close {
                                    ( __html_escape_char out ( nurl_str_get buf b ) )
                                    = b + b 1
                                }
                                ( string_push_str out `">` )
                                = i + close 1
                            } {
                                ( __html_escape_char out c )
                                = i + i 1
                            }
                        } {

                            // Link: [text](url)
                            ? == c 91 {
                                : ~ i mid - 0 1
                                : ~ i close - 0 1
                                : ~ i j + i 1
                                ~ < j to {
                                    ? == ( nurl_str_get buf j ) 93 {
                                        ? == ( __md_byte buf to + j 1 ) 40 { = mid j = close mid = j to } { = j to }
                                    } { = j + j 1 }
                                }
                                ? >= mid 0 {
                                    : ~ i k + mid 2
                                    ~ < k to {
                                        ? == ( nurl_str_get buf k ) 41 { = close k = k to } { = k + k 1 }
                                    }
                                } {}
                                ? & >= mid 0 > close mid {
                                    ( string_push_str out `<a href="` )
                                    : ~ i b + mid 2
                                    ~ < b close {
                                        ( __html_escape_char out ( nurl_str_get buf b ) )
                                        = b + b 1
                                    }
                                    ( string_push_str out `">` )
                                    ( __md_inline buf + i 1 mid out )
                                    ( string_push_str out `</a>` )
                                    = i + close 1
                                } {
                                    ( __html_escape_char out c )
                                    = i + i 1
                                }
                            } {

                                // Autolink: <http://…> / <https://…>
                                ? == c 60 {
                                    : i p2 ( __md_byte buf to + i 1 )
                                    : i p3 ( __md_byte buf to + i 2 )
                                    : i p4 ( __md_byte buf to + i 3 )
                                    : i p5 ( __md_byte buf to + i 4 )
                                    : i p6 ( __md_byte buf to + i 5 )
                                    : b is_url & & == p2 104 & == p3 116 & == p4 116 == p5 112 | == p6 58 == p6 115
                                    ? is_url {
                                        : ~ i end - 0 1
                                        : ~ i j + i 1
                                        ~ < j to {
                                            ? == ( nurl_str_get buf j ) 62 { = end j = j to } { = j + j 1 }
                                        }
                                        ? >= end 0 {
                                            ( string_push_str out `<a href="` )
                                            : ~ i k + i 1
                                            ~ < k end {
                                                ( __html_escape_char out ( nurl_str_get buf k ) )
                                                = k + k 1
                                            }
                                            ( string_push_str out `">` )
                                            : ~ i k2 + i 1
                                            ~ < k2 end {
                                                ( __html_escape_char out ( nurl_str_get buf k2 ) )
                                                = k2 + k2 1
                                            }
                                            ( string_push_str out `</a>` )
                                            = i + end 1
                                        } {
                                            ( __html_escape_char out c )
                                            = i + i 1
                                        }
                                    } {
                                        ( __html_escape_char out c )
                                        = i + i 1
                                    }
                                } {

                                    ( __html_escape_char out c )
                                    = i + i 1
                                } } } } } } }
    }
}

// Open / close block-level wrappers, closing whatever single open
// block was previously active. `state` is a 1-element mutable Vec[i]
// holding the active block kind (0=none, 1=p, 2=ul, 3=ol, 4=blockquote).
@ __md_close_block ( Vec i ) state String out → v {
    : i kind ?? ( vec_get [i] state 0 ) { T kv → kv F _ → 0 }
    ? == kind 1 { ( string_push_str out `</p>\n` ) } {}
    ? == kind 2 { ( string_push_str out `</ul>\n` ) } {}
    ? == kind 3 { ( string_push_str out `</ol>\n` ) } {}
    ? == kind 4 { ( string_push_str out `</blockquote>\n` ) } {}
    ( vec_set [i] state 0 0 )
}

@ __md_open_block ( Vec i ) state i kind String out s tag → v {
    : i cur ?? ( vec_get [i] state 0 ) { T cv → cv F _ → 0 }
    ? != cur kind {
        ( __md_close_block state out )
        ( string_push_char out 60 )  // '<'
        ( string_push_str out tag )
        ( string_push_str out `>\n` )
        ( vec_set [i] state 0 kind )
    } {}
}

// Render fenced code-block lines. `info` is the optional language tag.
@ __md_open_code String out s info → v {
    : i ilen ( nurl_str_len info )
    ? > ilen 0 {
        ( string_push_str out `<pre><code class="language-` )
        ( _html_escape_into info out )
        ( string_push_str out `">` )
    } {
        ( string_push_str out `<pre><code>` )
    }
}

// Convert `src` (markdown) to HTML. Returns an owned String.
// ── GFM table support ────────────────────────────────────────────────

// Index of the next '\n' at/after `pos`, or -1 if none.
@ __md_nl_at s src i pos i n → i {
    : ~ i scan pos
    ~ < scan n { ? == ( nurl_str_get src scan ) 10 { ^ scan } { = scan + scan 1 } }
    ^ - 0 1
}

// Start of the line after the one beginning at `pos`.
@ __md_next_pos s src i pos i n → i {
    : i nl ( __md_nl_at src pos n )
    ^ ? >= nl 0 + nl 1 n
}

// The line beginning at `pos` as an owned String, sans trailing \r / \n.
@ __md_read_line s src i pos i n → String {
    : i nl ( __md_nl_at src pos n )
    : i hard_end ? >= nl 0 nl n
    : i line_end ? & > hard_end pos == ( nurl_str_get src - hard_end 1 ) 13 - hard_end 1 hard_end
    : String line ( string_with_cap + - line_end pos 1 )
    : ~ i k pos ~ < k line_end { ( string_push_char line ( nurl_str_get src k ) ) = k + k 1 }
    ( _string_seal line )
    ^ line
}

@ __md_has_pipe s line i n → b {
    : ~ i i 0
    ~ < i n { ? == ( nurl_str_get line i ) 124 { ^ T } {} = i + i 1 }
    ^ F
}

// A GFM delimiter row: only `| - : space tab`, with at least one `-`.
@ __md_is_table_delim s line i n → b {
    ? == n 0 { ^ F } {}
    : ~ b seen_dash F
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get line i )
        ? | | | | == c 124 == c 45 == c 58 == c 32 == c 9 {
            ? == c 45 { = seen_dash T } {}
        } { ^ F }
        = i + i 1
    }
    ^ seen_dash
}

// Emit one `<tr>` of cells. `celltag` is "th" or "td". Splits on `|`,
// dropping the empty segments a leading/trailing `|` produces, and trims
// each cell before inline-formatting it.
@ __md_table_row s line i n String out s celltag → v {
    // Content range [s0, e0): skip outer whitespace + one outer pipe each end.
    : ~ i s0 0
    ~ & < s0 n | == ( nurl_str_get line s0 ) 32 == ( nurl_str_get line s0 ) 9 { = s0 + s0 1 }
    ? & < s0 n == ( nurl_str_get line s0 ) 124 { = s0 + s0 1 } {}
    : ~ i e0 n
    ~ & > e0 s0 | == ( nurl_str_get line - e0 1 ) 32 == ( nurl_str_get line - e0 1 ) 9 { = e0 - e0 1 }
    ? & > e0 s0 == ( nurl_str_get line - e0 1 ) 124 { = e0 - e0 1 } {}
    // Walk cells between pipes in [s0, e0].
    : ~ i cell_start s0
    : ~ i i s0
    ~ <= i e0 {
        ? | == i e0 & < i e0 == ( nurl_str_get line i ) 124 {
            // Trim [cell_start, i).
            : ~ i cs cell_start
            ~ & < cs i | == ( nurl_str_get line cs ) 32 == ( nurl_str_get line cs ) 9 { = cs + cs 1 }
            : ~ i ce i
            ~ & > ce cs | == ( nurl_str_get line - ce 1 ) 32 == ( nurl_str_get line - ce 1 ) 9 { = ce - ce 1 }
            ( string_push_char out 60 ) ( string_push_str out celltag ) ( string_push_char out 62 )
            ( __md_inline line cs ce out )
            ( string_push_str out `</` ) ( string_push_str out celltag ) ( string_push_char out 62 )
            = cell_start + i 1
        } {}
        = i + i 1
    }
}

@ md_to_html s src → String {
    : i n ( nurl_str_len src )
    : String out ( string_with_cap n )
    : ( Vec i ) state ( vec_new [i] ) ( vec_push [i] state 0 )

    : ~ b in_code F

    : ~ i pos 0
    ~ < pos n {
        // Find next newline.
        : ~ i nl_at - 0 1
        : ~ i scan pos
        ~ < scan n {
            ? == ( nurl_str_get src scan ) 10 { = nl_at scan = scan n } { = scan + scan 1 }
        }
        : i hard_end ? >= nl_at 0 nl_at n
        : ~ i next_pos ? >= nl_at 0 + nl_at 1 n
        : i line_end ? & > hard_end pos == ( nurl_str_get src - hard_end 1 ) 13 - hard_end 1 hard_end
        : i line_len - line_end pos

        : String line ( string_with_cap + line_len 1 )
        : ~ i k pos
        ~ < k line_end {
            ( string_push_char line ( nurl_str_get src k ) )
            = k + k 1
        }
        ( _string_seal line )

        : s lp ( string_data line )

        : b is_fence & & & >= line_len 3
        == ( nurl_str_get lp 0 ) 96
        == ( __md_byte lp line_len 1 ) 96
        == ( __md_byte lp line_len 2 ) 96
        ? in_code {
            ? is_fence {
                ( string_push_str out `</code></pre>\n` )
                = in_code F
            } {
                ( _html_escape_into lp out )
                ( string_push_char out 10 )
            }
        } {
            ? == line_len 0 {
                ( __md_close_block state out )
            } {
                ? is_fence {
                    ( __md_close_block state out )
                    : String info ( string_substr line 3 - line_len 3 )
                    ( __md_open_code out ( string_data info ) )
                    ( string_free info )
                    = in_code T
                } {
                    // Heading?
                    : ~ i hcount 0
                    : ~ i hi 0
                    ~ < hi line_len {
                        ? & == ( nurl_str_get lp hi ) 35 < hi 6 { = hcount + hcount 1 = hi + hi 1 } { = hi line_len }
                    }
                    ? & > hcount 0 == ( __md_byte lp line_len hcount ) 32 {
                        ( __md_close_block state out )
                        ( string_push_str out `<h` )
                        : String hn ( string_with_cap 2 ) ( string_push_char hn + 48 hcount ) ( _string_seal hn )
                        ( string_push_str out ( string_data hn ) )
                        ( string_push_char out 62 )
                        : i htxt_start + hcount 1
                        ( __md_inline lp htxt_start line_len out )
                        ( string_push_str out `</h` )
                        ( string_push_str out ( string_data hn ) )
                        ( string_push_str out `>\n` )
                        ( string_free hn )
                    } {
                        // Horizontal rule?
                        ? ( __md_is_hr lp line_len ) {
                            ( __md_close_block state out )
                            ( string_push_str out `<hr />\n` )
                        } {
                            // Blockquote?
                            ? & == ( nurl_str_get lp 0 ) 62 == ( __md_byte lp line_len 1 ) 32 {
                                ( __md_open_block state 4 out `blockquote` )
                                ( __md_inline lp 2 line_len out )
                                ( string_push_char out 10 )
                            } {
                                // Unordered list item?
                                ? & | == ( nurl_str_get lp 0 ) 45 == ( nurl_str_get lp 0 ) 42 == ( __md_byte lp line_len 1 ) 32 {
                                    ( __md_open_block state 2 out `ul` )
                                    ( string_push_str out `<li>` )
                                    ( __md_inline lp 2 line_len out )
                                    ( string_push_str out `</li>\n` )
                                } {
                                    // Ordered list item?
                                    ? ( __md_starts_ol lp line_len ) {
                                        ( __md_open_block state 3 out `ol` )
                                        : i dot_idx ( __md_find_dot lp line_len )
                                        : i text_idx + dot_idx 2
                                        ( string_push_str out `<li>` )
                                        ( __md_inline lp text_idx line_len out )
                                        ( string_push_str out `</li>\n` )
                                    } {
                                        // GFM table? Current line has a `|` and
                                        // the next line is a delimiter row.
                                        : ~ b is_table F
                                        ? ( __md_has_pipe lp line_len ) {
                                            : String dline ( __md_read_line src next_pos n )
                                            = is_table ( __md_is_table_delim ( string_data dline ) ( string_len dline ) )
                                            ( string_free dline )
                                        } {}
                                        ? is_table {
                                            ( __md_close_block state out )
                                            ( string_push_str out `<table>\n<thead>\n<tr>` )
                                            ( __md_table_row lp line_len out `th` )
                                            ( string_push_str out `</tr>\n</thead>\n<tbody>\n` )
                                            // Skip past the delimiter row, then
                                            // consume contiguous `|`-bearing rows.
                                            : ~ i tp ( __md_next_pos src next_pos n )
                                            : ~ b done F
                                            ~ & ! done < tp n {
                                                : String row ( __md_read_line src tp n )
                                                : i rl ( string_len row )
                                                ? & > rl 0 ( __md_has_pipe ( string_data row ) rl ) {
                                                    ( string_push_str out `<tr>` )
                                                    ( __md_table_row ( string_data row ) rl out `td` )
                                                    ( string_push_str out `</tr>\n` )
                                                    = tp ( __md_next_pos src tp n )
                                                } { = done T }
                                                ( string_free row )
                                            }
                                            ( string_push_str out `</tbody>\n</table>\n` )
                                            = next_pos tp
                                        } {
                                            // Paragraph
                                            ( __md_open_block state 1 out `p` )
                                            ( __md_inline lp 0 line_len out )
                                            ( string_push_char out 32 )
                                        }
                                    } } } } }
                } }
        }

        ( string_free line )
        = pos next_pos
    }
    ( __md_close_block state out )
    ? in_code { ( string_push_str out `</code></pre>\n` ) } {}
    ( vec_free [i] state )
    ^ out
}

// Horizontal rule detector: line is 3+ of one char from {-, *, _},
// optionally with intervening spaces, and nothing else.
@ __md_is_hr s line i n → b {
    ? < n 3 { ^ F } {}
    : i first ( nurl_str_get line 0 )
    ? & != first 45 & != first 42 != first 95 { ^ F } {}
    : ~ i k 0
    : ~ i count 0
    ~ < k n {
        : i c ( nurl_str_get line k )
        ? == c first { = count + count 1 } {
            ? | == c 32 == c 9 {} { ^ F } }
        = k + k 1
    }
    ^ >= count 3
}

// Detect ordered-list item prefix: digits followed by '.' and ' '.
@ __md_starts_ol s line i n → b {
    : ~ i k 0
    : ~ i digits 0
    ~ < k n {
        : i c ( nurl_str_get line k )
        ? & >= c 48 <= c 57 { = digits + digits 1 = k + k 1 } { = k n }
    }
    ? <= digits 0 { ^ F } {}
    ? & < digits n == ( nurl_str_get line digits ) 46 {
        ? & < + digits 1 n == ( nurl_str_get line + digits 1 ) 32 { ^ T } { ^ F }
    } { ^ F }
}

@ __md_find_dot s line i n → i {
    : ~ i k 0
    ~ < k n { : i c ( nurl_str_get line k ) ? == c 46 { ^ k } {} = k + k 1 }
    ^ - 0 1
}
