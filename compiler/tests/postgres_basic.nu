// postgres_basic.nu — round-trip exercise for stdlib/ext/postgres.nu.
//
// Gated by NURL_PG_TESTS=1 + PG_CONNINFO pointing at a reachable
// PostgreSQL instance, e.g.
//   PG_CONNINFO="host=/tmp port=5433 user=postgres dbname=postgres"
//
// Exercises the production surface end to end:
//   1. Connect + pg_ok status check.
//   2. CREATE TEMP TABLE via pg_run (auto-clear, → affected rows).
//   3. INSERT via pg_exec_params (Vec String, all-text).
//   4. INSERT a row with a SQL NULL via the PgParams builder.
//   5. Transaction: begin / insert / commit.
//   6. Prepared statement: prepare once, execute by name.
//   7. SELECT — walk rows with typed getters; show NULL handling.
//   8. Escaping smoke test.
//   9. Close.
//
// Default (gate unset) prints the skip notice.

$ `stdlib/std/process.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/postgres.nu`

@ kv s label s value → v {
    ( nurl_print label ) ( nurl_print `=` ) ( nurl_print value ) ( nurl_print `\n` )
}

// Report an Err arm uniformly: name + the connection's error text.
@ fail_pg Connection c s where PgErr e → v {
    : String msg ( pg_err_msg c )
    ( nurl_print where ) ( nurl_print ` failed: ` ) ( nurl_print ( pg_err_name e ) )
    ( nurl_print ` — ` ) ( nurl_print ( string_data msg ) ) ( nurl_print `\n` )
    ( string_free msg )
}

