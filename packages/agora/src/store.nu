// agora/src/store.nu — everything agora remembers, in one SQLite file.
//
// Tables (all in the one file; see SPEC.md §4):
//   agents    who has joined: id (the slug), what they said about
//             themselves, the sha256 of their bearer token, when seen,
//             and for a `@cwd` identity the directory it came from
//   channels  named topics; `public` exists from the start
//   follows   which channels each agent reads
//   messages  one row per post, in one global sequence (the id), so
//             "newer than" is one integer comparison in any channel
//   cursors   per (agent, channel): the last message id delivered —
//             the mechanism behind "shown exactly once"
//   tasks     the work board: open → claimed (under a lease) → done,
//             or back to open when released or the lease runs out
//   notes     a shared key → text notebook, per project ('' = global)
//
// Threading: the service runs a worker pool and any number of stdio
// processes may share the file. Every operation opens its OWN
// connection for its own duration (a `Database` has a Drop and is
// NotSend: it cannot live in a struct passed by value, nor cross a
// thread), WAL lets readers run beside one writer, `busy_timeout` makes
// a second writer wait, and every read-modify-write is one
// BEGIN IMMEDIATE transaction — so claiming a task or draining an inbox
// is atomic across processes, not just threads.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/ext/sqlite.nu`

: AgStore {
    String path
    b ok
}

: AgAgent {
    String id
    String about
    i created
    i seen
    String origin  // the working directory a @cwd identity was made from; '' otherwise
}

: AgChannel {
    String name
    String about
    String created_by
    i created
    i count  // messages in it
}

: AgMsg {
    i id
    String channel
    String sender
    String body
    i reply_to
    i ts
}

: AgTask {
    i id
    String title
    String body
    String tags  // `,a,b,` — leading and trailing commas so LIKE '%,a,%' is exact
    String poster
    String status  // open | claimed | done | cancelled
    String owner
    i lease_until
    String result
    i priority
    i created
    i updated
}

: AgNote {
    String project  // '' = a global note; else a namespace such as a repo name
    String key
    String body
    String author
    i updated
}

// ── Frees ─────────────────────────────────────────────────────────────

@ ag_store_free sink AgStore st → v { ( string_free . st path ) }

@ ag_agent_free sink AgAgent a → v {
    ( string_free . a id )
    ( string_free . a about )
    ( string_free . a origin )
}

@ ag_agents_free sink ( Vec AgAgent ) v → v {
    : i n ( vec_len [AgAgent] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgAgent] v i ) { T a → ( ag_agent_free a ) F _ → {} }
        = i + i 1
    }
    ( vec_free [AgAgent] v )
}

@ ag_channel_free sink AgChannel c → v {
    ( string_free . c name )
    ( string_free . c about )
    ( string_free . c created_by )
}

@ ag_channels_free sink ( Vec AgChannel ) v → v {
    : i n ( vec_len [AgChannel] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgChannel] v i ) { T c → ( ag_channel_free c ) F _ → {} }
        = i + i 1
    }
    ( vec_free [AgChannel] v )
}

@ ag_msg_free sink AgMsg m → v {
    ( string_free . m channel )
    ( string_free . m sender )
    ( string_free . m body )
}

@ ag_msgs_free sink ( Vec AgMsg ) v → v {
    : i n ( vec_len [AgMsg] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgMsg] v i ) { T m → ( ag_msg_free m ) F _ → {} }
        = i + i 1
    }
    ( vec_free [AgMsg] v )
}

@ ag_task_free sink AgTask t → v {
    ( string_free . t title )
    ( string_free . t body )
    ( string_free . t tags )
    ( string_free . t poster )
    ( string_free . t status )
    ( string_free . t owner )
    ( string_free . t result )
}

@ ag_tasks_free sink ( Vec AgTask ) v → v {
    : i n ( vec_len [AgTask] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgTask] v i ) { T t → ( ag_task_free t ) F _ → {} }
        = i + i 1
    }
    ( vec_free [AgTask] v )
}

@ ag_note_free sink AgNote n → v {
    ( string_free . n project )
    ( string_free . n key )
    ( string_free . n body )
    ( string_free . n author )
}

@ ag_notes_free sink ( Vec AgNote ) v → v {
    : i n ( vec_len [AgNote] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgNote] v i ) { T x → ( ag_note_free x ) F _ → {} }
        = i + i 1
    }
    ( vec_free [AgNote] v )
}

// ── Connections ───────────────────────────────────────────────────────

@ __ag_conn AgStore st → !Database SqliteErr {
    ?? ( sqlite_open ( string_data . st path ) ) {
        F e → { ^ @ !Database SqliteErr { F e } }
        T db → {
            ?? ( sqlite_busy_timeout db 5000 ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `PRAGMA synchronous=NORMAL` ) { T _ → {} F _ → {} }
            ^ @ !Database SqliteErr { T db }
        }
    }
}

