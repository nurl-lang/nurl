// sqlite_tier34.nu — Tier 3 + Tier 4 regression for stdlib/ext/sqlite.nu.
//
// Covers:
//   #8  double bind/column round-trip
//   #9  transactions: with_transaction rolls back on error
//   #10 sqlite_column_is_null
//   #11 extended constraint codes (UNIQUE vs FOREIGNKEY)
//   #12 last_insert_rowid
//   #13 defensive mode + extension-loading off (sqlite_harden)
//   #14 sqlite_limit bounds query complexity
//   #15 authorizer denies a disallowed action
//   #16 PRAGMA helpers (foreign_keys, journal_mode=WAL, synchronous)
//
// Every handle is a scope-local match-arm binding → auto-dropped.

$ `stdlib/ext/sqlite.nu`

@ fail s tag SqliteErr e → v {
    ( nurl_print `FAIL ` ) ( nurl_print tag )
    ( nurl_print `=` ) ( nurl_print ( sqlite_err_name e ) ) ( nurl_print `\n` )
}

// #8 + #10 + #12
@ test_double_null_rowid Database db → v {
    : !i SqliteErr ddl ( sqlite_exec db `CREATE TABLE m (id INTEGER PRIMARY KEY, r REAL, note TEXT)` )
    ?? ddl { F e → ( fail `ddl_m` e ) T _ → {} }

    : !Statement SqliteErr ins_r ( sqlite_prepare db `INSERT INTO m (r, note) VALUES (?1, ?2)` )
    ?? ins_r {
        F e → ( fail `prep_ins_m` e )
        T ins → {
            : !v SqliteErr bd ( sqlite_bind_double ins 1 # f 2.5 )
            ?? bd { F e → ( fail `bind_double` e ) T _ → {} }
            : !v SqliteErr bn ( sqlite_bind_null ins 2 )
            ?? bn { F e → ( fail `bind_null` e ) T _ → {} }
            : !b SqliteErr st ( sqlite_step ins )
            ?? st { F e → ( fail `step_m` e ) T _ → {} }
            // #12 last_insert_rowid
            ( nurl_print `rowid=` )
            ( nurl_print ( nurl_str_int ( sqlite_last_insert_rowid db ) ) )
            ( nurl_print ` (expect 1)\n` )
        }
    }

    : !Statement SqliteErr q_r ( sqlite_prepare db `SELECT r, note FROM m WHERE id = 1` )
    ?? q_r {
        F e → ( fail `prep_sel_m` e )
        T q → {
            : !b SqliteErr st ( sqlite_step q )
            ?? st {
                F e → ( fail `step_sel_m` e )
                T has → {
                    ? has {
                        : f r ( sqlite_column_double q 0 )
                        // print 10*r as int to avoid float formatting
                        ( nurl_print `dbl_x10=` )
                        ( nurl_print ( nurl_str_int # i * r # f 10 ) )
                        ( nurl_print ` (expect 25)\n` )
                        // #10 NULL check
                        ( nurl_print `note_is_null=` )
                        ( nurl_print ? ( sqlite_column_is_null q 1 ) `1` `0` )
                        ( nurl_print ` (expect 1)\n` )
                    } { ( nurl_print `FAIL no row m\n` ) }
                }
            }
        }
    }
}

// #11 — UNIQUE vs FOREIGNKEY extended codes.
@ test_constraints Database db → v {
    : !i SqliteErr d1 ( sqlite_exec db `CREATE TABLE u (id INTEGER PRIMARY KEY, email TEXT UNIQUE)` )
    ?? d1 { F e → ( fail `ddl_u` e ) T _ → {} }
    : !i SqliteErr i1 ( sqlite_exec db `INSERT INTO u VALUES (1, 'a@x')` )
    ?? i1 { F e → ( fail `ins_u1` e ) T _ → {} }
    : !i SqliteErr i2 ( sqlite_exec db `INSERT INTO u VALUES (2, 'a@x')` )
    ?? i2 {
        F e → { ( nurl_print `unique_err=` ) ( nurl_print ( sqlite_err_name e ) ) ( nurl_print `\n` ) }
        T _ → { ( nurl_print `FAIL unique not enforced\n` ) }
    }

    // foreign key violation (needs PRAGMA foreign_keys=ON — #16)
    : !i SqliteErr fk ( sqlite_foreign_keys db T )
    ?? fk { F e → ( fail `fk_pragma` e ) T _ → {} }
    : !i SqliteErr dp ( sqlite_exec db `CREATE TABLE parent (id INTEGER PRIMARY KEY)` )
    ?? dp { F e → ( fail `ddl_parent` e ) T _ → {} }
    : !i SqliteErr dc ( sqlite_exec db `CREATE TABLE child (id INTEGER PRIMARY KEY, pid INTEGER REFERENCES parent(id))` )
    ?? dc { F e → ( fail `ddl_child` e ) T _ → {} }
    : !i SqliteErr ic ( sqlite_exec db `INSERT INTO child VALUES (1, 999)` )
    ?? ic {
        F e → { ( nurl_print `fk_err=` ) ( nurl_print ( sqlite_err_name e ) ) ( nurl_print `\n` ) }
        T _ → { ( nurl_print `FAIL fk not enforced\n` ) }
    }
}

// #9 — with_transaction rolls back on error.
@ test_transaction Database db → v {
    : !i SqliteErr ddl ( sqlite_exec db `CREATE TABLE t (id INTEGER PRIMARY KEY)` )
    ?? ddl { F e → ( fail `ddl_t` e ) T _ → {} }

    : ( @ !v SqliteErr Database ) body \ Database d → !v SqliteErr {
        : !i SqliteErr a ( sqlite_exec d `INSERT INTO t VALUES (100)` )
        ?? a { F er → { ^ @ !v SqliteErr { F er } } T _ → {} }
        // duplicate PK → constraint error → should trigger rollback
        : !i SqliteErr b ( sqlite_exec d `INSERT INTO t VALUES (100)` )
        ?? b { F er → { ^ @ !v SqliteErr { F er } } T _ → {} }
        ^ @ !v SqliteErr { T 0 }
    }
    : !v SqliteErr tr ( with_transaction db body )
    ?? tr {
        F e → { ( nurl_print `txn_rolled_back_err=` ) ( nurl_print ( sqlite_err_name e ) ) ( nurl_print `\n` ) }
        T _ → { ( nurl_print `FAIL txn unexpectedly committed\n` ) }
    }
    // After rollback the row must be gone.
    : !Statement SqliteErr q_r ( sqlite_prepare db `SELECT COUNT(*) FROM t` )
    ?? q_r {
        F e → ( fail `prep_count` e )
        T q → {
            : !b SqliteErr st ( sqlite_step q )
            ?? st {
                F e → ( fail `step_count` e )
                T _ → {
                    ( nurl_print `rows_after_rollback=` )
                    ( nurl_print ( nurl_str_int ( sqlite_column_int q 0 ) ) )
                    ( nurl_print ` (expect 0)\n` )
                }
            }
        }
    }
}

// #14 — sqlite_limit bounds SQL length.
@ test_limit Database db → v {
    : i prior ( sqlite_limit db SQLITE_LIMIT_SQL_LENGTH 40 )
    ( nurl_print `limit_prior_positive=` )
    ( nurl_print ? > prior 0 `1` `0` )
    ( nurl_print `\n` )
    // A statement longer than 40 bytes must be rejected.
    : !i SqliteErr r ( sqlite_exec db `SELECT 1 WHERE 1=1 AND 2=2 AND 3=3 AND 4=4 AND 5=5` )
    ?? r {
        F e → { ( nurl_print `long_sql_blocked=` ) ( nurl_print ( sqlite_err_name e ) ) ( nurl_print `\n` ) }
        T _ → { ( nurl_print `FAIL long sql allowed\n` ) }
    }
    // Restore the limit so later statements on this connection are not
    // throttled (the limit is connection-scoped, not per-statement).
    : i _restore ( sqlite_limit db SQLITE_LIMIT_SQL_LENGTH prior )
}

// #15 — authorizer denies DROP TABLE. Uses its own connection so the
// authorizer state is fully isolated from the other sub-tests.
@ test_authorizer Database db → v {
    : !i SqliteErr ddl ( sqlite_exec db `CREATE TABLE z (id INTEGER)` )
    ?? ddl { F e → ( fail `ddl_z` e ) T _ → {} }

    : ( @ i i s s s s ) authcb \ i action s a s b s c s d → i {
        ? == action SQLITE_DROP_TABLE { ^ SQLITE_DENY } {}
        ^ SQLITE_OK
    }
    : !v SqliteErr sa ( sqlite_set_authorizer db authcb )
    ?? sa { F e → ( fail `set_auth` e ) T _ → {} }

    : !i SqliteErr dr ( sqlite_exec db `DROP TABLE z` )
    ?? dr {
        F e → { ( nurl_print `drop_denied=` ) ( nurl_print ( sqlite_err_name e ) ) ( nurl_print `\n` ) }
        T _ → { ( nurl_print `FAIL drop allowed by authorizer\n` ) }
    }

    : !v SqliteErr ca ( sqlite_clear_authorizer db )
    ?? ca { F e → ( fail `clear_auth` e ) T _ → {} }
    // After clearing, DROP is allowed again.
    : !i SqliteErr dr2 ( sqlite_exec db `DROP TABLE z` )
    ?? dr2 {
        F e → ( fail `drop_after_clear` e )
        T _ → { ( nurl_print `drop_after_clear=ok\n` ) }
    }
}

// #13 + #16(WAL) — harden + WAL on a file-backed DB.
@ test_harden_wal → v {
    : s path `/tmp/nurl_sqlite_t34.db`
    : !Database SqliteErr op ( sqlite_open path )
    ?? op {
        F e → ( fail `open_wal` e )
        T db → {
            : !v SqliteErr hd ( sqlite_harden db )
            ?? hd { F e → ( fail `harden` e ) T _ → { ( nurl_print `harden=ok\n` ) } }
            : !i SqliteErr w ( sqlite_journal_wal db )
            ?? w {
                F e → ( fail `wal` e )
                T _ → { ( nurl_print `wal=ok\n` ) }
            }
            : !i SqliteErr sy ( sqlite_synchronous db `NORMAL` )
            ?? sy { F e → ( fail `sync` e ) T _ → { ( nurl_print `sync=ok\n` ) } }
        }
    }
}

@ main → i {
    : !Database SqliteErr op ( sqlite_open `:memory:` )
    ?? op {
        F e → ( fail `open` e )
        T db → {
            ( test_double_null_rowid db )
            ( test_constraints db )
            ( test_transaction db )
            ( test_authorizer db )
            ( test_limit db )
        }
    }
    ( test_harden_wal )
    ( nurl_print `done\n` )
    ^ 0
}
