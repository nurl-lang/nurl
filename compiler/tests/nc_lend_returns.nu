// A value that is dropped but cannot be copied (a sqlite Database) and is
// LENT — read out of a parameter's field (`^ . h db`), or the payload of
// `?? . st db { T d → … }` — stays with its owner: the caller, or the arm,
// must not close it. Both did, and the next use of the owner's handle read
// freed memory. A function lending such a value on one path and opening a
// fresh one on another answers per call (the lend-back of a per-operation
// connection). A struct field `?Database` is dropped with its struct — it
// was never, and every connection leaked. Run under the sanitizer corpus.
$ `stdlib/core/string.nu`
$ `stdlib/ext/sqlite.nu`

: Holder {
    Database db
}

// (a) a parameter's field handed back: a lend
@ get Holder h → Database { ^ . h db }

@ use_get Holder h → i {
    : Database d ( get h )
    ?? ( sqlite_exec d `SELECT 1` ) { T _ → { ^ 1 } F _ → { ^ 0 } }
}

: Store {
    String path
    ? Database db  // an open connection to lend; None = open one per use
}

// (b) lends the store's connection, or opens a fresh one
@ conn Store st → !Database SqliteErr {
    ?? . st db {
        T d → { ^ @ !Database SqliteErr { T d } }
        F → {}
    }
    ^ ( sqlite_open ( string_data . st path ) )
}

@ with_conn Store st → Store {
    ?? ( sqlite_open ( string_data . st path ) ) {
        T d → { ^ @ Store { ( string_from ( string_data . st path ) ) @ ?Database { T d } } }
        F _ → {}
    }
    ^ @ Store { ( string_from ( string_data . st path ) ) @ ?Database { F } }
}

@ make_temp Store st → b {
    ?? ( conn st ) {
        T db → { ?? ( sqlite_exec db `CREATE TEMP TABLE IF NOT EXISTS t (x)` ) { T _ → { ^ T } F _ → { ^ F } } }
        F _ → {}
    }
    ^ F
}

// T only on the connection make_temp used: a TEMP table is per connection
@ sees_temp Store st → b {
    ?? ( conn st ) {
        T db → { ?? ( sqlite_exec db `INSERT INTO t VALUES (1)` ) { T _ → { ^ T } F _ → { ^ F } } }
        F _ → {}
    }
    ^ F
}

@ main → i {
    ?? ( sqlite_open `:memory:` ) {
        T db → {
            : Holder h @ Holder { db }
            : i a ( use_get h )
            : i b ( use_get h )
            ( nurl_println ( string_data ( string_from ? == + a b 2 `accessor: the owner's handle survives` `accessor: WRONG` ) ) )
        }
        F _ → {}
    }
    : Store base @ Store { ( string_from `:memory:` ) @ ?Database { F } }
    : ~ i shared 0
    : ~ i fresh 0
    : ~ i k 0
    ~ < k 20 {
        : Store s ( with_conn base )
        ? & ( make_temp s ) ( sees_temp s ) { = shared + shared 1 } {}
        ? & ( make_temp base ) ( sees_temp base ) { = fresh + fresh 1 } {}
        = k + k 1
    }
    ( nurl_println ( string_data ( string_from ? & == shared 20 == fresh 0 `lend-back: one connection per store, a fresh one each use otherwise` `lend-back: WRONG` ) ) )
    ^ 0
}
