// packages/nurllama/src/history.nu — the conversation store (nurldb).
//
// Every chat a web client has with a model is persisted, scoped to the
// client's cookie GUID, in a nurldb database: the directory
// $NURLLAMA_HOME/history. The server opens it once at startup
// (hist_open) and every request works through a Session of its own on
// the one shared Db; hist_close checkpoints it when the server stops.
// The Db holds the directory's lock while it is open, so a second
// nurllama server on the same NURLLAMA_HOME is refused at startup
// instead of writing the same files.
//
// nurldb has no AUTOINCREMENT: the ids come from counters this process
// keeps, read from the tables' largest id at open — the lock makes this
// process the only writer. Text reaches SQL as a literal with its quotes
// doubled (nurldb's only escape in a literal); a message of any length
// fits, its bytes kept on overflow pages when it is long.
//
//   ( hist_dir root )                         → String  the database directory
//   ( hist_open dir )                         → String  "" = open, else why not
//   ( hist_close )                            → v
//   ( hist_ensure_client guid now )           → b
//   ( hist_new_conversation guid model now )  → i   its id, -1 on error
//   ( hist_add_message conv role content now ) → b
//   ( hist_conversation_owner conv )          → String  ("" = none)
//   ( hist_list_conversations guid )          → Json  array
//   ( hist_get_messages conv )                → Json  array
//   ( hist_delete_conversation conv guid )    → b

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/ext/json.nu`
$ `deps/nurldb/src/nurldb.nu`

@ __hist_blank → ( Locked ? Db ) { ^ ( locked_new [? Db] @ ?Db { F } ) }

: ( Locked ? Db ) g_hist ( __hist_blank )  // the open database (F = none)

@ __hist_ids0 → ( Locked i ) { ^ ( locked_new [i] 0 ) }

: ( Locked i ) g_hist_conv_id ( __hist_ids0 )  // the last conversation id given out

: ( Locked i ) g_hist_msg_id ( __hist_ids0 )  // the last message id given out

@ hist_dir String root → String {
    ^ ( path_join ( string_data root ) `history` )
}

@ hist_now → i {
    ^ ( time_to_unix ( time_now ) )
}

// One more owner of the open database, or none.
@ __hist_db → ?Db {
    : ?Db cur ( locked_take [? Db] g_hist )
    : ~ ? Db out @ ?Db { F }
    ?? cur { T d → { = out @ ?Db { T ( Db_share d ) } } F → {} }
    ( locked_restore [? Db] g_hist cur )
    ^ out
}

// The next id of a counter.
@ __hist_next ( Locked i ) ids → i {
    : ~ i got 0
    ( locked_update [i] ids \ inout i last → v { = last + last 1 = got last } )
    ^ got
}

// `t` as an SQL literal: in quotes, each quote doubled.
@ __hist_lit s t → String {
    : String q ( string_from `'` )
    : ( Slice u ) b ( slice_of_str t )
    : ~ i k 0
    ~ < k ( slice_len [u] b ) {
        : i c ( slice_byte b k )
        ? == c 39 { ( string_push_str q `''` ) } { ( string_push_char q c ) }
        = k + k 1
    }
    ( string_push_char q 39 )
    ^ q
}

// Run one statement on `s`: its rows (none for a statement that returns
// none), or why it failed.
@ __hist_exec inout Session s String q → !( Vec ( Vec Value ) ) String {
    ?? ( session_exec s q ) {
        T r → { ^ @ !( Vec ( Vec Value ) ) String { T ( mem_dup . r rows ) } }
        F e → { ^ @ !( Vec ( Vec Value ) ) String { F e } }
    }
}

@ __hist_ok inout Session s String q → b {
    ^ ?? ( session_exec s q ) { T _ → T F _ → F }
}

// Column `col` of row `row`, as an INT (0 for anything else) and as text
// ("" for anything else).
@ __hist_int ( Vec ( Vec Value ) ) rows i row i col → i {
    ^ ?? ( vec_at [Value] ( vec_at [( Vec Value )] rows row ) col ) { VInt x → x _ → 0 }
}

@ __hist_text ( Vec ( Vec Value ) ) rows i row i col → String {
    ^ ?? ( vec_at [Value] ( vec_at [( Vec Value )] rows row ) col ) { VText x → ( string_clone x ) _ → ( string_new ) }
}

