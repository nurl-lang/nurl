// agora/src/trash.nu — expiry, and the trash bin it fills.
//
// Agents never clean up after themselves, so what a person used to clear
// out by hand on the Cleanup page expires by itself — and nothing that
// expires is deleted outright. It moves to the trash, whole: invisible to
// agents (not in brief, notes, history, tasks or any search), but kept,
// until a person restores it (back exactly as it was, same id or key) or
// deletes it for good on the web page. Deleting from the web page, the
// Cleanup page and an agent's `note_del` move things to the trash too.
//
// What expires, each kind on its own clock (an organisation's settings;
// 0 = never):
//
//   notes     not written (note_set) or read (note) for `notes` days;
//             never a rule, never a note a person marked to keep
//   posts     channel posts older than `posts` days
//   mail      direct mail (and task news) older than `mail` days that its
//             reader has been handed; unread mail never expires
//   tasks     done or cancelled `tasks` days ago; open and claimed never
//   agents    not seen for `agents` days, holding no task; with its
//             follows, cursors and mailbox
//   channels  every one but `public` with no post for `channels` days;
//             with its follows, cursors and what posts are left in it
//
// An item in the trash is one row: its kind, its ref (a note's key — with
// `project/` when it has one —, a message's or task's id, an agent's or
// channel's name), a line to recognise it by, and `data`: every row it
// was made of, per table, as JSON (SQLite's own json_object, so a column
// added later is carried too). Restoring writes the rows back; a note
// whose key was taken since asks to be renamed or to overwrite. A
// restored item is held from expiring for one more period (`hold`), or
// the next sweep would take it straight back.
//
// The trash is never emptied by itself unless the organisation says so
// (`empty_days`). Every move in or out is a line of `audit`.
//
// A sweep runs when a file is used, at most every AG_SWEEP_EVERY seconds
// per file (per process, and across processes through the file's
// `last_sweep` setting).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/ext/sqlite.nu`
$ `store.nu`

: i AG_SWEEP_EVERY 600

// ── Settings ─────────────────────────────────────────────────────────

: AgExpiry {
    i notes
    i posts
    i mail
    i tasks
    i agents
    i channels
    i empty_days  // empty the trash of what has been in it this long (0 = never)
}

@ ag_expiry_defaults → AgExpiry { ^ @ AgExpiry { 30 90 90 30 30 90 0 } }

@ __ag_setting_on Database db s key i dflt → i {
    : ~ i v dflt
    ?? ( sqlite_prepare db `SELECT value FROM settings WHERE key = ?1` ) {
        F _ → {}
        T q → {
            ( _ag_bind_s q 1 key )
            ? ( _ag_row q ) { = v ( sqlite_column_int q 0 ) } {}
        }
    }
    ^ v
}

@ __ag_setting_put_on Database db s key i value → b {
    ?? ( sqlite_prepare db `INSERT INTO settings (key, value) VALUES (?1, ?2) ON CONFLICT (key) DO UPDATE SET value = excluded.value` ) {
        F _ → { ^ F }
        T q → {
            ( _ag_bind_s q 1 key )
            ( _ag_bind_i q 2 value )
            ^ ( _ag_run q )
        }
    }
}

// The expiry times kept in `st` (an organisation's file, or the one
// local file); the defaults for what was never set.
@ ag_expiry_get AgStore st → AgExpiry {
    : AgExpiry d ( ag_expiry_defaults )
    ?? ( _ag_conn st ) {
        F _ → { ^ d }
        T db → {
            ^ @ AgExpiry {
                ( __ag_setting_on db `ttl_notes` . d notes )
                ( __ag_setting_on db `ttl_posts` . d posts )
                ( __ag_setting_on db `ttl_mail` . d mail )
                ( __ag_setting_on db `ttl_tasks` . d tasks )
                ( __ag_setting_on db `ttl_agents` . d agents )
                ( __ag_setting_on db `ttl_channels` . d channels )
                ( __ag_setting_on db `trash_empty_days` . d empty_days )
            }
        }
    }
}

@ ag_expiry_set AgStore st AgExpiry e → b {
    ?? ( _ag_conn st ) {
        F _ → { ^ F }
        T db → {
            ? ( _ag_begin db ) {} { ^ F }
            : b ok & & & & & & ( __ag_setting_put_on db `ttl_notes` . e notes )
            ( __ag_setting_put_on db `ttl_posts` . e posts )
            ( __ag_setting_put_on db `ttl_mail` . e mail )
            ( __ag_setting_put_on db `ttl_tasks` . e tasks )
            ( __ag_setting_put_on db `ttl_agents` . e agents )
            ( __ag_setting_put_on db `ttl_channels` . e channels )
            ( __ag_setting_put_on db `trash_empty_days` . e empty_days )
            ? ok { ^ ( _ag_commit db ) } {}
            ( _ag_rollback db )
            ^ F
        }
    }
}

// The days `kind` lives (0 = never expires).
@ ag_expiry_days AgExpiry e s kind → i {
    ? != 0 ( nurl_str_eq kind `note` ) { ^ . e notes } {}
    ? != 0 ( nurl_str_eq kind `task` ) { ^ . e tasks } {}
    ? != 0 ( nurl_str_eq kind `agent` ) { ^ . e agents } {}
    ? != 0 ( nurl_str_eq kind `channel` ) { ^ . e channels } {}
    ^ . e posts
}

