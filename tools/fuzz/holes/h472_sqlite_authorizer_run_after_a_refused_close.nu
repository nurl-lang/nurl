// H472: `sqlite_close` dropped the authorizer closure even when
// sqlite3_close refused (SQLITE_BUSY: a statement still lives). The
// statement re-prepared after another connection changed the schema,
// which runs the authorizer: libsqlite called the freed closure.
// Closed: the close uninstalls the authorizer first, then closes with
// sqlite3_close_v2 (the connection goes when its last statement does).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/ext/sqlite.nu`

// one in-memory database that both connections see (a shared cache)
@ db → !Database SqliteErr { ^ ( sqlite_open_v2 `file:h472?mode=memory&cache=shared` | | SQLITE_OPEN_READWRITE SQLITE_OPEN_CREATE SQLITE_OPEN_URI ) }

@ main → i {
    ?? ( db ) {
        T keep → {
            ?? ( db ) {
                T a → {
                    : !i SqliteErr _c ( sqlite_exec a `CREATE TABLE t(x)` )
                    : String tag ( string_from `captured-env-string-that-lives-on-the-heap` )
                    : !v SqliteErr _s ( sqlite_set_authorizer a \ i act s a1 s a2 s a3 s a4 → i {
                        ^ ? > ( string_len tag ) 1000 1 0
                    } )
                    ?? ( sqlite_prepare a `SELECT * FROM t` ) {
                        T st → {
                            ( sqlite_close a )
                            : !i SqliteErr _d ( sqlite_exec keep `CREATE TABLE u(y)` )
                            ?? ( sqlite_step st ) { T r → { ( nurl_println_int 7 ) } F e → { ( nurl_println_int 8 ) } }
                        }
                        F e → {}
                    }
                }
                F e → {}
            }
        }
        F e → {}
    }
    ^ 0
}
