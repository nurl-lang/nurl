// packages/nurllama/src/history.nu — the conversation store (SQLite).
//
// Every chat a web client has with a model is persisted, scoped to the
// client's cookie GUID, in $NURLLAMA_HOME/history.db. Following the
// registry's proven idiom, the DB is opened FRESH per operation (its
// handle is `% Drop` and auto-closes at the arm's scope exit — never
// closed by hand) with WAL + a busy timeout, so concurrent requests
// serialise cheaply and nothing has to keep a Drop handle alive across
// the globals-are-scalars boundary. The schema is `IF NOT EXISTS`, so
// the first open on a fresh box creates it.
//
//   ( hist_db_path root )                          → String
//   ( hist_ensure_client path guid now )           → b
//   ( hist_new_conversation path guid model now )  → i   rowid, -1 on error
//   ( hist_add_message path conv role content now ) → b
//   ( hist_conversation_owner path conv )          → String  ("" = none)
//   ( hist_list_conversations path guid )          → Json  array
//   ( hist_get_messages path conv )                → Json  array
//   ( hist_rename_conversation path conv guid title ) → b
//   ( hist_delete_conversation path conv guid )    → b

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/sqlite.nu`

@ hist_db_path String root → String {
    ^ ( path_join ( string_data root ) `history.db` )
}

@ hist_now → i {
    ^ ( time_to_unix ( time_now ) )
}

// Open + harden + migrate. The Database is `% Drop`: the caller uses it
// inside the `??` arm and lets it auto-close — NEVER sqlite_close it.
@ hist_open s path → !Database SqliteErr {
    : !Database SqliteErr dr ( sqlite_open path )
    ?? dr {
        F e → ^ @ !Database SqliteErr { F e }
        T db → {
            ?? ( sqlite_busy_timeout db 5000 ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `PRAGMA journal_mode=WAL` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `PRAGMA foreign_keys=ON` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `CREATE TABLE IF NOT EXISTS clients (
                guid TEXT PRIMARY KEY,
                created_at INTEGER NOT NULL
            )` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                client_guid TEXT NOT NULL,
                model TEXT NOT NULL,
                title TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL
            )` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversation_id INTEGER NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at INTEGER NOT NULL
            )` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `CREATE INDEX IF NOT EXISTS idx_conv_client
                ON conversations (client_guid, id DESC)` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `CREATE INDEX IF NOT EXISTS idx_msg_conv
                ON messages (conversation_id, id)` ) { T _ → {} F _ → {} }
            ^ @ !Database SqliteErr { T db }
        }
    }
}

// Bind a text parameter from a raw string. sqlite_bind_text BORROWS its
// String (SQLITE_TRANSIENT copies the bytes at bind time), so the copy
// is freed right after — the registry idiom.
@ __hist_bind Statement st i idx s val → v {
    : String v ( string_from val )
    ?? ( sqlite_bind_text st idx v ) { T _ → {} F _ → {} }
    ( string_free v )
}

// Step a prepared statement to completion, ignoring rows. The Statement
// is `% Drop` (auto-finalised at arm exit) — do not finalise by hand.
@ __hist_run Statement st → b {
    : ~ b ok T
    : ~ b more T
    ~ more {
        ?? ( sqlite_step st ) {
            T has → { ? ! has { = more F } {} }
            F _ → { = ok F = more F }
        }
    }
    ^ ok
}

@ hist_ensure_client s path s guid i now → b {
    : ~ b ok F
    ?? ( hist_open path ) {
        T db → {
            ?? ( sqlite_prepare db `INSERT OR IGNORE INTO clients (guid, created_at) VALUES (?1, ?2)` ) {
                T st → {
                    ( __hist_bind st 1 guid )
                    ?? ( sqlite_bind_int st 2 now ) { T _ → {} F _ → {} }
                    = ok ( __hist_run st )
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ ok
}

@ hist_new_conversation s path s guid s model i now → i {
    : ~ i rowid -1
    ?? ( hist_open path ) {
        T db → {
            ?? ( sqlite_prepare db `INSERT INTO conversations (client_guid, model, title, created_at)
                VALUES (?1, ?2, '', ?3)` ) {
                T st → {
                    ( __hist_bind st 1 guid )
                    ( __hist_bind st 2 model )
                    ?? ( sqlite_bind_int st 3 now ) { T _ → {} F _ → {} }
                    ? ( __hist_run st ) { = rowid ( sqlite_last_insert_rowid db ) } {}
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ rowid
}

@ hist_add_message s path i conv s role s content i now → b {
    : ~ b ok F
    ?? ( hist_open path ) {
        T db → {
            ?? ( sqlite_prepare db `INSERT INTO messages (conversation_id, role, content, created_at)
                VALUES (?1, ?2, ?3, ?4)` ) {
                T st → {
                    ?? ( sqlite_bind_int st 1 conv ) { T _ → {} F _ → {} }
                    ( __hist_bind st 2 role )
                    ( __hist_bind st 3 content )
                    ?? ( sqlite_bind_int st 4 now ) { T _ → {} F _ → {} }
                    = ok ( __hist_run st )
                    // A conversation with no title yet takes the first user
                    // message's opening as its title (trimmed to 60 chars) —
                    // done here so the sidebar has a label without a round trip.
                    ? & ok != 0 ( nurl_str_eq role `user` ) {
                        ( __hist_title_if_empty db conv content now )
                    } {}
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ ok
}

// Set the conversation title from `content` (first 60 chars) only when
// it is still blank.
@ __hist_title_if_empty Database db i conv s content i now → v {
    : String title ( string_new )
    : i n ( nurl_str_len content )
    : i take ? < n 60 n 60
    : ~ i k 0
    ~ < k take {
        : i c ( nurl_str_get content k )
        ( string_push_char title ? | == c 10 == c 13 32 c )
        = k + k 1
    }
    ? > n 60 { ( string_push_str title `…` ) } {}
    ?? ( sqlite_prepare db `UPDATE conversations SET title = ?1
        WHERE id = ?2 AND title = ''` ) {
        T st → {
            ?? ( sqlite_bind_text st 1 title ) { T _ → {} F _ → {} }
            ?? ( sqlite_bind_int st 2 conv ) { T _ → {} F _ → {} }
            : b _r ( __hist_run st )
        }
        F _ → {}
    }
    ( string_free title )
}

// The GUID that owns `conv`, or "" when the conversation does not exist.
// The web layer checks this before returning any conversation's contents.
@ hist_conversation_owner s path i conv → String {
    : ~ String owner ( string_new )
    ?? ( hist_open path ) {
        T db → {
            ?? ( sqlite_prepare db `SELECT client_guid FROM conversations WHERE id = ?1` ) {
                T st → {
                    ?? ( sqlite_bind_int st 1 conv ) { T _ → {} F _ → {} }
                    ?? ( sqlite_step st ) {
                        T has → {
                            ? has {
                                ( string_free owner )
                                = owner ( sqlite_column_text st 0 )
                            } {}
                        }
                        F _ → {}
                    }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ owner
}

// A JSON array of this client's conversations, newest first:
//   [ { "id":N, "model":"…", "title":"…", "created_at":T }, … ]
@ hist_list_conversations s path s guid → Json {
    : Json arr ( json_arr_new )
    ?? ( hist_open path ) {
        T db → {
            ?? ( sqlite_prepare db `SELECT id, model, title, created_at
                FROM conversations WHERE client_guid = ?1 ORDER BY id DESC` ) {
                T st → {
                    ( __hist_bind st 1 guid )
                    : ~ b more T
                    ~ more {
                        ?? ( sqlite_step st ) {
                            T has → {
                                ? has {
                                    : Json o ( json_obj_new )
                                    : b _1 ( json_obj_set o `id` ( json_int ( sqlite_column_int st 0 ) ) )
                                    : String md ( sqlite_column_text st 1 )
                                    : b _2 ( json_obj_set o `model` ( json_str_lit ( string_data md ) ) )
                                    ( string_free md )
                                    : String tt ( sqlite_column_text st 2 )
                                    : b _3 ( json_obj_set o `title` ( json_str_lit ( string_data tt ) ) )
                                    ( string_free tt )
                                    : b _4 ( json_obj_set o `created_at` ( json_int ( sqlite_column_int st 3 ) ) )
                                    : b _5 ( json_arr_push arr o )
                                } { = more F }
                            }
                            F _ → { = more F }
                        }
                    }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ arr
}

// A JSON array of a conversation's messages in order:
//   [ { "role":"user|assistant", "content":"…", "created_at":T }, … ]
@ hist_get_messages s path i conv → Json {
    : Json arr ( json_arr_new )
    ?? ( hist_open path ) {
        T db → {
            ?? ( sqlite_prepare db `SELECT role, content, created_at
                FROM messages WHERE conversation_id = ?1 ORDER BY id` ) {
                T st → {
                    ?? ( sqlite_bind_int st 1 conv ) { T _ → {} F _ → {} }
                    : ~ b more T
                    ~ more {
                        ?? ( sqlite_step st ) {
                            T has → {
                                ? has {
                                    : Json o ( json_obj_new )
                                    : String rl ( sqlite_column_text st 0 )
                                    : b _1 ( json_obj_set o `role` ( json_str_lit ( string_data rl ) ) )
                                    ( string_free rl )
                                    : String ct ( sqlite_column_text st 1 )
                                    : b _2 ( json_obj_set o `content` ( json_str_lit ( string_data ct ) ) )
                                    ( string_free ct )
                                    : b _3 ( json_obj_set o `created_at` ( json_int ( sqlite_column_int st 2 ) ) )
                                    : b _4 ( json_arr_push arr o )
                                } { = more F }
                            }
                            F _ → { = more F }
                        }
                    }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ arr
}

// Delete a conversation and its messages — only when `guid` owns it.
@ hist_delete_conversation s path i conv s guid → b {
    : ~ b ok F
    : String owner ( hist_conversation_owner path conv )
    : b owns ( nurl_str_eq ( string_data owner ) guid )
    ( string_free owner )
    ? owns {} { ^ F }
    ?? ( hist_open path ) {
        T db → {
            ?? ( sqlite_prepare db `DELETE FROM messages WHERE conversation_id = ?1` ) {
                T st → {
                    ?? ( sqlite_bind_int st 1 conv ) { T _ → {} F _ → {} }
                    : b _r ( __hist_run st )
                }
                F _ → {}
            }
            ?? ( sqlite_prepare db `DELETE FROM conversations WHERE id = ?1` ) {
                T st → {
                    ?? ( sqlite_bind_int st 1 conv ) { T _ → {} F _ → {} }
                    = ok ( __hist_run st )
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ ok
}