// ── Rows as JSON, and back ───────────────────────────────────────────

// The tables an item may carry, and so the only ones a restore writes.
@ __ag_trash_table_ok s t → b {
    ^ | | | | | | != 0 ( nurl_str_eq t `notes` ) != 0 ( nurl_str_eq t `messages` ) != 0 ( nurl_str_eq t `tasks` )
    != 0 ( nurl_str_eq t `agents` ) != 0 ( nurl_str_eq t `channels` ) != 0 ( nurl_str_eq t `follows` ) != 0 ( nurl_str_eq t `cursors` )
}

@ __ag_cols_on Database db s table → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( sqlite_prepare db `SELECT name FROM pragma_table_info(?1) ORDER BY cid` ) {
        F _ → {}
        T q → {
            ( _ag_bind_s q 1 table )
            ~ ( _ag_row q ) { ( vec_push [String] out ( sqlite_column_text q 0 ) ) }
        }
    }
    ^ out
}

// `json_object('c1', a.c1, 'c2', a.c2, …)` over every column of `table`.
@ __ag_jobj_on Database db s table s alias → String {
    : ( Vec String ) cols ( __ag_cols_on db table )
    : String out ( string_from `json_object(` )
    : i n ( vec_len [String] cols )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] cols k ) {
            T c → {
                ? > k 0 { ( string_push_str out `, ` ) } {}
                ( string_push_str out `'` )
                ( string_push_str out ( string_data c ) )
                ( string_push_str out `', ` )
                ( string_push_str out alias )
                ( string_push_str out `.` )
                ( string_push_str out ( string_data c ) )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( string_push_str out `)` )
    ^ out
}

// `(SELECT json_group_array(…) FROM table a WHERE cond)`.
@ __ag_jrows_on Database db s table s alias s cond → String {
    : String out ( string_from `(SELECT json_group_array(` )
    ( string_push_str out ( string_data ( __ag_jobj_on db table alias ) ) )
    ( string_push_str out `) FROM ` )
    ( string_push_str out table )
    ( string_push_str out ` ` )
    ( string_push_str out alias )
    ( string_push_str out ` WHERE ` )
    ( string_push_str out cond )
    ( string_push_str out `)` )
    ^ out
}

// Write back the rows of `table` in item `data` (`verb` INSERT, INSERT
// OR REPLACE or INSERT OR IGNORE). Only the columns both the item and
// the table have: a column added since takes its default.
@ __ag_restore_rows_on Database db s data s table s verb → b {
    : ( Vec String ) cols ( __ag_cols_on db table )
    : ( Vec String ) keys ( vec_new [String] )
    : String path ( string_from `$.` )
    ( string_push_str path table )
    : String first ( string_from ( string_data path ) )
    ( string_push_str first `[0]` )
    ?? ( sqlite_prepare db `SELECT key FROM json_each(json_extract(?1, ?2))` ) {
        F _ → { ^ F }
        T q → {
            ( _ag_bind_s q 1 data )
            ( _ag_bind_s q 2 ( string_data first ) )
            ~ ( _ag_row q ) { ( vec_push [String] keys ( sqlite_column_text q 0 ) ) }
        }
    }
    ? == ( vec_len [String] keys ) 0 { ^ T } {}
    : String names ( string_new )
    : String vals ( string_new )
    : i n ( vec_len [String] cols )
    : ~ i k 0
    : ~ i used 0
    ~ < k n {
        ?? ( vec_get [String] cols k ) {
            T c → {
                : ~ b has F
                : i m ( vec_len [String] keys )
                : ~ i j 0
                ~ & ! has < j m {
                    ?? ( vec_get [String] keys j ) { T x → { = has != 0 ( nurl_str_eq ( string_data x ) ( string_data c ) ) } F _ → {} }
                    = j + j 1
                }
                ? has {
                    ? > used 0 { ( string_push_str names `, ` ) ( string_push_str vals `, ` ) } {}
                    ( string_push_str names ( string_data c ) )
                    ( string_push_str vals `json_extract(value, '$.` )
                    ( string_push_str vals ( string_data c ) )
                    ( string_push_str vals `')` )
                    = used + used 1
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    : String sql ( string_from verb )
    ( string_push_str sql ` INTO ` )
    ( string_push_str sql table )
    ( string_push_str sql ` (` )
    ( string_push_str sql ( string_data names ) )
    ( string_push_str sql `) SELECT ` )
    ( string_push_str sql ( string_data vals ) )
    ( string_push_str sql ` FROM json_each(json_extract(?1, ?2))` )
    ?? ( sqlite_prepare db ( string_data sql ) ) {
        F _ → { ^ F }
        T q → {
            ( _ag_bind_s q 1 data )
            ( _ag_bind_s q 2 ( string_data path ) )
            ^ ( _ag_run q )
        }
    }
}

// ── Into the trash ───────────────────────────────────────────────────

// The SELECT list that makes `kind`'s trash row out of its table's row `x`.
@ __ag_trash_select_on Database db s kind → String {
    : String o ( string_new )
    ? != 0 ( nurl_str_eq kind `note` ) {
        ( string_push_str o `'note', CASE WHEN x.project = '' THEN x.key ELSE x.project || '/' || x.key END, CASE WHEN x.description != '' THEN x.description ELSE substr(x.body, 1, 160) END, x.author, MAX(x.updated, x.touched), ?3, ?4, ?5, json_object('notes', json_array(` )
        ( string_push_str o ( string_data ( __ag_jobj_on db `notes` `x` ) ) )
        ( string_push_str o `)) FROM notes x` )
        ^ o
    } {}
    ? != 0 ( nurl_str_eq kind `message` ) {
        ( string_push_str o `'message', CAST(x.id AS TEXT), x.channel || ': ' || substr(x.body, 1, 160), x.sender, x.ts, ?3, ?4, ?5, json_object('messages', json_array(` )
        ( string_push_str o ( string_data ( __ag_jobj_on db `messages` `x` ) ) )
        ( string_push_str o `)) FROM messages x` )
        ^ o
    } {}
    ? != 0 ( nurl_str_eq kind `task` ) {
        ( string_push_str o `'task', CAST(x.id AS TEXT), x.title, x.poster, x.updated, ?3, ?4, ?5, json_object('tasks', json_array(` )
        ( string_push_str o ( string_data ( __ag_jobj_on db `tasks` `x` ) ) )
        ( string_push_str o `)) FROM tasks x` )
        ^ o
    } {}
    ? != 0 ( nurl_str_eq kind `agent` ) {
        ( string_push_str o `'agent', x.id, x.about, '', x.seen, ?3, ?4, ?5, json_object('agents', json_array(` )
        ( string_push_str o ( string_data ( __ag_jobj_on db `agents` `x` ) ) )
        ( string_push_str o `), 'follows', json(` )
        ( string_push_str o ( string_data ( __ag_jrows_on db `follows` `f` `f.agent = x.id` ) ) )
        ( string_push_str o `), 'cursors', json(` )
        ( string_push_str o ( string_data ( __ag_jrows_on db `cursors` `c` `c.agent = x.id` ) ) )
        ( string_push_str o `), 'messages', json(` )
        ( string_push_str o ( string_data ( __ag_jrows_on db `messages` `m` `m.channel = '@' || x.id` ) ) )
        ( string_push_str o `)) FROM agents x` )
        ^ o
    } {}
    ( string_push_str o `'channel', x.name, x.about, x.created_by, (SELECT COALESCE(MAX(m.ts), x.created) FROM messages m WHERE m.channel = x.name), ?3, ?4, ?5, json_object('channels', json_array(` )
    ( string_push_str o ( string_data ( __ag_jobj_on db `channels` `x` ) ) )
    ( string_push_str o `), 'follows', json(` )
    ( string_push_str o ( string_data ( __ag_jrows_on db `follows` `f` `f.channel = x.name` ) ) )
    ( string_push_str o `), 'cursors', json(` )
    ( string_push_str o ( string_data ( __ag_jrows_on db `cursors` `c` `c.channel = x.name` ) ) )
    ( string_push_str o `), 'messages', json(` )
    ( string_push_str o ( string_data ( __ag_jrows_on db `messages` `m` `m.channel = x.name` ) ) )
    ( string_push_str o `)) FROM channels x` )
    ^ o
}

// What leaves the live tables once rows `id > ?1` of the trash hold it.
@ __ag_trash_deletes s kind → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ? != 0 ( nurl_str_eq kind `note` ) {
        ( vec_push [String] v ( string_from `DELETE FROM notes WHERE (project, key) IN (SELECT json_extract(data, '$.notes[0].project'), json_extract(data, '$.notes[0].key') FROM trash WHERE id > ?1 AND kind = 'note')` ) )
        ^ v
    } {}
    ? != 0 ( nurl_str_eq kind `message` ) {
        ( vec_push [String] v ( string_from `DELETE FROM messages WHERE id IN (SELECT CAST(ref AS INTEGER) FROM trash WHERE id > ?1 AND kind = 'message')` ) )
        ^ v
    } {}
    ? != 0 ( nurl_str_eq kind `task` ) {
        ( vec_push [String] v ( string_from `DELETE FROM tasks WHERE id IN (SELECT CAST(ref AS INTEGER) FROM trash WHERE id > ?1 AND kind = 'task')` ) )
        ^ v
    } {}
    ? != 0 ( nurl_str_eq kind `agent` ) {
        // A task the agent held is open again (a person's delete may take
        // a holder; expiry never does).
        ( vec_push [String] v ( string_from `INSERT INTO task_events (task, ts, kind, agent) SELECT id, ?2, 'open', 'web' FROM tasks WHERE status = 'claimed' AND owner IN (SELECT ref FROM trash WHERE id > ?1 AND kind = 'agent')` ) )
        ( vec_push [String] v ( string_from `UPDATE tasks SET status = 'open', owner = '', lease_until = 0, updated = ?2 WHERE status = 'claimed' AND owner IN (SELECT ref FROM trash WHERE id > ?1 AND kind = 'agent')` ) )
        ( vec_push [String] v ( string_from `DELETE FROM follows WHERE agent IN (SELECT ref FROM trash WHERE id > ?1 AND kind = 'agent')` ) )
        ( vec_push [String] v ( string_from `DELETE FROM cursors WHERE agent IN (SELECT ref FROM trash WHERE id > ?1 AND kind = 'agent')` ) )
        ( vec_push [String] v ( string_from `DELETE FROM messages WHERE channel IN (SELECT '@' || ref FROM trash WHERE id > ?1 AND kind = 'agent')` ) )
        ( vec_push [String] v ( string_from `DELETE FROM agents WHERE id IN (SELECT ref FROM trash WHERE id > ?1 AND kind = 'agent')` ) )
        ^ v
    } {}
    ( vec_push [String] v ( string_from `DELETE FROM follows WHERE channel IN (SELECT ref FROM trash WHERE id > ?1 AND kind = 'channel')` ) )
    ( vec_push [String] v ( string_from `DELETE FROM cursors WHERE channel IN (SELECT ref FROM trash WHERE id > ?1 AND kind = 'channel')` ) )
    ( vec_push [String] v ( string_from `DELETE FROM messages WHERE channel IN (SELECT ref FROM trash WHERE id > ?1 AND kind = 'channel')` ) )
    ( vec_push [String] v ( string_from `DELETE FROM channels WHERE name IN (SELECT ref FROM trash WHERE id > ?1 AND kind = 'channel')` ) )
    ^ v
}

@ __ag_max_trash_on Database db → i {
    : ~ i m 0
    ?? ( sqlite_prepare db `SELECT COALESCE(MAX(id), 0) FROM trash` ) {
        F _ → {}
        T q → { ? ( _ag_row q ) { = m ( sqlite_column_int q 0 ) } {} }
    }
    ^ m
}

// Move every `kind` row `x` that `cond` selects into the trash, inside
// the caller's transaction. `cond` may use ?1 (text `a`), ?2 (integer
// `n`), ?6 (now) and ?7 (text `b`); `held` T leaves out what a restore
// holds back (expiry), F takes it anyway (a person's delete). The count
// moved, -1 when a statement failed.
@ _ag_trash_on Database db s kind s cond s a i n s b b held s reason s by i now → i {
    : i m ( __ag_max_trash_on db )
    : String sql ( string_from `INSERT INTO trash (kind, ref, label, author, touched, trashed, reason, by, data) SELECT ` )
    ( string_push_str sql ( string_data ( __ag_trash_select_on db kind ) ) )
    ( string_push_str sql ` WHERE (` )
    ( string_push_str sql cond )
    ( string_push_str sql `)` )
    ? held {
        ( string_push_str sql ` AND NOT EXISTS (SELECT 1 FROM hold h WHERE h.kind = '` )
        ( string_push_str sql kind )
        ( string_push_str sql `' AND h.until > ?6 AND h.ref = ` )
        ( string_push_str sql ? != 0 ( nurl_str_eq kind `note` ) `CASE WHEN x.project = '' THEN x.key ELSE x.project || '/' || x.key END`
        ? | != 0 ( nurl_str_eq kind `message` ) != 0 ( nurl_str_eq kind `task` ) `CAST(x.id AS TEXT)`
        ? != 0 ( nurl_str_eq kind `agent` ) `x.id` `x.name` )
        ( string_push_str sql `)` )
    } {}
    : ~ i moved -1
    ?? ( sqlite_prepare db ( string_data sql ) ) {
        F _ → { ^ -1 }
        T q → {
            ( _ag_bind_s q 1 a )
            ( _ag_bind_i q 2 n )
            ( _ag_bind_i q 3 now )
            ( _ag_bind_s q 4 reason )
            ( _ag_bind_s q 5 by )
            ( _ag_bind_i q 6 now )
            ( _ag_bind_s q 7 b )
            ? ( _ag_run q ) { = moved ( sqlite_changes db ) } {}
        }
    }
    ? <= moved 0 { ^ moved } {}
    : ( Vec String ) dels ( __ag_trash_deletes kind )
    : i nd ( vec_len [String] dels )
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k nd {
        ?? ( vec_get [String] dels k ) {
            T d → {
                ?? ( sqlite_prepare db ( string_data d ) ) {
                    F _ → { = ok F }
                    T q → {
                        ( _ag_bind_i q 1 m )
                        ( _ag_bind_i q 2 now )
                        = ok ( _ag_run q )
                    }
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ? ok {} { ^ -1 }
    ?? ( sqlite_prepare db `DELETE FROM hold WHERE (kind, ref) IN (SELECT kind, ref FROM trash WHERE id > ?1)` ) {
        F _ → {}
        T q → { ( _ag_bind_i q 1 m ) ( _ag_run q ) }
    }
    ?? ( sqlite_prepare db `INSERT INTO audit (ts, action, kind, ref, label, by) SELECT trashed, CASE WHEN reason = 'expired' THEN 'expire' ELSE 'trash' END, kind, ref, label, by FROM trash WHERE id > ?1 ORDER BY id` ) {
        F _ → {}
        T q → { ( _ag_bind_i q 1 m ) ( _ag_run q ) }
    }
    ^ moved
}

// The same in a transaction of its own: one item a person (or an agent's
// note_del) deletes. 1 moved, 0 nothing matched, -1 failed.
@ ag_trash_put AgStore st s kind s cond s a i n s b s reason s by i now → i {
    ?? ( _ag_conn st ) {
        F _ → { ^ -1 }
        T db → {
            ? ( _ag_begin db ) {} { ^ -1 }
            : i r ( _ag_trash_on db kind cond a n b F reason by now )
            ? > r 0 { ? ( _ag_commit db ) { ^ r } {} } {}
            ( _ag_rollback db )
            ^ r
        }
    }
}

@ ag_trash_note AgStore st s project s key s by i now → i {
    ^ ( ag_trash_put st `note` `x.project = ?1 AND x.key = ?7` project 0 key `deleted` by now )
}

@ ag_trash_message AgStore st i id s by i now → i {
    ^ ( ag_trash_put st `message` `x.id = ?2` `` id `` `deleted` by now )
}

@ ag_trash_task AgStore st i id s by i now → i {
    ^ ( ag_trash_put st `task` `x.id = ?2` `` id `` `deleted` by now )
}

@ ag_trash_agent AgStore st s id s by i now → i {
    ^ ( ag_trash_put st `agent` `x.id = ?1` id 0 `` `deleted` by now )
}

@ ag_trash_channel AgStore st s name s by i now → i {
    ^ ( ag_trash_put st `channel` `x.name = ?1 AND x.name != 'public'` name 0 `` `deleted` by now )
}

// ── Expiry ───────────────────────────────────────────────────────────

: AgSwept {
    i notes
    i posts
    i mail
    i tasks
    i agents
    i channels
    i emptied
}

// Files swept in this process, and when each is next due.
: AgSweepClock {
    ( Vec String ) paths
    ( Vec i ) due
}

@ __ag_sweep_blank → ( Locked AgSweepClock ) {
    ^ ( locked_new [AgSweepClock] @ AgSweepClock { ( vec_new [String] ) ( vec_new [i] ) } )
}

: ( Locked AgSweepClock ) g_ag_sweep ( __ag_sweep_blank )

// Is the file at `path` due a sweep? Marks it swept when it is, so one
// request of many sweeps it.
@ __ag_sweep_due s path i now → b {
    : ~ AgSweepClock c ( locked_take [AgSweepClock] g_ag_sweep )
    : i n ( vec_len [String] . c paths )
    : ~ i k 0
    : ~ i at -1
    ~ & < at 0 < k n {
        ?? ( vec_get [String] . c paths k ) { T p → { ? != 0 ( nurl_str_eq ( string_data p ) path ) { = at k } {} } F _ → {} }
        = k + k 1
    }
    : ~ b due T
    ? >= at 0 {
        : i when ?? ( vec_get [i] . c due at ) { T x → x F _ → 0 }
        = due >= now when
        ? due { : b _set ( vec_set [i] . c due at + now AG_SWEEP_EVERY ) } {}
    } {
        ( vec_push [String] . c paths ( string_from path ) )
        ( vec_push [i] . c due + now AG_SWEEP_EVERY )
    }
    ( locked_restore [AgSweepClock] g_ag_sweep c )
    ^ due
}

// Forget when files were swept (tests: sweep again at once).
@ ag_sweep_clock_reset → v {
    : AgSweepClock c ( locked_take [AgSweepClock] g_ag_sweep )
    ( locked_restore [AgSweepClock] g_ag_sweep @ AgSweepClock { ( vec_new [String] ) ( vec_new [i] ) } )
}

@ __ag_cutoff i days i now → i { ^ - now * days 86400 }

// Expire what the settings in `settings` say has had its time in the
// file `st` — when it is due (see the header). Cheap when it is not:
// one look at a clock in memory.
@ ag_sweep_maybe AgStore st AgStore settings i now → v {
    ? & . st ok > ( string_len . st path ) 0 {} { ^ v }
    ? ( __ag_sweep_due ( string_data . st path ) now ) {} { ^ v }
    : AgSwept _r ( ag_sweep st ( ag_expiry_get settings ) F now )
}

// Expire what `e` says has had its time in the file `st`, now; `force`
// sweeps even when another process just did. Returns what moved.
@ ag_sweep AgStore st AgExpiry e b force i now → AgSwept {
    : ~ AgSwept r @ AgSwept { 0 0 0 0 0 0 0 }
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ? ( _ag_begin db ) {} { ^ r }
            // Another process sharing the file may have just swept it.
            : i last ( __ag_setting_on db `last_sweep` 0 )
            ? & ! force > + last AG_SWEEP_EVERY now { ( _ag_rollback db ) ^ r } {}
            ( __ag_setting_put_on db `last_sweep` now )
            : ~ b ok T
            ? > . e tasks 0 {
                = . r tasks ( _ag_trash_on db `task` `x.status IN ('done', 'cancelled') AND x.updated < ?2` `` ( __ag_cutoff . e tasks now ) `` T `expired` `agora` now )
            } {}
            ? > . e notes 0 {
                = . r notes ( _ag_trash_on db `note` `x.rule = 0 AND x.keep = 0 AND MAX(x.updated, x.touched) < ?2` `` ( __ag_cutoff . e notes now ) `` T `expired` `agora` now )
            } {}
            ? > . e posts 0 {
                = . r posts ( _ag_trash_on db `message` `x.channel NOT LIKE '@%' AND x.ts < ?2` `` ( __ag_cutoff . e posts now ) `` T `expired` `agora` now )
            } {}
            ? > . e mail 0 {
                = . r mail ( _ag_trash_on db `message` `x.channel LIKE '@%' AND x.ts < ?2 AND x.id <= COALESCE((SELECT c.last_id FROM cursors c WHERE c.agent = substr(x.channel, 2) AND c.channel = x.channel), 0)` `` ( __ag_cutoff . e mail now ) `` T `expired` `agora` now )
            } {}
            ? > . e agents 0 {
                = . r agents ( _ag_trash_on db `agent` `x.seen < ?2 AND NOT EXISTS (SELECT 1 FROM tasks t WHERE t.status = 'claimed' AND t.owner = x.id)` `` ( __ag_cutoff . e agents now ) `` T `expired` `agora` now )
            } {}
            ? > . e channels 0 {
                = . r channels ( _ag_trash_on db `channel` `x.name != 'public' AND x.created < ?2 AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.channel = x.name AND m.ts >= ?2)` `` ( __ag_cutoff . e channels now ) `` T `expired` `agora` now )
            } {}
            = ok & & & & & & ok >= . r tasks 0 >= . r notes 0 >= . r posts 0 >= . r mail 0 >= . r agents 0 >= . r channels 0
            ? & ok > . e empty_days 0 {
                : i cut ( __ag_cutoff . e empty_days now )
                ?? ( sqlite_prepare db `INSERT INTO audit (ts, action, kind, ref, label, by) SELECT ?2, 'empty', kind, ref, label, 'agora' FROM trash WHERE trashed < ?1` ) {
                    F _ → {}
                    T q → { ( _ag_bind_i q 1 cut ) ( _ag_bind_i q 2 now ) ( _ag_run q ) }
                }
                ?? ( sqlite_prepare db `DELETE FROM trash WHERE trashed < ?1` ) {
                    F _ → { = ok F }
                    T q → {
                        ( _ag_bind_i q 1 cut )
                        = ok ( _ag_run q )
                        = . r emptied ( sqlite_changes db )
                    }
                }
            } {}
            ? ok { ? ( _ag_commit db ) {} { ( _ag_rollback db ) = r @ AgSwept { 0 0 0 0 0 0 0 } } } {
                ( _ag_rollback db )
                = r @ AgSwept { 0 0 0 0 0 0 0 }
            }
        }
    }
    ^ r
}

// ── Out of the trash ─────────────────────────────────────────────────

: AgTrash {
    i id
    String kind
    String ref
    String label
    String author
    i touched
    i trashed
    String reason
    String by
}

: i AG_RESTORED 0
: i AG_RESTORE_GONE 1
: i AG_RESTORE_TAKEN 2  // a note's key, an agent's or channel's name is in use again
: i AG_RESTORE_FAILED 3

// Is `ref` of `kind` live again (made since it went to the trash)?
@ __ag_live_on Database db s kind s ref → b {
    : s sql ? != 0 ( nurl_str_eq kind `note` ) `SELECT COUNT(*) FROM notes WHERE (CASE WHEN project = '' THEN key ELSE project || '/' || key END) = ?1`
    ? != 0 ( nurl_str_eq kind `message` ) `SELECT COUNT(*) FROM messages WHERE id = CAST(?1 AS INTEGER)`
    ? != 0 ( nurl_str_eq kind `task` ) `SELECT COUNT(*) FROM tasks WHERE id = CAST(?1 AS INTEGER)`
    ? != 0 ( nurl_str_eq kind `agent` ) `SELECT COUNT(*) FROM agents WHERE id = ?1`
    `SELECT COUNT(*) FROM channels WHERE name = ?1`
    : ~ b live F
    ?? ( sqlite_prepare db sql ) {
        F _ → {}
        T q → {
            ( _ag_bind_s q 1 ref )
            ? ( _ag_row q ) { = live > ( sqlite_column_int q 0 ) 0 } {}
        }
    }
    ^ live
}

// Put item `id` back as it was. `mode` '' refuses to replace what has
// taken its name since (AG_RESTORE_TAKEN); `overwrite` replaces it;
// `rename` (a note) restores it under `new_key`. It is then held from
// expiring for `hold_days`.
@ ag_trash_restore AgStore st i id s mode s new_key i hold_days s by i now → i {
    ?? ( _ag_conn st ) {
        F _ → { ^ AG_RESTORE_FAILED }
        T db → {
            ? ( _ag_begin db ) {} { ^ AG_RESTORE_FAILED }
            : ~ String kind ( string_new )
            : ~ String ref ( string_new )
            : ~ String label ( string_new )
            : ~ String data ( string_new )
            : ~ b found F
            ?? ( sqlite_prepare db `SELECT kind, ref, label, data FROM trash WHERE id = ?1` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_i q 1 id )
                    ? ( _ag_row q ) {
                        = kind ( sqlite_column_text q 0 )
                        = ref ( sqlite_column_text q 1 )
                        = label ( sqlite_column_text q 2 )
                        = data ( sqlite_column_text q 3 )
                        = found T
                    } {}
                }
            }
            ? found {} { ( _ag_rollback db ) ^ AG_RESTORE_GONE }
            : b is_note != 0 ( nurl_str_eq ( string_data kind ) `note` )
            : b rename & is_note != 0 ( nurl_str_eq mode `rename` )
            : b overwrite != 0 ( nurl_str_eq mode `overwrite` )
            // A rename writes the note's new key into its row, and so its ref.
            ? rename {
                ?? ( sqlite_prepare db `SELECT json_set(?1, '$.notes[0].key', ?2), CASE WHEN json_extract(?1, '$.notes[0].project') = '' THEN ?2 ELSE json_extract(?1, '$.notes[0].project') || '/' || ?2 END` ) {
                    F _ → {}
                    T q → {
                        ( _ag_bind_s q 1 ( string_data data ) )
                        ( _ag_bind_s q 2 new_key )
                        ? ( _ag_row q ) {
                            = data ( sqlite_column_text q 0 )
                            = ref ( sqlite_column_text q 1 )
                        } {}
                    }
                }
            } {}
            ? & ! overwrite ( __ag_live_on db ( string_data kind ) ( string_data ref ) ) { ( _ag_rollback db ) ^ AG_RESTORE_TAKEN } {}
            // Each table the item carries, in the order it was taken: the
            // item's own row first, then what hung off it.
            : ( Vec String ) tables ( vec_new [String] )
            ?? ( sqlite_prepare db `SELECT key FROM json_each(?1)` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 ( string_data data ) )
                    ~ ( _ag_row q ) { ( vec_push [String] tables ( sqlite_column_text q 0 ) ) }
                }
            }
            : ~ b ok T
            : i nt ( vec_len [String] tables )
            : ~ i k 0
            ~ & ok < k nt {
                ?? ( vec_get [String] tables k ) {
                    T t → {
                        ? ( __ag_trash_table_ok ( string_data t ) ) {
                            : s verb ? == k 0 ? overwrite `INSERT OR REPLACE` `INSERT` `INSERT OR IGNORE`
                            = ok ( __ag_restore_rows_on db ( string_data data ) ( string_data t ) verb )
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ? ok {} { ( _ag_rollback db ) ^ AG_RESTORE_FAILED }
            ?? ( sqlite_prepare db `DELETE FROM trash WHERE id = ?1` ) {
                F _ → {}
                T q → { ( _ag_bind_i q 1 id ) ( _ag_run q ) }
            }
            ? > hold_days 0 {
                ?? ( sqlite_prepare db `INSERT INTO hold (kind, ref, until) VALUES (?1, ?2, ?3) ON CONFLICT (kind, ref) DO UPDATE SET until = excluded.until` ) {
                    F _ → {}
                    T q → {
                        ( _ag_bind_s q 1 ( string_data kind ) )
                        ( _ag_bind_s q 2 ( string_data ref ) )
                        ( _ag_bind_i q 3 + now * hold_days 86400 )
                        ( _ag_run q )
                    }
                }
            } {}
            ( __ag_audit_on db now `restore` ( string_data kind ) ( string_data ref ) ( string_data label ) by )
            ? ( _ag_commit db ) { ^ AG_RESTORED } {}
            ( _ag_rollback db )
            ^ AG_RESTORE_FAILED
        }
    }
}

@ __ag_audit_on Database db i now s action s kind s ref s label s by → v {
    ?? ( sqlite_prepare db `INSERT INTO audit (ts, action, kind, ref, label, by) VALUES (?1, ?2, ?3, ?4, ?5, ?6)` ) {
        F _ → {}
        T q → {
            ( _ag_bind_i q 1 now )
            ( _ag_bind_s q 2 action )
            ( _ag_bind_s q 3 kind )
            ( _ag_bind_s q 4 ref )
            ( _ag_bind_s q 5 label )
            ( _ag_bind_s q 6 by )
            ( _ag_run q )
        }
    }
}

// Delete item `id` for good. F: no such item.
@ ag_trash_delete AgStore st i id s by i now → b {
    ?? ( _ag_conn st ) {
        F _ → { ^ F }
        T db → {
            ? ( _ag_begin db ) {} { ^ F }
            ?? ( sqlite_prepare db `INSERT INTO audit (ts, action, kind, ref, label, by) SELECT ?2, 'delete', kind, ref, label, ?3 FROM trash WHERE id = ?1` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_i q 1 id )
                    ( _ag_bind_i q 2 now )
                    ( _ag_bind_s q 3 by )
                    ( _ag_run q )
                }
            }
            : ~ b gone F
            ?? ( sqlite_prepare db `DELETE FROM trash WHERE id = ?1` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_i q 1 id )
                    = gone & ( _ag_run q ) > ( sqlite_changes db ) 0
                }
            }
            ? gone { ? ( _ag_commit db ) { ^ T } {} } {}
            ( _ag_rollback db )
            ^ F
        }
    }
}

// ── Reading the trash ────────────────────────────────────────────────

: s AG_TRASH_WHERE ` FROM trash WHERE (?1 = '' OR kind = ?1) AND (?2 = '' OR author = ?2) AND (?3 = 0 OR trashed < ?3) AND (?4 = '' OR ref LIKE ?4 ESCAPE '\\' OR label LIKE ?4 ESCAPE '\\')`

@ __ag_trash_bind Statement q s kind s author i before s text → v {
    ( _ag_bind_s q 1 kind )
    ( _ag_bind_s q 2 author )
    ( _ag_bind_i q 3 before )
    ( _ag_bind_str q 4 ( _ag_like_pat text ) )
}

// A page of the trash, newest first: of `kind`, by `author`, trashed
// before `before` (0 = any), matching `text` ('' = any of each).
@ ag_trash_page AgStore st s kind s author i before s text i limit i offset → ( Vec AgTrash ) {
    : ( Vec AgTrash ) out ( vec_new [AgTrash] )
    : String sql ( string_from `SELECT id, kind, ref, label, author, touched, trashed, reason, by` )
    ( string_push_str sql AG_TRASH_WHERE )
    ( string_push_str sql ` ORDER BY trashed DESC, id DESC LIMIT ?5 OFFSET ?6` )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db ( string_data sql ) ) {
                F _ → {}
                T q → {
                    ( __ag_trash_bind q kind author before text )
                    ( _ag_bind_i q 5 limit )
                    ( _ag_bind_i q 6 offset )
                    ~ ( _ag_row q ) {
                        ( vec_push [AgTrash] out @ AgTrash {
                            ( sqlite_column_int q 0 )
                            ( sqlite_column_text q 1 )
                            ( sqlite_column_text q 2 )
                            ( sqlite_column_text q 3 )
                            ( sqlite_column_text q 4 )
                            ( sqlite_column_int q 5 )
                            ( sqlite_column_int q 6 )
                            ( sqlite_column_text q 7 )
                            ( sqlite_column_text q 8 )
                        } )
                    }
                }
            }
        }
    }
    ^ out
}

