// examples/pg_optional.nu — PostgreSQL with the language's option types.
//
// Shows the option-typed surface of `stdlib/ext/postgres.nu` end to end:
//
//   * Binding parameters with `Vec ?String` — `T text` binds a value,
//     `F` (None) binds SQL NULL — via `pg_exec_params_opt`. Internally
//     that walks the params with `vec_get [?String]` → `??String`.
//   * Reading nullable columns back as `?String` / `?i` via
//     `pg_get_opt` / `pg_get_opt_int`, matched with `??`.
//
// Connect via a conninfo argument or $PG_CONNINFO, e.g.
//   ./pg_optional "host=/tmp port=5433 user=postgres dbname=postgres"
//   PG_CONNINFO="host=/tmp …" ./pg_optional
//
// Build:  ./nurl.sh examples/pg_optional.nu pg_optional

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/postgres.nu`

// Push a `T value` (some text) onto a `Vec ?String`.
@ push_some ( Vec ? String ) ps s text → v {
    ( vec_push [? String] ps @ ?String { T ( string_from text ) } )
}

// Push an `F` (None) — binds SQL NULL.
@ push_null ( Vec ? String ) ps → v {
    ( vec_push [? String] ps @ ?String { F # String 0 } )
}

// Insert one (name, nickname) row where nickname may be NULL.
@ insert_person Connection c s name b has_nick s nick → v {
    : ( Vec ? String ) ps ( vec_with_cap [? String] 2 )
    ( push_some ps name )
    ? has_nick { ( push_some ps nick ) } { ( push_null ps ) }
    : !PgResult PgErr r ( pg_exec_params_opt c `INSERT INTO people (name, nickname) VALUES ($1, $2)` ps )
    ?? r {
        F e → {
            : String em ( pg_err_msg c )
            ( nurl_print `insert failed: ` ) ( nurl_print ( string_data em ) )
            ( string_free em )
        }
        T res → ( pg_clear res )
    }
}

@ run Connection c → v {
    // Schema — TEMP TABLE auto-drops at session end.
    : !i PgErr ddl ( pg_run c `CREATE TEMP TABLE people (id SERIAL PRIMARY KEY, name TEXT NOT NULL, nickname TEXT)` )
    ?? ddl { F _ → ( nurl_print `ddl failed\n` ) T _ → {} }

    ( insert_person c `Ada` T `Countess` )
    ( insert_person c `Alan` F `` )
    ( insert_person c `Grace` T `Amazing` )
    ( insert_person c `Dijkstra` F `` )

    // Read back, treating nickname as an optional value.
    : !PgResult PgErr q ( pg_exec c `SELECT name, nickname FROM people ORDER BY id` )
    ?? q {
        F e → {
            : String em ( pg_err_msg c )
            ( nurl_print `select failed: ` ) ( nurl_print ( string_data em ) )
            ( string_free em )
        }
        T r → {
            : i nrows ( pg_ntuples r )
            : ~ i row 0
            ~ < row nrows {
                : String name ( pg_get_value r row 0 )
                ( nurl_print ( string_data name ) ) ( nurl_print ` — ` )
                // pg_get_opt → ?String: None means the column was SQL NULL.
                ?? ( pg_get_opt r row 1 ) {
                    T nick → {
                        ( nurl_print `"` ) ( nurl_print ( string_data nick ) ) ( nurl_print `"\n` )
                        ( string_free nick )
                    }
                    F _ → ( nurl_print `(no nickname)\n` )
                }
                ( string_free name )
                = row + row 1
            }
            ( nurl_print `(` ) ( nurl_print ( nurl_str_int nrows ) ) ( nurl_print ` rows)\n` )
            ( pg_clear r )
        }
    }
}

@ main → i {
    : ~ s conninfo ``
    : ( Vec String ) args ( env_args_list )
    ? > ( vec_len [String] args ) 1 {
        ?? ( vec_get [String] args 1 ) { T a → = conninfo ( string_data a ) F _ → {} }
    } {}
    ? == 0 ( nurl_str_len conninfo ) {
        ?? ( env_get `PG_CONNINFO` ) { T ev → = conninfo ( string_data ev ) F _ → {} }
    } {}

    : Connection c ( pg_connect conninfo )
    ? ! ( pg_ok c ) {
        : String em ( pg_err_msg c )
        ( nurl_print `connect failed: ` ) ( nurl_print ( string_data em ) )
        ( string_free em )
        ( pg_close c )
        ^ 1
    } {}
    ( run c )
    ( pg_close c )
    ^ 0
}
