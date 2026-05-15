// postgres_basic.nu — round-trip exercise for stdlib/ext/postgres.nu.
//
// Gated by NURL_PG_TESTS=1 + the PG_CONNINFO env var pointing at a
// reachable PostgreSQL instance (e.g.
// `PG_CONNINFO="host=localhost user=postgres dbname=postgres"`).
//
// Round-trip:
//   1. Open a connection.
//   2. CREATE TEMP TABLE notes — drops automatically on session end,
//      so the test leaves no schema artifacts behind.
//   3. INSERT three rows via pg_exec_params with text-formatted
//      parameters (proves the parallel-Vec[String] → libpq parameter
//      array conversion works).
//   4. SELECT and walk rows via pg_get_value, print each.
//   5. Close.
//
// Default (gate unset) prints the skip notice.

$ `stdlib/std/process.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/postgres.nu`

@ println_label s label s value → v {
    ( nurl_print label ) ( nurl_print `=` ) ( nurl_print value ) ( nurl_print `\n` )
}

@ run_live_pg_test s conninfo → v {
    : !Connection PgErr cr ( pg_connect conninfo )
    ?? cr {
        F e → {
            ( println_label `connect` ( pg_err_name e ) )
        }
        T c → {
            // DDL — TEMP TABLE auto-drops at session end.
            : !PgResult PgErr ddl ( pg_exec c `CREATE TEMP TABLE pg_notes (id INTEGER PRIMARY KEY, body TEXT NOT NULL)` )
            ?? ddl {
                F e → ( println_label `ddl` ( pg_err_name e ) )
                T r → {
                    ( println_label `ddl_status` ( nurl_str_int ( pg_result_status r ) ) )
                    ( pg_clear r )
                }
            }

            // INSERT three rows via parameterised exec. Build the
            // params Vec freshly each iteration so the per-row cleanup
            // is unambiguous (pg_exec_params consumes the Strings).
            : ~ i k 1
            ~ <= k 3 {
                : String id_s ( string_from ( nurl_str_int k ) )
                : String body ( string_with_cap 32 )
                ( string_push_str body `note-` )
                ( string_push_str body ( nurl_str_int k ) )
                : ( Vec String ) params ( vec_with_cap [String] 2 )
                ( vec_push [String] params id_s )
                ( vec_push [String] params body )
                : !PgResult PgErr ins ( pg_exec_params c `INSERT INTO pg_notes (id, body) VALUES ($1, $2)` params )
                ( vec_free [String] params )
                ?? ins {
                    F e → ( println_label `insert` ( pg_err_name e ) )
                    T r → ( pg_clear r )
                }
                = k + k 1
            }

            // SELECT — walk rows. pg_ntuples gives the count;
            // pg_get_value pulls each cell as an OWNED String.
            : !PgResult PgErr q ( pg_exec c `SELECT id, body FROM pg_notes ORDER BY id ASC` )
            ?? q {
                F e → ( println_label `select` ( pg_err_name e ) )
                T r → {
                    : i nrows ( pg_ntuples r )
                    ( println_label `nrows` ( nurl_str_int nrows ) )
                    : ~ i row 0
                    ~ < row nrows {
                        : String idv ( pg_get_value r row 0 )
                        : String bodyv ( pg_get_value r row 1 )
                        ( nurl_print `row id=` ) ( nurl_print ( string_data idv ) )
                        ( nurl_print ` body=` ) ( nurl_print ( string_data bodyv ) )
                        ( nurl_print `\n` )
                        ( string_free idv )
                        ( string_free bodyv )
                        = row + row 1
                    }
                    ( pg_clear r )
                }
            }

            ( pg_close c )
        }
    }
}

@ main → i {
    : ?String gate ( env_get `NURL_PG_TESTS` )
    ?? gate {
        T g → {
            ( string_free g )
            : ?String ci ( env_get `PG_CONNINFO` )
            ?? ci {
                T conninfo → {
                    ( run_live_pg_test ( string_data conninfo ) )
                    ( string_free conninfo )
                }
                F _ → ( nurl_print `live pg test skipped (PG_CONNINFO unset)\n` )
            }
        }
        F _ → ( nurl_print `live pg test skipped (set NURL_PG_TESTS=1 + PG_CONNINFO=... to enable)\n` )
    }
    ^ 0
}
