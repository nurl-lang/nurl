// packages/psql/src/main.nu — the `psql` command: a pure-NURL PostgreSQL
// client. Connects over the v3 wire protocol with optional TLS (pure-NURL,
// no libpq / no OpenSSL needed on the target), authenticates with
// trust / cleartext / MD5 / SCRAM-SHA-256, runs queries and prints an
// aligned table.
//
//   psql [flags] ["postgres://user:pass@host:port/db?sslmode=..."]
//     -h HOST        host (default $PGHOST or localhost)
//     -p PORT        port (default $PGPORT or 5432)
//     -U USER        user (default $PGUSER or postgres)
//     -d DB          database (default $PGDATABASE or the user)
//     -c SQL         run one command and exit; otherwise read from stdin
//     --sslmode M    disable | prefer | require | verify-full (default prefer)
//   Password is taken from $PGPASSWORD.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `pg.nu`

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

// Display width of a String (byte length; assumes single-width chars).
@ __dw String s → i { ^ ( string_len s ) }

@ __pad String dst String s i width → v {
    ( string_push_str dst ( string_data s ) )
    : ~ i k ( string_len s )
    ~ < k width { ( string_push_char dst 32 ) = k + k 1 }
}

@ __repeat i c i n → String {
    : String out ( string_with_cap n )
    : ~ i k 0
    ~ < k n { ( string_push_char out c ) = k + k 1 }
    ^ out
}