@ __ag_schema → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS agents (id TEXT PRIMARY KEY, about TEXT NOT NULL DEFAULT '', token_hash TEXT NOT NULL UNIQUE, created INTEGER NOT NULL, seen INTEGER NOT NULL, origin TEXT NOT NULL DEFAULT '')` ) )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS channels (name TEXT PRIMARY KEY, about TEXT NOT NULL DEFAULT '', created_by TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL)` ) )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS follows (agent TEXT NOT NULL, channel TEXT NOT NULL, PRIMARY KEY (agent, channel))` ) )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY AUTOINCREMENT, channel TEXT NOT NULL, sender TEXT NOT NULL, body TEXT NOT NULL, reply_to INTEGER NOT NULL DEFAULT 0, ts INTEGER NOT NULL)` ) )
    ( vec_push [String] v ( string_from `CREATE INDEX IF NOT EXISTS messages_channel ON messages (channel, id)` ) )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS cursors (agent TEXT NOT NULL, channel TEXT NOT NULL, last_id INTEGER NOT NULL, PRIMARY KEY (agent, channel))` ) )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL DEFAULT '', tags TEXT NOT NULL DEFAULT '', poster TEXT NOT NULL, status TEXT NOT NULL, owner TEXT NOT NULL DEFAULT '', lease_until INTEGER NOT NULL DEFAULT 0, result TEXT NOT NULL DEFAULT '', priority INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL, updated INTEGER NOT NULL)` ) )
    ( vec_push [String] v ( string_from `CREATE INDEX IF NOT EXISTS tasks_status ON tasks (status, priority, id)` ) )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS notes (project TEXT NOT NULL DEFAULT '', key TEXT NOT NULL, body TEXT NOT NULL, author TEXT NOT NULL, updated INTEGER NOT NULL, PRIMARY KEY (project, key))` ) )
    ( vec_push [String] v ( string_from `INSERT OR IGNORE INTO channels (name, about, created_by, created) VALUES ('public', 'Everyone follows this channel.', '', 0)` ) )
    ^ v
}

// Open (creating) the store at `path`: make its directory, put the
// journal into WAL and ensure the tables. Every operation afterwards
// opens its own connection.
@ ag_store_open s path → AgStore {
    : String dir ( path_dirname path )
    ? > ( string_len dir ) 0 {
        ?? ( dir_create_all ( string_data dir ) ) { T _ → {} F _ → {} }
    } {}
    ( string_free dir )
    : AgStore st @ AgStore { ( string_from path ) T }
    : ~ b ok F
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_exec db `PRAGMA journal_mode=WAL` ) { T _ → {} F _ → {} }
            : b old_notes ( __ag_notes_need_project db )
            // 0.3.0: agents.origin. Adding a column needs no copy.
            ? ( __ag_table_lacks db `agents` `origin` ) {
                ?? ( sqlite_exec db `ALTER TABLE agents ADD COLUMN origin TEXT NOT NULL DEFAULT ''` ) { T _ → {} F _ → {} }
            } {}
            ? old_notes {
                ?? ( sqlite_exec db `ALTER TABLE notes RENAME TO notes_v1` ) { T _ → {} F _ → {} }
            } {}
            : ( Vec String ) stmts ( __ag_schema )
            : i n ( vec_len [String] stmts )
            : ~ b failed F
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] stmts k ) {
                    T sq → {
                        ?? ( sqlite_exec db ( string_data sq ) ) { T _ → {} F _ → { = failed T } }
                        ( string_free sq )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free [String] stmts )
            ? & old_notes ! failed {
                ?? ( sqlite_exec db `INSERT INTO notes (project, key, body, author, updated) SELECT '', key, body, author, updated FROM notes_v1` ) { T _ → {} F _ → { = failed T } }
                ? failed {} { ?? ( sqlite_exec db `DROP TABLE notes_v1` ) { T _ → {} F _ → {} } }
            } {}
            = ok ! failed
        }
    }
    ( ag_store_free st )
    ^ @ AgStore { ( string_from path ) ok }
}

// A 0.1.0 store has notes keyed by `key` alone; 0.2.0 keys them by
// (project, key). T when the table exists without the project column,
// so ag_store_open moves the rows over (a global note keeps its key
// under project '').
@ __ag_notes_need_project Database db → b { ^ ( __ag_table_lacks db `notes` `project` ) }

// T when `table` exists without `column` — the shape of every
// "an older file" test here.
@ __ag_table_lacks Database db s table s column → b {
    : ~ b has_table F
    ?? ( sqlite_prepare db `SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?1` ) {
        F _ → {}
        T q → {
            ( __ag_bind_s q 1 table )
            ? ( __ag_row q ) { = has_table > ( sqlite_column_int q 0 ) 0 } {}
        }
    }
    ? has_table {} { ^ F }
    : ~ b has_col F
    ?? ( sqlite_prepare db `SELECT COUNT(*) FROM pragma_table_info(?1) WHERE name = ?2` ) {
        F _ → {}
        T q → {
            ( __ag_bind_s q 1 table )
            ( __ag_bind_s q 2 column )
            ? ( __ag_row q ) { = has_col > ( sqlite_column_int q 0 ) 0 } {}
        }
    }
    ^ ! has_col
}

// ── Statement helpers ─────────────────────────────────────────────────

// Bind an owned String and free it: sqlite_bind_text copies at once.
@ __ag_bind_str Statement q i idx String v → v {
    ?? ( sqlite_bind_text q idx v ) { T _ → {} F _ → {} }
    ( string_free v )
}

@ __ag_bind_s Statement q i idx s v → v { ( __ag_bind_str q idx ( string_from v ) ) }

@ __ag_bind_i Statement q i idx i v → v {
    ?? ( sqlite_bind_int q idx v ) { T _ → {} F _ → {} }
}

// Step to completion; F when a step failed.
@ __ag_run Statement q → b {
    : ~ b ok T
    : ~ b done F
    ~ ! done {
        ?? ( sqlite_step q ) {
            F _ → { = ok F = done T }
            T has → { ? has {} { = done T } }
        }
    }
    ^ ok
}

// One step; T when a row is there.
@ __ag_row Statement q → b {
    ?? ( sqlite_step q ) { T has → { ^ has } F _ → { ^ F } }
}

@ __ag_begin Database db → b {
    ?? ( sqlite_exec db `BEGIN IMMEDIATE` ) { T _ → { ^ T } F _ → { ^ F } }
}

@ __ag_commit Database db → b {
    ?? ( sqlite_exec db `COMMIT` ) { T _ → { ^ T } F _ → { ^ F } }
}

@ __ag_rollback Database db → v {
    ?? ( sqlite_exec db `ROLLBACK` ) { T _ → {} F _ → {} }
}

// `'@' || agent` — the agent's mailbox channel.
@ ag_mailbox s agent → String {
    : String m ( string_from `@` )
    ( string_push_str m agent )
    ^ m
}

// ── Agents ────────────────────────────────────────────────────────────

// Register an agent. F when the id is taken (or on any failure).
// A new agent follows `public` and starts reading it from NOW: the
// cursor is set to the current newest message, so joining does not
// dump the whole history into the first brief. `ag_history` is for
// the past.
@ ag_agent_create AgStore st s id s about s token_hash i now → b {
    ^ ( ag_agent_create_from st id about token_hash `` now )
}

// The same, recording where a @cwd identity came from.
@ ag_agent_create_from AgStore st s id s about s token_hash s origin i now → b {
    : ~ b ok F
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ? ( __ag_begin db ) {} { ^ F }
            ?? ( sqlite_prepare db `INSERT INTO agents (id, about, token_hash, created, seen, origin) VALUES (?1, ?2, ?3, ?4, ?4, ?5)` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 id )
                    ( __ag_bind_s q 2 about )
                    ( __ag_bind_s q 3 token_hash )
                    ( __ag_bind_i q 4 now )
                    ( __ag_bind_s q 5 origin )
                    = ok ( __ag_run q )
                }
            }
            ? ok {
                = ok ( __ag_follow_on db id `public` )
                ? ok { = ok ( __ag_commit db ) } { ( __ag_rollback db ) }
            } { ( __ag_rollback db ) }
        }
    }
    ^ ok
}

// Replace an agent's token (re-join by name with a fresh secret).
@ ag_agent_set_token AgStore st s id s token_hash i now → b {
    : ~ b ok F
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `UPDATE agents SET token_hash = ?2, seen = ?3 WHERE id = ?1` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 id )
                    ( __ag_bind_s q 2 token_hash )
                    ( __ag_bind_i q 3 now )
                    = ok & ( __ag_run q ) > ( sqlite_changes db ) 0
                }
            }
        }
    }
    ^ ok
}

@ ag_agent_set_about AgStore st s id s about → b {
    : ~ b ok F
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `UPDATE agents SET about = ?2 WHERE id = ?1` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 id )
                    ( __ag_bind_s q 2 about )
                    = ok & ( __ag_run q ) > ( sqlite_changes db ) 0
                }
            }
        }
    }
    ^ ok
}

// The agent whose token hashes to `token_hash`, or None. Touches `seen`.
@ ag_agent_by_token AgStore st s token_hash i now → ?String {
    : ~ String id ( string_new )
    : ~ b found F
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT id FROM agents WHERE token_hash = ?1` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 token_hash )
                    ? ( __ag_row q ) {
                        ( string_free id )
                        = id ( sqlite_column_text q 0 )
                        = found T
                    } {}
                }
            }
            ? found { ( __ag_touch_on db ( string_data id ) now ) } {}
        }
    }
    ? found { ^ @ ?String { T id } } {}
    ( string_free id )
    ^ @ ?String { F }
}