// Whether table `t` has an index named `name`.
@ __hist_has_index Db d s t s name → b {
    ?? ( db_table d ( string_from t ) ) {
        T ti → {
            ~ ix . ( ti_meta ti ) indexes {
                ? != 0 ( nurl_str_eq ( string_data . ix name ) name ) { ^ T } {}
            }
        }
        F → {}
    }
    ^ F
}

@ __hist_has_table Db d s t → b {
    ^ ?? ( db_table d ( string_from t ) ) { T _ → T F → F }
}

// Each table and index, made unless it is there: a crash between two of
// them leaves the rest for the next open.
@ __hist_schema Db d → String {
    : ~ Session s ( session_new d )
    : ~ String err ( string_new )
    ? ( __hist_has_table d `clients` ) {} {
        ?? ( session_exec s ( string_from `CREATE TABLE clients (guid TEXT PRIMARY KEY, created_at INT NOT NULL)` ) ) { T _ → {} F e → { = err e } }
    }
    ? ( __hist_has_table d `conversations` ) {} {
        ?? ( session_exec s ( string_from `CREATE TABLE conversations (id INT PRIMARY KEY, client_guid TEXT NOT NULL,
            model TEXT NOT NULL, title TEXT NOT NULL, created_at INT NOT NULL)` ) ) { T _ → {} F e → { = err e } }
    }
    ? ( __hist_has_index d `conversations` `idx_conv_client` ) {} {
        ?? ( session_exec s ( string_from `CREATE INDEX idx_conv_client ON conversations (client_guid)` ) ) { T _ → {} F e → { = err e } }
    }
    ? ( __hist_has_table d `messages` ) {} {
        ?? ( session_exec s ( string_from `CREATE TABLE messages (id INT PRIMARY KEY, conversation_id INT NOT NULL,
            role TEXT NOT NULL, content TEXT NOT NULL, created_at INT NOT NULL)` ) ) { T _ → {} F e → { = err e } }
    }
    ? ( __hist_has_index d `messages` `idx_msg_conv` ) {} {
        ?? ( session_exec s ( string_from `CREATE INDEX idx_msg_conv ON messages (conversation_id)` ) ) { T _ → {} F e → { = err e } }
    }
    ( session_close s )
    ^ err
}

// The largest id in `table` (0 when it is empty).
@ __hist_max_id Db d s table → i {
    : ~ Session s ( session_new d )
    : String q ( string_from `SELECT MAX(id) FROM ` )
    ( string_push_str q table )
    : ~ i m 0
    ?? ( __hist_exec s q ) {
        T rows → { ? > ( vec_len [( Vec Value )] rows ) 0 { = m ( __hist_int rows 0 0 ) } {} }
        F _ → {}
    }
    ( session_close s )
    ^ m
}

// Open (or create) the database in `dir` for this process: "" when it is
// open, else why not — another nurllama has it open, say.
@ hist_open String dir → String {
    : DbOpts o @ DbOpts { 256 T }
    ?? ( db_open ( string_data dir ) o ) {
        F e → {
            : String m ( string_from `cannot open the conversation history (` )
            ( string_push_str m ( string_data dir ) )
            ( string_push_str m `): ` )
            ( string_push_str m ( string_data e ) )
            ^ m
        }
        T d → {
            : String err ( __hist_schema d )
            ? > ( string_len err ) 0 {
                ( db_close d )
                : String m ( string_from `cannot set up the conversation history: ` )
                ( string_push_str m ( string_data err ) )
                ^ m
            } {}
            ( locked_set [i] g_hist_conv_id ( __hist_max_id d `conversations` ) )
            ( locked_set [i] g_hist_msg_id ( __hist_max_id d `messages` ) )
            ( locked_set [? Db] g_hist @ ?Db { T d } )
        }
    }
    ^ ( string_new )
}

// Checkpoint and let go of the database (the server is stopping).
@ hist_close → v {
    ?? ( __hist_db ) { T d → { ( db_close d ) } F → {} }
    ( locked_set [? Db] g_hist @ ?Db { F } )
}

