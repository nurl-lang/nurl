// md2html — render Markdown to HTML from the command line.
//
// Reads Markdown from stdin (or --file) and writes HTML to stdout. With
// --full it emits a complete, styled HTML document; otherwise it emits an
// HTML fragment (just the rendered body), handy for embedding.
//
//   md2html < README.md                 # fragment to stdout
//   md2html -f README.md --full         # full styled page
//   md2html -f doc.md -t "My Doc" -F    # full page with a custom title
//
// Built on the stdlib `std/args` parser (flags) and this package's own
// `markdown` renderer library.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/args.nu`
$ `src/markdown.nu`

// Wrap a rendered HTML body in a complete, self-contained document with a
// clean, readable stylesheet.
@ __full_page s title String body → String {
    : String out ( string_with_cap + ( string_len body ) 2048 )
    ( string_push_str out `<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8" />\n` )
    ( string_push_str out `<meta name="viewport" content="width=device-width,initial-scale=1" />\n<title>` )
    ( _html_escape_into title out )
    ( string_push_str out `</title>\n<style>\n` )
    ( string_push_str out `  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;line-height:1.6;` )
    ( string_push_str out `color:#1a1a1a;max-width:46rem;margin:2.5rem auto;padding:0 1.25rem}\n` )
    ( string_push_str out `  h1,h2{border-bottom:1px solid #eee;padding-bottom:.25em}\n` )
    ( string_push_str out `  a{color:#0b62d6}\n` )
    ( string_push_str out `  code{background:#f4f4f4;padding:.1em .35em;border-radius:4px;font-size:.92em}\n` )
    ( string_push_str out `  pre{background:#f4f4f4;padding:1rem;border-radius:6px;overflow:auto}\n` )
    ( string_push_str out `  pre code{background:transparent;padding:0}\n` )
    ( string_push_str out `  blockquote{border-left:3px solid #ddd;margin:1em 0;padding:.2rem 1rem;color:#555}\n` )
    ( string_push_str out `  table{border-collapse:collapse;margin:1rem 0}\n` )
    ( string_push_str out `  th,td{border:1px solid #ddd;padding:.4rem .7rem;text-align:left}\n` )
    ( string_push_str out `  th{background:#f4f4f4}\n` )
    ( string_push_str out `  hr{border:0;border-top:1px solid #e5e5e5;margin:2rem 0}\n` )
    ( string_push_str out `  img{max-width:100%}\n` )
    ( string_push_str out `</style>\n</head>\n<body>\n` )
    ( string_push_str out ( string_data body ) )
    ( string_push_str out `</body>\n</html>\n` )
    ^ out
}

@ main → i {
    : ArgParser p ( args_new `md2html` `render Markdown to HTML` )
    ( args_flag p `full` 70 `emit a complete styled HTML document (not just a fragment)` )  // -F
    ( args_flag p `help` 104 `show this help` )  // -h
    ( args_opt p `file` 102 `FILE` `read Markdown from FILE instead of stdin` )  // -f
    ( args_opt p `title` 116 `TITLE` `document <title> when used with --full (default "Document")` )  // -t

    : ( Vec String ) argv ( vec_new [String] )
    : i ac ( env_args_count )
    : ~ i ai 1
    ~ < ai ac {
        ( vec_push [String] argv ( env_arg ai ) )
        = ai + ai 1
    }

    : ~ i rc 0
    ? ( args_parse p argv ) {
        ? ( args_present p `help` ) {
            : String h ( args_usage p )
            ( nurl_print `md2html — render Markdown to HTML\n\nUsage: md2html [OPTIONS]\n\n` )
            ( nurl_print `Reads Markdown from stdin unless --file is given.\n\n` )
            ( nurl_print ( string_data h ) )
            ( string_free h )
        } {
            : b full ( args_present p `full` )

            // Input: --file, else stdin.
            : ~ String input ( string_new )
            : ~ b have_input T
            ?? ( args_value p `file` ) {
                T fv → {
                    ?? ( read_file ( string_data fv ) ) {
                        T txt → { ( string_free input ) = input txt }
                        F _ → {
                            ( nurl_eprint `md2html: cannot read file: ` )
                            ( nurl_eprintln ( string_data fv ) )
                            = rc 1
                            = have_input F
                        }
                    }
                    ( string_free fv )
                }
                F _ → {
                    ( string_free input )
                    = input ( read_all_stdin )
                }
            }

            ? have_input {
                : String body ( md_to_html ( string_data input ) )
                ? full {
                    : ~ String titlestr ( string_from `Document` )
                    ?? ( args_value p `title` ) { T tv → { ( string_free titlestr ) = titlestr tv } F _ → {} }
                    : String page ( __full_page ( string_data titlestr ) body )
                    ( nurl_print ( string_data page ) )
                    ( string_free page )
                    ( string_free titlestr )
                } {
                    ( nurl_print ( string_data body ) )
                }
                ( string_free body )
            } {}
            ( string_free input )
        }
    } {
        ( nurl_eprint `md2html: ` ) ( nurl_eprintln ( args_error p ) )
        ( nurl_eprintln `try 'md2html --help'` )
        = rc 2
    }

    ( args_free p )
    ( vec_free_with [String] argv \ String x → v { ( string_free x ) } )
    ^ rc
}