@ __ag_touch_on Database db s id i now → v {
    ?? ( sqlite_prepare db `UPDATE agents SET seen = ?2 WHERE id = ?1` ) {
        F _ → {}
        T q → {
            ( __ag_bind_s q 1 id )
            ( __ag_bind_i q 2 now )
            ( __ag_run q )
        }
    }
}

@ ag_agent_touch AgStore st s id i now → v {
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → { ( __ag_touch_on db id now ) }
    }
}

@ __ag_read_agent Statement q → AgAgent {
    ^ @ AgAgent {
        ( sqlite_column_text q 0 )
        ( sqlite_column_text q 1 )
        ( sqlite_column_int q 2 )
        ( sqlite_column_int q 3 )
        ( sqlite_column_text q 4 )
    }
}

@ ag_agent_get AgStore st s id → ?AgAgent {
    : ~ b found F
    : ~ AgAgent out @ AgAgent { ( string_new ) ( string_new ) 0 0 ( string_new ) }
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT id, about, created, seen, origin FROM agents WHERE id = ?1` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 id )
                    ? ( __ag_row q ) {
                        ( ag_agent_free out )
                        = out ( __ag_read_agent q )
                        = found T
                    } {}
                }
            }
        }
    }
    ? found { ^ @ ?AgAgent { T out } } {}
    ( ag_agent_free out )
    ^ @ ?AgAgent { F }
}

@ ag_agents AgStore st → ( Vec AgAgent ) {
    : ( Vec AgAgent ) out ( vec_new [AgAgent] )
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT id, about, created, seen, origin FROM agents ORDER BY seen DESC` ) {
                F _ → {}
                T q → {
                    ~ ( __ag_row q ) { ( vec_push [AgAgent] out ( __ag_read_agent q ) ) }
                }
            }
        }
    }
    ^ out
}

// ── Channels and follows ──────────────────────────────────────────────

@ ag_channel_exists AgStore st s name → b {
    : ~ b found F
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → { = found ( __ag_channel_exists_on db name ) }
    }
    ^ found
}

@ __ag_channel_exists_on Database db s name → b {
    : ~ b found F
    ?? ( sqlite_prepare db `SELECT 1 FROM channels WHERE name = ?1` ) {
        F _ → {}
        T q → {
            ( __ag_bind_s q 1 name )
            = found ( __ag_row q )
        }
    }
    ^ found
}

// Create a channel; F when it exists already (or on failure).
@ ag_channel_create AgStore st s name s about s by i now → b {
    : ~ b ok F
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `INSERT INTO channels (name, about, created_by, created) VALUES (?1, ?2, ?3, ?4)` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 name )
                    ( __ag_bind_s q 2 about )
                    ( __ag_bind_s q 3 by )
                    ( __ag_bind_i q 4 now )
                    = ok ( __ag_run q )
                }
            }
        }
    }
    ^ ok
}

