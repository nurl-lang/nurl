// agora/src/ghstore.nu — GitHub pull requests and CI, as an agent needs them.
//
// What arrives from GitHub (github.nu: webhook deliveries, and the
// reconciliation that fills gaps) is normalised to a few fields and kept
// in the repository's own agora file, next to everything else:
//
//   gh_deliveries  accepted deliveries, by GitHub's delivery id: the queue
//                  the worker applies in order, and the retry dedup
//   gh_prs         a watched pull request: title, link, open | merged |
//                  closed, head and merge sha, the CI summary last told
//   gh_runs        the latest attempt of each Actions workflow run, by
//                  head sha
//   gh_watches     an agent watches a PR until a time (24 h by default)
//   gh_links       a task is about a PR: whoever holds it (else whoever
//                  posted it) is told too, while the task is unfinished
//   gh_notices     what each agent is to be told, at most one CI summary
//                  pending per PR and agent
//   gh_health      when an event last arrived, when GitHub was last asked,
//                  the last error
//
// The rules that keep it cheap for a model:
//   * state changes, not callbacks: a notice only when what an agent
//     would read changes — a merge, a close, a CI result for the PR's
//     current head that differs from the one last told; running and
//     re-running stay silent;
//   * a CI notice waits at most AG_GH_COALESCE seconds (a fixed window,
//     never sliding) and is rewritten, not repeated, while it waits; a
//     merge or close goes at once and drops the CI notice it makes moot;
//   * a notice is one line of at most AG_GH_NOTICE_MAX bytes, and a brief
//     carries at most AG_GH_BRIEF_N of them in AG_GH_BRIEF_BYTES; the
//     rest wait for the next brief, nothing is dropped unread;
//   * stale is ignored: a CI result for an older head, an older attempt,
//     or a pull_request event older than what is stored changes nothing;
//   * nothing about a PR nobody watches is kept (but a merge, when the
//     repository has a merge feed);
//   * GitHub's text is data: titles go into a notice cut and on one line,
//     and nothing in an event reaches a rule, a task's state or a command.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/sqlite.nu`
$ `stdlib/std/thread.nu`
$ `store.nu`

: i AG_GH_COALESCE 30  // seconds a CI notice waits for the rest of a burst
: i AG_GH_NOTICE_MAX 300  // bytes of one notice
: i AG_GH_BRIEF_N 5  // notices in one brief
: i AG_GH_BRIEF_BYTES 1500  // bytes of notices in one brief
: i AG_GH_WATCH_HOURS 24  // a watch's default life
: i AG_GH_WATCH_MAX_HOURS 72  // the longest one renewal gives
: i AG_GH_WATCHES_PER_AGENT 25
: i AG_GH_WATCHES_PER_REPO 300
: i AG_GH_QUEUE_MAX 5000  // deliveries accepted but not yet applied
: i AG_GH_PENDING_MAX 200  // undelivered notices of one agent

// ── Which agoras are connected ───────────────────────────────────────

// Set once at start (github.nu, from the configuration): the repository
// keys of the agoras GitHub events reach ('' stands for the one local
// file). The agent tools exist only when there is at least one.
: GhRoutes {
    b on
    ( Vec String ) repos
}

@ __gh_routes_blank → ( Locked GhRoutes ) { ^ ( locked_new [GhRoutes] @ GhRoutes { F ( vec_new [String] ) } ) }

: ( Locked GhRoutes ) g_gh_routes ( __gh_routes_blank )

@ ag_gh_set_routes b on ( Vec String ) repos → v {
    : GhRoutes old ( locked_take [GhRoutes] g_gh_routes )
    ( locked_restore [GhRoutes] g_gh_routes @ GhRoutes { on repos } )
}

@ ag_gh_on → b {
    : GhRoutes r ( locked_take [GhRoutes] g_gh_routes )
    : b on . r on
    ( locked_restore [GhRoutes] g_gh_routes r )
    ^ on
}

// Do GitHub events reach the agora of repository `repo` ('' = local)?
@ ag_gh_connected s repo → b {
    : GhRoutes r ( locked_take [GhRoutes] g_gh_routes )
    : ~ b yes F
    ? . r on {
        : i n ( vec_len [String] . r repos )
        : ~ i k 0
        ~ < k n {
            ?? ( vec_get [String] . r repos k ) { T x → { ? != 0 ( nurl_str_eq ( string_data x ) repo ) { = yes T } {} } F _ → {} }
            = k + k 1
        }
    } {}
    ( locked_restore [GhRoutes] g_gh_routes r )
    ^ yes
}

// ── Events, normalised ───────────────────────────────────────────────

: GhPr {
    i number
    String title
    String url
    String state  // open | merged | closed
    String head
    String merge
    i updated  // GitHub's updated_at, unix seconds
    ( Vec i ) refs  // the tasks its title or body names (AGORA-N)
}

// The task ids `text` names as AGORA-N (any case), each once.
@ gh_task_refs String text → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : s t ( string_data text )
    : ( Slice u ) v ( slice_of_str t )
    : i n ( nurl_str_len t )
    : ~ i k 0
    ~ < k - n 6 {
        : i c0 ( slice_byte v k )
        : b start | == k 0 ! | | & >= ( slice_byte v - k 1 ) 48 <= ( slice_byte v - k 1 ) 57 & >= ( slice_byte v - k 1 ) 65 <= ( slice_byte v - k 1 ) 90 & >= ( slice_byte v - k 1 ) 97 <= ( slice_byte v - k 1 ) 122
        : ~ b hit & start | == c0 65 == c0 97
        : ( Slice u ) w ( slice_of_str `gora-` )
        : ~ i j 1
        ~ & hit < j 6 {
            : i a ( slice_byte v + k j )
            : i al ? & >= a 65 <= a 90 + a 32 a
            ? != al ( slice_byte w - j 1 ) { = hit F } {}
            = j + j 1
        }
        : ~ i e + k 6
        : ~ i num 0
        : ~ b over F
        ~ & & hit < e n & >= ( slice_byte v e ) 48 <= ( slice_byte v e ) 57 {
            : i d - ( slice_byte v e ) 48
            // Past the largest `i`: not a task number (it would wrap).
            ? | > num 922337203685477580 & == num 922337203685477580 > d 7 { = over T } { = num + * num 10 d }
            = e + e 1
        }
        ? & & hit ! over > num 0 {
            : ~ b dup F
            : i m ( vec_len [i] out )
            : ~ i x 0
            ~ < x m { ?? ( vec_get [i] out x ) { T y → { ? == y num { = dup T } {} } F _ → {} } = x + x 1 }
            ? | dup >= m 20 {} { ( vec_push [i] out num ) }
            = k e
        } { = k + k 1 }
    }
    ^ out
}

