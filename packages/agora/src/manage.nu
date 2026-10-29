// agora/src/manage.nu — what a signed-in service adds to the store.
//
// A local agora is one file and one trust boundary: whoever can open
// the file is everybody. A signed-in service (`[auth] mode = "oidc"`)
// keeps, per ORGANISATION, one agora file per repository (store.nu's
// schema; auth.nu picks the file) and one file of its people:
//
//   users     everyone who has signed in, with a role. The first person
//             of an organisation becomes its admin — nobody else could
//             have granted it, and an organisation with no admin could
//             never be administered.
//   skills    the organisation's playbooks (store.nu's table), for every
//             repository's agents alike
//
// People and agents are not tied together: a repository's agora is one
// shared room for everybody of the organisation who works on it, and an
// agent is just the name a caller says it is (`as=`).
//
// Plus the editing a person does from the web page and an agent never
// does: rewrite or delete a message, edit or delete a task, delete a
// channel or an agent, page through and sort what is there, and clear
// out what has gone stale. Same rules as store.nu: a connection per
// operation, BEGIN IMMEDIATE around anything that writes twice.

$ `store.nu`

: s AG_ROLE_ADMIN `admin`
: s AG_ROLE_MEMBER `member`

: AgUser {
    String sub
    String email
    String name
    String role
    i created
    i seen
}

// ── Small statement runners ──────────────────────────────────────────

// Run `sql` with ?1 = a; the number of rows changed, -1 on failure.
@ __ag_exec_s AgStore st s sql s a → i {
    : ~ i n -1
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db sql ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 a )
                    ? ( _ag_run q ) { = n ( sqlite_changes db ) } {}
                }
            }
        }
    }
    ^ n
}

@ _ag_exec_ss AgStore st s sql s a s b → i {
    : ~ i n -1
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db sql ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 a )
                    ( _ag_bind_s q 2 b )
                    ? ( _ag_run q ) { = n ( sqlite_changes db ) } {}
                }
            }
        }
    }
    ^ n
}

// The same on an open connection (inside a transaction).
@ __ag_on_s Database db s sql s a → b {
    : ~ b ok F
    ?? ( sqlite_prepare db sql ) {
        F _ → {}
        T q → {
            ( _ag_bind_s q 1 a )
            = ok ( _ag_run q )
        }
    }
    ^ ok
}

@ __ag_on_i Database db s sql i a → b {
    : ~ b ok F
    ?? ( sqlite_prepare db sql ) {
        F _ → {}
        T q → {
            ( _ag_bind_i q 1 a )
            = ok ( _ag_run q )
        }
    }
    ^ ok
}

// One text column of the first row of `sql` with ?1 = a ('' = no row).
@ __ag_text_s AgStore st s sql s a → String {
    : ~ String out ( string_new )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db sql ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 a )
                    ? ( _ag_row q ) { = out ( sqlite_column_text q 0 ) } {}
                }
            }
        }
    }
    ^ out
}

// ── The organisation's file ──────────────────────────────────────────

// Open (creating) an organisation's file of people at `path`.
@ ag_orgdb_open s path → AgStore {
    : String dir ( path_dirname path )
    ? > ( string_len dir ) 0 {
        ?? ( dir_create_all ( string_data dir ) ) { T _ → {} F _ → {} }
    } {}
    : AgStore st @ AgStore { ( string_from path ) T @ ?Database { F } }
    : ~ b ok F
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_exec db `PRAGMA journal_mode=WAL` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `CREATE TABLE IF NOT EXISTS users (sub TEXT PRIMARY KEY, email TEXT NOT NULL DEFAULT '', name TEXT NOT NULL DEFAULT '', role TEXT NOT NULL, created INTEGER NOT NULL, seen INTEGER NOT NULL)` ) {
                T _ → { = ok T }
                F _ → {}
            }
            ?? ( sqlite_exec db AG_SKILLS_TABLE ) { T _ → {} F _ → { = ok F } }
        }
    }
    ^ @ AgStore { ( string_from path ) ok @ ?Database { F } }
}

