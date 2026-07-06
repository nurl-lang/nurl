// packages/psql/src/main.nu — the `psql` command: a pure-NURL PostgreSQL
// client. Connects over the v3 wire protocol with optional TLS (pure-NURL,
// no libpq / no OpenSSL needed on the target), authenticates with
// trust / cleartext / MD5 / SCRAM-SHA-256, and behaves like psql for
// everyday use: aligned result tables, backslash meta-commands, a
// multi-line REPL terminated by ';', and one-shot `-c`.
//
//   psql [flags] ["postgres://user:pass@host:port/db?sslmode=..."]
//     -h HOST        host (default $PGHOST or localhost)
//     -p PORT        port (default $PGPORT or 5432)
//     -U USER        user (default $PGUSER or postgres)
//     -d DB          database (default $PGDATABASE or the user)
//     -c SQL         run one command and exit; otherwise read from stdin
//     --sslmode M    disable | prefer | require | verify-full (default prefer)
//   Password is taken from $PGPASSWORD.
//
//   Meta-commands (when no statement is pending):
//     \dt          list tables          \l         list databases
//     \d TABLE     describe a table     \du        list roles
//     \dn          list schemas         \conninfo  connection info
//     \?           this help            \q         quit

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `deps/cli/src/cli.nu`
$ `pg.nu`

& `c` @ isatty i32 fd → i32

& `c` @ nurl_read_password s prompt → s

@ __sslmode_code s m → i {
    ? ( nurl_str_eq m `disable` ) { ^ 0 } {}
    ? ( nurl_str_eq m `prefer` ) { ^ 1 } {}
    ? ( nurl_str_eq m `require` ) { ^ 2 } {}
    ? ( nurl_str_eq m `verify-full` ) { ^ 3 } {}
    ^ 1
}

@ __atoi s str → i {
    : i n ( nurl_str_len str )
    : ~ i v 0
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get str k )
        ? & >= c 48 <= c 57 { = v + * v 10 - c 48 } {}
        = k + k 1
    }
    ^ v
}

// ── result rendering ───────────────────────────────────────────────

// Append `s` then pad with spaces out to `width` (left-aligned).
@ __pad String dst String s i width → v {
    ( string_push_str dst ( string_data s ) )
    : ~ i k ( string_len s )
    ~ < k width { ( string_push_char dst 32 ) = k + k 1 }
}

// Append `width-len` leading spaces then `s` (right-aligned).
@ __pad_r String dst String s i width → v {
    : ~ i k ( string_len s )
    ~ < k width { ( string_push_char dst 32 ) = k + k 1 }
    ( string_push_str dst ( string_data s ) )
}

// True when `txt` looks like a number (optional leading '-', digits, at
// most one '.') — used to right-align numeric columns the way psql does.
@ __is_num s txt → b {
    : i n ( nurl_str_len txt )
    ? == n 0 { ^ F } {}
    : ~ i k 0
    : ~ i digits 0
    : ~ i dots 0
    ~ < k n {
        : i ch ( nurl_str_get txt k )
        ? & == k 0 == ch 45 {} {
            ? & >= ch 48 <= ch 57 { = digits + digits 1 } {
                ? == ch 46 { = dots + dots 1 } { ^ F }
            }
        }
        = k + k 1
    }
    ^ & > digits 0 <= dots 1
}

// A column is right-aligned when it has at least one value and every
// non-NULL value is numeric.
@ __col_numeric PgResult r i col i nr → b {
    : ~ i any 0
    : ~ i rr 0
    ~ < rr nr {
        ? ( pg_result_is_null r rr col ) {} {
            = any 1
            ? ( __is_num ( string_data ( pg_result_cell r rr col ) ) ) {} { ^ F }
        }
        = rr + rr 1
    }
    ^ == any 1
}

@ __wat ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

