// nurl-cov/html.nu — one self-contained page you can send to someone.
//
// A coverage report is read by opening it, scrolling to the red, and
// writing a test. That wants the source next to the counts, not a
// percentage in a table — so this emits the summary AND every file's text,
// line by line, with its count in the gutter and uncovered lines marked.
//
// One file, no assets, no JavaScript beyond a details/summary toggle the
// browser implements itself. It opens from a file:// URL, survives being
// mailed around, and can be published as a CI artifact without a server.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `model.nu`
$ `report.nu`

@ __ht_esc String out s text → v {
    : i n ( nurl_str_len text )
    : ~ i k 0
    ~ < k n {
        : i ch ( nurl_str_at text n k )
        ? == ch 38 { ( string_push_str out `&amp;` ) } {
            ? == ch 60 { ( string_push_str out `&lt;` ) } {
                ? == ch 62 { ( string_push_str out `&gt;` ) } {
                    ( string_push_char out ch )
                }
            }
        }
        = k + k 1
    }
}

@ __ht_pct String out i tenths → v {
    ( string_push_int out / tenths 10 )
    ( string_push_char out 46 )
    ( string_push_int out % tenths 10 )
    ( string_push_char out 37 )
}

@ __ht_class i tenths i floor_tenths → s {
    ? < tenths floor_tenths { ^ `bad` } {}
    ? < tenths 900 { ^ `warn` } {}
    ^ `good`
}

@ html_render * Cov c i floor_tenths s title s root → String {
    : String out ( string_with_cap 262144 )
    ( string_push_str out `<!doctype html>\n<html lang="en"><head><meta charset="utf-8">\n` )
    ( string_push_str out `<meta name="viewport" content="width=device-width,initial-scale=1">\n<title>` )
    ( __ht_esc out title )
    ( string_push_str out `</title>\n<style>\n` )
    ( __ht_style out )
    ( string_push_str out `</style></head><body>\n<h1>` )
    ( __ht_esc out title )
    ( string_push_str out `</h1>\n` )

    : CovStat t ( cov_total c )
    ( string_push_str out `<p class="lede">` )
    ( __ht_headline out t floor_tenths )
    ( string_push_str out `</p>\n` )

    ( string_push_str out `<table class="idx"><thead><tr><th>File</th><th>Lines</th>` )
    ( string_push_str out `<th>Coverage</th><th>Branches</th><th>Functions</th></tr></thead><tbody>\n` )
    : i n ( cov_file_count c )
    : ~ i i 0
    ~ < i n {
        : CovStat s ( cov_file_stat c i )
        : i tenths ( cov_pct_tenths . s lines_hit . s lines_found )
        ( string_push_str out `<tr><td><a href="#f` )
        ( string_push_int out i )
        ( string_push_str out `">` )
        ( __ht_esc out ( report_display ( cov_file_path c i ) root ) )
        ( string_push_str out `</a></td><td>` )
        ( __ht_ratio out . s lines_hit . s lines_found )
        ( string_push_str out `</td><td class="` )
        ( string_push_str out ( __ht_class tenths floor_tenths ) )
        ( string_push_str out `"><span class="bar" style="--v:` )
        ( string_push_int out / tenths 10 )
        ( string_push_str out `"></span>` )
        ( __ht_pct out tenths )
        ( string_push_str out `</td><td>` )
        ( __ht_ratio out . s branches_hit . s branches_found )
        ( string_push_str out `</td><td>` )
        ( __ht_ratio out . s funcs_hit . s funcs_found )
        ( string_push_str out `</td></tr>\n` )
        = i + i 1
    }
    ( string_push_str out `</tbody></table>\n` )

    = i 0
    ~ < i n {
        ( __ht_file out c i floor_tenths root )
        = i + i 1
    }
    ( string_push_str out `</body></html>\n` )
    ^ out
}

@ __ht_ratio String out i hit i found → v {
    ( string_push_int out hit )
    ( string_push_str out ` / ` )
    ( string_push_int out found )
}

@ __ht_headline String out CovStat t i floor_tenths → v {
    : i tenths ( cov_pct_tenths . t lines_hit . t lines_found )
    ( string_push_str out `<strong class="` )
    ( string_push_str out ( __ht_class tenths floor_tenths ) )
    ( string_push_str out `">` )
    ( __ht_pct out tenths )
    ( string_push_str out `</strong> of ` )
    ( string_push_int out . t lines_found )
    ( string_push_str out ` executable lines ran. ` )
    ( string_push_int out - . t lines_found . t lines_hit )
    ( string_push_str out ` did not.` )
}