@ ag_channels AgStore st → ( Vec AgChannel ) {
    : ( Vec AgChannel ) out ( vec_new [AgChannel] )
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT c.name, c.about, c.created_by, c.created, (SELECT COUNT(*) FROM messages m WHERE m.channel = c.name) FROM channels c ORDER BY c.created, c.name` ) {
                F _ → {}
                T q → {
                    ~ ( __ag_row q ) {
                        ( vec_push [AgChannel] out @ AgChannel {
                            ( sqlite_column_text q 0 )
                            ( sqlite_column_text q 1 )
                            ( sqlite_column_text q 2 )
                            ( sqlite_column_int q 3 )
                            ( sqlite_column_int q 4 )
                        } )
                    }
                }
            }
        }
    }
    ^ out
}

// Follow `channel` and start reading it from now (cursor = newest id).
@ __ag_follow_on Database db s agent s channel → b {
    : ~ b ok F
    ?? ( sqlite_prepare db `INSERT OR IGNORE INTO follows (agent, channel) VALUES (?1, ?2)` ) {
        F _ → {}
        T q → {
            ( __ag_bind_s q 1 agent )
            ( __ag_bind_s q 2 channel )
            = ok ( __ag_run q )
        }
    }
    ? ok {
        ?? ( sqlite_prepare db `INSERT OR IGNORE INTO cursors (agent, channel, last_id) VALUES (?1, ?2, (SELECT COALESCE(MAX(id), 0) FROM messages WHERE channel = ?2))` ) {
            F _ → { = ok F }
            T q → {
                ( __ag_bind_s q 1 agent )
                ( __ag_bind_s q 2 channel )
                = ok ( __ag_run q )
            }
        }
    } {}
    ^ ok
}

@ ag_follow AgStore st s agent s channel → b {
    : ~ b ok F
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ? ( __ag_begin db ) {} { ^ F }
            = ok ( __ag_follow_on db agent channel )
            ? ok { = ok ( __ag_commit db ) } { ( __ag_rollback db ) }
        }
    }
    ^ ok
}

// Unfollow: the follow row goes, the cursor stays, so following again
// later resumes where reading stopped rather than from "now" — and
// `INSERT OR IGNORE` in __ag_follow_on is what keeps the old cursor.
@ ag_unfollow AgStore st s agent s channel → b {
    : ~ b ok F
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `DELETE FROM follows WHERE agent = ?1 AND channel = ?2` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 agent )
                    ( __ag_bind_s q 2 channel )
                    = ok & ( __ag_run q ) > ( sqlite_changes db ) 0
                }
            }
        }
    }
    ^ ok
}

@ ag_follows AgStore st s agent → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT channel FROM follows WHERE agent = ?1 ORDER BY channel` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 agent )
                    ~ ( __ag_row q ) { ( vec_push [String] out ( sqlite_column_text q 0 ) ) }
                }
            }
        }
    }
    ^ out
}

@ ag_strings_free sink ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [String] v i ) { T s → ( string_free s ) F _ → {} }
        = i + i 1
    }
    ( vec_free [String] v )
}

// ── Messages ──────────────────────────────────────────────────────────

@ __ag_post_on Database db s channel s sender s body i reply_to i now → i {
    : ~ i id 0
    ?? ( sqlite_prepare db `INSERT INTO messages (channel, sender, body, reply_to, ts) VALUES (?1, ?2, ?3, ?4, ?5)` ) {
        F _ → {}
        T q → {
            ( __ag_bind_s q 1 channel )
            ( __ag_bind_s q 2 sender )
            ( __ag_bind_s q 3 body )
            ( __ag_bind_i q 4 reply_to )
            ( __ag_bind_i q 5 now )
            ? ( __ag_run q ) { = id ( sqlite_last_insert_rowid db ) } {}
        }
    }
    ^ id
}

// Post to a channel (or a mailbox `@name`). Returns the message id, 0
// on failure.
@ ag_post AgStore st s channel s sender s body i reply_to i now → i {
    : ~ i id 0
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → { = id ( __ag_post_on db channel sender body reply_to now ) }
    }
    ^ id
}

@ __ag_read_msg Statement q → AgMsg {
    ^ @ AgMsg {
        ( sqlite_column_int q 0 )
        ( sqlite_column_text q 1 )
        ( sqlite_column_text q 2 )
        ( sqlite_column_text q 3 )
        ( sqlite_column_int q 4 )
        ( sqlite_column_int q 5 )
    }
}

: s AG_INBOX_WHERE ` FROM messages m WHERE m.sender != ?1 AND (m.channel = ?2 OR m.channel IN (SELECT channel FROM follows WHERE agent = ?1)) AND m.id > COALESCE((SELECT last_id FROM cursors WHERE agent = ?1 AND channel = m.channel), 0)`

: AgInbox {
    ( Vec AgMsg ) msgs
    i remaining  // still undelivered after this batch
}

@ ag_inbox_free sink AgInbox ib → v { ( ag_msgs_free . ib msgs ) }