: GhRun {
    i id
    i attempt
    String workflow
    String head
    ( Vec i ) prs
    String status  // queued | in_progress | completed | …
    String conclusion  // success | failure | cancelled | … ('' while running)
    String url
    i updated
}

@ _gh_s Json o s key → String {
    ? ( json_is_obj o ) {
        ?? ( json_obj_get o key ) { T v → { ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } {} } F → {} }
    } {}
    ^ ( string_new )
}

@ _gh_i Json o s key → i {
    ? ( json_is_obj o ) {
        ?? ( json_obj_get o key ) { T v → { ? ( json_is_num v ) { ^ ( json_as_int v ) } {} } F → {} }
    } {}
    ^ 0
}

// A PR as the delivery queue keeps it: {"t":"pr", …}.
@ gh_pr_json GhPr p → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `t` ( json_str_lit `pr` ) )
    ( json_obj_set o `number` ( json_int . p number ) )
    ( json_obj_set o `title` ( json_str_lit ( string_data . p title ) ) )
    ( json_obj_set o `url` ( json_str_lit ( string_data . p url ) ) )
    ( json_obj_set o `state` ( json_str_lit ( string_data . p state ) ) )
    ( json_obj_set o `head` ( json_str_lit ( string_data . p head ) ) )
    ( json_obj_set o `merge` ( json_str_lit ( string_data . p merge ) ) )
    ( json_obj_set o `updated` ( json_int . p updated ) )
    : Json rs ( json_arr_new )
    : i n ( vec_len [i] . p refs )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [i] . p refs k ) { T x → { ( json_arr_push rs ( json_int x ) ) } F _ → {} }
        = k + k 1
    }
    ( json_obj_set o `refs` rs )
    ^ o
}

@ gh_pr_of Json o → GhPr {
    : ( Vec i ) refs ( vec_new [i] )
    ? ( json_is_obj o ) {
        ?? ( json_obj_get o `refs` ) {
            T a → {
                : i n ( json_arr_len a )
                : ~ i k 0
                ~ < k n {
                    ?? ( json_arr_get a k ) { T x → { ( vec_push [i] refs ( json_as_int x ) ) } F → {} }
                    = k + k 1
                }
            }
            F → {}
        }
    } {}
    ^ @ GhPr { ( _gh_i o `number` ) ( _gh_s o `title` ) ( _gh_s o `url` ) ( _gh_s o `state` ) ( _gh_s o `head` ) ( _gh_s o `merge` ) ( _gh_i o `updated` ) refs }
}

// Tie task `task` to PR `pr` for good (once); a mirrored task's issue is
// told of it (ghmirror.nu, kind `pr`).
@ _gh_tie_on Database db i task i pr i now → v {
    ?? ( sqlite_prepare db `INSERT INTO gh_task_prs (task, pr, ts) SELECT ?1, ?2, ?3 WHERE EXISTS (SELECT 1 FROM tasks WHERE id = ?1) ON CONFLICT DO NOTHING` ) {
        F _ → {}
        T q → {
            ( _ag_bind_i q 1 task )
            ( _ag_bind_i q 2 pr )
            ( _ag_bind_i q 3 now )
            ? ( _ag_run q ) { ? > ( sqlite_changes db ) 0 { ( _ag_mirror_on db task `pr` pr now ) } {} } {}
        }
    }
}

@ gh_run_json GhRun r → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `t` ( json_str_lit `run` ) )
    ( json_obj_set o `id` ( json_int . r id ) )
    ( json_obj_set o `attempt` ( json_int . r attempt ) )
    ( json_obj_set o `workflow` ( json_str_lit ( string_data . r workflow ) ) )
    ( json_obj_set o `head` ( json_str_lit ( string_data . r head ) ) )
    : Json ps ( json_arr_new )
    : i n ( vec_len [i] . r prs )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [i] . r prs k ) { T x → { ( json_arr_push ps ( json_int x ) ) } F _ → {} }
        = k + k 1
    }
    ( json_obj_set o `prs` ps )
    ( json_obj_set o `status` ( json_str_lit ( string_data . r status ) ) )
    ( json_obj_set o `conclusion` ( json_str_lit ( string_data . r conclusion ) ) )
    ( json_obj_set o `url` ( json_str_lit ( string_data . r url ) ) )
    ( json_obj_set o `updated` ( json_int . r updated ) )
    ^ o
}

@ gh_run_of Json o → GhRun {
    : ( Vec i ) prs ( vec_new [i] )
    ? ( json_is_obj o ) {
        ?? ( json_obj_get o `prs` ) {
            T a → {
                : i n ( json_arr_len a )
                : ~ i k 0
                ~ < k n {
                    ?? ( json_arr_get a k ) { T x → { ( vec_push [i] prs ( json_as_int x ) ) } F → {} }
                    = k + k 1
                }
            }
            F → {}
        }
    } {}
    ^ @ GhRun { ( _gh_i o `id` ) ( _gh_i o `attempt` ) ( _gh_s o `workflow` ) ( _gh_s o `head` ) prs
        ( _gh_s o `status` ) ( _gh_s o `conclusion` ) ( _gh_s o `url` ) ( _gh_i o `updated` ) }
}

// ── Text for a model ─────────────────────────────────────────────────

// `raw` on one line, at most `maxb` bytes, never splitting a UTF-8
// sequence; `…` when cut.
@ gh_line String raw i maxb → String {
    : String out ( string_new )
    : s t ( string_data raw )
    : ( Slice u ) v ( slice_of_str t )
    : i n ( nurl_str_len t )
    : ~ i lim n
    ? > n maxb {
        // Room for the `…` (3 bytes) inside maxb.
        = lim ? > maxb 3 - maxb 3 0
        ~ & > lim 0 & >= ( slice_byte v lim ) 128 < ( slice_byte v lim ) 192 { = lim - lim 1 }
    } {}
    : ~ i k 0
    ~ < k lim {
        : i c ( slice_byte v k )
        ( string_push_char out ? | | == c 10 == c 13 == c 9 32 c )
        = k + k 1
    }
    ? > n maxb { ( string_push_str out `…` ) } {}
    ^ out
}

@ __gh_sha7 String sha → String {
    ? > ( string_len sha ) 7 { ^ ( string_substr sha 0 7 ) } {}
    ^ ( string_from ( string_data sha ) )
}

// ── Health ───────────────────────────────────────────────────────────

@ _gh_health_set_on Database db s key i ts s text → v {
    ?? ( sqlite_prepare db `INSERT INTO gh_health (key, ts, text) VALUES (?1, ?2, ?3) ON CONFLICT (key) DO UPDATE SET ts = excluded.ts, text = excluded.text` ) {
        F _ → {}
        T q → {
            ( _ag_bind_s q 1 key )
            ( _ag_bind_i q 2 ts )
            ( _ag_bind_s q 3 text )
            ( _ag_run q )
        }
    }
}