@ __ht_file String out * Cov c i idx i floor_tenths s root → v {
    : CovStat s ( cov_file_stat c idx )
    : i tenths ( cov_pct_tenths . s lines_hit . s lines_found )
    ( string_push_str out `<details id="f` )
    ( string_push_int out idx )
    // A file that is fully covered opens closed: nothing in it needs
    // reading. The ones with gaps are the ones worth landing on.
    ? < . s lines_hit . s lines_found { ( string_push_str out ` open` ) } {}
    ( string_push_str out `><summary><code>` )
    ( __ht_esc out ( report_display ( cov_file_path c idx ) root ) )
    ( string_push_str out `</code> <span class="` )
    ( string_push_str out ( __ht_class tenths floor_tenths ) )
    ( string_push_str out `">` )
    ( __ht_pct out tenths )
    ( string_push_str out `</span></summary>\n<table class="src">\n` )

    : ( Vec String ) lines ( __ht_source ( cov_file_path c idx ) )
    : i nsrc ( vec_len [String] lines )
    : i last ( cov_max_line c idx )
    : i upto ? > nsrc last nsrc last
    : ~ i l 1
    ~ <= l upto {
        : b has ( cov_line_exists c idx l )
        : i count ( cov_line_count c idx l )
        ( string_push_str out `<tr class="` )
        ? ! has { ( string_push_str out `n` ) } {
            ? == count 0 { ( string_push_str out `u` ) } { ( string_push_str out `h` ) }
        }
        ( string_push_str out `"><td class="ln">` )
        ( string_push_int out l )
        ( string_push_str out `</td><td class="ct">` )
        ? has { ( string_push_int out count ) } {}
        ( string_push_str out `</td><td class="co">` )
        ?? ( vec_get [String] lines - l 1 ) {
            T text → ( __ht_esc out ( string_data text ) )
            F _ → {}
        }
        ( string_push_str out `</td></tr>\n` )
        = l + l 1
    }
    ( __ht_free lines )
    ( string_push_str out `</table></details>\n` )
}

@ __ht_source s path → ( Vec String ) {
    ^ ?? ( read_file path ) {
        T text → {
            : ( Vec String ) v ( __ht_split ( string_data text ) )
            ( string_free text )
            v
        }
        F _ → ( vec_new [String] )
    }
}

@ __ht_split s text → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( nurl_str_len text )
    : ~ i start 0
    : ~ i i 0
    ~ < i n {
        ? == 10 ( nurl_str_at text n i ) {
            ( vec_push [String] out ( __ht_slice text start - i start ) )
            = start + i 1
        } {}
        = i + i 1
    }
    ? < start n { ( vec_push [String] out ( __ht_slice text start - n start ) ) } {}
    ^ out
}

@ __ht_slice s text i from i len → String {
    : *u at # *u + # i text from
    ^ ( string_from_bytes at len )
}

@ __ht_free ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [String] v i ) { T s → ( string_free s ) F _ → {} }
        = i + i 1
    }
    ( vec_free [String] v )
}

@ __ht_style String out → v {
    ( string_push_str out `:root{--bg:#fff;--fg:#1a1a1a;--dim:#6b7280;--line:#e5e7eb;` )
    ( string_push_str out `--hit:#e8f5e9;--miss:#fdecea;--good:#15803d;--warn:#b45309;--bad:#b91c1c}\n` )
    ( string_push_str out `@media(prefers-color-scheme:dark){:root{--bg:#0f1115;--fg:#e5e7eb;` )
    ( string_push_str out `--dim:#9ca3af;--line:#252a33;--hit:#0f2a17;--miss:#2b1416;` )
    ( string_push_str out `--good:#4ade80;--warn:#fbbf24;--bad:#f87171}}\n` )
    ( string_push_str out `body{background:var(--bg);color:var(--fg);margin:0;padding:1.5rem;` )
    ( string_push_str out `font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}\n` )
    ( string_push_str out `h1{font-size:1.3rem;margin:0 0 .5rem}\n` )
    ( string_push_str out `.lede{color:var(--dim);margin:0 0 1.5rem}\n` )
    ( string_push_str out `table{border-collapse:collapse;width:100%}\n` )
    ( string_push_str out `.idx{margin-bottom:2rem}\n` )
    ( string_push_str out `.idx th,.idx td{text-align:left;padding:.35rem .6rem;` )
    ( string_push_str out `border-bottom:1px solid var(--line)}\n` )
    ( string_push_str out `.idx th{font-weight:600;color:var(--dim);font-size:.85em}\n` )
    ( string_push_str out `.idx td:nth-child(n+2){text-align:right;white-space:nowrap;` )
    ( string_push_str out `font-variant-numeric:tabular-nums}\n` )
    ( string_push_str out `a{color:inherit}\n` )
    ( string_push_str out `.good{color:var(--good)}.warn{color:var(--warn)}.bad{color:var(--bad)}\n` )
    ( string_push_str out `.bar{display:inline-block;width:4rem;height:.5rem;margin-right:.5rem;` )
    ( string_push_str out `border-radius:2px;background:linear-gradient(to right,currentColor ` )
    ( string_push_str out `calc(var(--v)*1%),var(--line) calc(var(--v)*1%))}\n` )
    ( string_push_str out `details{border:1px solid var(--line);border-radius:6px;margin:0 0 1rem;` )
    ( string_push_str out `overflow:hidden}\n` )
    ( string_push_str out `summary{padding:.5rem .75rem;cursor:pointer;background:var(--line)}\n` )
    ( string_push_str out `summary code{font-size:.95em}\n` )
    ( string_push_str out `.src{font:12px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace}\n` )
    ( string_push_str out `.src td{padding:0 .5rem;white-space:pre-wrap;word-break:break-word}\n` )
    ( string_push_str out `.ln,.ct{text-align:right;color:var(--dim);width:1%;` )
    ( string_push_str out `white-space:nowrap;user-select:none;font-variant-numeric:tabular-nums}\n` )
    ( string_push_str out `tr.h{background:var(--hit)}tr.u{background:var(--miss)}\n` )
    ( string_push_str out `tr.u .ct{color:var(--bad);font-weight:600}\n` )
}