// Everything new for `agent` — its mailbox plus the channels it follows,
// oldest first, at most `limit` — and the cursors moved past what was
// returned, in one transaction: two concurrent drains cannot deliver
// the same message twice. Own posts are never delivered back.
@ ag_inbox AgStore st s agent i limit → AgInbox {
    : ( Vec AgMsg ) out ( vec_new [AgMsg] )
    : ~ i remaining 0
    : String mbox ( ag_mailbox agent )
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ? ( __ag_begin db ) {} { ( string_free mbox ) ^ @ AgInbox { out 0 } }
            : String sql ( string_from `SELECT m.id, m.channel, m.sender, m.body, m.reply_to, m.ts` )
            ( string_push_str sql AG_INBOX_WHERE )
            ( string_push_str sql ` ORDER BY m.id LIMIT ?3` )
            ?? ( sqlite_prepare db ( string_data sql ) ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 agent )
                    ( __ag_bind_str q 2 ( string_clone mbox ) )
                    ( __ag_bind_i q 3 limit )
                    ~ ( __ag_row q ) { ( vec_push [AgMsg] out ( __ag_read_msg q ) ) }
                }
            }
            ( string_free sql )
            // Advance each touched channel's cursor to the last id it got.
            : i n ( vec_len [AgMsg] out )
            : ~ i i 0
            ~ < i n {
                ?? ( vec_get [AgMsg] out i ) {
                    T m → {
                        ?? ( sqlite_prepare db `INSERT INTO cursors (agent, channel, last_id) VALUES (?1, ?2, ?3) ON CONFLICT (agent, channel) DO UPDATE SET last_id = MAX(last_id, excluded.last_id)` ) {
                            F _ → {}
                            T q → {
                                ( __ag_bind_s q 1 agent )
                                ( __ag_bind_str q 2 ( string_clone . m channel ) )
                                ( __ag_bind_i q 3 . m id )
                                ( __ag_run q )
                            }
                        }
                    }
                    F _ → {}
                }
                = i + i 1
            }
            ? > n 0 {
                : String csql ( string_from `SELECT COUNT(*)` )
                ( string_push_str csql AG_INBOX_WHERE )
                ?? ( sqlite_prepare db ( string_data csql ) ) {
                    F _ → {}
                    T q → {
                        ( __ag_bind_s q 1 agent )
                        ( __ag_bind_str q 2 ( string_clone mbox ) )
                        ? ( __ag_row q ) { = remaining ( sqlite_column_int q 0 ) } {}
                    }
                }
                ( string_free csql )
            } {}
            ? ( __ag_commit db ) {} { ( __ag_rollback db ) }
        }
    }
    ( string_free mbox )
    ^ @ AgInbox { out remaining }
}

// How many are waiting, without delivering anything.
@ ag_unread AgStore st s agent → i {
    : ~ i n 0
    : String mbox ( ag_mailbox agent )
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            : String csql ( string_from `SELECT COUNT(*)` )
            ( string_push_str csql AG_INBOX_WHERE )
            ?? ( sqlite_prepare db ( string_data csql ) ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 agent )
                    ( __ag_bind_str q 2 ( string_clone mbox ) )
                    ? ( __ag_row q ) { = n ( sqlite_column_int q 0 ) } {}
                }
            }
            ( string_free csql )
        }
    }
    ( string_free mbox )
    ^ n
}

// The newest `limit` messages of a channel with id < `before` (0 = from
// the newest), returned oldest first. Moves no cursor.
@ ag_history AgStore st s channel i before i limit → ( Vec AgMsg ) {
    : ( Vec AgMsg ) out ( vec_new [AgMsg] )
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT id, channel, sender, body, reply_to, ts FROM (SELECT * FROM messages WHERE channel = ?1 AND (?2 = 0 OR id < ?2) ORDER BY id DESC LIMIT ?3) ORDER BY id` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 channel )
                    ( __ag_bind_i q 2 before )
                    ( __ag_bind_i q 3 limit )
                    ~ ( __ag_row q ) { ( vec_push [AgMsg] out ( __ag_read_msg q ) ) }
                }
            }
        }
    }
    ^ out
}

@ ag_msg_get AgStore st i id → ?AgMsg {
    : ~ b found F
    : ~ AgMsg out @ AgMsg { 0 ( string_new ) ( string_new ) ( string_new ) 0 0 }
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT id, channel, sender, body, reply_to, ts FROM messages WHERE id = ?1` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_i q 1 id )
                    ? ( __ag_row q ) {
                        ( ag_msg_free out )
                        = out ( __ag_read_msg q )
                        = found T
                    } {}
                }
            }
        }
    }
    ? found { ^ @ ?AgMsg { T out } } {}
    ( ag_msg_free out )
    ^ @ ?AgMsg { F }
}

// ── Tasks ─────────────────────────────────────────────────────────────

@ __ag_read_task Statement q → AgTask {
    ^ @ AgTask {
        ( sqlite_column_int q 0 )
        ( sqlite_column_text q 1 )
        ( sqlite_column_text q 2 )
        ( sqlite_column_text q 3 )
        ( sqlite_column_text q 4 )
        ( sqlite_column_text q 5 )
        ( sqlite_column_text q 6 )
        ( sqlite_column_int q 7 )
        ( sqlite_column_text q 8 )
        ( sqlite_column_int q 9 )
        ( sqlite_column_int q 10 )
        ( sqlite_column_int q 11 )
    }
}

: s AG_TASK_COLS `id, title, body, tags, poster, status, owner, lease_until, result, priority, created, updated`

// Leases that ran out: the task goes back to open and the holder that
// went quiet hears about it in its mailbox. Called at the start of every
// task operation, so nobody ever sees a claimed task whose lease is over.
@ __ag_expire_on Database db i now → v {
    : ( Vec i ) ids ( vec_new [i] )
    : ( Vec String ) owners ( vec_new [String] )
    : ( Vec String ) titles ( vec_new [String] )
    ?? ( sqlite_prepare db `SELECT id, owner, title FROM tasks WHERE status = 'claimed' AND lease_until < ?1` ) {
        F _ → {}
        T q → {
            ( __ag_bind_i q 1 now )
            ~ ( __ag_row q ) {
                ( vec_push [i] ids ( sqlite_column_int q 0 ) )
                ( vec_push [String] owners ( sqlite_column_text q 1 ) )
                ( vec_push [String] titles ( sqlite_column_text q 2 ) )
            }
        }
    }
    : i n ( vec_len [i] ids )
    : ~ i i 0
    ~ < i n {
        : i id ?? ( vec_get [i] ids i ) { T x → x F _ → 0 }
        ?? ( sqlite_prepare db `UPDATE tasks SET status = 'open', owner = '', lease_until = 0, updated = ?2 WHERE id = ?1 AND status = 'claimed'` ) {
            F _ → {}
            T q → {
                ( __ag_bind_i q 1 id )
                ( __ag_bind_i q 2 now )
                ( __ag_run q )
            }
        }
        ?? ( vec_get [String] owners i ) {
            T owner → {
                : String mbox ( ag_mailbox ( string_data owner ) )
                : String body ( string_from `task #` )
                ( string_push_int body id )
                ( string_push_str body ` lease expired, back to open: ` )
                ?? ( vec_get [String] titles i ) { T t → ( string_push_str body ( string_data t ) ) F _ → {} }
                ( __ag_post_on db ( string_data mbox ) `agora` ( string_data body ) 0 now )
                ( string_free body )
                ( string_free mbox )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( vec_free [i] ids )
    ( ag_strings_free owners )
    ( ag_strings_free titles )
}

@ ag_task_post AgStore st s title s body s tags s poster i priority i now → i {
    : ~ i id 0
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `INSERT INTO tasks (title, body, tags, poster, status, priority, created, updated) VALUES (?1, ?2, ?3, ?4, 'open', ?5, ?6, ?6)` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 title )
                    ( __ag_bind_s q 2 body )
                    ( __ag_bind_s q 3 tags )
                    ( __ag_bind_s q 4 poster )
                    ( __ag_bind_i q 5 priority )
                    ( __ag_bind_i q 6 now )
                    ? ( __ag_run q ) { = id ( sqlite_last_insert_rowid db ) } {}
                }
            }
        }
    }
    ^ id
}

