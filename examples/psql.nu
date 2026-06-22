// examples/psql.nu — a small but real `psql`-style PostgreSQL client.
//
// Built entirely on stdlib/ext/postgres.nu (direct libpq FFI). Behaves
// like psql for everyday use:
//
//   * Connects from a conninfo argument, $PG_CONNINFO, or libpq's own
//     PG* env-var defaults when neither is given.
//   * Reads SQL from stdin, one statement at a time (terminated by `;`),
//     across multiple lines, and prints result sets as aligned tables —
//     headers, a rule, rows, and an "(N rows)" footer — exactly like
//     psql's default aligned output.
//   * Reports the command tag ("INSERT 0 1", "CREATE TABLE", …) for
//     non-SELECT statements and "ERROR:  …" with the server message on
//     failure.
//   * Backslash meta-commands: \dt \d <table> \l \du \conninfo \? \q
//   * One-shot mode: `psql [conninfo] -c "SQL"` runs a single command.
//   * Prompts are shown only on an interactive terminal, so piping a
//     script through it produces clean, prompt-free output.
//
// Build:  ./nurl.sh examples/psql.nu psql
// Run:    ./psql "host=/tmp port=5433 user=postgres dbname=postgres"
//         echo 'SELECT 1 AS one;' | ./psql "$PG_CONNINFO"
//         ./psql "$PG_CONNINFO" -c '\dt'

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/postgres.nu`

& `c` @ isatty i32 fd → i32

// ── Small Vec[i] accessor with a 0 default ───────────────────────
@ veci ( Vec i ) w i idx → i {
    ?? ( vec_get [i] w idx ) { T x → ^ x F _ → ^ 0 }
}

// Print `str` then pad with spaces out to column width `w`.
@ print_padded s str i w → v {
    ( nurl_print str )
    : ~ i pad - w ( nurl_str_len str )
    ~ > pad 0 { ( nurl_print ` ` ) = pad - pad 1 }
}

// ── Result rendering ─────────────────────────────────────────────

// Display length of a cell: 0 for SQL NULL (rendered blank), else the
// text length.
@ cell_len PgResult r i row i col → i {
    ? ( pg_get_is_null r row col ) { ^ 0 } {}
    : String v ( pg_get_value r row col )
    : i l ( string_len v )
    ( string_free v )
    ^ l
}

@ print_header PgResult r ( Vec i ) w i nf → v {
    : ~ i ci 0
    ~ < ci nf {
        ? > ci 0 { ( nurl_print `|` ) } {}
        : String hn ( pg_field_name r ci )
        ( nurl_print ` ` )
        ( print_padded ( string_data hn ) ( veci w ci ) )
        ( nurl_print ` ` )
        ( string_free hn )
        = ci + ci 1
    }
    ( nurl_print `\n` )
}

@ print_rule ( Vec i ) w i nf → v {
    : ~ i ci 0
    ~ < ci nf {
        ? > ci 0 { ( nurl_print `+` ) } {}
        : ~ i d + ( veci w ci ) 2
        ~ > d 0 { ( nurl_print `-` ) = d - d 1 }
        = ci + ci 1
    }
    ( nurl_print `\n` )
}

@ print_data_row PgResult r ( Vec i ) w i nf i row → v {
    : ~ i ci 0
    ~ < ci nf {
        ? > ci 0 { ( nurl_print `|` ) } {}
        ( nurl_print ` ` )
        ? ( pg_get_is_null r row ci ) {
            ( print_padded `` ( veci w ci ) )
        } {
            : String v ( pg_get_value r row ci )
            ( print_padded ( string_data v ) ( veci w ci ) )
            ( string_free v )
        }
        ( nurl_print ` ` )
        = ci + ci 1
    }
    ( nurl_print `\n` )
}

// Render a PgResult: an aligned table for row-returning statements, or
// the command tag otherwise.
@ render_result PgResult r → v {
    : i nf ( pg_nfields r )
    ? == nf 0 {
        : String cs ( pg_cmd_status r )
        ( nurl_print ( string_data cs ) ) ( nurl_print `\n` )
        ( string_free cs )
        ^ v
    } {}
    : i nt ( pg_ntuples r )
    // Column widths: header length widened by each cell.
    : ( Vec i ) w ( vec_with_cap [i] nf )
    : ~ i ci 0
    ~ < ci nf {
        : String hn ( pg_field_name r ci )
        ( vec_push [i] w ( string_len hn ) )
        ( string_free hn )
        = ci + ci 1
    }
    : ~ i ri 0
    ~ < ri nt {
        = ci 0
        ~ < ci nf {
            : i cl ( cell_len r ri ci )
            ? > cl ( veci w ci ) { ( vec_set [i] w ci cl ) } {}
            = ci + ci 1
        }
        = ri + ri 1
    }
    ( print_header r w nf )
    ( print_rule w nf )
    = ri 0
    ~ < ri nt {
        ( print_data_row r w nf ri )
        = ri + ri 1
    }
    ( nurl_print `(` ) ( nurl_print ( nurl_str_int nt ) )
    ( nurl_print ? == nt 1 ` row)\n\n` ` rows)\n\n` )
    ( vec_free [i] w )
}

// Execute `sql` and render whatever comes back (rows, tag, or error).
@ exec_and_render Connection c s sql → v {
    : !PgResult PgErr r ( pg_exec c sql )
    ?? r {
        F e → {
            // libpq's message already carries its own "ERROR:  " prefix
            // and trailing newline — print it verbatim.
            : String em ( pg_err_msg c )
            ( nurl_print ( string_data em ) )
            ( string_free em )
        }
        T res → {
            ( render_result res )
            ( pg_clear res )
        }
    }
}

// ── Meta-commands ────────────────────────────────────────────────

@ print_help → v {
    ( nurl_print `Meta-commands:\n` )
    ( nurl_print `  \\dt          list tables\n` )
    ( nurl_print `  \\d  TABLE    describe a table's columns\n` )
    ( nurl_print `  \\l           list databases\n` )
    ( nurl_print `  \\du          list roles\n` )
    ( nurl_print `  \\conninfo    show connection info\n` )
    ( nurl_print `  \\?           this help\n` )
    ( nurl_print `  \\q           quit\n` )
    ( nurl_print `Anything else is sent to the server as SQL (end with ';').\n` )
}