@ ag_gh_health_set AgStore st s key i ts s text → v {
    ?? ( _ag_conn st ) { F _ → {} T db → { ( _gh_health_set_on db key ts text ) } }
}

: GhHealth {
    i ts
    String text
}

@ ag_gh_health_get AgStore st s key → GhHealth {
    : ~ GhHealth h @ GhHealth { 0 ( string_new ) }
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT ts, text FROM gh_health WHERE key = ?1` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 key )
                    ? ( _ag_row q ) { = h @ GhHealth { ( sqlite_column_int q 0 ) ( sqlite_column_text q 1 ) } } {}
                }
            }
        }
    }
    ^ h
}

// ── Accepting deliveries ─────────────────────────────────────────────

: i AG_GH_ACCEPTED 1
: i AG_GH_DUPLICATE 0
: i AG_GH_FULL -2
: i AG_GH_FAILED -1

// Keep a delivery for the worker. A retry of one already kept (same
// GitHub delivery id) is a duplicate; a full queue refuses — never
// acknowledged as kept when it is not.
@ ag_gh_accept AgStore st s delivery s event s data i now → i {
    ?? ( _ag_conn st ) {
        F _ → { ^ AG_GH_FAILED }
        T db → {
            : ~ i queued 0
            ?? ( sqlite_prepare db `SELECT COUNT(*) FROM gh_deliveries WHERE done = 0` ) {
                F _ → {}
                T q → { ? ( _ag_row q ) { = queued ( sqlite_column_int q 0 ) } {} }
            }
            ? >= queued AG_GH_QUEUE_MAX { ^ AG_GH_FULL } {}
            ?? ( sqlite_prepare db `INSERT INTO gh_deliveries (id, received, event, data) VALUES (?1, ?2, ?3, ?4) ON CONFLICT (id) DO NOTHING` ) {
                F _ → { ^ AG_GH_FAILED }
                T q → {
                    ( _ag_bind_s q 1 delivery )
                    ( _ag_bind_i q 2 now )
                    ( _ag_bind_s q 3 event )
                    ( _ag_bind_s q 4 data )
                    ? ( _ag_run q ) {} { ^ AG_GH_FAILED }
                    ^ ? > ( sqlite_changes db ) 0 AG_GH_ACCEPTED AG_GH_DUPLICATE
                }
            }
        }
    }
}

// ── Who is told ──────────────────────────────────────────────────────

// Is anyone interested in PR `pr`: a live watch, or a link from an
// unfinished task?
@ __gh_interested_on Database db i pr i now → b {
    : ~ b yes F
    ?? ( sqlite_prepare db `SELECT EXISTS (SELECT 1 FROM gh_watches WHERE pr = ?1 AND until > ?2) OR EXISTS (SELECT 1 FROM gh_links l JOIN tasks t ON t.id = l.task WHERE l.pr = ?1 AND t.status IN ('open', 'claimed'))` ) {
        F _ → {}
        T q → {
            ( _ag_bind_i q 1 pr )
            ( _ag_bind_i q 2 now )
            ? ( _ag_row q ) { = yes != ( sqlite_column_int q 0 ) 0 } {}
        }
    }
    ^ yes
}

// Its audience, each agent once: who watches it, and for each unfinished
// task linked to it, its holder (else its poster) — resolved now, not when
// the link was made.
@ __gh_audience_on Database db i pr i now → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( sqlite_prepare db `SELECT agent FROM gh_watches WHERE pr = ?1 AND until > ?2 UNION SELECT CASE WHEN t.status = 'claimed' AND t.owner != '' THEN t.owner ELSE t.poster END FROM gh_links l JOIN tasks t ON t.id = l.task WHERE l.pr = ?1 AND t.status IN ('open', 'claimed') ORDER BY 1` ) {
        F _ → {}
        T q → {
            ( _ag_bind_i q 1 pr )
            ( _ag_bind_i q 2 now )
            ~ ( _ag_row q ) {
                : String a ( sqlite_column_text q 0 )
                ? > ( string_len a ) 0 { ( vec_push [String] out a ) } {}
            }
        }
    }
    ^ out
}

// Tell PR `pr`'s audience `text`. `kind` ci: one pending per agent and PR,
// rewritten while it waits (its time to go is fixed when it is first
// made); state: at once, once per `key`, replacing a pending CI notice.
@ __gh_notify_on Database db i pr s kind s key s text i now → b {
    : ~ b ok T
    : ( Vec String ) who ( __gh_audience_on db pr now )
    : b ci != 0 ( nurl_str_eq kind `ci` )
    : i n ( vec_len [String] who )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] who k ) {
            T a → {
                // Only a merge or close makes a pending CI result moot.
                ? != 0 ( nurl_str_eq kind `state` ) {
                    ?? ( sqlite_prepare db `DELETE FROM gh_notices WHERE agent = ?1 AND pr = ?2 AND kind = 'ci' AND delivered = 0` ) {
                        F _ → {}
                        T q → { ( _ag_bind_s q 1 ( string_data a ) ) ( _ag_bind_i q 2 pr ) ( _ag_run q ) }
                    }
                } {}
                : s sql ? ci
                `INSERT INTO gh_notices (agent, pr, kind, key, text, created, due) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) ON CONFLICT (agent, key) DO UPDATE SET text = excluded.text WHERE delivered = 0`
                `INSERT INTO gh_notices (agent, pr, kind, key, text, created, due) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) ON CONFLICT (agent, key) DO NOTHING`
                ?? ( sqlite_prepare db sql ) {
                    F _ → { = ok F }
                    T q → {
                        ( _ag_bind_s q 1 ( string_data a ) )
                        ( _ag_bind_i q 2 pr )
                        ( _ag_bind_s q 3 kind )
                        ( _ag_bind_s q 4 key )
                        ( _ag_bind_s q 5 text )
                        ( _ag_bind_i q 6 now )
                        ( _ag_bind_i q 7 ? ci + now AG_GH_COALESCE now )
                        = ok & ok ( _ag_run q )
                    }
                }
                // An agent nobody reads for: its oldest waiting CI notices go
                // first, a merge or a close never.
                ?? ( sqlite_prepare db `DELETE FROM gh_notices WHERE id IN (SELECT id FROM gh_notices WHERE agent = ?1 AND delivered = 0 AND kind = 'ci' ORDER BY id DESC LIMIT -1 OFFSET ?2)` ) {
                    F _ → {}
                    T q → { ( _ag_bind_s q 1 ( string_data a ) ) ( _ag_bind_i q 2 AG_GH_PENDING_MAX ) ( _ag_run q ) }
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ ok
}

// Tell everyone who watches anything here about the connection itself
// (events stopped, or came back): one notice per change, not per brief.
@ ag_gh_tell_all AgStore st s key s text i now → v {
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            : ( Vec i ) prs ( vec_new [i] )
            ?? ( sqlite_prepare db `SELECT DISTINCT pr FROM gh_watches WHERE until > ?1 UNION SELECT DISTINCT l.pr FROM gh_links l JOIN tasks t ON t.id = l.task WHERE t.status IN ('open', 'claimed')` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_i q 1 now )
                    ~ ( _ag_row q ) { ( vec_push [i] prs ( sqlite_column_int q 0 ) ) }
                }
            }
            // One notice per agent: the first PR it is told through carries it.
            : i n ( vec_len [i] prs )
            : ~ i k 0
            ~ < k n {
                : i pr ?? ( vec_get [i] prs k ) { T x → x F _ → 0 }
                : b _told ( __gh_notify_on db pr `health` key text now )
                = k + k 1
            }
        }
    }
}

// ── Applying events ──────────────────────────────────────────────────

: GhPrRow {
    b found
    String state
    String head
    i updated
    String ci_noted
    b announced
    String title
}

@ __gh_pr_row_on Database db i number → GhPrRow {
    : ~ GhPrRow r @ GhPrRow { F ( string_new ) ( string_new ) 0 ( string_new ) F ( string_new ) }
    ?? ( sqlite_prepare db `SELECT state, head_sha, updated, ci_noted, announced, title FROM gh_prs WHERE number = ?1` ) {
        F _ → {}
        T q → {
            ( _ag_bind_i q 1 number )
            ? ( _ag_row q ) {
                = r @ GhPrRow { T ( sqlite_column_text q 0 ) ( sqlite_column_text q 1 ) ( sqlite_column_int q 2 )
                    ( sqlite_column_text q 3 ) != ( sqlite_column_int q 4 ) 0 ( sqlite_column_text q 5 ) }
            } {}
        }
    }
    ^ r
}

// The settings of one repository's GitHub connection that applying needs.
: GhRoute {
    String merge_channel  // '' = no merge feed
    ( Vec String ) workflows  // the Actions workflows that count ('' = every one)
}

@ __gh_workflow_counts GhRoute rt s name → b {
    : i n ( vec_len [String] . rt workflows )
    ? == n 0 { ^ T } {}
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] . rt workflows k ) { T w → { ? != 0 ( nurl_str_eq ( string_data w ) name ) { ^ T } {} } F _ → {} }
        = k + k 1
    }
    ^ F
}

// A pull_request event (or what reconciliation read). `silent`: take the
// state, tell nobody (a watch's first look at a PR is not news).
@ _gh_apply_pr_on Database db GhPr e GhRoute rt b silent i now → b {
    : ~ b ok T
    : GhPrRow old ( __gh_pr_row_on db . e number )
    // Older than what is kept: GitHub delivered it late.
    ? & . old found < . e updated . old updated { ^ T } {}
    // A PR that names a task is tied to it, watched or not.
    : i nr ( vec_len [i] . e refs )
    : ~ i ri 0
    ~ < ri nr {
        ?? ( vec_get [i] . e refs ri ) { T t → { ( _gh_tie_on db t . e number now ) } F _ → {} }
        = ri + ri 1
    }
    // A new head: a CI result still waiting is for the old one.
    ? & . old found == 0 ( nurl_str_eq ( string_data . old head ) ( string_data . e head ) ) {
        ?? ( sqlite_prepare db `DELETE FROM gh_notices WHERE pr = ?1 AND kind = 'ci' AND delivered = 0` ) {
            F _ → {}
            T q → { ( _ag_bind_i q 1 . e number ) ( _ag_run q ) }
        }
    } {}
    : b merged != 0 ( nurl_str_eq ( string_data . e state ) `merged` )
    : b feed & merged > ( string_len . rt merge_channel ) 0
    : b want | feed ( __gh_interested_on db . e number now )
    ? want {} { ^ T } {}
    ?? ( sqlite_prepare db `INSERT INTO gh_prs (number, title, url, state, head_sha, merge_sha, updated, seen) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8) ON CONFLICT (number) DO UPDATE SET title = excluded.title, url = excluded.url, state = excluded.state, head_sha = excluded.head_sha, merge_sha = excluded.merge_sha, updated = excluded.updated, seen = excluded.seen, ci_noted = CASE WHEN gh_prs.head_sha = excluded.head_sha THEN gh_prs.ci_noted ELSE '' END` ) {
        F _ → { = ok F }
        T q → {
            ( _ag_bind_i q 1 . e number )
            ( _ag_bind_s q 2 ( string_data ( gh_line ( string_from ( string_data . e title ) ) 200 ) ) )
            ( _ag_bind_s q 3 ( string_data . e url ) )
            ( _ag_bind_s q 4 ( string_data . e state ) )
            ( _ag_bind_s q 5 ( string_data . e head ) )
            ( _ag_bind_s q 6 ( string_data . e merge ) )
            ( _ag_bind_i q 7 . e updated )
            ( _ag_bind_i q 8 now )
            = ok & ok ( _ag_run q )
        }
    }
    : b was_open | ! . old found != 0 ( nurl_str_eq ( string_data . old state ) `open` )
    : b ended & was_open | merged != 0 ( nurl_str_eq ( string_data . e state ) `closed` )
    ? & ended ! silent {
        : String t ( string_from `github#` )
        ( string_push_int t . e number )
        ? merged {
            ( string_push_str t ` merged` )
            ? > ( string_len . e merge ) 0 {
                ( string_push_str t ` as ` )
                ( string_push_str t ( string_data ( __gh_sha7 ( string_from ( string_data . e merge ) ) ) ) )
            } {}
        } { ( string_push_str t ` closed without merging` ) }
        ( string_push_str t ` — ` )
        ( string_push_str t ( string_data ( gh_line ( string_from ( string_data . e title ) ) 200 ) ) )
        : String key ( string_from `state:` )
        ( string_push_int key . e number )
        ( string_push_str key ? merged `:merged` `:closed` )
        = ok & ok ( __gh_notify_on db . e number `state` ( string_data key ) ( string_data ( gh_line t AG_GH_NOTICE_MAX ) ) now )
        // The merge feed: one post per merged PR, in the chosen channel.
        ? & feed ! . old announced {
            : String fp ( string_from `merged: ` )
            ( string_push_str fp ( string_data t ) )
            ? > ( string_len . e url ) 0 { ( string_push_str fp `\n` ) ( string_push_str fp ( string_data . e url ) ) } {}
            : i _id ( _ag_post_on db ( string_data . rt merge_channel ) `github` ( string_data fp ) 0 now )
            ?? ( sqlite_prepare db `UPDATE gh_prs SET announced = 1 WHERE number = ?1` ) {
                F _ → {}
                T q → { ( _ag_bind_i q 1 . e number ) ( _ag_run q ) }
            }
        } {}
        // Told; nothing more will come of it.
        ?? ( sqlite_prepare db `DELETE FROM gh_watches WHERE pr = ?1` ) { F _ → {} T q → { ( _ag_bind_i q 1 . e number ) ( _ag_run q ) } }
        ?? ( sqlite_prepare db `DELETE FROM gh_links WHERE pr = ?1` ) { F _ → {} T q → { ( _ag_bind_i q 1 . e number ) ( _ag_run q ) } }
    } {}
    ^ ok
}