// Render a PgResult as a psql-style aligned table (or the command tag for
// statements that return no rows).
@ __print_result PgResult r → v {
    : i nc . r ncols
    : i nr . r nrows
    ? == nc 0 {
        ( nurl_print ( string_data . r tag ) ) ( nurl_print `\n` )
        ^ v
    } {}

    // Column widths (max of header and cells) and right-justify flags.
    : ( Vec u ) widths ( vec_with_cap [u] nc )
    : ( Vec u ) rjust ( vec_with_cap [u] nc )
    : ~ i c 0
    ~ < c nc {
        : ~ i w ( string_len ( pg_result_col r c ) )
        : ~ i rr 0
        ~ < rr nr {
            ? ( pg_result_is_null r rr c ) {} {
                : i cw ( string_len ( pg_result_cell r rr c ) )
                ? > cw w { = w cw } {}
            }
            = rr + rr 1
        }
        ( vec_push [u] widths # u ? > w 255 255 w )
        ( vec_push [u] rjust # u ? ( __col_numeric r c nr ) 1 0 )
        = c + c 1
    }

    // Header:  ` h0 | h1 | … `
    : String hdr ( string_with_cap 80 )
    = c 0
    ~ < c nc {
        : i w ( __wat widths c )
        ? > c 0 { ( string_push_char hdr 124 ) } {}
        ( string_push_char hdr 32 )
        ? == ( __wat rjust c ) 1 { ( __pad_r hdr ( pg_result_col r c ) w ) } { ( __pad hdr ( pg_result_col r c ) w ) }
        ( string_push_char hdr 32 )
        = c + c 1
    }
    ( nurl_print ( string_data hdr ) ) ( nurl_print `\n` )
    ( string_free hdr )

    // Separator:  `----+-----+…`
    : String sep ( string_with_cap 80 )
    = c 0
    ~ < c nc {
        : i w ( __wat widths c )
        ? > c 0 { ( string_push_char sep 43 ) } {}
        : ~ i d + w 2
        ~ > d 0 { ( string_push_char sep 45 ) = d - d 1 }
        = c + c 1
    }
    ( nurl_print ( string_data sep ) ) ( nurl_print `\n` )
    ( string_free sep )

    // Rows.
    : ~ i rr 0
    ~ < rr nr {
        : String row ( string_with_cap 80 )
        = c 0
        ~ < c nc {
            : i w ( __wat widths c )
            ? > c 0 { ( string_push_char row 124 ) } {}
            ( string_push_char row 32 )
            ? ( pg_result_is_null r rr c ) {
                : ~ i k 0
                ~ < k w { ( string_push_char row 32 ) = k + k 1 }
            } {
                ? == ( __wat rjust c ) 1 { ( __pad_r row ( pg_result_cell r rr c ) w ) } { ( __pad row ( pg_result_cell r rr c ) w ) }
            }
            ( string_push_char row 32 )
            = c + c 1
        }
        ( nurl_print ( string_data row ) ) ( nurl_print `\n` )
        ( string_free row )
        = rr + rr 1
    }

    : String foot ( string_with_cap 16 )
    ( string_push_str foot `(` )
    ( string_push_int foot nr )
    ( string_push_str foot ? == nr 1 ` row)` ` rows)` )
    ( nurl_print ( string_data foot ) ) ( nurl_print `\n\n` )
    ( string_free foot )

    ( vec_free [u] widths ) ( vec_free [u] rjust )
}

// Run one statement and render rows / tag / error.
@ __run_one * PgConn c s sql → v {
    ?? ( pg_query c sql ) {
        T r → { ( __print_result r ) ( pg_result_free r ) }
        F e → {
            ( nurl_eprint `ERROR:  ` )
            ? > ( string_len . c lasterr ) 0 { ( nurl_eprint ( string_data . c lasterr ) ) } { ( nurl_eprint ( pg_err_name e ) ) }
            ( nurl_eprint `\n` )
        }
    }
}

// ── meta-commands ──────────────────────────────────────────────────

// Quote `txt` as a SQL string literal: wrap in single quotes, double any
// embedded single quotes.
@ __quote_lit s txt → String {
    : i n ( nurl_str_len txt )
    : String out ( string_with_cap + n 4 )
    ( string_push_char out 39 )
    : ~ i k 0
    ~ < k n {
        : i ch ( nurl_str_get txt k )
        ? == ch 39 { ( string_push_char out 39 ) } {}
        ( string_push_char out ch )
        = k + k 1
    }
    ( string_push_char out 39 )
    ^ out
}

@ __meta_help → v {
    ( nurl_print `Meta-commands:\n` )
    ( nurl_print `  \dt          list tables\n` )
    ( nurl_print `  \d  TABLE    describe a table's columns\n` )
    ( nurl_print `  \dn          list schemas\n` )
    ( nurl_print `  \l           list databases\n` )
    ( nurl_print `  \du          list roles\n` )
    ( nurl_print `  \conninfo    show connection info\n` )
    ( nurl_print `  \?           this help\n` )
    ( nurl_print `  \q           quit\n` )
    ( nurl_print `Anything else is sent to the server as SQL (end with ';').\n` )
}

@ __conninfo * PgConn c → v {
    ( nurl_print `You are connected to database "` )
    ( nurl_print ( string_data . c db_name ) )
    ( nurl_print `" as user "` )
    ( nurl_print ( string_data . c user_name ) )
    ( nurl_print `" on host "` )
    ( nurl_print ( string_data . c host_name ) )
    ( nurl_print `"` )
    ? == . c tls 1 { ( nurl_print ` (TLS encrypted)` ) } {}
    ( nurl_print `.\n` )
}

@ __describe * PgConn c s tbl → v {
    : String lit ( __quote_lit tbl )
    : String q ( string_with_cap 256 )
    ( string_push_str q `SELECT column_name AS column, data_type AS type, is_nullable AS nullable, column_default AS default FROM information_schema.columns WHERE table_name = ` )
    ( string_push_str q ( string_data lit ) )
    ( string_push_str q ` ORDER BY ordinal_position` )
    ( __run_one c ( string_data q ) )
    ( string_free q ) ( string_free lit )
}

// Returns 1 to quit, 0 to continue. `cmd` starts with '\'.
@ __handle_meta * PgConn c s cmd → i {
    ? ( nurl_str_eq cmd `\q` ) { ^ 1 } {}
    ? ( nurl_str_eq cmd `\?` ) { ( __meta_help ) ^ 0 } {}
    ? ( nurl_str_eq cmd `\conninfo` ) { ( __conninfo c ) ^ 0 } {}
    ? ( nurl_str_eq cmd `\dt` ) {
        ( __run_one c `SELECT schemaname AS "Schema", tablename AS "Name", tableowner AS "Owner" FROM pg_catalog.pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 1,2` )
        ^ 0
    } {}
    ? ( nurl_str_eq cmd `\l` ) {
        ( __run_one c `SELECT datname AS "Name" FROM pg_database WHERE datistemplate = false ORDER BY 1` )
        ^ 0
    } {}
    ? ( nurl_str_eq cmd `\du` ) {
        ( __run_one c `SELECT rolname AS "Role", rolsuper AS "Superuser", rolcanlogin AS "Login" FROM pg_roles ORDER BY 1` )
        ^ 0
    } {}
    ? ( nurl_str_eq cmd `\dn` ) {
        ( __run_one c `SELECT nspname AS "Name", pg_catalog.pg_get_userbyid(nspowner) AS "Owner" FROM pg_catalog.pg_namespace WHERE nspname NOT LIKE 'pg_%' AND nspname <> 'information_schema' ORDER BY 1` )
        ^ 0
    } {}
    ? ( nurl_str_starts cmd `\d ` ) {
        : String raw ( string_from ( nurl_str_slice cmd 3 - ( nurl_str_len cmd ) 3 ) )
        : String tbl ( string_trim raw )
        ( string_free raw )
        ( __describe c ( string_data tbl ) )
        ( string_free tbl )
        ^ 0
    } {}
    ( nurl_eprint `invalid command: ` ) ( nurl_eprint cmd ) ( nurl_eprint `\nTry \? for help.\n` )
    ^ 0
}

// ── REPL ───────────────────────────────────────────────────────────

// Process one input line. Accumulates into `buf` until a ';' terminator,
// then executes. Meta-commands act only when no statement is pending.
// Returns 1 to quit, 0 to continue.
@ __process_line * PgConn c String buf String line → i {
    : String t ( string_trim line )
    : i tl ( string_len t )
    ? == tl 0 { ( string_free t ) ^ 0 } {}
    ? & == ( string_len buf ) 0 == ( string_get t 0 ) 92 {
        : i q ( __handle_meta c ( string_data t ) )
        ( string_free t )
        ^ q
    } {}
    ( string_push_str buf ( string_data t ) )
    ( string_push_char buf 32 )
    : b done ( string_ends_with t `;` )
    ( string_free t )
    ? done {
        ( __run_one c ( string_data buf ) )
        ( string_clear buf )
    } {}
    ^ 0
}

@ __repl * PgConn c i tty → v {
    : ~ String buf ( string_new )
    : ~ b running T
    ~ running {
        ? != tty 0 { ( nurl_print ? == ( string_len buf ) 0 `nurl=> ` `nurl-> ` ) } {}
        : String line ( read_line )
        ? & == ( string_len line ) 0 ( stdin_eof ) {
            = running F
            ? != tty 0 { ( nurl_print `\n` ) } {}
        } {
            : i q ( __process_line c buf line )
            ? != q 0 { = running F } {}
        }
        ( string_free line )
    }
    ( string_free buf )
}

@ __banner * PgConn c → v {
    ( nurl_print `psql (NURL) — pure-NURL PostgreSQL client\n` )
    ( nurl_print `Connected to "` ) ( nurl_print ( string_data . c db_name ) )
    ( nurl_print `" as "` ) ( nurl_print ( string_data . c user_name ) ) ( nurl_print `"` )
    ? > ( string_len . c srv_ver ) 0 { ( nurl_print ` (server ` ) ( nurl_print ( string_data . c srv_ver ) ) ( nurl_print `)` ) } {}
    ? == . c tls 1 { ( nurl_print ` [TLS]` ) } {}
    ( nurl_print `\nType \? for help, \q to quit.\n\n` )
}

// ── connection-info parsing ────────────────────────────────────────

// postgres://[user[:pass]@]host[:port][/db][?sslmode=M]
: ConnInfo {
    String host
    i port
    String user
    String password
    String database
    i sslmode
    b has_url
}

@ __parse_url s url ConnInfo ci → ConnInfo {
    : ~ ConnInfo c ci
    : i n ( nurl_str_len url )
    : ~ i p 0
    ? ( nurl_str_starts url `postgres://` ) { = p 11 } {}
    ? ( nurl_str_starts url `postgresql://` ) { = p 13 } {}
    = . c has_url T
    : ~ i at -1
    : ~ i slash -1
    : ~ i k p
    ~ < k n {
        : i ch ( nurl_str_get url k )
        ? & == ch 64 == at -1 { = at k } {}
        ? & == ch 47 == slash -1 { = slash k } {}
        = k + k 1
    }
    : ~ i hoststart p
    ? & != at -1 | == slash -1 < at slash {
        : String usrc ( string_from url )
        : String ui ( string_substr usrc p - at p )
        ( string_free usrc )
        : ?i colon ( string_index_of ui `:` )
        ?? colon {
            T ci2 → {
                ( string_free . c user ) = . c user ( string_substr ui 0 ci2 )
                ( string_free . c password ) = . c password ( string_substr ui + ci2 1 - ( string_len ui ) + ci2 1 )
                ( string_free ui )
            }
            F _ → { ( string_free . c user ) = . c user ui }
        }
        = hoststart + at 1
    } {}
    : ~ i hostend ? != slash -1 slash n
    : ~ i q -1
    = k hoststart
    ~ < k n { ? & == ( nurl_str_get url k ) 63 == q -1 { = q k } {} = k + k 1 }
    ? & != q -1 | == slash -1 < q hostend { = hostend q } {}
    : String uall ( string_from url )
    : String hostport ( string_substr uall hoststart - hostend hoststart )
    : ?i pc ( string_index_of hostport `:` )
    ?? pc {
        T pci → {
            ( string_free . c host ) = . c host ( string_substr hostport 0 pci )
            : String pstr ( string_substr hostport + pci 1 - ( string_len hostport ) + pci 1 )
            = . c port ( __atoi ( string_data pstr ) )
            ( string_free pstr )
            ( string_free hostport )
        }
        F _ → { ( string_free . c host ) = . c host hostport }
    }
    ? != slash -1 {
        : i dbend ? != q -1 q n
        ( string_free . c database ) = . c database ( string_substr uall + slash 1 - dbend + slash 1 )
    } {}
    ? != q -1 {
        : String qs ( string_substr uall + q 1 - n + q 1 )
        : ?i si ( string_index_of qs `sslmode=` )
        ?? si {
            T sidx → {
                : String ms ( string_substr qs + sidx 8 - ( string_len qs ) + sidx 8 )
                = . c sslmode ( __sslmode_code ( string_data ms ) )
                ( string_free ms )
            }
            F _ → {}
        }
        ( string_free qs )
    } {}
    ( string_free uall )
    ^ c
}

// Connect, and if the server demands a password we don't have, prompt for
// one on the terminal (echo disabled) and retry once — the way psql does.
@ __connect ConnInfo ci i tty → !*PgConn PgErr {
    : !*PgConn PgErr cr ( pg_connect ( string_data . ci host ) . ci port ( string_data . ci user ) ( string_data . ci password ) ( string_data . ci database ) . ci sslmode )
    ?? cr {
        T c → ^ @ !*PgConn PgErr { T c }
        F e → {
            : b need ?? e { PgNeedPassword → T _ → F }
            ? & need != tty 0 {
                : String prompt ( string_with_cap 32 )
                ( string_push_str prompt `Password for user ` )
                ( string_push_str prompt ( string_data . ci user ) )
                ( string_push_str prompt `: ` )
                : s pw ( nurl_read_password ( string_data prompt ) )
                ( string_free prompt )
                ^ ( pg_connect ( string_data . ci host ) . ci port ( string_data . ci user ) pw ( string_data . ci database ) . ci sslmode )
            } { ^ @ !*PgConn PgErr { F e } }
        }
    }
}

// The whole program is one default command (psql style): flags, an optional
// postgres://… URL positional, then one-shot -c or the REPL.
@ __psql_go CliCtx x → i {
    : String hostv ( ctx_str x `host` )
    : String userv ( ctx_str x `user` )
    : String passv ( ctx_str x `password` )
    : String dbv ( ctx_str x `dbname` )
    : String sslv ( ctx_str x `sslmode` )
    : ~ ConnInfo ci @ ConnInfo {
        hostv
        ( ctx_int x `port` )
        userv
        passv
        dbv
        ( __sslmode_code ( string_data sslv ) )
        F
    }
    ( string_free sslv )
    : String sql ( ctx_str x `command` )
    : b have_c > ( string_len sql ) 0
    // an optional postgres:// / postgresql:// URL positional overrides flags
    ? > ( ctx_nargs x ) 0 {
        : String u ( ctx_arg x 0 )
        : s us ( string_data u )
        ? | ( nurl_str_starts us `postgres://` ) ( nurl_str_starts us `postgresql://` ) {
            = ci ( __parse_url us ci )
        } {
            ( nurl_eprint `psql: unknown argument: ` ) ( nurl_eprint us ) ( nurl_eprint `\n` )
        }
    } {}

    // database defaults to the user name if unset (copied — both are freed)
    ? == ( string_len . ci database ) 0 {
        ( string_free . ci database )
        = . ci database ( string_from ( string_data . ci user ) )
    } {}

    : i tty # i ( isatty # i32 0 )
    : !*PgConn PgErr cr ( __connect ci tty )
    ?? cr {
        F e → {
            ( nurl_eprint `psql: connection failed: ` ) ( nurl_eprint ( pg_err_name e ) ) ( nurl_eprint `\n` )
            ( string_free . ci host ) ( string_free . ci user ) ( string_free . ci password ) ( string_free . ci database )
            ( string_free sql )
            ^ 1
        }
        T c → {
            ? have_c {
                : String t ( string_trim sql )
                ? & > ( string_len t ) 0 == ( string_get t 0 ) 92 {
                    : i _q ( __handle_meta c ( string_data t ) )
                } {
                    ( __run_one c ( string_data sql ) )
                }
                ( string_free t )
            } {
                ? != tty 0 { ( __banner c ) } {}
                ( __repl c tty )
            }
            ( pg_close c )
            ( string_free . ci host ) ( string_free . ci user ) ( string_free . ci password ) ( string_free . ci database )
            ( string_free sql )
            ^ 0
        }
    }
}

@ main → i {
    : *Cli c ( cli_new `psql` `a pure-NURL PostgreSQL client (no libpq, no OpenSSL); postgres://user:pass@host:port/db?sslmode=… as the argument` `0.3.0` )
    ( cli_flag_str c `host` 104 `HOST` `server host` `localhost` `PGHOST` )
    ( cli_flag_int c `port` 112 `PORT` `server port` 5432 `PGPORT` )
    ( cli_flag_str c `user` 85 `USER` `user name` `postgres` `PGUSER` )
    ( cli_flag_str c `password` 0 `PASS` `password (usually via $PGPASSWORD)` `` `PGPASSWORD` )
    ( cli_flag_str c `dbname` 100 `DB` `database (default: the user name)` `` `PGDATABASE` )
    ( cli_flag_str c `command` 99 `SQL` `run one command and exit (otherwise start a REPL)` `` `` )
    ( cli_flag_str c `sslmode` 0 `MODE` `disable | prefer | require | verify-full` `prefer` `` )
    ( cli_default c \ CliCtx x → i { ^ ( __psql_go x ) } )
    : i rc ( cli_run c )
    ( cli_free c )
    ^ rc
}