@ ag_task_get AgStore st i id i now → ?AgTask {
    : ~ b found F
    : ~ AgTask out @ AgTask { 0 ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) 0 ( string_new ) 0 0 0 }
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ? ( __ag_begin db ) { ( __ag_expire_on db now ) ( __ag_commit db ) } {}
            : String sql ( string_from `SELECT ` )
            ( string_push_str sql AG_TASK_COLS )
            ( string_push_str sql ` FROM tasks WHERE id = ?1` )
            ?? ( sqlite_prepare db ( string_data sql ) ) {
                F _ → {}
                T q → {
                    ( __ag_bind_i q 1 id )
                    ? ( __ag_row q ) {
                        ( ag_task_free out )
                        = out ( __ag_read_task q )
                        = found T
                    } {}
                }
            }
            ( string_free sql )
        }
    }
    ? found { ^ @ ?AgTask { T out } } {}
    ( ag_task_free out )
    ^ @ ?AgTask { F }
}

// `which`: open | mine (claimed by `agent`) | posted (by `agent`, not
// done) | done | all. `tag` empty = any. Open tasks come highest
// priority first, then oldest first; the rest newest first.
@ ag_tasks AgStore st s which s agent s tag i limit i now → ( Vec AgTask ) {
    : ( Vec AgTask ) out ( vec_new [AgTask] )
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ? ( __ag_begin db ) { ( __ag_expire_on db now ) ( __ag_commit db ) } {}
            : String sql ( string_from `SELECT ` )
            ( string_push_str sql AG_TASK_COLS )
            ( string_push_str sql ` FROM tasks WHERE (?3 = '' OR tags LIKE ?3) AND ` )
            : ~ b by_prio F
            ? != 0 ( nurl_str_eq which `mine` ) {
                ( string_push_str sql `status = 'claimed' AND owner = ?1` )
            } {
                ? != 0 ( nurl_str_eq which `posted` ) {
                    ( string_push_str sql `poster = ?1 AND status IN ('open', 'claimed')` )
                } {
                    ? != 0 ( nurl_str_eq which `done` ) {
                        ( string_push_str sql `status = 'done'` )
                    } {
                        ? != 0 ( nurl_str_eq which `all` ) {
                            ( string_push_str sql `?1 = ?1` )
                        } {
                            ( string_push_str sql `status = 'open'` )
                            = by_prio T
                        }
                    }
                }
            }
            ? by_prio { ( string_push_str sql ` ORDER BY priority DESC, id LIMIT ?2` ) }
            { ( string_push_str sql ` ORDER BY updated DESC, id DESC LIMIT ?2` ) }
            ?? ( sqlite_prepare db ( string_data sql ) ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 agent )
                    ( __ag_bind_i q 2 limit )
                    : ~ String pat ( string_new )
                    ? > ( nurl_str_len tag ) 0 {
                        ( string_push_str pat `%,` )
                        ( string_push_str pat tag )
                        ( string_push_str pat `,%` )
                    } {}
                    ( __ag_bind_str q 3 pat )
                    ~ ( __ag_row q ) { ( vec_push [AgTask] out ( __ag_read_task q ) ) }
                }
            }
            ( string_free sql )
        }
    }
    ^ out
}

@ ag_task_count_open AgStore st → i {
    : ~ i n 0
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT COUNT(*) FROM tasks WHERE status = 'open'` ) {
                F _ → {}
                T q → { ? ( __ag_row q ) { = n ( sqlite_column_int q 0 ) } {} }
            }
        }
    }
    ^ n
}

// Outcome of a state change on a task.
: i AG_TASK_OK 0
: i AG_TASK_NOT_FOUND 1
: i AG_TASK_WRONG_STATE 2  // not open (claim), not yours (done/release), …
: i AG_TASK_FAILED 3

// Atomically take an open task: UPDATE … WHERE status = 'open' inside
// BEGIN IMMEDIATE, and `changes` says whether we won. The poster hears
// about it.
@ ag_task_claim AgStore st i id s agent i lease_s i now → i {
    : ~ i rc AG_TASK_FAILED
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ? ( __ag_begin db ) {} { ^ AG_TASK_FAILED }
            ( __ag_expire_on db now )
            : ~ String poster ( string_new )
            : ~ String title ( string_new )
            : ~ String status ( string_new )
            : ~ b found F
            ?? ( sqlite_prepare db `SELECT poster, title, status FROM tasks WHERE id = ?1` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_i q 1 id )
                    ? ( __ag_row q ) {
                        ( string_free poster ) = poster ( sqlite_column_text q 0 )
                        ( string_free title ) = title ( sqlite_column_text q 1 )
                        ( string_free status ) = status ( sqlite_column_text q 2 )
                        = found T
                    } {}
                }
            }
            ? ! found { = rc AG_TASK_NOT_FOUND } {
                ? != 0 ( nurl_str_eq ( string_data status ) `open` ) {
                    ?? ( sqlite_prepare db `UPDATE tasks SET status = 'claimed', owner = ?2, lease_until = ?3, updated = ?4 WHERE id = ?1 AND status = 'open'` ) {
                        F _ → {}
                        T q → {
                            ( __ag_bind_i q 1 id )
                            ( __ag_bind_s q 2 agent )
                            ( __ag_bind_i q 3 + now lease_s )
                            ( __ag_bind_i q 4 now )
                            ? & ( __ag_run q ) > ( sqlite_changes db ) 0 { = rc AG_TASK_OK } { = rc AG_TASK_WRONG_STATE }
                        }
                    }
                } { = rc AG_TASK_WRONG_STATE }
            }
            ? & == rc AG_TASK_OK == 0 ( nurl_str_eq ( string_data poster ) agent ) {
                : String body ( string_from `task #` )
                ( string_push_int body id )
                ( string_push_str body ` claimed by ` )
                ( string_push_str body agent )
                ( string_push_str body `: ` )
                ( string_push_str body ( string_data title ) )
                : String mbox ( ag_mailbox ( string_data poster ) )
                ( __ag_post_on db ( string_data mbox ) agent ( string_data body ) 0 now )
                ( string_free mbox )
                ( string_free body )
            } {}
            ( string_free poster )
            ( string_free title )
            ( string_free status )
            ? == rc AG_TASK_OK { ? ( __ag_commit db ) {} { = rc AG_TASK_FAILED ( __ag_rollback db ) } } { ( __ag_rollback db ) }
        }
    }
    ^ rc
}