// The CI of PR `pr` at head `head`: the latest run of each workflow that
// counts, as `name conclusion` (or `running`), and whether every one has
// finished. Never "all green": what ran, and how it ended.
: GhCi {
    String text
    i done
    i running
    i failed
}

@ __gh_ci_on Database db s head GhRoute rt → GhCi {
    : String t ( string_new )
    : ~ i done 0
    : ~ i running 0
    : ~ i failed 0
    : ( Vec String ) seen ( vec_new [String] )
    ?? ( sqlite_prepare db `SELECT workflow, status, conclusion FROM gh_runs r WHERE head_sha = ?1 AND run_id = (SELECT run_id FROM gh_runs r2 WHERE r2.head_sha = r.head_sha AND r2.workflow = r.workflow ORDER BY updated DESC, run_id DESC LIMIT 1) ORDER BY workflow` ) {
        F _ → {}
        T q → {
            ( _ag_bind_s q 1 head )
            ~ ( _ag_row q ) {
                : String w ( sqlite_column_text q 0 )
                ? ( __gh_workflow_counts rt ( string_data w ) ) {
                    : String status ( sqlite_column_text q 1 )
                    : String concl ( sqlite_column_text q 2 )
                    ? > ( string_len t ) 0 { ( string_push_str t `, ` ) } {}
                    ( string_push_str t ( string_data w ) )
                    ( string_push_str t ` ` )
                    ? != 0 ( nurl_str_eq ( string_data status ) `completed` ) {
                        ( string_push_str t ( string_data concl ) )
                        = done + done 1
                        ? | | != 0 ( nurl_str_eq ( string_data concl ) `failure` ) != 0 ( nurl_str_eq ( string_data concl ) `timed_out` ) != 0 ( nurl_str_eq ( string_data concl ) `startup_failure` ) { = failed + failed 1 } {}
                    } {
                        ( string_push_str t `running` )
                        = running + running 1
                    }
                    ( vec_push [String] seen w )
                } {}
            }
        }
    }
    // A workflow that counts and has not reported is unknown, not passed.
    : i nw ( vec_len [String] . rt workflows )
    : ~ i k 0
    ~ < k nw {
        ?? ( vec_get [String] . rt workflows k ) {
            T w → {
                : ~ b has F
                : i ns ( vec_len [String] seen )
                : ~ i j 0
                ~ < j ns {
                    ?? ( vec_get [String] seen j ) { T x → { ? ( string_eq x w ) { = has T } {} } F _ → {} }
                    = j + j 1
                }
                ? has {} {
                    ? > ( string_len t ) 0 { ( string_push_str t `, ` ) } {}
                    ( string_push_str t ( string_data w ) )
                    ( string_push_str t ` not started` )
                    = running + running 1
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ @ GhCi { t done running failed }
}

// A workflow_run event (or one reconciliation read).
@ _gh_apply_run_on Database db GhRun r GhRoute rt b silent i now → b {
    : ~ b ok T
    ? ( __gh_workflow_counts rt ( string_data . r workflow ) ) {} { ^ T } {}
    // The PRs it is about: those it names (same-repository PRs) and any
    // watched PR whose head it ran on (a fork's PR names none).
    : ( Vec i ) prs ( vec_new [i] )
    ?? ( sqlite_prepare db `SELECT number FROM gh_prs WHERE head_sha = ?1` ) {
        F _ → {}
        T q → {
            ( _ag_bind_s q 1 ( string_data . r head ) )
            ~ ( _ag_row q ) { ( vec_push [i] prs ( sqlite_column_int q 0 ) ) }
        }
    }
    : i nn ( vec_len [i] . r prs )
    : ~ i k 0
    ~ < k nn {
        : i p ?? ( vec_get [i] . r prs k ) { T x → x F _ → 0 }
        : ~ b dup F
        : i m ( vec_len [i] prs )
        : ~ i j 0
        ~ < j m {
            ?? ( vec_get [i] prs j ) { T x → { ? == x p { = dup T } {} } F _ → {} }
            = j + j 1
        }
        ? & ! dup ( __gh_interested_on db p now ) { ( vec_push [i] prs p ) } {}
        = k + k 1
    }
    ? == ( vec_len [i] prs ) 0 { ^ T } {}
    // An older attempt, or a late "in progress" for an attempt that has
    // finished, changes nothing.
    : ~ b stale F
    ?? ( sqlite_prepare db `SELECT attempt, status, updated FROM gh_runs WHERE run_id = ?1` ) {
        F _ → {}
        T q → {
            ( _ag_bind_i q 1 . r id )
            ? ( _ag_row q ) {
                : i att ( sqlite_column_int q 0 )
                : String st ( sqlite_column_text q 1 )
                : i upd ( sqlite_column_int q 2 )
                : b was_done != 0 ( nurl_str_eq ( string_data st ) `completed` )
                : b is_done != 0 ( nurl_str_eq ( string_data . r status ) `completed` )
                = stale | < . r attempt att & == . r attempt att | & was_done ! is_done & & was_done is_done < . r updated upd
            } {}
        }
    }
    ? stale { ^ T } {}
    ?? ( sqlite_prepare db `INSERT INTO gh_runs (run_id, attempt, workflow, head_sha, pr, status, conclusion, url, updated) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9) ON CONFLICT (run_id) DO UPDATE SET attempt = excluded.attempt, status = excluded.status, conclusion = excluded.conclusion, url = excluded.url, updated = excluded.updated` ) {
        F _ → { = ok F }
        T q → {
            ( _ag_bind_i q 1 . r id )
            ( _ag_bind_i q 2 . r attempt )
            ( _ag_bind_s q 3 ( string_data ( gh_line ( string_from ( string_data . r workflow ) ) 200 ) ) )
            ( _ag_bind_s q 4 ( string_data . r head ) )
            ( _ag_bind_i q 5 ?? ( vec_get [i] prs 0 ) { T x → x F _ → 0 } )
            ( _ag_bind_s q 6 ( string_data . r status ) )
            ( _ag_bind_s q 7 ( string_data . r conclusion ) )
            ( _ag_bind_s q 8 ( string_data . r url ) )
            ( _ag_bind_i q 9 . r updated )
            = ok & ok ( _ag_run q )
        }
    }
    // Each PR whose CURRENT head this is: tell what changed.
    : i np ( vec_len [i] prs )
    : ~ i x 0
    ~ < x np {
        : i p ?? ( vec_get [i] prs x ) { T y → y F _ → 0 }
        : GhPrRow row ( __gh_pr_row_on db p )
        ? & . row found & ( string_eq . row head . r head ) != 0 ( nurl_str_eq ( string_data . row state ) `open` ) {
            : GhCi ci ( __gh_ci_on db ( string_data . r head ) rt )
            // Running is silent; a finished set, or a failure while the rest
            // still runs, is news — once per distinct result.
            : b news & > . ci done 0 | == . ci running 0 > . ci failed 0
            ? & news ! ( string_eq . ci text . row ci_noted ) {
                ?? ( sqlite_prepare db `UPDATE gh_prs SET ci_noted = ?2 WHERE number = ?1` ) {
                    F _ → {}
                    T q → { ( _ag_bind_i q 1 p ) ( _ag_bind_s q 2 ( string_data . ci text ) ) ( _ag_run q ) }
                }
                ? silent {} {
                    : String t ( string_from `github#` )
                    ( string_push_int t p )
                    ( string_push_str t ` CI at ` )
                    ( string_push_str t ( string_data ( __gh_sha7 ( string_from ( string_data . r head ) ) ) ) )
                    ( string_push_str t `: ` )
                    ( string_push_str t ( string_data ( gh_line ( string_from ( string_data . ci text ) ) 180 ) ) )
                    ? > . ci running 0 {
                        ( string_push_str t ` (` )
                        ( string_push_int t . ci running )
                        ( string_push_str t ` not finished)` )
                    } {}
                    ( string_push_str t ` — ` )
                    ( string_push_str t ( string_data ( gh_line ( string_from ( string_data . row title ) ) 80 ) ) )
                    : String key ( string_from `ci:` )
                    ( string_push_int key p )
                    = ok & ok ( __gh_notify_on db p `ci` ( string_data key ) ( string_data ( gh_line t AG_GH_NOTICE_MAX ) ) now )
                }
            } {}
        } {}
        = x + x 1
    }
    ^ ok
}

// Apply what is waiting in the queue, oldest first, each delivery in a
// transaction of its own with its `done` mark: a crash replays it, and
// replaying changes nothing twice. Returns how many were applied.
@ ag_gh_process AgStore st GhRoute rt i now → i {
    : ~ i applied 0
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            : ( Vec String ) ids ( vec_new [String] )
            : ( Vec String ) datas ( vec_new [String] )
            ?? ( sqlite_prepare db `SELECT id, data FROM gh_deliveries WHERE done = 0 ORDER BY rowid LIMIT 500` ) {
                F _ → {}
                T q → {
                    ~ ( _ag_row q ) {
                        ( vec_push [String] ids ( sqlite_column_text q 0 ) )
                        ( vec_push [String] datas ( sqlite_column_text q 1 ) )
                    }
                }
            }
            : i n ( vec_len [String] ids )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] ids k ) {
                    T id → {
                        ? ( _ag_begin db ) {
                            : ~ b ok T
                            ?? ( vec_get [String] datas k ) {
                                T d → { = ok ( __gh_apply_data_on db ( string_data d ) rt F now ) }
                                F _ → {}
                            }
                            ?? ( sqlite_prepare db `UPDATE gh_deliveries SET done = 1 WHERE id = ?1` ) {
                                F _ → { = ok F }
                                T q → { ( _ag_bind_s q 1 ( string_data id ) ) = ok & ok ( _ag_run q ) }
                            }
                            // A part that failed leaves the delivery waiting, in
                            // order: the rest go after it, next round.
                            : ~ b done F
                            ? ok { = done ( _ag_commit db ) } {}
                            ? done { = applied + applied 1 } { ( _ag_rollback db ) = k n }
                        } { = k n }
                    }
                    F _ → {}
                }
                = k + k 1
            }
        }
    }
    ^ applied
}