@ run_live_pg_test s conninfo → v {
    : Connection c ( pg_connect conninfo )
    ? ! ( pg_ok c ) {
        : String em ( pg_err_msg c )
        ( nurl_print `connect failed: ` ) ( nurl_print ( string_data em ) ) ( nurl_print `\n` )
        ( string_free em )
        ( pg_close c )
        ^ v
    } {}

    ( kv `server_version` ( nurl_str_int ( pg_server_version c ) ) )

    // DDL via pg_run.
    : !i PgErr ddl ( pg_run c `CREATE TEMP TABLE pg_notes (id INTEGER PRIMARY KEY, body TEXT, score DOUBLE PRECISION, ok BOOLEAN)` )
    ?? ddl {
        F e → ( fail_pg c `ddl` e )
        T _ → ( nurl_print `ddl ok\n` )
    }

    // INSERT three rows via all-text pg_exec_params.
    : ~ i k 1
    ~ <= k 3 {
        : ( Vec String ) params ( vec_with_cap [String] 4 )
        ( vec_push [String] params ( string_from ( nurl_str_int k ) ) )
        : String body ( string_with_cap 16 )
        ( string_push_str body `note-` )
        ( string_push_str body ( nurl_str_int k ) )
        ( vec_push [String] params body )
        ( vec_push [String] params ( string_from ( nurl_str_int + 100 k ) ) )
        ( vec_push [String] params ( string_from `t` ) )
        : !PgResult PgErr ins ( pg_exec_params c `INSERT INTO pg_notes (id, body, score, ok) VALUES ($1, $2, $3, $4)` params )
        ?? ins {
            F e → ( fail_pg c `insert` e )
            T r → ( pg_clear r )
        }
        = k + k 1
    }

    // INSERT a row with a NULL body + NULL score via the builder.
    : PgParams ps ( pg_params 4 )
    ( pg_bind_int ps 4 )
    ( pg_bind_null ps )
    ( pg_bind_null ps )
    ( pg_bind_bool ps F )
    : !PgResult PgErr insn ( pg_exec_params_b c `INSERT INTO pg_notes (id, body, score, ok) VALUES ($1, $2, $3, $4)` ps )
    ?? insn {
        F e → ( fail_pg c `insert_null` e )
        T r → {
            : String cs ( pg_cmd_status r )
            ( kv `insert_null` ( string_data cs ) )
            ( string_free cs )
            ( pg_clear r )
        }
    }

    // INSERT id=6 with a NULL body via the OPTION-typed params API
    // (`Vec ?String`, None = SQL NULL — internally walked with
    // `vec_get [?String]` → `??String`).
    : ( Vec ?String ) op ( vec_with_cap [?String] 4 )
    ( vec_push [?String] op @ ?String { T ( string_from `6` ) } )
    ( vec_push [?String] op @ ?String { F # String 0 } )
    ( vec_push [?String] op @ ?String { T ( string_from `106` ) } )
    ( vec_push [?String] op @ ?String { T ( string_from `t` ) } )
    : !PgResult PgErr inso ( pg_exec_params_opt c `INSERT INTO pg_notes (id, body, score, ok) VALUES ($1,$2,$3,$4)` op )
    ?? inso {
        F e → ( fail_pg c `insert_opt` e )
        T r → {
            : String cs ( pg_cmd_status r )
            ( kv `insert_opt` ( string_data cs ) )
            ( string_free cs )
            ( pg_clear r )
        }
    }

    // Transaction: insert id=5 inside begin/commit.
    : !i PgErr bt ( pg_begin c )
    ?? bt { F e → ( fail_pg c `begin` e )  T _ → {} }
    : ( Vec String ) tp ( vec_with_cap [String] 4 )
    ( vec_push [String] tp ( string_from `5` ) )
    ( vec_push [String] tp ( string_from `note-5` ) )
    ( vec_push [String] tp ( string_from `105` ) )
    ( vec_push [String] tp ( string_from `f` ) )
    : !PgResult PgErr tx ( pg_exec_params c `INSERT INTO pg_notes (id, body, score, ok) VALUES ($1,$2,$3,$4)` tp )
    ?? tx { F e → ( fail_pg c `tx_insert` e )  T r → ( pg_clear r ) }
    : !i PgErr ct ( pg_commit c )
    ?? ct { F e → ( fail_pg c `commit` e )  T _ → ( nurl_print `commit ok\n` ) }

    // Prepared statement: count rows with score above a threshold.
    : !PgResult PgErr pr ( pg_prepare c `cnt` `SELECT count(*) FROM pg_notes WHERE score > $1` 1 )
    ?? pr {
        F e → ( fail_pg c `prepare` e )
        T r → {
            ( pg_clear r )
            : PgParams qp ( pg_params 1 )
            ( pg_bind_int qp 101 )
            : !PgResult PgErr q ( pg_exec_prepared_b c `cnt` qp )
            ?? q {
                F e → ( fail_pg c `exec_prepared` e )
                T rr → {
                    ( kv `count_score_gt_101` ( nurl_str_int ( pg_get_int rr 0 0 ) ) )
                    ( pg_clear rr )
                }
            }
        }
    }

    // SELECT — walk rows with typed getters + NULL handling.
    : !PgResult PgErr sel ( pg_exec c `SELECT id, body, score, ok FROM pg_notes ORDER BY id ASC` )
    ?? sel {
        F e → ( fail_pg c `select` e )
        T r → {
            : i nrows ( pg_ntuples r )
            ( kv `nrows` ( nurl_str_int nrows ) )
            : ~ i row 0
            ~ < row nrows {
                : i id ( pg_get_int r row 0 )
                ( nurl_print `row id=` ) ( nurl_print ( nurl_str_int id ) )
                // Option-typed read: body comes back as ?String (None on NULL).
                ?? ( pg_get_opt r row 1 ) {
                    T body → {
                        ( nurl_print ` body=` ) ( nurl_print ( string_data body ) )
                        ( string_free body )
                    }
                    F _ → ( nurl_print ` body=<null>` )
                }
                // Option-typed integer read for the (nullable) score.
                ?? ( pg_get_opt_int r row 2 ) {
                    T sc → { ( nurl_print ` score=` ) ( nurl_print ( nurl_str_int sc ) ) }
                    F _ → ( nurl_print ` score=<null>` )
                }
                ( nurl_print ` ok=` ) ( nurl_print ? ( pg_get_bool r row 3 ) `T` `F` )
                ( nurl_print `\n` )
                = row + row 1
            }
            ( pg_clear r )
        }
    }

    // Escaping smoke test — a value with an embedded quote.
    : String lit ( pg_escape_literal c `O'Brien` )
    ( kv `escaped` ( string_data lit ) )
    ( string_free lit )

    ( pg_close c )
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