// Extend the lease of a task `agent` holds.
@ ag_task_extend AgStore st i id s agent i lease_s i now → i {
    : ~ i rc AG_TASK_FAILED
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ? ( __ag_begin db ) {} { ^ AG_TASK_FAILED }
            ( __ag_expire_on db now )
            ?? ( sqlite_prepare db `UPDATE tasks SET lease_until = ?3, updated = ?4 WHERE id = ?1 AND status = 'claimed' AND owner = ?2` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_i q 1 id )
                    ( __ag_bind_s q 2 agent )
                    ( __ag_bind_i q 3 + now lease_s )
                    ( __ag_bind_i q 4 now )
                    ? & ( __ag_run q ) > ( sqlite_changes db ) 0 { = rc AG_TASK_OK } { = rc AG_TASK_WRONG_STATE }
                }
            }
            ? == rc AG_TASK_OK { ? ( __ag_commit db ) {} { = rc AG_TASK_FAILED ( __ag_rollback db ) } } { ( __ag_rollback db ) }
        }
    }
    ^ rc
}

// Finish (`to_status` = done, with a result) or give back (`to_status`
// = open, with a note) a task `agent` holds. The poster is told either
// way, unless the poster is the holder.
@ __ag_task_settle AgStore st i id s agent s to_status s text i now → i {
    : ~ i rc AG_TASK_FAILED
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ? ( __ag_begin db ) {} { ^ AG_TASK_FAILED }
            ( __ag_expire_on db now )
            : ~ String poster ( string_new )
            : ~ String title ( string_new )
            : ~ b mine F
            ?? ( sqlite_prepare db `SELECT poster, title FROM tasks WHERE id = ?1 AND status = 'claimed' AND owner = ?2` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_i q 1 id )
                    ( __ag_bind_s q 2 agent )
                    ? ( __ag_row q ) {
                        ( string_free poster ) = poster ( sqlite_column_text q 0 )
                        ( string_free title ) = title ( sqlite_column_text q 1 )
                        = mine T
                    } {}
                }
            }
            : b is_done != 0 ( nurl_str_eq to_status `done` )
            ? ! mine { = rc AG_TASK_WRONG_STATE } {
                : s sql ? is_done
                `UPDATE tasks SET status = 'done', result = ?3, updated = ?4 WHERE id = ?1 AND owner = ?2 AND status = 'claimed'`
                `UPDATE tasks SET status = 'open', owner = '', lease_until = 0, updated = ?4 WHERE id = ?1 AND owner = ?2 AND status = 'claimed'`
                ?? ( sqlite_prepare db sql ) {
                    F _ → {}
                    T q → {
                        ( __ag_bind_i q 1 id )
                        ( __ag_bind_s q 2 agent )
                        ? is_done { ( __ag_bind_s q 3 text ) } {}
                        ( __ag_bind_i q 4 now )
                        ? & ( __ag_run q ) > ( sqlite_changes db ) 0 { = rc AG_TASK_OK } {}
                    }
                }
            }
            ? & == rc AG_TASK_OK == 0 ( nurl_str_eq ( string_data poster ) agent ) {
                : String body ( string_from `task #` )
                ( string_push_int body id )
                ( string_push_str body ? is_done ` done by ` ` released by ` )
                ( string_push_str body agent )
                ( string_push_str body `: ` )
                ( string_push_str body ( string_data title ) )
                ? > ( nurl_str_len text ) 0 {
                    ( string_push_str body ? is_done `\nresult: ` `\nnote: ` )
                    ( string_push_str body text )
                } {}
                : String mbox ( ag_mailbox ( string_data poster ) )
                ( __ag_post_on db ( string_data mbox ) agent ( string_data body ) 0 now )
                ( string_free mbox )
                ( string_free body )
            } {}
            ( string_free poster )
            ( string_free title )
            ? == rc AG_TASK_OK { ? ( __ag_commit db ) {} { = rc AG_TASK_FAILED ( __ag_rollback db ) } } { ( __ag_rollback db ) }
        }
    }
    ^ rc
}

@ ag_task_done AgStore st i id s agent s result i now → i {
    ^ ( __ag_task_settle st id agent `done` result now )
}

@ ag_task_release AgStore st i id s agent s note i now → i {
    ^ ( __ag_task_settle st id agent `open` note now )
}