@ ag_trash_count AgStore st s kind s author i before s text → i {
    : ~ i n 0
    : String sql ( string_from `SELECT COUNT(*)` )
    ( string_push_str sql AG_TRASH_WHERE )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db ( string_data sql ) ) {
                F _ → {}
                T q → {
                    ( __ag_trash_bind q kind author before text )
                    ? ( _ag_row q ) { = n ( sqlite_column_int q 0 ) } {}
                }
            }
        }
    }
    ^ n
}

// The ids a filter selects (for "restore / delete all of these").
@ ag_trash_ids AgStore st s kind s author i before s text → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : String sql ( string_from `SELECT id` )
    ( string_push_str sql AG_TRASH_WHERE )
    ( string_push_str sql ` ORDER BY id` )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db ( string_data sql ) ) {
                F _ → {}
                T q → {
                    ( __ag_trash_bind q kind author before text )
                    ~ ( _ag_row q ) { ( vec_push [i] out ( sqlite_column_int q 0 ) ) }
                }
            }
        }
    }
    ^ out
}

// Item `id`'s rows as JSON text ('' when there is no such item).
@ ag_trash_data AgStore st i id → String {
    : ~ String out ( string_new )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT data FROM trash WHERE id = ?1` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_i q 1 id )
                    ? ( _ag_row q ) { = out ( sqlite_column_text q 0 ) } {}
                }
            }
        }
    }
    ^ out
}

// When `ref` of `kind` went to the trash, and why (trashed 0: it is not
// there). An agent asking for something gone is told where it went.
: AgGone {
    i trashed
    String reason
}

@ ag_trash_find AgStore st s kind s ref → AgGone {
    : ~ AgGone g @ AgGone { 0 ( string_new ) }
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT trashed, reason FROM trash WHERE kind = ?1 AND ref = ?2 ORDER BY id DESC LIMIT 1` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 kind )
                    ( _ag_bind_s q 2 ref )
                    ? ( _ag_row q ) { = g @ AgGone { ( sqlite_column_int q 0 ) ( sqlite_column_text q 1 ) } } {}
                }
            }
        }
    }
    ^ g
}

: AgAudit {
    i ts
    String action
    String kind
    String ref
    String label
    String by
}

@ ag_audit_page AgStore st i limit i offset → ( Vec AgAudit ) {
    : ( Vec AgAudit ) out ( vec_new [AgAudit] )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT ts, action, kind, ref, label, by FROM audit ORDER BY id DESC LIMIT ?1 OFFSET ?2` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_i q 1 limit )
                    ( _ag_bind_i q 2 offset )
                    ~ ( _ag_row q ) {
                        ( vec_push [AgAudit] out @ AgAudit {
                            ( sqlite_column_int q 0 )
                            ( sqlite_column_text q 1 )
                            ( sqlite_column_text q 2 )
                            ( sqlite_column_text q 3 )
                            ( sqlite_column_text q 4 )
                            ( sqlite_column_text q 5 )
                        } )
                    }
                }
            }
        }
    }
    ^ out
}

@ ag_audit_count AgStore st → i {
    : ~ i n 0
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT COUNT(*) FROM audit` ) {
                F _ → {}
                T q → { ? ( _ag_row q ) { = n ( sqlite_column_int q 0 ) } {} }
            }
        }
    }
    ^ n
}