@ hist_ensure_client s guid i now → b {
    ?? ( __hist_db ) {
        T d → {
            : ~ Session s ( session_new d )
            : String q ( string_from `SELECT guid FROM clients WHERE guid = ` )
            ( string_push_str q ( string_data ( __hist_lit guid ) ) )
            : ~ b ok F
            ?? ( __hist_exec s q ) {
                T rows → {
                    ? > ( vec_len [( Vec Value )] rows ) 0 { = ok T } {
                        : String ins ( string_from `INSERT INTO clients VALUES (` )
                        ( string_push_str ins ( string_data ( __hist_lit guid ) ) )
                        ( string_push_str ins `, ` )
                        ( string_push_int ins now )
                        ( string_push_str ins `)` )
                        = ok ( __hist_ok s ins )
                    }
                }
                F _ → {}
            }
            ( session_close s )
            ^ ok
        }
        F → {}
    }
    ^ F
}

@ hist_new_conversation s guid s model i now → i {
    ?? ( __hist_db ) {
        T d → {
            : i id ( __hist_next g_hist_conv_id )
            : ~ Session s ( session_new d )
            : String q ( string_from `INSERT INTO conversations VALUES (` )
            ( string_push_int q id )
            ( string_push_str q `, ` )
            ( string_push_str q ( string_data ( __hist_lit guid ) ) )
            ( string_push_str q `, ` )
            ( string_push_str q ( string_data ( __hist_lit model ) ) )
            ( string_push_str q `, '', ` )
            ( string_push_int q now )
            ( string_push_str q `)` )
            : b ok ( __hist_ok s q )
            ( session_close s )
            ^ ? ok id -1
        }
        F → {}
    }
    ^ -1
}

// The first 60 bytes of `content`, line breaks as spaces, and "…" when
// there was more: a conversation's title.
@ __hist_title s content → String {
    : ( Slice u ) cv ( slice_of_str content )
    : String title ( string_new )
    : i n ( slice_len [u] cv )
    : i take ? < n 60 n 60
    : ~ i k 0
    ~ < k take {
        : i c ( slice_byte cv k )
        ( string_push_char title ? | == c 10 == c 13 32 c )
        = k + k 1
    }
    ? > n 60 { ( string_push_str title `…` ) } {}
    ^ title
}

// The message, and — for the first user message of a conversation with
// no title yet — its opening as the title, so the sidebar has a label
// without a round trip. One transaction: both or neither.
@ hist_add_message i conv s role s content i now → b {
    ?? ( __hist_db ) {
        T d → {
            : i id ( __hist_next g_hist_msg_id )
            : ~ Session s ( session_new d )
            : String q ( string_from `INSERT INTO messages VALUES (` )
            ( string_push_int q id )
            ( string_push_str q `, ` )
            ( string_push_int q conv )
            ( string_push_str q `, ` )
            ( string_push_str q ( string_data ( __hist_lit role ) ) )
            ( string_push_str q `, ` )
            ( string_push_str q ( string_data ( __hist_lit content ) ) )
            ( string_push_str q `, ` )
            ( string_push_int q now )
            ( string_push_str q `)` )
            : ~ b ok ( __hist_ok s ( string_from `BEGIN` ) )
            ? ok { = ok ( __hist_ok s q ) } {}
            ? & ok != 0 ( nurl_str_eq role `user` ) {
                : String u ( string_from `UPDATE conversations SET title = ` )
                ( string_push_str u ( string_data ( __hist_lit ( string_data ( __hist_title content ) ) ) ) )
                ( string_push_str u ` WHERE id = ` )
                ( string_push_int u conv )
                ( string_push_str u ` AND title = ''` )
                = ok ( __hist_ok s u )
            } {}
            // A failed statement has already rolled the transaction back.
            ? ok { = ok ( __hist_ok s ( string_from `COMMIT` ) ) } {}
            ( session_close s )
            ^ ok
        }
        F → {}
    }
    ^ F
}