// ── Users ────────────────────────────────────────────────────────────

// Record a sign-in and return the person's role. The first person of
// the organisation is its admin; everyone after is a member until an
// admin says otherwise. One transaction, so two first sign-ins racing
// cannot both become the first.
@ ag_user_touch AgStore st s sub s email s name i now → String {
    : ~ String role ( string_new )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ? ( _ag_begin db ) {} { ^ role }
            ?? ( sqlite_prepare db `SELECT role FROM users WHERE sub = ?1` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 sub )
                    ? ( _ag_row q ) { = role ( sqlite_column_text q 0 ) } {}
                }
            }
            ? > ( string_len role ) 0 {
                ?? ( sqlite_prepare db `UPDATE users SET email = ?2, name = ?3, seen = ?4 WHERE sub = ?1` ) {
                    F _ → {}
                    T q → {
                        ( _ag_bind_s q 1 sub )
                        ( _ag_bind_s q 2 email )
                        ( _ag_bind_s q 3 name )
                        ( _ag_bind_i q 4 now )
                        ( _ag_run q )
                    }
                }
            } {
                : ~ i nusers 0
                ?? ( sqlite_prepare db `SELECT COUNT(*) FROM users` ) {
                    F _ → {}
                    T q → { ? ( _ag_row q ) { = nusers ( sqlite_column_int q 0 ) } {} }
                }
                = role ( string_from ? == nusers 0 AG_ROLE_ADMIN AG_ROLE_MEMBER )
                ?? ( sqlite_prepare db `INSERT INTO users (sub, email, name, role, created, seen) VALUES (?1, ?2, ?3, ?4, ?5, ?5)` ) {
                    F _ → {}
                    T q → {
                        ( _ag_bind_s q 1 sub )
                        ( _ag_bind_s q 2 email )
                        ( _ag_bind_s q 3 name )
                        ( _ag_bind_s q 4 ( string_data role ) )
                        ( _ag_bind_i q 5 now )
                        ( _ag_run q )
                    }
                }
            }
            ? ( _ag_commit db ) {} { ( _ag_rollback db ) = role ( string_new ) }
        }
    }
    ^ role
}

@ ag_user_role AgStore st s sub → String {
    ^ ( __ag_text_s st `SELECT role FROM users WHERE sub = ?1` sub )
}

@ ag_users AgStore st → ( Vec AgUser ) {
    : ( Vec AgUser ) out ( vec_new [AgUser] )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT sub, email, name, role, created, seen FROM users ORDER BY seen DESC` ) {
                F _ → {}
                T q → {
                    ~ ( _ag_row q ) {
                        ( vec_push [AgUser] out @ AgUser {
                            ( sqlite_column_text q 0 )
                            ( sqlite_column_text q 1 )
                            ( sqlite_column_text q 2 )
                            ( sqlite_column_text q 3 )
                            ( sqlite_column_int q 4 )
                            ( sqlite_column_int q 5 )
                        } )
                    }
                }
            }
        }
    }
    ^ out
}

@ ag_admin_count AgStore st → i {
    : ~ i n 0
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT COUNT(*) FROM users WHERE role = 'admin'` ) {
                F _ → {}
                T q → { ? ( _ag_row q ) { = n ( sqlite_column_int q 0 ) } {} }
            }
        }
    }
    ^ n
}

// Change a role. Refuses to take the last admin's away: an organisation
// nobody can administer is not recoverable from the web page.
@ ag_user_set_role AgStore st s sub s role → b {
    : b demote & == 0 ( nurl_str_eq role AG_ROLE_ADMIN )
    == 0 ( nurl_str_eq ( string_data ( ag_user_role st sub ) ) AG_ROLE_MEMBER )
    ? & demote <= ( ag_admin_count st ) 1 { ^ F } {}
    ^ > ( _ag_exec_ss st `UPDATE users SET role = ?2 WHERE sub = ?1` sub role ) 0
}