// The poster withdraws a task that is open or claimed. A holder hears
// about it.
@ ag_task_cancel AgStore st i id s agent i now → i {
    : ~ i rc AG_TASK_FAILED
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ? ( __ag_begin db ) {} { ^ AG_TASK_FAILED }
            ( __ag_expire_on db now )
            : ~ String owner ( string_new )
            : ~ String title ( string_new )
            : ~ b found F
            : ~ b cancellable F
            ?? ( sqlite_prepare db `SELECT owner, title, status, poster FROM tasks WHERE id = ?1` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_i q 1 id )
                    ? ( __ag_row q ) {
                        = found T
                        ( string_free owner ) = owner ( sqlite_column_text q 0 )
                        ( string_free title ) = title ( sqlite_column_text q 1 )
                        : String status ( sqlite_column_text q 2 )
                        : String poster ( sqlite_column_text q 3 )
                        = cancellable & != 0 ( nurl_str_eq ( string_data poster ) agent )
                        | != 0 ( nurl_str_eq ( string_data status ) `open` ) != 0 ( nurl_str_eq ( string_data status ) `claimed` )
                        ( string_free status )
                        ( string_free poster )
                    } {}
                }
            }
            ? ! found { = rc AG_TASK_NOT_FOUND } {
                ? ! cancellable { = rc AG_TASK_WRONG_STATE } {
                    ?? ( sqlite_prepare db `UPDATE tasks SET status = 'cancelled', updated = ?2 WHERE id = ?1` ) {
                        F _ → {}
                        T q → {
                            ( __ag_bind_i q 1 id )
                            ( __ag_bind_i q 2 now )
                            ? ( __ag_run q ) { = rc AG_TASK_OK } {}
                        }
                    }
                }
            }
            ? & == rc AG_TASK_OK & > ( string_len owner ) 0 == 0 ( nurl_str_eq ( string_data owner ) agent ) {
                : String body ( string_from `task #` )
                ( string_push_int body id )
                ( string_push_str body ` cancelled by ` )
                ( string_push_str body agent )
                ( string_push_str body `: ` )
                ( string_push_str body ( string_data title ) )
                : String mbox ( ag_mailbox ( string_data owner ) )
                ( __ag_post_on db ( string_data mbox ) agent ( string_data body ) 0 now )
                ( string_free mbox )
                ( string_free body )
            } {}
            ( string_free owner )
            ( string_free title )
            ? == rc AG_TASK_OK { ? ( __ag_commit db ) {} { = rc AG_TASK_FAILED ( __ag_rollback db ) } } { ( __ag_rollback db ) }
        }
    }
    ^ rc
}

// ── Notes ─────────────────────────────────────────────────────────────
//
// A note lives under a project ('' = global). The project is a
// namespace an agent chooses — a repository's name, say — so that the
// same key can mean one thing here and another there, and `notes
// project=x` is everything known about x.

@ ag_note_set AgStore st s project s key s body s author i now → b {
    : ~ b ok F
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `INSERT INTO notes (project, key, body, author, updated) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT (project, key) DO UPDATE SET body = excluded.body, author = excluded.author, updated = excluded.updated` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 project )
                    ( __ag_bind_s q 2 key )
                    ( __ag_bind_s q 3 body )
                    ( __ag_bind_s q 4 author )
                    ( __ag_bind_i q 5 now )
                    = ok ( __ag_run q )
                }
            }
        }
    }
    ^ ok
}

@ __ag_read_note Statement q → AgNote {
    ^ @ AgNote {
        ( sqlite_column_text q 0 )
        ( sqlite_column_text q 1 )
        ( sqlite_column_text q 2 )
        ( sqlite_column_text q 3 )
        ( sqlite_column_int q 4 )
    }
}

@ ag_note_get AgStore st s project s key → ?AgNote {
    : ~ b found F
    : ~ AgNote out @ AgNote { ( string_new ) ( string_new ) ( string_new ) ( string_new ) 0 }
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT project, key, body, author, updated FROM notes WHERE project = ?1 AND key = ?2` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 project )
                    ( __ag_bind_s q 2 key )
                    ? ( __ag_row q ) {
                        ( ag_note_free out )
                        = out ( __ag_read_note q )
                        = found T
                    } {}
                }
            }
        }
    }
    ? found { ^ @ ?AgNote { T out } } {}
    ( ag_note_free out )
    ^ @ ?AgNote { F }
}

// The notes of one project (`all` F), or every note of every project
// (`all` T), project then key order. `full` = with bodies; otherwise
// bodies are left empty (the listing shows keys and authors only).
@ ag_notes AgStore st s project b all b full → ( Vec AgNote ) {
    : ( Vec AgNote ) out ( vec_new [AgNote] )
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            : String sql ( string_from ? full `SELECT project, key, body, author, updated FROM notes` `SELECT project, key, '', author, updated FROM notes` )
            ? all {} { ( string_push_str sql ` WHERE project = ?1` ) }
            ( string_push_str sql ` ORDER BY project, key` )
            ?? ( sqlite_prepare db ( string_data sql ) ) {
                F _ → {}
                T q → {
                    ? all {} { ( __ag_bind_s q 1 project ) }
                    ~ ( __ag_row q ) { ( vec_push [AgNote] out ( __ag_read_note q ) ) }
                }
            }
            ( string_free sql )
        }
    }
    ^ out
}

@ ag_note_del AgStore st s project s key → b {
    : ~ b ok F
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `DELETE FROM notes WHERE project = ?1 AND key = ?2` ) {
                F _ → {}
                T q → {
                    ( __ag_bind_s q 1 project )
                    ( __ag_bind_s q 2 key )
                    = ok & ( __ag_run q ) > ( sqlite_changes db ) 0
                }
            }
        }
    }
    ^ ok
}

@ ag_note_count AgStore st → i {
    : ~ i n 0
    ?? ( __ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT COUNT(*) FROM notes` ) {
                F _ → {}
                T q → { ? ( __ag_row q ) { = n ( sqlite_column_int q 0 ) } {} }
            }
        }
    }
    ^ n
}