@ print_conninfo Connection c → v {
    : String db ( pg_db c )
    : String usr ( pg_user c )
    : String host ( pg_host c )
    ( nurl_print `Connected to database "` ) ( nurl_print ( string_data db ) )
    ( nurl_print `" as user "` ) ( nurl_print ( string_data usr ) )
    ( nurl_print `" on host "` ) ( nurl_print ( string_data host ) ) ( nurl_print `".\n` )
    ( string_free db ) ( string_free usr ) ( string_free host )
}

// Describe a table: run an information_schema query with the table name
// safely quoted as a SQL literal.
@ describe_table Connection c s tbl → v {
    : String esc ( pg_escape_literal c tbl )
    : String q ( string_new )
    ( string_push_str q `SELECT column_name AS column, data_type AS type, is_nullable AS nullable, column_default AS default FROM information_schema.columns WHERE table_name = ` )
    ( string_push_str q ( string_data esc ) )
    ( string_push_str q ` ORDER BY ordinal_position` )
    ( exec_and_render c ( string_data q ) )
    ( string_free q )
    ( string_free esc )
}

// Returns 1 to quit, 0 to continue. `cmd` is the trimmed line, already
// known to start with '\'.
@ handle_meta Connection c s cmd → i {
    ? ( nurl_str_eq cmd `\q` ) { ^ 1 } {}
    ? ( nurl_str_eq cmd `\dt` ) {
        ( exec_and_render c `SELECT schemaname AS schema, tablename AS name, tableowner AS owner FROM pg_catalog.pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 1,2` )
        ^ 0
    } {}
    ? ( nurl_str_eq cmd `\l` ) {
        ( exec_and_render c `SELECT datname AS name FROM pg_database WHERE datistemplate = false ORDER BY 1` )
        ^ 0
    } {}
    ? ( nurl_str_eq cmd `\du` ) {
        ( exec_and_render c `SELECT rolname AS role, rolsuper AS superuser, rolcanlogin AS login FROM pg_roles ORDER BY 1` )
        ^ 0
    } {}
    ? ( nurl_str_eq cmd `\conninfo` ) { ( print_conninfo c ) ^ 0 } {}
    ? ( nurl_str_eq cmd `\?` ) { ( print_help ) ^ 0 } {}
    ? ( nurl_str_starts cmd `\d ` ) {
        : s tbl ( nurl_str_slice cmd 3 - ( nurl_str_len cmd ) 3 )
        ( describe_table c tbl )
        ^ 0
    } {}
    ( nurl_print `invalid command: ` ) ( nurl_print cmd ) ( nurl_print `\nTry \\? for help.\n` )
    ^ 0
}