// The GUID that owns `conv`, or "" when the conversation does not exist.
// The web layer checks this before returning any conversation's contents.
@ hist_conversation_owner i conv → String {
    ?? ( __hist_db ) {
        T d → {
            : ~ Session s ( session_new d )
            : String q ( string_from `SELECT client_guid FROM conversations WHERE id = ` )
            ( string_push_int q conv )
            : ~ String owner ( string_new )
            ?? ( __hist_exec s q ) {
                T rows → { ? > ( vec_len [( Vec Value )] rows ) 0 { = owner ( __hist_text rows 0 0 ) } {} }
                F _ → {}
            }
            ( session_close s )
            ^ owner
        }
        F → {}
    }
    ^ ( string_new )
}

// A JSON array of this client's conversations, newest first:
//   [ { "id":N, "model":"…", "title":"…", "created_at":T }, … ]
@ hist_list_conversations s guid → Json {
    : Json arr ( json_arr_new )
    ?? ( __hist_db ) {
        T d → {
            : ~ Session s ( session_new d )
            : String q ( string_from `SELECT id, model, title, created_at FROM conversations WHERE client_guid = ` )
            ( string_push_str q ( string_data ( __hist_lit guid ) ) )
            ( string_push_str q ` ORDER BY id DESC` )
            ?? ( __hist_exec s q ) {
                T rows → {
                    : ~ i k 0
                    ~ < k ( vec_len [( Vec Value )] rows ) {
                        : Json o ( json_obj_new )
                        : b _1 ( json_obj_set o `id` ( json_int ( __hist_int rows k 0 ) ) )
                        : String md ( __hist_text rows k 1 )
                        : b _2 ( json_obj_set o `model` ( json_str_lit ( string_data md ) ) )
                        : String tt ( __hist_text rows k 2 )
                        : b _3 ( json_obj_set o `title` ( json_str_lit ( string_data tt ) ) )
                        : b _4 ( json_obj_set o `created_at` ( json_int ( __hist_int rows k 3 ) ) )
                        : b _5 ( json_arr_push arr o )
                        = k + k 1
                    }
                }
                F _ → {}
            }
            ( session_close s )
        }
        F → {}
    }
    ^ arr
}

// A JSON array of a conversation's messages in order:
//   [ { "role":"user|assistant", "content":"…", "created_at":T }, … ]
@ hist_get_messages i conv → Json {
    : Json arr ( json_arr_new )
    ?? ( __hist_db ) {
        T d → {
            : ~ Session s ( session_new d )
            : String q ( string_from `SELECT role, content, created_at FROM messages WHERE conversation_id = ` )
            ( string_push_int q conv )
            ( string_push_str q ` ORDER BY id` )
            ?? ( __hist_exec s q ) {
                T rows → {
                    : ~ i k 0
                    ~ < k ( vec_len [( Vec Value )] rows ) {
                        : Json o ( json_obj_new )
                        : String rl ( __hist_text rows k 0 )
                        : b _1 ( json_obj_set o `role` ( json_str_lit ( string_data rl ) ) )
                        : String ct ( __hist_text rows k 1 )
                        : b _2 ( json_obj_set o `content` ( json_str_lit ( string_data ct ) ) )
                        : b _3 ( json_obj_set o `created_at` ( json_int ( __hist_int rows k 2 ) ) )
                        : b _4 ( json_arr_push arr o )
                        = k + k 1
                    }
                }
                F _ → {}
            }
            ( session_close s )
        }
        F → {}
    }
    ^ arr
}

// Delete a conversation and its messages — only when `guid` owns it. One
// transaction: a crash leaves both or neither.
@ hist_delete_conversation i conv s guid → b {
    : String owner ( hist_conversation_owner conv )
    ? != 0 ( nurl_str_eq ( string_data owner ) guid ) {} { ^ F }
    ?? ( __hist_db ) {
        T d → {
            : ~ Session s ( session_new d )
            : String qm ( string_from `DELETE FROM messages WHERE conversation_id = ` )
            ( string_push_int qm conv )
            : String qc ( string_from `DELETE FROM conversations WHERE id = ` )
            ( string_push_int qc conv )
            : ~ b ok ( __hist_ok s ( string_from `BEGIN` ) )
            ? ok { = ok ( __hist_ok s qm ) } {}
            ? ok { = ok ( __hist_ok s qc ) } {}
            ? ok { = ok ( __hist_ok s ( string_from `COMMIT` ) ) } {}
            ( session_close s )
            ^ ok
        }
        F → {}
    }
    ^ F
}