// Forget a person (the next sign-in makes them a member again — the
// organisation's identity provider, not this list, says who may come).
// What their agents wrote stays: it is the repository's record. The
// last admin cannot be removed.
@ ag_user_delete AgStore st s sub → b {
    : b is_admin != 0 ( nurl_str_eq ( string_data ( ag_user_role st sub ) ) AG_ROLE_ADMIN )
    ? & is_admin <= ( ag_admin_count st ) 1 { ^ F } {}
    ^ > ( __ag_exec_s st `DELETE FROM users WHERE sub = ?1` sub ) 0
}

// ── Agents ───────────────────────────────────────────────────────────

// Delete an agent: the row, what it follows and where it has read to,
// and its mailbox. What it posted to channels stays — the
// other agents have read it and may refer to it. A task it held goes
// back to open, as an expired lease would.
@ ag_agent_delete AgStore st s id i now → b {
    : ~ b ok F
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ? ( _ag_begin db ) {} { ^ F }
            = ok ( __ag_agent_delete_on db id now )
            ? ok { = ok ( _ag_commit db ) } { ( _ag_rollback db ) }
        }
    }
    ^ ok
}

// The same inside the caller's transaction; F when there was no such
// agent or a statement failed.
@ __ag_agent_delete_on Database db s id i now → b {
    : String mbox ( ag_mailbox id )
    : ~ b ok ( __ag_on_s db `DELETE FROM agents WHERE id = ?1` id )
    : b existed > ( sqlite_changes db ) 0
    = ok & & ok ( __ag_on_s db `DELETE FROM follows WHERE agent = ?1` id )
    ( __ag_on_s db `DELETE FROM cursors WHERE agent = ?1` id )
    = ok & ok ( __ag_on_s db `DELETE FROM messages WHERE channel = ?1` ( string_data mbox ) )
    ?? ( sqlite_prepare db `UPDATE tasks SET status = 'open', owner = '', lease_until = 0, updated = ?2 WHERE status = 'claimed' AND owner = ?1` ) {
        F _ → { = ok F }
        T q → {
            ( _ag_bind_s q 1 id )
            ( _ag_bind_i q 2 now )
            = ok & ok ( _ag_run q )
        }
    }
    ^ & ok existed
}

// ── Channels ─────────────────────────────────────────────────────────

// Delete a channel with everything in it. `public` stays: every agent
// follows it from the start, and the store re-creates it anyway.
@ ag_channel_delete AgStore st s name → b {
    ? != 0 ( nurl_str_eq name `public` ) { ^ F } {}
    : ~ b ok F
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ? ( _ag_begin db ) {} { ^ F }
            = ok ( __ag_channel_delete_on db name )
            ? ok { = ok ( _ag_commit db ) } { ( _ag_rollback db ) }
        }
    }
    ^ ok
}

@ __ag_channel_delete_on Database db s name → b {
    : b ok ( __ag_on_s db `DELETE FROM channels WHERE name = ?1` name )
    : b existed > ( sqlite_changes db ) 0
    ^ & & & & ok existed ( __ag_on_s db `DELETE FROM messages WHERE channel = ?1` name )
    ( __ag_on_s db `DELETE FROM follows WHERE channel = ?1` name )
    ( __ag_on_s db `DELETE FROM cursors WHERE channel = ?1` name )
}

// ── Messages ─────────────────────────────────────────────────────────

@ ag_msg_set_body AgStore st i id s body → b {
    : ~ b ok F
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `UPDATE messages SET body = ?2 WHERE id = ?1` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_i q 1 id )
                    ( _ag_bind_s q 2 body )
                    = ok & ( _ag_run q ) > ( sqlite_changes db ) 0
                }
            }
        }
    }
    ^ ok
}

