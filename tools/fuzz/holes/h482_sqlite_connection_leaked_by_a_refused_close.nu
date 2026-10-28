// H482: `sqlite_close` of a connection with a live statement cleared the
// handle's sqlite3* although sqlite3_close had refused (SQLITE_BUSY):
// nothing closed the connection after that.
// Closed: the close is sqlite3_close_v2's — the connection is released
// when its last statement is finalized.
// v0.80.0: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`
$ `stdlib/ext/sqlite.nu`

@ main → i {
    ?? ( sqlite_open `:memory:` ) {
        T db → {
            ?? ( sqlite_prepare db `SELECT 1` ) {
                T st → {
                    ( sqlite_close db )
                    ?? ( sqlite_step st ) { T b → { ( nurl_println_int ( sqlite_column_int st 0 ) ) } F e → {} }
                }
                F e → {}
            }
        }
        F e → {}
    }
    ^ 0
}