@ __gh_apply_data_on Database db s data GhRoute rt b silent i now → b {
    ?? ( json_parse data ) {
        F _ → { ^ T }
        T o → {
            : String t ( _gh_s o `t` )
            ? != 0 ( nurl_str_eq ( string_data t ) `pr` ) { ^ ( _gh_apply_pr_on db ( gh_pr_of o ) rt silent now ) } {}
            ? != 0 ( nurl_str_eq ( string_data t ) `run` ) { ^ ( _gh_apply_run_on db ( gh_run_of o ) rt silent now ) } {}
        }
    }
    ^ T
}

// What reconciliation read, applied in one transaction; `silent` for a
// PR seen for the first time.
@ ag_gh_apply AgStore st s data GhRoute rt b silent i now → b {
    ?? ( _ag_conn st ) {
        F _ → { ^ F }
        T db → {
            ? ( _ag_begin db ) {} { ^ F }
            ? ( __gh_apply_data_on db data rt silent now ) {
                ? ( _ag_commit db ) { ^ T } {}
            } {}
            ( _ag_rollback db )
            ^ F
        }
    }
}

// PR `number` asked about and not seen (404): kept as an open PR with no
// head and no time, so any real event or read replaces it.
@ ag_gh_pr_placeholder AgStore st i number i now → v {
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `INSERT INTO gh_prs (number, title, url, state, head_sha, merge_sha, updated, seen) VALUES (?1, '', '', 'open', '', '', 0, ?2) ON CONFLICT (number) DO NOTHING` ) {
                F _ → {}
                T q → { ( _ag_bind_i q 1 number ) ( _ag_bind_i q 2 now ) ( _ag_run q ) }
            }
        }
    }
}