@ ag_msg_delete AgStore st i id → b {
    : ~ b ok F
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → { = ok & ( __ag_on_i db `DELETE FROM messages WHERE id = ?1` id ) > ( sqlite_changes db ) 0 }
    }
    ^ ok
}

// The messages, newest first — channel posts and mail alike: the room is
// shared by everybody in it. `channel` '' = all channels; `text` '' = any
// body; `before` 0 = from the newest.
@ ag_messages_list AgStore st s channel s text i before i limit → ( Vec AgMsg ) {
    ^ ( ag_messages_page st channel `` text before F limit 0 )
}

// The filter every message listing shares: ?1 channel, ?2 sender, ?3 a
// LIKE pattern for the body ('' = any of each), ?4 ids below (0 = any).
: s AG_MSG_WHERE ` FROM messages WHERE (?1 = '' OR channel = ?1) AND (?2 = '' OR sender = ?2) AND (?3 = '' OR body LIKE ?3 ESCAPE '\\') AND (?4 = 0 OR id < ?4)`

// A page of them: `offset` rows past the first, newest first (`oldest`
// T: oldest first). `from` '' = anyone.
@ ag_messages_page AgStore st s channel s from s text i before b oldest i limit i offset → ( Vec AgMsg ) {
    : ( Vec AgMsg ) out ( vec_new [AgMsg] )
    : String sql ( string_from `SELECT id, channel, sender, body, reply_to, ts` )
    ( string_push_str sql AG_MSG_WHERE )
    ( string_push_str sql ? oldest ` ORDER BY id LIMIT ?5 OFFSET ?6` ` ORDER BY id DESC LIMIT ?5 OFFSET ?6` )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db ( string_data sql ) ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 channel )
                    ( _ag_bind_s q 2 from )
                    ( _ag_bind_str q 3 ( _ag_like_pat text ) )
                    ( _ag_bind_i q 4 before )
                    ( _ag_bind_i q 5 limit )
                    ( _ag_bind_i q 6 offset )
                    ~ ( _ag_row q ) { ( vec_push [AgMsg] out ( _ag_read_msg q ) ) }
                }
            }
        }
    }
    ^ out
}

// How many the same filter matches (for "page 2 of 7").
@ ag_messages_count AgStore st s channel s from s text → i {
    : ~ i n 0
    : String sql ( string_from `SELECT COUNT(*)` )
    ( string_push_str sql AG_MSG_WHERE )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db ( string_data sql ) ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 channel )
                    ( _ag_bind_s q 2 from )
                    ( _ag_bind_str q 3 ( _ag_like_pat text ) )
                    ( _ag_bind_i q 4 0 )
                    ? ( _ag_row q ) { = n ( sqlite_column_int q 0 ) } {}
                }
            }
        }
    }
    ^ n
}

// ── Tasks ────────────────────────────────────────────────────────────

// Rewrite a task's text and standing. `status` must be one of the
// four; a task set back to open loses its holder and lease.
@ ag_task_edit AgStore st i id s title s body s tags i priority s status i now → b {
    : b known | | | != 0 ( nurl_str_eq status `open` ) != 0 ( nurl_str_eq status `claimed` )
    != 0 ( nurl_str_eq status `done` ) != 0 ( nurl_str_eq status `cancelled` )
    ? known {} { ^ F }
    : ~ b ok F
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `UPDATE tasks SET title = ?2, body = ?3, tags = ?4, priority = ?5, status = ?6, updated = ?7, owner = CASE WHEN ?6 = 'open' THEN '' ELSE owner END, lease_until = CASE WHEN ?6 = 'open' THEN 0 ELSE lease_until END WHERE id = ?1` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_i q 1 id )
                    ( _ag_bind_s q 2 title )
                    ( _ag_bind_s q 3 body )
                    ( _ag_bind_s q 4 tags )
                    ( _ag_bind_i q 5 priority )
                    ( _ag_bind_s q 6 status )
                    ( _ag_bind_i q 7 now )
                    = ok & ( _ag_run q ) > ( sqlite_changes db ) 0
                }
            }
        }
    }
    ^ ok
}