// Render a PgResult as an aligned table to stdout.
@ __print_result PgResult r → v {
    : i nc . r ncols
    : i nr . r nrows
    ? == nc 0 {
        ( nurl_print ( string_data . r tag ) ) ( nurl_print `\n` )
    } {
        // column widths = max(header, cells)
        : ( Vec u ) widths ( vec_with_cap [u] nc )
        : ~ i c 0
        ~ < c nc {
            : ~ i w ( __dw ( pg_result_col r c ) )
            : ~ i rr 0
            ~ < rr nr {
                : i cw ? ( pg_result_is_null r rr c ) 6 ( __dw ( pg_result_cell r rr c ) )
                ? > cw w { = w cw } {}
                = rr + rr 1
            }
            ( vec_push [u] widths # u ? > w 255 255 w )
            = c + c 1
        }
        // header
        = c 0
        ~ < c nc {
            : i w ?? ( vec_get [u] widths c ) { T x → # i x F _ → 0 }
            ? > c 0 { ( nurl_print ` | ` ) } {}
            : String h ( string_with_cap + w 1 )
            ( __pad h ( pg_result_col r c ) w )
            ( nurl_print ( string_data h ) )
            = c + c 1
        }
        ( nurl_print `\n` )
        // separator
        = c 0
        ~ < c nc {
            : i w ?? ( vec_get [u] widths c ) { T x → # i x F _ → 0 }
            ? > c 0 { ( nurl_print `-+-` ) } {}
            ( nurl_print ( string_data ( __repeat 45 w ) ) )
            = c + c 1
        }
        ( nurl_print `\n` )
        // rows
        : ~ i rr 0
        ~ < rr nr {
            = c 0
            ~ < c nc {
                : i w ?? ( vec_get [u] widths c ) { T x → # i x F _ → 0 }
                ? > c 0 { ( nurl_print ` | ` ) } {}
                : String cell ? ( pg_result_is_null r rr c ) ( string_from `(null)` ) ( pg_result_cell r rr c )
                : String padded ( string_with_cap + w 1 )
                ( __pad padded cell w )
                ( nurl_print ( string_data padded ) )
                = c + c 1
            }
            ( nurl_print `\n` )
            = rr + rr 1
        }
        : String foot ( string_with_cap 16 )
        ( string_push_str foot `(` )
        ( string_push_int foot nr )
        ( string_push_str foot ? == nr 1 ` row)` ` rows)` )
        ( nurl_print ( string_data foot ) ) ( nurl_print `\n` )
    }
}

@ __run_one * PgConn c s sql → v {
    ?? ( pg_query c sql ) {
        T r → { ( __print_result r ) ( pg_result_free r ) }
        F e → {
            ( nurl_eprint `error: ` ) ( nurl_eprint ( pg_err_name e ) )
            ( nurl_eprint `: ` ) ( nurl_eprint ( string_data . c lasterr ) ) ( nurl_eprint `\n` )
        }
    }
}

// Parse postgres://[user[:pass]@]host[:port][/db][?sslmode=M] into the
// mutable refs via return of a small struct.
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
    // strip scheme
    : ~ i p 0
    ? ( nurl_str_starts url `postgres://` ) { = p 11 } {}
    ? ( nurl_str_starts url `postgresql://` ) { = p 13 } {}
    = . c has_url T
    // userinfo @ — find '@' before the first '/'
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
        // userinfo present
        : String ui ( string_substr ( string_from url ) p - at p )
        : ?i colon ( string_index_of ui `:` )
        ?? colon {
            T ci2 → {
                = . c user ( string_substr ui 0 ci2 )
                = . c password ( string_substr ui + ci2 1 - ( string_len ui ) + ci2 1 )
            }
            F _ → { = . c user ui }
        }
        = hoststart + at 1
    } {}
    // host[:port] up to slash or ?
    : ~ i hostend ? != slash -1 slash n
    : ~ i q -1
    = k hoststart
    ~ < k n { ? & == ( nurl_str_get url k ) 63 == q -1 { = q k } {} = k + k 1 }
    ? & != q -1 | == slash -1 < q hostend { = hostend q } {}
    : String hostport ( string_substr ( string_from url ) hoststart - hostend hoststart )
    : ?i pc ( string_index_of hostport `:` )
    ?? pc {
        T pci → {
            = . c host ( string_substr hostport 0 pci )
            = . c port ( __atoi ( string_data ( string_substr hostport + pci 1 - ( string_len hostport ) + pci 1 ) ) )
        }
        F _ → { = . c host hostport }
    }
    // database between slash and ?
    ? != slash -1 {
        : i dbend ? != q -1 q n
        = . c database ( string_substr ( string_from url ) + slash 1 - dbend + slash 1 )
    } {}
    // query: sslmode
    ? != q -1 {
        : String qs ( string_substr ( string_from url ) + q 1 - n + q 1 )
        : ?i si ( string_index_of qs `sslmode=` )
        ?? si {
            T sidx → { = . c sslmode ( __sslmode_code ( string_data ( string_substr qs + sidx 8 - ( string_len qs ) + sidx 8 ) ) ) }
            F _ → {}
        }
    } {}
    ^ c
}

@ main → i {
    : ( Vec String ) args ( env_args_list )
    : i argc ( vec_len [String] args )

    : ~ ConnInfo ci @ ConnInfo {
        ( env_var_or `PGHOST` `localhost` )
        ( __atoi ( string_data ( env_var_or `PGPORT` `5432` ) ) )
        ( env_var_or `PGUSER` `postgres` )
        ( env_var_or `PGPASSWORD` `` )
        ( env_var_or `PGDATABASE` `` )
        1
        F
    }
    : ~ String sql ( string_new )
    : ~ b have_c F

    : ~ i ai 1
    ~ < ai argc {
        : String a ?? ( vec_get [String] args ai ) { T x → x F _ → ( string_new ) }
        : s as ( string_data a )
        ? ( nurl_str_eq as `-h` ) { = ai + ai 1 = . ci host ?? ( vec_get [String] args ai ) { T x → x F _ → . ci host } } {
            ? ( nurl_str_eq as `-p` ) { = ai + ai 1 = . ci port ( __atoi ( string_data ?? ( vec_get [String] args ai ) { T x → x F _ → ( string_from `5432` ) } ) ) } {
                ? ( nurl_str_eq as `-U` ) { = ai + ai 1 = . ci user ?? ( vec_get [String] args ai ) { T x → x F _ → . ci user } } {
                    ? ( nurl_str_eq as `-d` ) { = ai + ai 1 = . ci database ?? ( vec_get [String] args ai ) { T x → x F _ → . ci database } } {
                        ? ( nurl_str_eq as `-c` ) { = ai + ai 1 = sql ?? ( vec_get [String] args ai ) { T x → x F _ → ( string_new ) } = have_c T } {
                            ? ( nurl_str_eq as `--sslmode` ) { = ai + ai 1 = . ci sslmode ( __sslmode_code ( string_data ?? ( vec_get [String] args ai ) { T x → x F _ → ( string_from `prefer` ) } ) ) } {
                                ? | ( nurl_str_starts as `postgres://` ) ( nurl_str_starts as `postgresql://` ) { = ci ( __parse_url as ci ) } {
                                    ( nurl_eprint `psql: unknown argument: ` ) ( nurl_eprint as ) ( nurl_eprint `\n` )
                                } } } } } } }
        = ai + ai 1
    }

    // database defaults to the user name if unset
    ? == ( string_len . ci database ) 0 { = . ci database . ci user } {}

    : !*PgConn PgErr cr ( pg_connect ( string_data . ci host ) . ci port ( string_data . ci user ) ( string_data . ci password ) ( string_data . ci database ) . ci sslmode )
    ?? cr {
        F e → {
            ( nurl_eprint `psql: connection failed: ` ) ( nurl_eprint ( pg_err_name e ) ) ( nurl_eprint `\n` )
            ^ 1
        }
        T c → {
            ? have_c {
                ( __run_one c ( string_data sql ) )
            } {
                // read statements (one per line) from stdin
                : ~ b eof F
                ~ ! eof {
                    : String line ( read_line )
                    ? ( stdin_eof ) { = eof T } {
                        ? > ( string_len line ) 0 { ( __run_one c ( string_data line ) ) } {}
                    }
                }
            }
            ( pg_close c )
            ^ 0
        }
    }
}