// ── REPL ─────────────────────────────────────────────────────────

// Process one input line. Accumulates into `buf` until a `;` terminator,
// then executes. Meta-commands act only when no statement is pending.
// Returns 1 to quit, 0 to continue.
@ process_line Connection c String buf String line → i {
    : String t ( string_trim line )
    : i tl ( string_len t )
    ? == 0 tl { ( string_free t ) ^ 0 } {}
    ? & == 0 ( string_len buf ) == ( string_get t 0 ) 92 {
        : i q ( handle_meta c ( string_data t ) )
        ( string_free t )
        ^ q
    } {}
    ( string_push_str buf ( string_data line ) )
    ( string_push_char buf 32 )
    : i done ( string_ends_with t `;` )
    ( string_free t )
    ? done {
        ( exec_and_render c ( string_data buf ) )
        ( string_clear buf )
    } {}
    ^ 0
}

@ run_repl Connection c i tty → v {
    : String buf ( string_new )
    : ~ i running 1
    ~ != running 0 {
        ? != 0 tty {
            ( nurl_print ? == 0 ( string_len buf ) `nurl=> ` `nurl-> ` )
        } {}
        : String line ( read_line )
        ? & == 0 ( string_len line ) ( stdin_eof ) {
            = running 0
            ? != 0 tty { ( nurl_print `\n` ) } {}
        } {
            : i q ( process_line c buf line )
            ? != 0 q { = running 0 } {}
        }
        ( string_free line )
    }
    ( string_free buf )
}

// ── Banner + entry point ─────────────────────────────────────────

@ print_banner Connection c → v {
    : String db ( pg_db c )
    : String usr ( pg_user c )
    ( nurl_print `psql (NURL) — connected to "` ) ( nurl_print ( string_data db ) )
    ( nurl_print `" as "` ) ( nurl_print ( string_data usr ) )
    ( nurl_print `" (server ` ) ( nurl_print ( nurl_str_int ( pg_server_version c ) ) )
    ( nurl_print `)\nType \\? for help, \\q to quit.\n\n` )
    ( string_free db ) ( string_free usr )
}

@ main → i {
    : ( Vec String ) args ( env_args_list )
    : i argc ( vec_len [String] args )
    : ~ s conninfo ``
    : ~ s command ``
    : ~ i has_cmd 0
    : ~ i i 1
    ~ < i argc {
        ?? ( vec_get [String] args i ) {
            T av → {
                : s as ( string_data av )
                ? ( nurl_str_eq as `-c` ) {
                    = i + i 1
                    ?? ( vec_get [String] args i ) {
                        T cv → { = command ( string_data cv ) = has_cmd 1 }
                        F _ → {}
                    }
                } {
                    ? ( nurl_str_starts as `-` ) {} { = conninfo as }
                }
            }
            F _ → {}
        }
        = i + i 1
    }
    // Fall back to $PG_CONNINFO, then to libpq's own env/defaults ("").
    ? == 0 ( nurl_str_len conninfo ) {
        ?? ( env_get `PG_CONNINFO` ) {
            T ev → = conninfo ( string_data ev )
            F _ → {}
        }
    } {}

    : Connection c ( pg_connect conninfo )
    ? ! ( pg_ok c ) {
        : String em ( pg_err_msg c )
        ( nurl_print `psql: error: ` ) ( nurl_print ( string_data em ) )
        ( string_free em )
        ( pg_close c )
        ^ 1
    } {}

    ? != 0 has_cmd {
        : String t ( string_trim ( string_from command ) )
        ? & > ( string_len t ) 0 == ( string_get t 0 ) 92 {
            ( handle_meta c ( string_data t ) )
        } {
            ( exec_and_render c command )
        }
        ( string_free t )
        ( pg_close c )
        ^ 0
    } {}

    : i tty # i ( isatty # i32 0 )
    ? != 0 tty { ( print_banner c ) } {}
    ( run_repl c tty )
    ( pg_close c )
    ^ 0
}