@ ag_task_delete AgStore st i id → b {
    : ~ b ok F
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → { = ok & ( __ag_on_i db `DELETE FROM tasks WHERE id = ?1` id ) > ( sqlite_changes db ) 0 }
    }
    ^ ok
}

// The filter every task listing of the page shares: ?1 status, ?2
// holder, ?3 a LIKE pattern for title, body or tags ('' = any of each),
// ?4 1 = leave out what is finished (done, cancelled).
: s AG_TASK_WHERE ` FROM tasks WHERE (?1 = '' OR status = ?1) AND (?2 = '' OR owner = ?2) AND (?3 = '' OR title LIKE ?3 ESCAPE '\\' OR body LIKE ?3 ESCAPE '\\' OR tags LIKE ?3 ESCAPE '\\') AND (?4 = 0 OR status NOT IN ('done', 'cancelled'))`

// The column a page is sorted by: one of a fixed list, so nothing a
// caller writes reaches the SQL. Anything else is `updated`.
@ ag_task_sort_col s sort → s {
    ? != 0 ( nurl_str_eq sort `id` ) { ^ `id` } {}
    ? != 0 ( nurl_str_eq sort `title` ) { ^ `title COLLATE NOCASE` } {}
    ? != 0 ( nurl_str_eq sort `status` ) { ^ `status` } {}
    ? != 0 ( nurl_str_eq sort `poster` ) { ^ `poster` } {}
    ? != 0 ( nurl_str_eq sort `owner` ) { ^ `owner` } {}
    ? != 0 ( nurl_str_eq sort `priority` ) { ^ `priority` } {}
    ? != 0 ( nurl_str_eq sort `created` ) { ^ `created` } {}
    ^ `updated`
}

// A page of tasks for the web page: filtered (`status` '' = any, `holder`
// '' = anyone, `text` '' = anything, `hide_done`), sorted by `sort`
// (ag_task_sort_col) ascending or `desc`, `limit` from `offset`. Leases
// that ran out are reopened first, as every task read does.
@ ag_tasks_page AgStore st s status s holder s text b hide_done s sort b desc i limit i offset i now → ( Vec AgTask ) {
    : ( Vec AgTask ) out ( vec_new [AgTask] )
    : s dir ? desc ` DESC` ` ASC`
    : String sql ( string_from `SELECT ` )
    ( string_push_str sql AG_TASK_COLS )
    ( string_push_str sql AG_TASK_WHERE )
    ( string_push_str sql ` ORDER BY ` )
    ( string_push_str sql ( ag_task_sort_col sort ) )
    ( string_push_str sql dir )
    ( string_push_str sql `, id` )
    ( string_push_str sql dir )
    ( string_push_str sql ` LIMIT ?5 OFFSET ?6` )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ? ( _ag_begin db ) { ( _ag_expire_on db now ) ( _ag_commit db ) } {}
            ?? ( sqlite_prepare db ( string_data sql ) ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 status )
                    ( _ag_bind_s q 2 holder )
                    ( _ag_bind_str q 3 ( _ag_like_pat text ) )
                    ( _ag_bind_i q 4 ? hide_done 1 0 )
                    ( _ag_bind_i q 5 limit )
                    ( _ag_bind_i q 6 offset )
                    ~ ( _ag_row q ) { ( vec_push [AgTask] out ( _ag_read_task q ) ) }
                }
            }
        }
    }
    ^ out
}

@ ag_tasks_count AgStore st s status s holder s text b hide_done → i {
    : ~ i n 0
    : String sql ( string_from `SELECT COUNT(*)` )
    ( string_push_str sql AG_TASK_WHERE )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db ( string_data sql ) ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 status )
                    ( _ag_bind_s q 2 holder )
                    ( _ag_bind_str q 3 ( _ag_like_pat text ) )
                    ( _ag_bind_i q 4 ? hide_done 1 0 )
                    ? ( _ag_row q ) { = n ( sqlite_column_int q 0 ) } {}
                }
            }
        }
    }
    ^ n
}