// Is PR `number` known (has GitHub been asked about it, or told us)?
@ ag_gh_pr_known AgStore st i number → b {
    : ~ b known F
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → { : GhPrRow r ( __gh_pr_row_on db number ) = known . r found }
    }
    ^ known
}

// Where task `task` is on GitHub: its mirrored issue (0 = none; a dry
// run's stand-ins are not issues) and every PR tied to it.
: GhTaskRefs {
    i issue
    ( Vec i ) prs
}

@ ag_gh_task_refs AgStore st i task → GhTaskRefs {
    : ~ i issue 0
    : ( Vec i ) prs ( vec_new [i] )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT number FROM gh_issues WHERE task = ?1 AND number > 0` ) {
                F _ → {}
                T q → { ( _ag_bind_i q 1 task ) ? ( _ag_row q ) { = issue ( sqlite_column_int q 0 ) } {} }
            }
            ?? ( sqlite_prepare db `SELECT pr FROM gh_task_prs WHERE task = ?1 ORDER BY pr` ) {
                F _ → {}
                T q → { ( _ag_bind_i q 1 task ) ~ ( _ag_row q ) { ( vec_push [i] prs ( sqlite_column_int q 0 ) ) } }
            }
        }
    }
    ^ @ GhTaskRefs { issue prs }
}

// ── Housekeeping ─────────────────────────────────────────────────────

// Watches past their time, links of finished tasks, delivered notices
// a week old, waiting ones a month old, applied deliveries three days
// old, and the state of PRs nobody watches any more.
@ ag_gh_tidy AgStore st i now → v {
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            : ( Vec String ) sqls ( vec_new [String] )
            ( vec_push [String] sqls ( string_from `DELETE FROM gh_watches WHERE until <= ?1` ) )
            ( vec_push [String] sqls ( string_from `DELETE FROM gh_links WHERE task NOT IN (SELECT id FROM tasks WHERE status IN ('open', 'claimed'))` ) )
            ( vec_push [String] sqls ( string_from `DELETE FROM gh_notices WHERE (delivered = 1 AND created < ?1 - 604800) OR created < ?1 - 2592000` ) )
            ( vec_push [String] sqls ( string_from `DELETE FROM gh_deliveries WHERE done = 1 AND received < ?1 - 259200` ) )
            ( vec_push [String] sqls ( string_from `DELETE FROM gh_prs WHERE seen < ?1 - 86400 AND number NOT IN (SELECT pr FROM gh_watches) AND number NOT IN (SELECT pr FROM gh_links)` ) )
            ( vec_push [String] sqls ( string_from `DELETE FROM gh_runs WHERE head_sha NOT IN (SELECT head_sha FROM gh_prs)` ) )
            : i n ( vec_len [String] sqls )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] sqls k ) {
                    T sq → {
                        ?? ( sqlite_prepare db ( string_data sq ) ) {
                            F _ → {}
                            T q → { ? ( string_contains sq `?1` ) { ( _ag_bind_i q 1 now ) } {} ( _ag_run q ) }
                        }
                    }
                    F _ → {}
                }
                = k + k 1
            }
        }
    }
}

// The PRs reconciliation keeps current: every one watched or linked.
@ ag_gh_watched_prs AgStore st i now → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT pr FROM gh_watches WHERE until > ?1 UNION SELECT l.pr FROM gh_links l JOIN tasks t ON t.id = l.task WHERE t.status IN ('open', 'claimed') ORDER BY 1` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_i q 1 now )
                    ~ ( _ag_row q ) { ( vec_push [i] out ( sqlite_column_int q 0 ) ) }
                }
            }
        }
    }
    ^ out
}

