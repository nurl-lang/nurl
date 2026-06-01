// sqlite_basic.nu — in-memory CRUD round-trip for stdlib/ext/sqlite.nu.
//
// Exercises the full lifecycle: open(:memory:), CREATE TABLE via
// sqlite_exec, parameterised INSERT via prepare + bind + step + reset,
// SELECT walking rows with sqlite_step + sqlite_column_*. Prints
// row count + each row's columns so the snapshot covers both the
// DDL and the DML paths.
//
// Offline (no network gate) — sqlite3 is purely in-process. Skips
// cleanly when stdlib/runtime.sqlite3 sentinel is absent (build host
// lacked libsqlite3-dev): every call returns SqliteUnsupported.

$ `stdlib/core/string.nu`
$ `stdlib/ext/sqlite.nu`

@ die_with s tag SqliteErr e → v {
    ( nurl_print tag )
    ( nurl_print `=` )
    ( nurl_print ( sqlite_err_name e ) )
    ( nurl_print `\n` )
}

@ main → i {
    : !Database SqliteErr op_r ( sqlite_open `:memory:` )
    ?? op_r {
        F e → {
            ( die_with `open` e )
            ^ 0
        }
        T db → {
            // DDL.
            : !i SqliteErr ddl ( sqlite_exec db `CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT NOT NULL)` )
            ?? ddl {
                F e → ( die_with `ddl` e )
                T n → {
                    ( nurl_print `ddl_changes=` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
                }
            }

            // Prepared INSERT with two binds, reused for three rows.
            : !Statement SqliteErr ins_r ( sqlite_prepare db `INSERT INTO notes (id, body) VALUES (?1, ?2)` )
            ?? ins_r {
                F e → ( die_with `prepare` e )
                T ins → {
                    : ~ i k 1
                    ~ <= k 3 {
                        : String body ( string_with_cap 32 )
                        ( string_push_str body `note-` )
                        ( string_push_str body ( nurl_str_int k ) )
                        : !v SqliteErr bi1 ( sqlite_bind_int ins 1 k )
                        ?? bi1 {
                            F e → ( die_with `bind_int` e )
                            T _ → {}
                        }
                        : !v SqliteErr bi2 ( sqlite_bind_text ins 2 body )
                        ?? bi2 {
                            F e → ( die_with `bind_text` e )
                            T _ → {}
                        }
                        : !b SqliteErr st ( sqlite_step ins )
                        ?? st {
                            F e → ( die_with `step_ins` e )
                            T _ → {}
                        }
                        : !v SqliteErr rs ( sqlite_reset ins )
                        ?? rs {
                            F e → ( die_with `reset` e )
                            T _ → {}
                        }
                        ( string_free body )
                        = k + k 1
                    }
                    // `ins` auto-closes here (Drop on the match-arm binding).
                }
            }

            // SELECT — walk rows, print columns. Verifies that the
            // three INSERTs landed in the table in id order.
            : !Statement SqliteErr q_r ( sqlite_prepare db `SELECT id, body FROM notes ORDER BY id ASC` )
            ?? q_r {
                F e → ( die_with `prepare_select` e )
                T q → {
                    : ~ i nrows 0
                    : ~ b done F
                    ~ ! done {
                        : !b SqliteErr st ( sqlite_step q )
                        ?? st {
                            F e → { ( die_with `step_sel` e ) = done T }
                            T has_row → {
                                ? has_row {
                                    = nrows + nrows 1
                                    : i id ( sqlite_column_int q 0 )
                                    : String body ( sqlite_column_text q 1 )
                                    ( nurl_print `row id=` )
                                    ( nurl_print ( nurl_str_int id ) )
                                    ( nurl_print ` body=` )
                                    ( nurl_print ( string_data body ) )
                                    ( nurl_print `\n` )
                                    ( string_free body )
                                } { = done T }
                            }
                        }
                    }
                    ( nurl_print `nrows=` ) ( nurl_print ( nurl_str_int nrows ) ) ( nurl_print `\n` )
                    // `q` auto-closes here (Drop on the match-arm binding).
                }
            }
            // `db` auto-closes at the end of this arm (Drop).
        }
    }
    ^ 0
}
