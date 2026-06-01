// sqlite_hardening.nu — Tier 1/Tier 2 regression for stdlib/ext/sqlite.nu.
//
// Covers the production-hardening work:
//   * BLOB round-trip (bind_blob / column_blob, exact bytes incl. NUL)
//   * embedded-NUL TEXT round-trip (column_text uses column_bytes, not
//     strlen — so "a\0b" survives as 3 bytes, not 1)
//   * busy_timeout set succeeds
//   * read-only open (sqlite_open_v2 + SQLITE_OPEN_READONLY) refuses a
//     write — surfaces SqliteReadOnly rather than silently creating
//   * auto-drop: every handle below is a scope-local match-arm binding;
//     NONE is closed by hand. Run under ./build.sh --san to prove the
//     Drop trait releases them with no leak and no double free.
//
// Offline (no network gate) — sqlite3 is purely in-process.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/sqlite.nu`

@ fail s tag SqliteErr e → v {
    ( nurl_print `FAIL ` ) ( nurl_print tag )
    ( nurl_print `=` ) ( nurl_print ( sqlite_err_name e ) ) ( nurl_print `\n` )
}

// Build a 3-byte text value "a\0b" with an embedded NUL.
@ make_nul_text → String {
    : String s ( string_with_cap 8 )
    ( string_push_char s 97 )  // 'a'
    ( string_push_char s 0 )   // NUL
    ( string_push_char s 98 )  // 'b'
    ^ s
}

// Build a 5-byte blob [0x00 0x01 0x02 0xFF 0x00].
@ make_blob → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] 5 )
    ( vec_push [u] v # u 0x00 )
    ( vec_push [u] v # u 0x01 )
    ( vec_push [u] v # u 0x02 )
    ( vec_push [u] v # u 0xFF )
    ( vec_push [u] v # u 0x00 )
    ^ v
}

@ test_blob_and_nul → v {
    : !Database SqliteErr op ( sqlite_open `:memory:` )
    ?? op {
        F e → ( fail `open` e )
        T db → {
            // busy_timeout is harmless on :memory: but must succeed.
            : !v SqliteErr bt ( sqlite_busy_timeout db 2000 )
            ?? bt { F e → ( fail `busy_timeout` e ) T _ → {} }

            : !i SqliteErr ddl ( sqlite_exec db `CREATE TABLE t (id INTEGER PRIMARY KEY, txt TEXT, blob BLOB)` )
            ?? ddl { F e → ( fail `ddl` e ) T _ → {} }

            : !Statement SqliteErr ins_r ( sqlite_prepare db `INSERT INTO t (id, txt, blob) VALUES (1, ?1, ?2)` )
            ?? ins_r {
                F e → ( fail `prepare_ins` e )
                T ins → {
                    : String txt ( make_nul_text )
                    : ( Vec u ) blob ( make_blob )
                    : !v SqliteErr b1 ( sqlite_bind_text ins 1 txt )
                    ?? b1 { F e → ( fail `bind_text` e ) T _ → {} }
                    : !v SqliteErr b2 ( sqlite_bind_blob ins 2 blob )
                    ?? b2 { F e → ( fail `bind_blob` e ) T _ → {} }
                    : !b SqliteErr st ( sqlite_step ins )
                    ?? st { F e → ( fail `step_ins` e ) T _ → {} }
                    ( string_free txt )
                    ( vec_free [u] blob )
                    // `ins` auto-finalizes here.
                }
            }

            : !Statement SqliteErr q_r ( sqlite_prepare db `SELECT txt, blob FROM t WHERE id = 1` )
            ?? q_r {
                F e → ( fail `prepare_sel` e )
                T q → {
                    : !b SqliteErr st ( sqlite_step q )
                    ?? st {
                        F e → ( fail `step_sel` e )
                        T has_row → {
                            ? has_row {
                                : String txt ( sqlite_column_text q 0 )
                                ( nurl_print `txt_len=` )
                                ( nurl_print ( nurl_str_int ( string_len txt ) ) )
                                ( nurl_print ` (expect 3)\n` )
                                ( string_free txt )
                                : ( Vec u ) blob ( sqlite_column_blob q 1 )
                                ( nurl_print `blob_len=` )
                                ( nurl_print ( nurl_str_int ( vec_len [u] blob ) ) )
                                ( nurl_print ` (expect 5)\n` )
                                : ?u b3 ( vec_get [u] blob 3 )
                                ?? b3 {
                                    T byte → {
                                        ( nurl_print `blob[3]=` )
                                        ( nurl_print ( nurl_str_int # i byte ) )
                                        ( nurl_print ` (expect 255)\n` )
                                    }
                                    F → { ( nurl_print `blob[3]=missing\n` ) }
                                }
                                ( vec_free [u] blob )
                            } { ( nurl_print `FAIL no row\n` ) }
                        }
                    }
                    // `q` auto-finalizes here.
                }
            }
            // `db` auto-closes here.
        }
    }
}

// Read-only open must refuse a write rather than create/insert.
@ test_readonly → v {
    : s path `/tmp/nurl_sqlite_ro_test.db`
    // Set up: create the DB read/write, then it auto-closes.
    : !Database SqliteErr setup ( sqlite_open path )
    ?? setup {
        F e → ( fail `ro_setup_open` e )
        T db → {
            : !i SqliteErr ddl ( sqlite_exec db `CREATE TABLE IF NOT EXISTS k (v INTEGER)` )
            ?? ddl { F e → ( fail `ro_setup_ddl` e ) T _ → {} }
        }
    }
    // Re-open read-only; a write must error.
    : !Database SqliteErr ro ( sqlite_open_v2 path SQLITE_OPEN_READONLY )
    ?? ro {
        F e → ( fail `ro_open` e )
        T db → {
            : !i SqliteErr w ( sqlite_exec db `INSERT INTO k (v) VALUES (1)` )
            ?? w {
                F e → {
                    ( nurl_print `readonly_write_blocked=` )
                    ( nurl_print ( sqlite_err_name e ) )
                    ( nurl_print `\n` )
                }
                T _ → { ( nurl_print `FAIL readonly write SUCCEEDED\n` ) }
            }
        }
    }
}

@ main → i {
    ( test_blob_and_nul )
    ( test_readonly )
    ( nurl_print `done\n` )
    ^ 0
}