// The head a PR is at, as kept ('' when unknown).
@ ag_gh_pr_head AgStore st i number → String {
    : ~ String h ( string_new )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → { : GhPrRow r ( __gh_pr_row_on db number ) = h . r head }
    }
    ^ h
}

// ── Watches ──────────────────────────────────────────────────────────

// GitHub has no such PR: nobody watches it any more.
@ ag_gh_unwatch_all AgStore st i pr → v {
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `DELETE FROM gh_watches WHERE pr = ?1` ) { F _ → {} T q → { ( _ag_bind_i q 1 pr ) ( _ag_run q ) } }
            ?? ( sqlite_prepare db `DELETE FROM gh_links WHERE pr = ?1` ) { F _ → {} T q → { ( _ag_bind_i q 1 pr ) ( _ag_run q ) } }
        }
    }
}

: i AG_GH_WATCH_NEW 1
: i AG_GH_WATCH_RENEWED 2
: i AG_GH_WATCH_CAP -2
: i AG_GH_WATCH_NO_TASK -3

// Watch PR `pr` for `hours` (clamped), linking task `task` (0 = none) to
// it. Doing it again renews it: one watch per agent and PR, however
// often it is asked for.
@ ag_gh_watch AgStore st s agent i pr i task i hours i now → i {
    : i h ? < hours 1 AG_GH_WATCH_HOURS ? > hours AG_GH_WATCH_MAX_HOURS AG_GH_WATCH_MAX_HOURS hours
    ?? ( _ag_conn st ) {
        F _ → { ^ AG_GH_FAILED }
        T db → {
            ? ( _ag_begin db ) {} { ^ AG_GH_FAILED }
            : ~ b had F
            : ~ i mine 0
            : ~ i all 0
            ?? ( sqlite_prepare db `SELECT (SELECT COUNT(*) FROM gh_watches WHERE agent = ?1 AND pr = ?2 AND until > ?3), (SELECT COUNT(*) FROM gh_watches WHERE agent = ?1 AND until > ?3), (SELECT COUNT(*) FROM gh_watches WHERE until > ?3)` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 agent )
                    ( _ag_bind_i q 2 pr )
                    ( _ag_bind_i q 3 now )
                    ? ( _ag_row q ) {
                        = had > ( sqlite_column_int q 0 ) 0
                        = mine ( sqlite_column_int q 1 )
                        = all ( sqlite_column_int q 2 )
                    } {}
                }
            }
            ? & ! had | >= mine AG_GH_WATCHES_PER_AGENT >= all AG_GH_WATCHES_PER_REPO { ( _ag_rollback db ) ^ AG_GH_WATCH_CAP } {}
            ? > task 0 {
                : ~ b live F
                ?? ( sqlite_prepare db `SELECT COUNT(*) FROM tasks WHERE id = ?1 AND status IN ('open', 'claimed')` ) {
                    F _ → {}
                    T q → { ( _ag_bind_i q 1 task ) ? ( _ag_row q ) { = live > ( sqlite_column_int q 0 ) 0 } {} }
                }
                ? live {} { ( _ag_rollback db ) ^ AG_GH_WATCH_NO_TASK }
                ?? ( sqlite_prepare db `INSERT INTO gh_links (task, pr) VALUES (?1, ?2) ON CONFLICT DO NOTHING` ) {
                    F _ → {}
                    T q → { ( _ag_bind_i q 1 task ) ( _ag_bind_i q 2 pr ) ( _ag_run q ) }
                }
                ( _gh_tie_on db task pr now )
            } {}
            ?? ( sqlite_prepare db `INSERT INTO gh_watches (agent, pr, until, created) VALUES (?1, ?2, ?3, ?4) ON CONFLICT (agent, pr) DO UPDATE SET until = excluded.until` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 agent )
                    ( _ag_bind_i q 2 pr )
                    ( _ag_bind_i q 3 + now * h 3600 )
                    ( _ag_bind_i q 4 now )
                    ( _ag_run q )
                }
            }
            ? ( _ag_commit db ) { ^ ? had AG_GH_WATCH_RENEWED AG_GH_WATCH_NEW } {}
            ( _ag_rollback db )
            ^ AG_GH_FAILED
        }
    }
}

