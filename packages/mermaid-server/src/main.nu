// mermaid-server — render mermaid flowcharts to SVG over HTTP and MCP.
//
//   mermaid-server                        serve HTTP + MCP on 127.0.0.1:8808
//   mermaid-server --stdio                serve MCP over stdio instead
//   mermaid-server render diagram.mmd     one-shot: SVG on stdout
//   mermaid-server templates              list the loaded templates
//
// Templates are read from an external directory — never compiled in — so
// the set of looks a server offers is a deployment decision. See
// `--templates` and the resolution order in `__mmdm_template_dir`.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/sysinfo.nu`
$ `stdlib/ext/env.nu`
$ `service.nu`

: s MMD_VERSION `0.1.0`

// ── Template directory resolution ────────────────────────────────────
//
// In order: `--templates`, `$MERMAID_TEMPLATES`, `./.templates`, and the
// toolchain's share directory (where `nurlpkg install` puts the templates
// shipped with the package). The first one that exists wins; when none
// does the error names every path that was tried, because "no templates"
// is otherwise a very quiet failure.

@ __mmdm_share_dir → String {
    : String home ( env_var_or `NURL_HOME` `` )
    : ~ String base ( string_new )
    ? > ( string_len home ) 0 { = base home } {
        ( string_free base )
        ( string_free home )
        : String h ( env_var_or `HOME` `.` )
        = base ( path_join ( string_data h ) `.nurl` )
        ( string_free h )
    }
    : String share ( path_join ( string_data base ) `share/mermaid-server/.templates` )
    ( string_free base )
    ^ share
}

// `--templates` and `$MERMAID_TEMPLATES` are EXPLICIT: when either names
// a directory that does not work out, the server says so rather than
// quietly serving some other directory's templates. Only the implicit
// chain falls through.
@ __mmdm_candidates String flag → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ? > ( string_len flag ) 0 {
        ( vec_push [String] out ( string_clone flag ) )
        ^ out
    } {}
    : String env ( env_var_or `MERMAID_TEMPLATES` `` )
    ? > ( string_len env ) 0 {
        ( vec_push [String] out env )
        ^ out
    } {}
    ( string_free env )
    ( vec_push [String] out ( string_from `.templates` ) )
    ( vec_push [String] out ( __mmdm_share_dir ) )
    ^ out
}

@ __mmdm_free_strings ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [String] v i ) {
            T s → ( string_free s )
            F _ → {}
        }
        = i + i 1
    }
    ( vec_free [String] v )
}