// ── Notes ────────────────────────────────────────────────────────────

// The filter of the page's notes: ?1 a LIKE pattern for key or body ('' =
// any), ?2 `rules` (only rules), `notes` (only plain notes) or '' (both).
: s AG_NOTE_WHERE ` FROM notes WHERE (?1 = '' OR key LIKE ?1 ESCAPE '\\' OR body LIKE ?1 ESCAPE '\\') AND (?2 = '' OR (?2 = 'rules' AND rule = 1) OR (?2 = 'notes' AND rule = 0))`

// A page of notes with their bodies: rules first, then by key (`sort`
// `updated`: the most recently written first).
@ ag_notes_page AgStore st s text s kind s sort i limit i offset → ( Vec AgNote ) {
    : ( Vec AgNote ) out ( vec_new [AgNote] )
    : String sql ( string_from `SELECT ` )
    ( string_push_str sql AG_NOTE_COLS )
    ( string_push_str sql AG_NOTE_WHERE )
    ( string_push_str sql ? != 0 ( nurl_str_eq sort `updated` ) ` ORDER BY updated DESC, project, key` ` ORDER BY rule DESC, project, key` )
    ( string_push_str sql ` LIMIT ?3 OFFSET ?4` )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db ( string_data sql ) ) {
                F _ → {}
                T q → {
                    ( _ag_bind_str q 1 ( _ag_like_pat text ) )
                    ( _ag_bind_s q 2 kind )
                    ( _ag_bind_i q 3 limit )
                    ( _ag_bind_i q 4 offset )
                    ~ ( _ag_row q ) { ( vec_push [AgNote] out ( _ag_read_note q ) ) }
                }
            }
        }
    }
    ^ out
}

@ ag_notes_count AgStore st s text s kind → i {
    : ~ i n 0
    : String sql ( string_from `SELECT COUNT(*)` )
    ( string_push_str sql AG_NOTE_WHERE )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db ( string_data sql ) ) {
                F _ → {}
                T q → {
                    ( _ag_bind_str q 1 ( _ag_like_pat text ) )
                    ( _ag_bind_s q 2 kind )
                    ? ( _ag_row q ) { = n ( sqlite_column_int q 0 ) } {}
                }
            }
        }
    }
    ^ n
}

// ── Cleaning up ──────────────────────────────────────────────────────
//
// An agent name is made on first use and nobody's, so a busy repository
// collects agents that came once and never again, finished tasks, and
// channels nobody posts to. Each kind has its own cutoff time (0 leaves
// that kind alone); `dry` counts what would go and changes nothing.
//
//   agents    not seen since the cutoff: deleted as ag_agent_delete does
//             (mailbox, follows, cursors; a held task reopens)
//   tasks     done or cancelled, last changed before the cutoff
//   messages  posted before the cutoff, channel posts and mail alike
//   channels  every one but `public` made before the cutoff with no post
//             since, with what is left in it

: AgCleanup {
    i agents
    i tasks
    i messages
    i channels
}

// The names `sql` (?1 = cutoff) selects.
@ __ag_names_on Database db s sql i cutoff → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( sqlite_prepare db sql ) {
        F _ → {}
        T q → {
            ( _ag_bind_i q 1 cutoff )
            ~ ( _ag_row q ) { ( vec_push [String] out ( sqlite_column_text q 0 ) ) }
        }
    }
    ^ out
}

// The count `sql` (?1 = cutoff) answers.
@ __ag_count_on Database db s sql i cutoff → i {
    : ~ i n 0
    ?? ( sqlite_prepare db sql ) {
        F _ → {}
        T q → {
            ( _ag_bind_i q 1 cutoff )
            ? ( _ag_row q ) { = n ( sqlite_column_int q 0 ) } {}
        }
    }
    ^ n
}