// Stop watching `pr` (0 = every PR). The count dropped.
@ ag_gh_unwatch AgStore st s agent i pr → i {
    : ~ i n 0
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `DELETE FROM gh_watches WHERE agent = ?1 AND (?2 = 0 OR pr = ?2)` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 agent )
                    ( _ag_bind_i q 2 pr )
                    ? ( _ag_run q ) { = n ( sqlite_changes db ) } {}
                }
            }
        }
    }
    ^ n
}

: GhWatch {
    i pr
    i until
    String state  // '' = not known yet
    String title
    String head
    String ci
    String url
}

// The PRs `agent` watches (live ones), with what is known of each.
@ ag_gh_watches AgStore st s agent i now → ( Vec GhWatch ) {
    : ( Vec GhWatch ) out ( vec_new [GhWatch] )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT w.pr, w.until, COALESCE(p.state, ''), COALESCE(p.title, ''), COALESCE(p.head_sha, ''), COALESCE(p.ci_noted, ''), COALESCE(p.url, '') FROM gh_watches w LEFT JOIN gh_prs p ON p.number = w.pr WHERE w.agent = ?1 AND w.until > ?2 ORDER BY w.pr` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 agent )
                    ( _ag_bind_i q 2 now )
                    ~ ( _ag_row q ) {
                        ( vec_push [GhWatch] out @ GhWatch { ( sqlite_column_int q 0 ) ( sqlite_column_int q 1 ) ( sqlite_column_text q 2 )
                            ( sqlite_column_text q 3 ) ( sqlite_column_text q 4 ) ( sqlite_column_text q 5 ) ( sqlite_column_text q 6 ) } )
                    }
                }
            }
        }
    }
    ^ out
}

// One PR in full: what is kept of it and of each workflow's latest run.
: GhRunRow {
    String workflow
    String status
    String conclusion
    i attempt
    String url
}

@ ag_gh_pr_detail AgStore st i pr → ?GhWatch {
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT number, 0, state, title, head_sha, ci_noted, url FROM gh_prs WHERE number = ?1` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_i q 1 pr )
                    ? ( _ag_row q ) {
                        ^ @ ?GhWatch { T @ GhWatch { ( sqlite_column_int q 0 ) 0 ( sqlite_column_text q 2 ) ( sqlite_column_text q 3 )
                                ( sqlite_column_text q 4 ) ( sqlite_column_text q 5 ) ( sqlite_column_text q 6 ) } }
                    } {}
                }
            }
        }
    }
    ^ @ ?GhWatch { F }
}

@ ag_gh_runs AgStore st s head → ( Vec GhRunRow ) {
    : ( Vec GhRunRow ) out ( vec_new [GhRunRow] )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT workflow, status, conclusion, attempt, url FROM gh_runs r WHERE head_sha = ?1 AND run_id = (SELECT run_id FROM gh_runs r2 WHERE r2.head_sha = r.head_sha AND r2.workflow = r.workflow ORDER BY updated DESC, run_id DESC LIMIT 1) ORDER BY workflow` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 head )
                    ~ ( _ag_row q ) {
                        ( vec_push [GhRunRow] out @ GhRunRow { ( sqlite_column_text q 0 ) ( sqlite_column_text q 1 ) ( sqlite_column_text q 2 )
                            ( sqlite_column_int q 3 ) ( sqlite_column_text q 4 ) } )
                    }
                }
            }
        }
    }
    ^ out
}

// ── Into a brief ─────────────────────────────────────────────────────

: GhTake {
    ( Vec String ) lines
    i left  // due and not taken (budget)
    i waiting  // CI notices still inside their window
}

// The notices due for `agent`, oldest first, within `max_n` and
// AG_GH_BRIEF_BYTES: those handed over are marked delivered (a CI one
// frees its slot for the next), the rest wait for the next brief.
@ ag_gh_take AgStore st s agent i max_n i now → GhTake {
    : ( Vec String ) lines ( vec_new [String] )
    : ~ i left 0
    : ~ i waiting 0
    : i cap ? < max_n AG_GH_BRIEF_N max_n AG_GH_BRIEF_N
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            // What is read and what is marked delivered are one transaction:
            // a CI result rewritten in between would otherwise be marked
            // delivered unread.
            ? ( _ag_begin db ) {} { ^ @ GhTake { lines 0 0 } }
            : ( Vec i ) ids ( vec_new [i] )
            : ~ i bytes 0
            ?? ( sqlite_prepare db `SELECT id, text FROM gh_notices WHERE agent = ?1 AND delivered = 0 AND due <= ?2 ORDER BY id` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 agent )
                    ( _ag_bind_i q 2 now )
                    ~ ( _ag_row q ) {
                        : String t ( sqlite_column_text q 1 )
                        ? & < ( vec_len [i] ids ) cap <= + bytes + ( string_len t ) 1 AG_GH_BRIEF_BYTES {
                            = bytes + bytes + ( string_len t ) 1
                            ( vec_push [i] ids ( sqlite_column_int q 0 ) )
                            ( vec_push [String] lines t )
                        } { = left + left 1 }
                    }
                }
            }
            : i n ( vec_len [i] ids )
            : ~ b marked T
            : ~ i k 0
            ~ < k n {
                : i id ?? ( vec_get [i] ids k ) { T x → x F _ → 0 }
                ?? ( sqlite_prepare db `UPDATE gh_notices SET delivered = 1, key = key || ':' || id WHERE id = ?1` ) {
                    F _ → { = marked F }
                    T q → { ( _ag_bind_i q 1 id ) = marked & marked ( _ag_run q ) }
                }
                = k + k 1
            }
            // Not marked, not shown: the next brief has them all again.
            : ~ b done F
            ? marked { = done ( _ag_commit db ) } {}
            ? done {} {
                ( _ag_rollback db )
                ^ @ GhTake { ( vec_new [String] ) 0 0 }
            }
            ?? ( sqlite_prepare db `SELECT COUNT(*) FROM gh_notices WHERE agent = ?1 AND delivered = 0 AND due > ?2` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 agent )
                    ( _ag_bind_i q 2 now )
                    ? ( _ag_row q ) { = waiting ( sqlite_column_int q 0 ) } {}
                }
            }
        }
    }
    ^ @ GhTake { lines left waiting }
}

// Has `agent` a notice due (wait returns for it)?
@ ag_gh_due AgStore st s agent i now → b {
    : ~ b due F
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT EXISTS (SELECT 1 FROM gh_notices WHERE agent = ?1 AND delivered = 0 AND due <= ?2)` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 agent )
                    ( _ag_bind_i q 2 now )
                    ? ( _ag_row q ) { = due != ( sqlite_column_int q 0 ) 0 } {}
                }
            }
        }
    }
    ^ due
}