// Load the template set into the process state. Returns T on success and
// prints the reason on stderr otherwise.
@ __mmdm_load String flag → b {
    : ( Vec String ) cands ( __mmdm_candidates flag )
    : i n ( vec_len [String] cands )
    : ~ b ok F
    : ~ i i 0
    : ~ String last ( string_new )
    ~ & ! ok < i n {
        ?? ( vec_get [String] cands i ) {
            T dir → {
                ?? ( fs_stat ( string_data dir ) ) {
                    T st → {
                        ? ( stat_is_dir st ) {
                            : MmdTemplatesRes r ( mmd_templates_load MMD_TSRC_DIR ( string_data dir ) )
                            ? . r ok {
                                ( mmd_state_init . r set )
                                ( string_free . r message )
                                = ok T
                            } {
                                ( mmd_templates_free . r set )
                                ( string_free last )
                                = last . r message
                                = i n  // a directory that exists but is broken is fatal
                            }
                        } {}
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = i + i 1
    }

    ? ! ok {
        ( nurl_eprint `mermaid-server: ` )
        ? > ( string_len last ) 0 {
            ( nurl_eprintln ( string_data last ) )
        } {
            ( nurl_eprintln `no template directory found. Tried:` )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] cands k ) {
                    T dir → {
                        ( nurl_eprint `  ` )
                        ( nurl_eprintln ( string_data dir ) )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( nurl_eprintln `Point --templates at a directory of *.toml templates, or set $MERMAID_TEMPLATES.` )
        }
    } {}
    ( string_free last )
    ( __mmdm_free_strings cands )
    ^ ok
}

// ── stdio MCP transport ──────────────────────────────────────────────

@ __mmdm_serve_stdio → i {
    ( mcp_log `mermaid-server MCP (stdio) ready` )
    : ~ b going T
    ~ going {
        ?? ( mcp_read_request ) {
            T req → {
                ?? ( mmd_mcp_dispatch req ) {
                    T reply → ( mcp_send_message reply )
                    F placeholder → ( json_free placeholder )
                }
                ( json_free req )
            }
            F _ → = going F
        }
    }
    ^ 0
}

// ── One-shot rendering ───────────────────────────────────────────────

@ __mmdm_read_input ( Vec String ) rest → String {
    ? > ( vec_len [String] rest ) 1 {
        ?? ( vec_get [String] rest 1 ) {
            T path → {
                ?? ( read_file ( string_data path ) ) {
                    T src → ^ src
                    F e → {
                        ( nurl_eprint `mermaid-server: cannot read ` )
                        ( nurl_eprint ( string_data path ) )
                        ( nurl_eprint ` — ` )
                        ( nurl_eprintln ( io_err_msg e ) )
                        ( nurl_exit 1 )
                    }
                }
            }
            F _ → {}
        }
    } {}
    ^ ( read_all_stdin )
}

@ __mmdm_render_cli ( Vec String ) rest String tmpl String outfile → i {
    : String src ( __mmdm_read_input rest )
    : MmdRenderRes res ( mmd_render_source ( string_data src ) ( string_data tmpl ) )
    ( string_free src )
    : ~ i rc 0
    ? . res ok {
        : i nw ( vec_len [String] . res warnings )
        : ~ i wi 0
        ~ < wi nw {
            ?? ( vec_get [String] . res warnings wi ) {
                T s → {
                    ( nurl_eprint `mermaid-server: ` )
                    ( nurl_eprintln ( string_data s ) )
                }
                F _ → {}
            }
            = wi + wi 1
        }
        ? > ( string_len outfile ) 0 {
            ?? ( write_file ( string_data outfile ) ( string_data . res svg ) ) {
                T _ → {}
                F e → {
                    ( nurl_eprint `mermaid-server: cannot write ` )
                    ( nurl_eprint ( string_data outfile ) )
                    ( nurl_eprint ` — ` )
                    ( nurl_eprintln ( io_err_msg e ) )
                    = rc 1
                }
            }
        } { ( nurl_print ( string_data . res svg ) ) }
    } {
        ( nurl_eprint `mermaid-server: ` )
        ? > . res line 0 {
            ( nurl_eprint `line ` )
            : String pos ( string_with_cap 24 )
            ( string_push_int pos . res line )
            ( string_push_str pos `, column ` )
            ( string_push_int pos . res col )
            ( string_push_str pos `: ` )
            ( nurl_eprint ( string_data pos ) )
            ( string_free pos )
        } {}
        ( nurl_eprintln ( string_data . res svg ) )
        = rc 1
    }
    ( mmd_render_res_free res )
    ^ rc
}

@ __mmdm_list_templates → i {
    : MmdTemplateSet ts ( mmd_state )
    : i n ( mmd_templates_count ts )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [MmdTemplate] . ts items i ) {
            T tp → {
                : MmdTheme th . tp theme
                : String line ( string_with_cap 96 )
                ( string_push_str line ( string_data . tp name ) )
                ? != 0 ( nurl_str_eq ( string_data . tp name ) ( string_data . ts default_name ) ) {
                    ( string_push_str line ` (default)` )
                } {}
                ? > ( string_len . th desc ) 0 {
                    ( string_push_str line `  — ` )
                    ( string_push_str line ( string_data . th desc ) )
                } {}
                ( string_push_str line `\n    ` )
                ( string_push_str line ( string_data . tp path ) )
                ( nurl_println ( string_data line ) )
                ( string_free line )
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ 0
}

// ── main ─────────────────────────────────────────────────────────────

@ main → i {
    : ArgParser p ( args_new `mermaid-server` `render mermaid flowcharts to SVG over HTTP and MCP` )
    ( args_flag p `help` 104 `show this help` )  // -h
    ( args_flag p `version` 86 `print the version and exit` )  // -V
    ( args_flag p `stdio` 0 `speak MCP over stdin/stdout instead of serving HTTP` )
    ( args_flag p `quiet` 113 `do not print the startup banner` )  // -q
    ( args_opt p `host` 0 `HOST` `bind address (default 127.0.0.1)` )
    ( args_opt p `port` 112 `PORT` `bind port (default 8808)` )  // -p
    ( args_opt p `workers` 119 `N` `worker threads (default: one per CPU)` )  // -w
    ( args_opt p `templates` 0 `DIR` `template directory (default: $MERMAID_TEMPLATES, ./.templates, then the toolchain share dir)` )
    ( args_opt p `template` 116 `NAME` `template to render with (default: the set's default)` )  // -t
    ( args_opt p `out` 111 `FILE` `write the SVG here instead of stdout (render)` )  // -o

    : ~ i rc 0
    ? ( args_parse_argv p ) {
        ? ( args_present p `help` ) {
            : String h ( args_usage p )
            ( nurl_print `mermaid-server — mermaid flowcharts to SVG, over HTTP and MCP\n\n` )
            ( nurl_print ( string_data h ) )
            ( nurl_print `\nCommands:\n` )
            ( nurl_print `  (none)            serve HTTP (and MCP at /mcp)\n` )
            ( nurl_print `  render [FILE]     render one diagram to stdout (stdin when FILE is omitted)\n` )
            ( nurl_print `  templates         list the loaded templates\n` )
            ( string_free h )
        } {
            ? ( args_present p `version` ) {
                ( nurl_print `mermaid-server ` )
                ( nurl_println MMD_VERSION )
            } {
                : String tdir ( args_value_or p `templates` `` )
                ? ! ( __mmdm_load tdir ) {
                    ( string_free tdir )
                    ( args_free p )
                    ^ 1
                } {}
                ( string_free tdir )

                : ( Vec String ) rest ( args_positionals p )
                : ~ String cmd ( string_new )
                ? > ( vec_len [String] rest ) 0 {
                    ?? ( vec_get [String] rest 0 ) {
                        T c → {
                            ( string_free cmd )
                            = cmd ( string_clone c )
                        }
                        F _ → {}
                    }
                } {}

                ? ( args_present p `stdio` ) {
                    = rc ( __mmdm_serve_stdio )
                } {
                    ? != 0 ( nurl_str_eq ( string_data cmd ) `render` ) {
                        : String tmpl ( args_value_or p `template` `` )
                        : String outf ( args_value_or p `out` `` )
                        = rc ( __mmdm_render_cli rest tmpl outf )
                        ( string_free tmpl )
                        ( string_free outf )
                    } {
                        ? != 0 ( nurl_str_eq ( string_data cmd ) `templates` ) {
                            = rc ( __mmdm_list_templates )
                        } {
                            ? > ( string_len cmd ) 0 {
                                ( nurl_eprint `mermaid-server: unknown command '` )
                                ( nurl_eprint ( string_data cmd ) )
                                ( nurl_eprintln `' — try --help` )
                                = rc 2
                            } {
                                : String host ( args_value_or p `host` `127.0.0.1` )
                                : String port_s ( args_value_or p `port` `8808` )
                                : i port ( nurl_str_to_int ( string_data port_s ) )
                                ( string_free port_s )
                                : ~ i workers ( sys_cpu_count )
                                ?? ( args_value p `workers` ) {
                                    T wv → {
                                        = workers ( nurl_str_to_int ( string_data wv ) )
                                        ( string_free wv )
                                    }
                                    F _ → {}
                                }
                                ? < workers 1 { = workers 1 } {}
                                : b quiet ( args_present p `quiet` )
                                : *HttpApp a ( mmd_build_app workers quiet )
                                ? ! quiet {
                                    ( nurl_eprint `mermaid-server ` )
                                    ( nurl_eprint MMD_VERSION )
                                    ( nurl_eprint ` — ` )
                                    : String b ( string_with_cap 64 )
                                    ( string_push_int b ( mmd_templates_count ( mmd_state ) ) )
                                    ( string_push_str b ` template(s), ` )
                                    ( string_push_int b workers )
                                    ( string_push_str b ` worker(s); MCP at /mcp` )
                                    ( nurl_eprintln ( string_data b ) )
                                    ( string_free b )
                                } {}
                                = rc ( http_app_listen a ( string_data host ) port )
                                ( http_app_free a )
                                ( string_free host )
                            }
                        }
                    }
                }
                ( string_free cmd )
            }
        }
    } {
        ( nurl_eprint `mermaid-server: ` )
        ( nurl_eprintln ( args_error p ) )
        = rc 2
    }
    ( args_free p )
    ( mmd_state_free )
    ^ rc
}