: s AG_STALE_CHANNELS `SELECT name FROM channels c WHERE name != 'public' AND created < ?1 AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.channel = c.name AND m.ts >= ?1) ORDER BY name`

@ ag_cleanup AgStore st i agents_before i tasks_before i msgs_before i channels_before b dry i now → AgCleanup {
    : ~ AgCleanup r @ AgCleanup { 0 0 0 0 }
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ? ( _ag_begin db ) {} { ^ r }
            : ~ b ok T
            ? > agents_before 0 {
                : ( Vec String ) ids ( __ag_names_on db `SELECT id FROM agents WHERE seen < ?1 ORDER BY id` agents_before )
                : i n ( vec_len [String] ids )
                = . r agents n
                ? dry {} {
                    : ~ i k 0
                    ~ < k n {
                        ?? ( vec_get [String] ids k ) {
                            T id → { = ok & ok ( __ag_agent_delete_on db ( string_data id ) now ) }
                            F _ → {}
                        }
                        = k + k 1
                    }
                }
            } {}
            ? > tasks_before 0 {
                = . r tasks ( __ag_count_on db `SELECT COUNT(*) FROM tasks WHERE status IN ('done', 'cancelled') AND updated < ?1` tasks_before )
                ? dry {} { = ok & ok ( __ag_on_i db `DELETE FROM tasks WHERE status IN ('done', 'cancelled') AND updated < ?1` tasks_before ) }
            } {}
            ? > msgs_before 0 {
                = . r messages ( __ag_count_on db `SELECT COUNT(*) FROM messages WHERE ts < ?1` msgs_before )
                ? dry {} { = ok & ok ( __ag_on_i db `DELETE FROM messages WHERE ts < ?1` msgs_before ) }
            } {}
            ? > channels_before 0 {
                : ( Vec String ) names ( __ag_names_on db AG_STALE_CHANNELS channels_before )
                : i n ( vec_len [String] names )
                = . r channels n
                ? dry {} {
                    : ~ i k 0
                    ~ < k n {
                        ?? ( vec_get [String] names k ) {
                            T c → { = ok & ok ( __ag_channel_delete_on db ( string_data c ) ) }
                            F _ → {}
                        }
                        = k + k 1
                    }
                }
            } {}
            ? & ok ! dry {
                ? ( _ag_commit db ) {} { ( _ag_rollback db ) = r @ AgCleanup { -1 -1 -1 -1 } }
            } {
                ( _ag_rollback db )
                ? ok {} { = r @ AgCleanup { -1 -1 -1 -1 } }
            }
        }
    }
    ^ r
}

// ── Counts for the overview ──────────────────────────────────────────

: AgTotals {
    i agents
    i channels
    i messages
    i tasks_open
    i tasks
    i notes
    i rules
}

@ ag_totals AgStore st → AgTotals {
    : ~ AgTotals t @ AgTotals { 0 0 0 0 0 0 0 }
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT (SELECT COUNT(*) FROM agents), (SELECT COUNT(*) FROM channels), (SELECT COUNT(*) FROM messages WHERE substr(channel, 1, 1) != '@'), (SELECT COUNT(*) FROM tasks WHERE status IN ('open', 'claimed')), (SELECT COUNT(*) FROM tasks), (SELECT COUNT(*) FROM notes), (SELECT COUNT(*) FROM notes WHERE rule = 1)` ) {
                F _ → {}
                T q → {
                    ? ( _ag_row q ) {
                        = t @ AgTotals {
                            ( sqlite_column_int q 0 )
                            ( sqlite_column_int q 1 )
                            ( sqlite_column_int q 2 )
                            ( sqlite_column_int q 3 )
                            ( sqlite_column_int q 4 )
                            ( sqlite_column_int q 5 )
                            ( sqlite_column_int q 6 )
                        }
                    } {}
                }
            }
        }
    }
    ^ t
}
