// agora/src/ghmirror.nu — the task board, mirrored to GitHub issues.
//
// One way only: agora → GitHub. Every task of a mirrored repository
// gets a public issue that follows it; nothing on GitHub changes agora.
// Agents work as before (task_post, task_claim, post `t<N>: …` in dev,
// task_done); rule public-tasks tells them what they write is public.
//
//   task_post                 an issue: the title, a head line
//                             `AGORA-N · posted by A · priority P`, the
//                             body; tags as labels, `prio:P` when P ≠ 0
//   claim / release / expiry  label `in-progress` on and off, the holder
//                             in the head line (an edit, not a comment)
//   `t<N>: …` in dev          a comment `**agent** (Agora): …`
//   task_done                 the result as the last comment, closed as
//                             completed
//   task_cancel               closed as not planned — as a duplicate when
//                             another task's body starts `Supersedes
//                             AGORA-N`
//   a person's edit           title, body, labels and open/closed follow
//
// References are rewritten on the way: AGORA-N (and the older `Agora #N`)
// become the mirrored issue's `#M`, or stay `AGORA-N` when that task has
// no issue; `github#N` becomes `#N`. A bare `#N` is ambiguous (an old task
// reference, a rank, a message) and is kept as written, with a WORD
// JOINER after the '#' so GitHub does not link it to its own #N. The configured redaction patterns replace what
// they match with `[redacted]` in every title, body and comment. A task
// tagged `private` or `security` is never mirrored.
//
// Reliability. Each step goes to gh_outbox in the same transaction as
// the task change (store.nu _ag_mirror_on), so an agent's call never
// waits on GitHub and nothing is lost to a crash. The worker drains the
// queue in order, at most about one write a second, honouring
// Retry-After and the rate-limit reset, backing off on errors; a write
// that fails stops the queue there, so order holds. Creating an issue
// is keyed on the task: a row with number 0 is written before the call,
// and a crash before the number is kept is resolved by finding the issue
// by its body marker `<!-- agora-task: N -->` rather than creating a
// second one. A comment is keyed on its message.
//
// Enabling (`[github] mirror = ["owner/name"]`) mirrors every open task,
// oldest first, with its `t<N>:` comments; finished tasks are not
// back-filled. `dry_run = true` (the default) writes nothing to GitHub:
// each request is logged in gh_dry for a person to read on the web page
// (redaction included) before switching it on.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/regex.nu`
$ `stdlib/ext/sqlite.nu`
$ `github.nu`
$ `web.nu`

: i AG_GH_MIRROR_STUCK 1800  // seconds the queue may stand before the alert agent hears
: i AG_GH_MIRROR_ATTEMPTS 6  // a write refused this often (not a rate limit) is given up

// ── Configuration ────────────────────────────────────────────────────

: AgGhMirror {
    ( Vec String ) repos  // owner/name, lowercase
    b dry
    ( Vec String ) redact  // regular expressions (stdlib/ext/regex.nu)
    String alert  // an agent told when the queue is stuck ('' = none)
}

@ __ghm_blank → ( Locked AgGhMirror ) {
    ^ ( locked_new [AgGhMirror] @ AgGhMirror { ( vec_new [String] ) T ( vec_new [String] ) ( string_new ) } )
}

: ( Locked AgGhMirror ) g_ghm ( __ghm_blank )

@ ag_gh_mirror_configure ( Vec String ) repos b dry ( Vec String ) redact s alert → v {
    : AgGhMirror old ( locked_take [AgGhMirror] g_ghm )
    ( locked_restore [AgGhMirror] g_ghm @ AgGhMirror { ( _gh_strs_clone repos ) dry ( _gh_strs_clone redact ) ( string_from alert ) } )
}

@ _ghm_conf → AgGhMirror {
    : AgGhMirror m ( locked_take [AgGhMirror] g_ghm )
    : AgGhMirror out @ AgGhMirror { ( _gh_strs_clone . m repos ) . m dry ( _gh_strs_clone . m redact ) ( string_clone . m alert ) }
    ( locked_restore [AgGhMirror] g_ghm m )
    ^ out
}

// ── A stand-in for GitHub (tests) ────────────────────────────────────

// When on, requests are answered here, not sent: numbers count up, the
// next `fail` requests answer `fail_status`; every request is logged in
// gh_dry like a dry run's, so a test reads what would have been sent.
: AgGhFake {
    b on
    i next
    i fail
    i fail_status
    i find_task  // a GET of the issues lists one issue of this task…
    i find_number  // …under this number
}

@ __ghf_blank → ( Locked AgGhFake ) { ^ ( locked_new [AgGhFake] @ AgGhFake { F 100 0 0 0 0 } ) }

: ( Locked AgGhFake ) g_ghf ( __ghf_blank )

@ ag_gh_fake b on i fail i fail_status → v {
    : AgGhFake f ( locked_take [AgGhFake] g_ghf )
    ( locked_restore [AgGhFake] g_ghf @ AgGhFake { on . f next fail fail_status . f find_task . f find_number } )
}

@ ag_gh_fake_find i task i number → v {
    : AgGhFake f ( locked_take [AgGhFake] g_ghf )
    ( locked_restore [AgGhFake] g_ghf @ AgGhFake { . f on . f next . f fail . f fail_status task number } )
}

@ __ghf_on → b {
    : AgGhFake f ( locked_take [AgGhFake] g_ghf )
    : b on . f on
    ( locked_restore [AgGhFake] g_ghf f )
    ^ on
}

// ── Settings in the repository's file ────────────────────────────────

@ __ghm_setting AgStore st s key i dflt → i {
    : ~ i v dflt
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT value FROM settings WHERE key = ?1` ) {
                F _ → {}
                T q → { ( _ag_bind_s q 1 key ) ? ( _ag_row q ) { = v ( sqlite_column_int q 0 ) } {} }
            }
        }
    }
    ^ v
}

@ __ghm_set_on Database db s key i value → v {
    ?? ( sqlite_prepare db `INSERT INTO settings (key, value) VALUES (?1, ?2) ON CONFLICT (key) DO UPDATE SET value = excluded.value` ) {
        F _ → {}
        T q → { ( _ag_bind_s q 1 key ) ( _ag_bind_i q 2 value ) ( _ag_run q ) }
    }
}

// Switch the mirror of the file `st` to `mode` (0 off, 1 dry run, 2 live).
// Turning it on — or from a dry run to live — queues every open task,
// oldest first, each followed by its `t<N>:` comments.
@ ag_gh_mirror_mode AgStore st i mode i now → v {
    : i was ( __ghm_setting st `gh_mirror_mode` 0 )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ? ( _ag_begin db ) {} { ^ v }
            ( __ghm_set_on db `gh_mirror` ? > mode 0 1 0 )
            ( __ghm_set_on db `gh_mirror_mode` mode )
            ? & > mode 0 != was mode {
                ? == was 0 { ( __ghm_set_on db `gh_mirror_since` now ) } {}
                // A dry run's stand-ins go; live starts from nothing.
                ?? ( sqlite_prepare db `DELETE FROM gh_issues WHERE number <= 0` ) { F _ → {} T q → { ( _ag_run q ) } }
                ?? ( sqlite_prepare db `DELETE FROM gh_comments WHERE id <= 0` ) { F _ → {} T q → { ( _ag_run q ) } }
                ?? ( sqlite_prepare db `UPDATE gh_task_prs SET noted = 0` ) { F _ → {} T q → { ( _ag_run q ) } }
                ? == mode 2 { ?? ( sqlite_prepare db `DELETE FROM gh_labels` ) { F _ → {} T q → { ( _ag_run q ) } } } {}
                ?? ( sqlite_prepare db `UPDATE gh_outbox SET done = 1, error = 'superseded by a back-fill' WHERE done = 0` ) { F _ → {} T q → { ( _ag_run q ) } }
                ?? ( sqlite_prepare db `INSERT INTO gh_outbox (task, kind, msg, created) SELECT task, kind, msg, ?1 FROM (SELECT t.id AS task, 'post' AS kind, 0 AS msg, t.id AS o1, 0 AS o2 FROM tasks t WHERE t.status IN ('open', 'claimed') UNION ALL SELECT t.id, 'comment', m.id, t.id, m.id FROM tasks t JOIN messages m ON m.channel = 'dev' AND (m.body LIKE 't' || t.id || ':%') WHERE t.status IN ('open', 'claimed') UNION ALL SELECT t.id, 'pr', p.pr, t.id, 1000000000 + p.pr FROM tasks t JOIN gh_task_prs p ON p.task = t.id WHERE t.status IN ('open', 'claimed') UNION ALL SELECT t.id, CASE WHEN t.status = 'done' THEN 'done' ELSE 'cancel' END, 0, t.id, 2000000000 FROM tasks t JOIN gh_issues g ON g.task = t.id AND g.number > 0 AND g.state != 'closed' WHERE t.status IN ('done', 'cancelled')) ORDER BY o1, o2` ) {
                    F _ → {}
                    T q → { ( _ag_bind_i q 1 now ) ( _ag_run q ) }
                }
            } {}
            ? ( _ag_commit db ) {} { ( _ag_rollback db ) }
        }
    }
}

// Every configured repository's mirror set from the configuration (and
// those no longer named switched off is left to whoever removed them:
// a file never mirrored has the setting 0 already).
@ ag_gh_mirror_setup i now → v {
    : AgGhConf c ( _gh_conf )
    ? . c on {} { ^ v }
    : AgGhMirror m ( _ghm_conf )
    : i n ( vec_len [String] . c repos )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] . c repos k ) {
            T full → {
                : AgStore st ( _gh_store c ( string_data full ) )
                ? . st ok {
                    : b on ( _gh_repo_in . m repos ( string_data full ) )
                    ( ag_gh_mirror_mode st ? on ? . m dry 1 2 0 now )
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
}

// ── Text ─────────────────────────────────────────────────────────────

@ __ghm_digit i c → b { ^ & >= c 48 <= c 57 }

@ __ghm_word i c → b { ^ | | | ( __ghm_digit c ) & >= c 65 <= c 90 & >= c 97 <= c 122 == c 95 }

// Does `t` at `k` start with `w`, ignoring case?
@ __ghm_at ( Slice u ) v i n i k s w → b {
    : i m ( nurl_str_len w )
    ? > + k m n { ^ F } {}
    : ( Slice u ) wv ( slice_of_str w )
    : ~ i j 0
    ~ < j m {
        : i a ( slice_byte v + k j )
        : i b ( slice_byte wv j )
        : i al ? & >= a 65 <= a 90 + a 32 a
        ? != al b { ^ F } {}
        = j + j 1
    }
    ^ T
}

// The issue of task `task` (0 = none yet).
@ __ghm_issue_on Database db i task → i {
    : ~ i n 0
    ?? ( sqlite_prepare db `SELECT number FROM gh_issues WHERE task = ?1` ) {
        F _ → {}
        T q → { ( _ag_bind_i q 1 task ) ? ( _ag_row q ) { = n ( sqlite_column_int q 0 ) } {} }
    }
    ^ n
}

// References rewritten for GitHub (see the header).
@ gh_rewrite Database db String text → String {
    : String out ( string_new )
    : s t ( string_data text )
    : ( Slice u ) v ( slice_of_str t )
    : i n ( nurl_str_len t )
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte v k )
        : b start | == k 0 ! ( __ghm_word ( slice_byte v - k 1 ) )
        : ~ i skip 0  // bytes of a recognised prefix before the number
        : ~ b gh F
        : ~ b bare F
        ? & start ( __ghm_at v n k `github#` ) { = skip 7 = gh T } {
            ? & start ( __ghm_at v n k `agora-` ) { = skip 6 } {
                ? & start ( __ghm_at v n k `agora #` ) { = skip 7 } {
                    ? & == c 35 & start ! & > k 0 | == ( slice_byte v - k 1 ) 47 == ( slice_byte v - k 1 ) 38 { = skip 1 = bare T } {}
                }
            }
        }
        : ~ i e + k skip
        ~ & > skip 0 & < e n ( __ghm_digit ( slice_byte v e ) ) { = e + e 1 }
        // At most 18 digits: a longer run is no task number (and would wrap).
        ? & & > skip 0 & > e + k skip <= - e + k skip 18 | == e n ! ( __ghm_word ( slice_byte v e ) ) {
            : ~ i num 0
            : ~ i j + k skip
            ~ < j e { = num + * num 10 - ( slice_byte v j ) 48 = j + j 1 }
            // A bare #N could be anything (an old task reference, a rank, a
            // message): kept as written, but with a WORD JOINER (U+2060)
            // after the '#' so GitHub does not link it to its own #N.
            ? bare {
                ( string_push_str out `#` )
                ( string_push_char out 226 )
                ( string_push_char out 129 )
                ( string_push_char out 160 )
                ( string_push_int out num )
            } {
                ? gh { ( string_push_str out `#` ) ( string_push_int out num ) } {
                    : i iss ( __ghm_issue_on db num )
                    ? > iss 0 { ( string_push_str out `#` ) ( string_push_int out iss ) } {
                        ( string_push_str out `AGORA-` )
                        ( string_push_int out num )
                    }
                }
            }
            = k e
        } {
            ( string_push_char out c )
            = k + k 1
        }
    }
    ^ out
}

// Every redaction pattern's matches → `[redacted]`.
@ gh_redact String text ( Vec String ) pats → String {
    : ~ String out ( string_clone text )
    : i n ( vec_len [String] pats )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] pats k ) {
            T p → {
                ?? ( regex_compile ( string_data p ) ) {
                    T r → { = out ( regex_replace r ( string_data out ) `[redacted]` ) }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

// Redacted as written (a pattern may name `#123` the way the author
// wrote it), then rewritten, then redacted again (for what rewriting made).
@ __ghm_public Database db String text ( Vec String ) pats → String {
    : String r0 ( gh_redact text pats )
    : String r ( gh_rewrite db r0 )
    : String out ( gh_redact r pats )
    ^ out
}

// ── What a task looks like on GitHub ─────────────────────────────────

: GhmTask {
    b found
    i id
    String title
    String body
    String tags  // ,a,b,
    String poster
    String status
    String owner
    String result
    i priority
    i created
}

@ __ghm_task_on Database db i id → GhmTask {
    ?? ( sqlite_prepare db `SELECT title, body, tags, poster, status, owner, result, priority, created FROM tasks WHERE id = ?1` ) {
        F _ → {}
        T q → {
            ( _ag_bind_i q 1 id )
            ? ( _ag_row q ) {
                ^ @ GhmTask { T id ( sqlite_column_text q 0 ) ( sqlite_column_text q 1 ) ( sqlite_column_text q 2 ) ( sqlite_column_text q 3 )
                    ( sqlite_column_text q 4 ) ( sqlite_column_text q 5 ) ( sqlite_column_text q 6 ) ( sqlite_column_int q 7 ) ( sqlite_column_int q 8 ) }
            } {}
        }
    }
    ^ @ GhmTask { F id ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) 0 0 }
}

@ __ghm_private GhmTask t → b { ^ | ( string_contains . t tags `,private,` ) ( string_contains . t tags `,security,` ) }

// Agora's priority in words, as the tool describes it: 0 low, 1 medium,
// 2 high, 3 urgent (below and above clamp to the ends). On GitHub a bare
// number would read the wrong way round (P1 is GitHub's most urgent).
@ gh_prio_name i p → s {
    ? <= p 0 { ^ `low` } {}
    ? == p 1 { ^ `medium` } {}
    ? == p 2 { ^ `high` } {}
    ^ `urgent`
}

// `["a","b","priority: high","in-progress"]`
@ __ghm_labels GhmTask t → Json {
    : Json arr ( json_arr_new )
    : s tg ( string_data . t tags )
    : ( Slice u ) v ( slice_of_str tg )
    : i n ( nurl_str_len tg )
    : String cur ( string_new )
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte v k )
        ? == c 44 {
            ? > ( string_len cur ) 0 { ( json_arr_push arr ( json_str_lit ( string_data cur ) ) ) ( string_clear cur ) } {}
        } { ( string_push_char cur c ) }
        = k + k 1
    }
    : String p ( string_from `priority: ` )
    ( string_push_str p ( gh_prio_name . t priority ) )
    ( json_arr_push arr ( json_str_lit ( string_data p ) ) )
    ? != 0 ( nurl_str_eq ( string_data . t status ) `claimed` ) { ( json_arr_push arr ( json_str_lit `in-progress` ) ) } {}
    ^ arr
}

@ __ghm_issue_body Database db GhmTask t ( Vec String ) pats → String {
    : String b ( string_from `AGORA-` )
    ( string_push_int b . t id )
    ( string_push_str b ` · posted by ` )
    ( string_push_str b ( string_data ( gh_redact ( string_clone . t poster ) pats ) ) )
    ( string_push_str b ` · priority ` )
    ( string_push_str b ( gh_prio_name . t priority ) )
    ? != 0 ( nurl_str_eq ( string_data . t status ) `claimed` ) {
        ( string_push_str b ` · claimed by ` )
        ( string_push_str b ( string_data ( gh_redact ( string_clone . t owner ) pats ) ) )
    } {}
    ( string_push_str b `\n\n` )
    ( string_push_str b ( string_data ( __ghm_public db ( string_clone . t body ) pats ) ) )
    ( string_push_str b `\n\n---\n_This issue mirrors an Agora task; comments here are not read by the agents._` )
    ( string_push_str b `\n\n<!-- agora-task: ` )
    ( string_push_int b . t id )
    ( string_push_str b ` -->` )
    ^ b
}

// ── Sending ──────────────────────────────────────────────────────────

: GhmOut {
    i status
    Json body
    i retry_at
    String err
}

// One write (or the read that finds an issue after a crash): to GitHub,
// or to the dry-run log, or to the test stand-in.
@ __ghm_send AgStore st AgGhConf c HttpClient h s auth b dry i task s method s path Json body i now → GhmOut {
    : String bs ( json_stringify body )
    : AgGhFake f ( locked_take [AgGhFake] g_ghf )
    : b fake . f on
    : i num . f next
    : b failing & fake > . f fail 0
    : i fst . f fail_status
    : i ftask . f find_task
    : i fnum . f find_number
    ( locked_restore [AgGhFake] g_ghf @ AgGhFake { . f on ? & fake ! failing + num 1 num ? failing - . f fail 1 . f fail . f fail_status . f find_task . f find_number } )
    ? | dry fake {
        ?? ( _ag_conn st ) {
            F _ → {}
            T db → {
                ?? ( sqlite_prepare db `INSERT INTO gh_dry (ts, task, method, path, body) VALUES (?1, ?2, ?3, ?4, ?5)` ) {
                    F _ → {}
                    T q → {
                        ( _ag_bind_i q 1 now )
                        ( _ag_bind_i q 2 task )
                        ( _ag_bind_s q 3 method )
                        ( _ag_bind_s q 4 path )
                        ( _ag_bind_s q 5 ( string_data bs ) )
                        ( _ag_run q )
                    }
                }
            }
        }
        ? failing { ^ @ GhmOut { fst ( json_null ) ? == fst 429 + now 60 0 ( string_from `stand-in failure` ) } } {}
        ? != 0 ( nurl_str_eq method `GET` ) {
            : Json arr ( json_arr_new )
            ? > ftask 0 {
                : Json it ( json_obj_new )
                ( json_obj_set it `number` ( json_int fnum ) )
                : Json u ( json_obj_new )
                ( json_obj_set u `type` ( json_str_lit `Bot` ) )
                ( json_obj_set u `login` ( json_str_lit `agora-test[bot]` ) )
                ( json_obj_set it `user` u )
                : String mk ( string_from `…\n\n<!-- agora-task: ` )
                ( string_push_int mk ftask )
                ( string_push_str mk ` -->` )
                ( json_obj_set it `body` ( json_str_lit ( string_data mk ) ) )
                ( json_arr_push arr it )
            } {}
            ^ @ GhmOut { 200 arr 0 ( string_new ) }
        } {}
        : Json r ( json_obj_new )
        // A dry run's stand-in numbers are negative: never a real issue.
        ( json_obj_set r `number` ( json_int ? dry - 0 task num ) )
        ( json_obj_set r `id` ( json_int ? dry - 0 1 num ) )
        ^ @ GhmOut { ? != 0 ( nurl_str_eq method `POST` ) 201 200 r 0 ( string_new ) }
    } {}
    : String url ( string_clone . c api )
    ( string_push_str url path )
    : GhResp r ( _gh_req h method ( string_data url ) auth ( string_data bs ) now )
    : Json jb ?? ( json_parse ( string_data . r body ) ) { T j → j F _ → ( json_null ) }
    : String err ( string_new )
    ? | == . r status 0 >= . r status 300 {
        ( string_push_str err method )
        ( string_push_str err ` ` )
        ( string_push_str err path )
        ( string_push_str err `: ` )
        ? > . r status 0 {
            ( string_push_str err `HTTP ` )
            ( string_push_int err . r status )
            : String msg ( _gh_s jb `message` )
            ? > ( string_len msg ) 0 { ( string_push_str err ` ` ) ( string_push_str err ( string_data ( gh_line msg 120 ) ) ) } {}
        } { ( string_push_str err ( string_data . r body ) ) }
    } {}
    ^ @ GhmOut { . r status jb . r retry_at err }
}

// The result of handling one queued step.
: i GHM_DONE 0
: i GHM_RETRY 1  // try again later (GitHub failed, or a rate limit)
: i GHM_GIVE_UP 2  // GitHub refused it for good; the queue moves on

: GhmStep {
    i rc
    i retry_at
    String err
    i writes
}

@ __ghm_ok i rc i writes → GhmStep { ^ @ GhmStep { rc 0 ( string_new ) writes } }

@ __ghm_fail GhmOut o i writes → GhmStep {
    : b rate | | == . o status 429 == . o status 0 | >= . o status 500 & == . o status 403 > . o retry_at 0
    ^ @ GhmStep { ? rate GHM_RETRY GHM_GIVE_UP . o retry_at ( string_clone . o err ) writes }
}

// Pause between writes: about one a second.
@ __ghm_pace i writes b dry → v { ? & & > writes 0 ! dry ! ( __ghf_on ) { ( sleep_ms 1000 ) } {} }

@ __ghm_label_color s name → s {
    ? != 0 ( nurl_str_eq name `priority: urgent` ) { ^ `b60205` } {}
    ? != 0 ( nurl_str_eq name `priority: high` ) { ^ `d93f0b` } {}
    ? != 0 ( nurl_str_eq name `priority: medium` ) { ^ `fbca04` } {}
    ? != 0 ( nurl_str_eq name `priority: low` ) { ^ `c2e0c6` } {}
    ? != 0 ( nurl_str_eq name `in-progress` ) { ^ `0e8a16` } {}
    ^ `ededed`
}

// Make sure every label exists (created on first use; 422 = it does).
@ __ghm_labels_on AgStore st AgGhConf c HttpClient h s auth b dry i task s full Json labels i now inout i writes → !v GhmOut {
    : i n ( json_arr_len labels )
    : ~ i k 0
    ~ < k n {
        ?? ( json_arr_get labels k ) {
            T l → {
                : String name ( string_from ( json_as_str l ) )
                : ~ b known F
                ?? ( _ag_conn st ) {
                    F _ → {}
                    T db → {
                        ?? ( sqlite_prepare db `SELECT COUNT(*) FROM gh_labels WHERE name = ?1` ) {
                            F _ → {}
                            T q → { ( _ag_bind_s q 1 ( string_data name ) ) ? ( _ag_row q ) { = known > ( sqlite_column_int q 0 ) 0 } {} }
                        }
                    }
                }
                ? known {} {
                    ( __ghm_pace writes dry )
                    : String path ( string_from `/repos/` )
                    ( string_push_str path full )
                    ( string_push_str path `/labels` )
                    : Json b ( json_obj_new )
                    ( json_obj_set b `name` ( json_str_lit ( string_data name ) ) )
                    ( json_obj_set b `color` ( json_str_lit ( __ghm_label_color ( string_data name ) ) ) )
                    : GhmOut o ( __ghm_send st c h auth dry task `POST` ( string_data path ) b now )
                    = writes + writes 1
                    ? | == . o status 201 == . o status 422 {
                        // Kept in a dry run too (its log names each label once);
                        // going live forgets them (ag_gh_mirror_mode).
                        ?? ( _ag_conn st ) {
                            F _ → {}
                            T db → {
                                ?? ( sqlite_prepare db `INSERT OR IGNORE INTO gh_labels (name) VALUES (?1)` ) {
                                    F _ → {}
                                    T q → { ( _ag_bind_s q 1 ( string_data name ) ) ( _ag_run q ) }
                                }
                            }
                        }
                    } { ^ @ !v GhmOut { F o } }
                }
            }
            F → {}
        }
        = k + k 1
    }
    ^ @ !v GhmOut { T }
}

@ __ghm_exec AgStore st s sql i a i b s c → v {
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db sql ) {
                F _ → {}
                T q → {
                    ( _ag_bind_i q 1 a )
                    ( _ag_bind_i q 2 b )
                    ( _ag_bind_s q 3 c )
                    ( _ag_run q )
                }
            }
        }
    }
}

// Find the issue of task `task` among the App's own recent issues by its
// body marker (after a crash between creating it and keeping its number).
// 200 with `number` (0: not there — make it); anything else: the read
// failed, so try again later rather than make a second one. Only an
// issue (not a PR) by the App's own bot counts: anyone can write a marker.
@ __ghm_find AgStore st AgGhConf c HttpClient h s auth i task s full i now → GhmOut {
    : String slug ( _gh_slug )
    // Without the App's slug its own issues cannot be told from another
    // bot's: never adopt one then — and never make a second either.
    ? == ( string_len slug ) 0 { ^ @ GhmOut { 0 ( json_null ) 0 ( string_from `github-app.json has no slug: cannot tell the App's issues` ) } } {}
    : String bot ( string_clone slug )
    ( string_push_str bot `[bot]` )
    : String path ( string_from `/repos/` )
    ( string_push_str path full )
    ( string_push_str path `/issues?state=all&sort=created&direction=desc&per_page=100` )
    ( string_push_str path `&creator=` )
    ( string_push_str path ( string_data slug ) )
    ( string_push_str path `%5Bbot%5D` )
    : GhmOut o ( __ghm_send st c h auth F task `GET` ( string_data path ) ( json_null ) now )
    ? != . o status 200 { ^ o } {}
    : String marker ( string_from `<!-- agora-task: ` )
    ( string_push_int marker task )
    ( string_push_str marker ` -->` )
    : i n ? ( json_is_arr . o body ) ( json_arr_len . o body ) 0
    : ~ i k 0
    ~ < k n {
        ?? ( json_arr_get . o body k ) {
            T it → {
                : String b ( _gh_s it `body` )
                : Json u ( _gh_obj it `user` )
                : b by_app & != 0 ( nurl_str_eq ( string_data ( _gh_s u `type` ) ) `Bot` ) ( string_eq ( _gh_s u `login` ) bot )
                : b is_pr ! ( json_is_null ( _gh_obj it `pull_request` ) )
                ? & & by_app ! is_pr ( string_contains b ( string_data marker ) ) {
                    : Json r ( json_obj_new )
                    ( json_obj_set r `number` ( json_int ( _gh_i it `number` ) ) )
                    ^ @ GhmOut { 200 r 0 ( string_new ) }
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    : Json none ( json_obj_new )
    ( json_obj_set none `number` ( json_int 0 ) )
    ^ @ GhmOut { 200 none 0 ( string_new ) }
}

// ── One queued step ──────────────────────────────────────────────────

: GhmIssue {
    b found  // a row: the issue is made, or being made (number 0)
    i number  // 0 = being made; < 0 = a dry run's stand-in
    String state
    String labels
    String head  // the title and body last written
}

@ __ghm_issue_row AgStore st i task → GhmIssue {
    : ~ GhmIssue r @ GhmIssue { F 0 ( string_new ) ( string_new ) ( string_new ) }
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT number, state, labels, head FROM gh_issues WHERE task = ?1` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_i q 1 task )
                    ? ( _ag_row q ) { = r @ GhmIssue { T ( sqlite_column_int q 0 ) ( sqlite_column_text q 1 ) ( sqlite_column_text q 2 ) ( sqlite_column_text q 3 ) } } {}
                }
            }
        }
    }
    ^ r
}

@ ag_gh_mirror_step AgStore st AgGhConf c HttpClient h s auth b dry ( Vec String ) pats s full i task s kind i msg i now → GhmStep {
    : ~ i writes 0
    : ~ GhmTask t @ GhmTask { F task ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) 0 0 }
    : ~ String body ( string_new )
    : ~ String title ( string_new )
    ?? ( _ag_conn st ) {
        F _ → { ^ @ GhmStep { GHM_RETRY 0 ( string_from `the agora file could not be opened` ) 0 } }
        T db → {
            = t ( __ghm_task_on db task )
            ? . t found {
                = body ( __ghm_issue_body db t pats )
                = title ( __ghm_public db ( string_clone . t title ) pats )
            } {}
        }
    }
    ? . t found {} { ^ ( __ghm_ok GHM_DONE 0 ) }
    ? ( __ghm_private t ) { ^ ( __ghm_ok GHM_DONE 0 ) } {}
    : GhmIssue iss ( __ghm_issue_row st task )
    : String base ( string_from `/repos/` )
    ( string_push_str base full )
    ( string_push_str base `/issues` )
    : Json labels ( __ghm_labels t )
    : String lab_s ( json_stringify labels )
    : String head ( string_clone title )
    ( string_push_str head `\n` )
    ( string_push_str head ( string_data body ) )
    : ~ i number . iss number
    : ~ String state ( string_clone . iss state )
    : b finished | != 0 ( nurl_str_eq ( string_data . t status ) `done` ) != 0 ( nurl_str_eq ( string_data . t status ) `cancelled` )
    // No issue yet: a task finished before the mirror started gets none.
    ? ! . iss found {
        : i since ( __ghm_setting st `gh_mirror_since` 0 )
        ? & finished < . t created since { ^ ( __ghm_ok GHM_DONE 0 ) } {}
    } {}
    // A crash between creating it and keeping its number: find it.
    ? & & . iss found == number 0 ! dry {
        : GhmOut fo ( __ghm_find st c h auth task full now )
        // Never a second issue on a failed read: always try again later.
        ? != . fo status 200 { ^ @ GhmStep { GHM_RETRY . fo retry_at ( string_clone . fo err ) writes } } {}
        = number ( _gh_i . fo body `number` )
        ? > number 0 { ( __ghm_exec st `UPDATE gh_issues SET number = ?2 WHERE task = ?1` task number `` ) } {}
    } {}
    ? == number 0 {
        ?? ( __ghm_labels_on st c h auth dry task full labels now writes ) { T _ → {} F o → { ^ ( __ghm_fail o writes ) } }
        ( __ghm_exec st `INSERT INTO gh_issues (task, number, state, labels, head) VALUES (?1, 0, 'open', ?3, '') ON CONFLICT (task) DO NOTHING` task 0 ( string_data lab_s ) )
        ( __ghm_pace writes dry )
        : Json b ( json_obj_new )
        ( json_obj_set b `title` ( json_str_lit ( string_data title ) ) )
        ( json_obj_set b `body` ( json_str_lit ( string_data body ) ) )
        ( json_obj_set b `labels` ( json_clone labels ) )
        : GhmOut o ( __ghm_send st c h auth dry task `POST` ( string_data base ) b now )
        = writes + writes 1
        ? != . o status 201 { ^ ( __ghm_fail o writes ) } {}
        = number ( _gh_i . o body `number` )
        ( __ghm_exec st `UPDATE gh_issues SET number = ?2, head = ?3 WHERE task = ?1` task number ( string_data head ) )
        = state ( string_from `open` )
    } {
        // Title, body and labels follow the task; written only when changed.
        : String ipath ( string_clone base )
        ( string_push_str ipath `/` )
        ( string_push_int ipath number )
        ? ! ( string_eq head . iss head ) {
            ( __ghm_pace writes dry )
            : Json b ( json_obj_new )
            ( json_obj_set b `title` ( json_str_lit ( string_data title ) ) )
            ( json_obj_set b `body` ( json_str_lit ( string_data body ) ) )
            : GhmOut o ( __ghm_send st c h auth dry task `PATCH` ( string_data ipath ) b now )
            = writes + writes 1
            ? != . o status 200 { ^ ( __ghm_fail o writes ) } {}
            // A dry run never moves a real issue's checkpoints: live
            // must still write what the dry run only pretended to.
            ? | ! dry < number 0 { ( __ghm_exec st `UPDATE gh_issues SET head = ?3 WHERE task = ?1` task 0 ( string_data head ) ) } {}
        } {}
        ? ! ( string_eq lab_s . iss labels ) {
            ?? ( __ghm_labels_on st c h auth dry task full labels now writes ) { T _ → {} F o → { ^ ( __ghm_fail o writes ) } }
            ( __ghm_pace writes dry )
            : String lpath ( string_clone ipath )
            ( string_push_str lpath `/labels` )
            : Json b ( json_obj_new )
            ( json_obj_set b `labels` ( json_clone labels ) )
            : GhmOut o ( __ghm_send st c h auth dry task `PUT` ( string_data lpath ) b now )
            = writes + writes 1
            ? != . o status 200 { ^ ( __ghm_fail o writes ) } {}
            ? | ! dry < number 0 { ( __ghm_exec st `UPDATE gh_issues SET labels = ?3 WHERE task = ?1` task 0 ( string_data lab_s ) ) } {}
        } {}
    }
    : String ipath ( string_clone base )
    ( string_push_str ipath `/` )
    ( string_push_int ipath number )
    : String cpath ( string_clone ipath )
    ( string_push_str cpath `/comments` )
    // A `t<N>:` post: one comment, keyed on the message.
    ? != 0 ( nurl_str_eq kind `comment` ) {
        : ~ b had F
        : ~ String who ( string_new )
        : ~ String text ( string_new )
        ?? ( _ag_conn st ) {
            F _ → {}
            T db → {
                ?? ( sqlite_prepare db `SELECT (SELECT COUNT(*) FROM gh_comments WHERE msg = ?1), sender, body FROM messages WHERE id = ?1` ) {
                    F _ → {}
                    T q → {
                        ( _ag_bind_i q 1 msg )
                        ? ( _ag_row q ) {
                            = had > ( sqlite_column_int q 0 ) 0
                            = who ( sqlite_column_text q 1 )
                            = text ( __ghm_public db ( sqlite_column_text q 2 ) pats )
                        } { = had T }
                    }
                }
            }
        }
        ? had {} {
            ( __ghm_pace writes dry )
            : String cb ( string_from `**` )
            ( string_push_str cb ( string_data ( gh_redact ( string_clone who ) pats ) ) )
            ( string_push_str cb `** (Agora): ` )
            ( string_push_str cb ( string_data text ) )
            : Json b ( json_obj_new )
            ( json_obj_set b `body` ( json_str_lit ( string_data cb ) ) )
            : GhmOut o ( __ghm_send st c h auth dry task `POST` ( string_data cpath ) b now )
            = writes + writes 1
            ? != . o status 201 { ^ ( __ghm_fail o writes ) } {}
            ( __ghm_exec st `INSERT OR IGNORE INTO gh_comments (msg, task, id) VALUES (?1, ?2, CAST(?3 AS INTEGER))` msg task ( string_data ( __ghm_int_str ( _gh_i . o body `id` ) ) ) )
        }
        ^ ( __ghm_ok GHM_DONE writes )
    } {}
    // A pull request that names the task: one comment, which GitHub shows
    // on the PR's timeline too.
    ? != 0 ( nurl_str_eq kind `pr` ) {
        : ~ b noted T
        ?? ( _ag_conn st ) {
            F _ → {}
            T db → {
                ?? ( sqlite_prepare db `SELECT noted FROM gh_task_prs WHERE task = ?1 AND pr = ?2` ) {
                    F _ → {}
                    T q → { ( _ag_bind_i q 1 task ) ( _ag_bind_i q 2 msg ) ? ( _ag_row q ) { = noted != ( sqlite_column_int q 0 ) 0 } {} }
                }
            }
        }
        ? noted {} {
            ( __ghm_pace writes dry )
            : String cb ( string_from `Pull request #` )
            ( string_push_int cb msg )
            : Json b ( json_obj_new )
            ( json_obj_set b `body` ( json_str_lit ( string_data cb ) ) )
            : GhmOut o ( __ghm_send st c h auth dry task `POST` ( string_data cpath ) b now )
            = writes + writes 1
            ? != . o status 201 { ^ ( __ghm_fail o writes ) } {}
            ? dry {} { ( __ghm_exec st `UPDATE gh_task_prs SET noted = 1 WHERE task = ?1 AND pr = ?2` task msg `` ) }
        }
        ^ ( __ghm_ok GHM_DONE writes )
    } {}
    // Done: the result as the last comment (keyed on the task: -id).
    : b to_done != 0 ( nurl_str_eq ( string_data . t status ) `done` )
    : b to_cancel != 0 ( nurl_str_eq ( string_data . t status ) `cancelled` )
    ? & to_done > ( string_len . t result ) 0 {
        : ~ b had F
        ?? ( _ag_conn st ) {
            F _ → {}
            T db → {
                ?? ( sqlite_prepare db `SELECT COUNT(*) FROM gh_comments WHERE msg = ?1` ) {
                    F _ → {}
                    T q → { ( _ag_bind_i q 1 - 0 task ) ? ( _ag_row q ) { = had > ( sqlite_column_int q 0 ) 0 } {} }
                }
            }
        }
        ? had {} {
            : ~ String text ( string_new )
            ?? ( _ag_conn st ) { F _ → {} T db → { = text ( __ghm_public db ( string_clone . t result ) pats ) } }
            ( __ghm_pace writes dry )
            : String cb ( string_from `**` )
            ( string_push_str cb ( string_data ( gh_redact ( string_clone . t owner ) pats ) ) )
            ( string_push_str cb `** (Agora) finished it: ` )
            ( string_push_str cb ( string_data text ) )
            : Json b ( json_obj_new )
            ( json_obj_set b `body` ( json_str_lit ( string_data cb ) ) )
            : GhmOut o ( __ghm_send st c h auth dry task `POST` ( string_data cpath ) b now )
            = writes + writes 1
            ? != . o status 201 { ^ ( __ghm_fail o writes ) } {}
            ( __ghm_exec st `INSERT OR IGNORE INTO gh_comments (msg, task, id) VALUES (?1, ?2, CAST(?3 AS INTEGER))` - 0 task task ( string_data ( __ghm_int_str ( _gh_i . o body `id` ) ) ) )
        }
    } {}
    // Open or closed as the task is.
    : b want_closed | to_done to_cancel
    : b is_closed != 0 ( nurl_str_eq ( string_data state ) `closed` )
    ? != want_closed is_closed {
        // Superseded: another task's body starts `Supersedes AGORA-N`.
        : ~ i dup 0
        ? to_cancel {
            ?? ( _ag_conn st ) {
                F _ → {}
                T db → {
                    ?? ( sqlite_prepare db `SELECT g.number FROM tasks s JOIN gh_issues g ON g.task = s.id WHERE g.number > 0 AND ((s.body LIKE 'Supersedes AGORA-' || ?1 || '%' AND substr(s.body, length('Supersedes AGORA-' || ?1) + 1, 1) NOT GLOB '[0-9]') OR (s.body LIKE 'Supersedes #' || ?1 || '%' AND substr(s.body, length('Supersedes #' || ?1) + 1, 1) NOT GLOB '[0-9]')) ORDER BY s.id DESC LIMIT 1` ) {
                        F _ → {}
                        T q → { ( _ag_bind_i q 1 task ) ? ( _ag_row q ) { = dup ( sqlite_column_int q 0 ) } {} }
                    }
                }
            }
        } {}
        // The "Superseded by" comment is kept under its own key, so a close
        // that fails after it is retried without writing it twice.
        : i skey - 0 + 1000000000000 task
        : ~ b said F
        ?? ( _ag_conn st ) {
            F _ → {}
            T db → {
                ?? ( sqlite_prepare db `SELECT COUNT(*) FROM gh_comments WHERE msg = ?1` ) {
                    F _ → {}
                    T q → { ( _ag_bind_i q 1 skey ) ? ( _ag_row q ) { = said > ( sqlite_column_int q 0 ) 0 } {} }
                }
            }
        }
        ? & > dup 0 ! said {
            ( __ghm_pace writes dry )
            : String cb ( string_from `Superseded by #` )
            ( string_push_int cb dup )
            ( string_push_str cb `.` )
            : Json b ( json_obj_new )
            ( json_obj_set b `body` ( json_str_lit ( string_data cb ) ) )
            : GhmOut o ( __ghm_send st c h auth dry task `POST` ( string_data cpath ) b now )
            = writes + writes 1
            ? != . o status 201 { ^ ( __ghm_fail o writes ) } {}
            ( __ghm_exec st `INSERT OR IGNORE INTO gh_comments (msg, task, id) VALUES (?1, ?2, CAST(?3 AS INTEGER))` skey task ( string_data ( __ghm_int_str ( _gh_i . o body `id` ) ) ) )
        } {}
        ( __ghm_pace writes dry )
        : Json b ( json_obj_new )
        ( json_obj_set b `state` ( json_str_lit ? want_closed `closed` `open` ) )
        ? want_closed { ( json_obj_set b `state_reason` ( json_str_lit ? to_done `completed` ? > dup 0 `duplicate` `not_planned` ) ) } {}
        : GhmOut o ( __ghm_send st c h auth dry task `PATCH` ( string_data ipath ) b now )
        = writes + writes 1
        ? != . o status 200 { ^ ( __ghm_fail o writes ) } {}
        ? | ! dry < number 0 { ( __ghm_exec st `UPDATE gh_issues SET state = ?3 WHERE task = ?1` task 0 ? want_closed `closed` `open` ) } {}
    } {}
    ^ ( __ghm_ok GHM_DONE writes )
}

@ __ghm_int_str i n → String {
    : String s ( string_new )
    ( string_push_int s n )
    ^ s
}

// Drain the queue of repository `full` in order until a write was made
// (about one a second: the worker comes back each second) or GitHub
// fails; returns the writes made.
@ ag_gh_mirror_round AgStore st AgGhConf c s full i now → i {
    : i mode ( __ghm_setting st `gh_mirror_mode` 0 )
    ? == mode 0 { ^ 0 } {}
    : b dry == mode 1
    ? ( _gh_bo_ok now ) {} { ^ 0 }
    : AgGhMirror m ( _ghm_conf )
    : HttpClient h ( _gh_client )
    : ~ String auth ( string_new )
    : AgGhFake f ( locked_take [AgGhFake] g_ghf )
    : b fake . f on
    ( locked_restore [AgGhFake] g_ghf f )
    : ~ i writes 0
    ~ < writes 1 {
        : ~ i id 0
        : ~ i task 0
        : ~ String kind ( string_new )
        : ~ i msg 0
        : ~ i next_at 0
        : ~ i attempts 0
        ?? ( _ag_conn st ) {
            F _ → { ^ writes }
            T db → {
                ?? ( sqlite_prepare db `SELECT id, task, kind, msg, next_at, attempts FROM gh_outbox WHERE done = 0 ORDER BY id LIMIT 1` ) {
                    F _ → {}
                    T q → {
                        ? ( _ag_row q ) {
                            = id ( sqlite_column_int q 0 )
                            = task ( sqlite_column_int q 1 )
                            = kind ( sqlite_column_text q 2 )
                            = msg ( sqlite_column_int q 3 )
                            = next_at ( sqlite_column_int q 4 )
                            = attempts ( sqlite_column_int q 5 )
                        } {}
                    }
                }
            }
        }
        ? | == id 0 > next_at now { ^ writes } {}
        ? & & == ( string_len auth ) 0 ! dry ! fake {
            : GhResp a ( _gh_auth h c now )
            ? != . a status 200 {
                ( _gh_bo_note T . a retry_at now )
                ( __ghm_exec st `UPDATE gh_outbox SET attempts = attempts + 1, error = ?3 WHERE id = ?1` id 0 `no installation token` )
                ( ag_gh_health_set st `mirror_error` now `no installation token` )
                ^ writes
            } {}
            = auth ( string_clone . a body )
        } {}
        : GhmStep r ( ag_gh_mirror_step st c h ( string_data auth ) dry . m redact full task ( string_data kind ) msg now )
        = writes + writes . r writes
        ? == . r rc GHM_DONE {
            ( __ghm_exec st `UPDATE gh_outbox SET done = 1, error = '' WHERE id = ?1` id 0 `` )
            ? > . r writes 0 { ( ag_gh_health_set st `mirror_write` now `` ) } {}
        } {
            : b give_up | == . r rc GHM_GIVE_UP >= + attempts 1 AG_GH_MIRROR_ATTEMPTS
            ? & give_up != . r rc GHM_RETRY {
                ( __ghm_exec st `UPDATE gh_outbox SET done = 1, attempts = attempts + 1, error = ?3 WHERE id = ?1` id 0 ( string_data . r err ) )
            } {
                // Back off: the step stays first in the queue.
                : i wait ? > . r retry_at now - . r retry_at now * 30 + attempts 1
                ( __ghm_exec st `UPDATE gh_outbox SET attempts = attempts + 1, next_at = ?2, error = ?3 WHERE id = ?1` id + now wait ( string_data . r err ) )
                ( _gh_bo_note T . r retry_at now )
            }
            ( ag_gh_health_set st `mirror_error` now ( string_data . r err ) )
            ^ writes
        }
        // A dry run writes nothing: one step per round is enough to read.
        ? dry { = writes + writes 1 } {}
    }
    ^ writes
}

: GhMirrorHealth {
    i mode
    i queue
    i oldest
    i last_write
    String error
    i error_at
}

// The queue stuck past AG_GH_MIRROR_STUCK: the alert agent hears once.
@ __ghm_stuck AgStore st i now → v {
    : AgGhMirror m ( _ghm_conf )
    ? == ( string_len . m alert ) 0 { ^ v } {}
    : GhMirrorHealth hh ( ag_gh_mirror_health st )
    : i oldest . hh oldest
    : GhHealth told ( ag_gh_health_get st `mirror_stuck` )
    : GhHealth e ( ag_gh_health_get st `mirror_error` )
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ? & > oldest 0 < oldest - now AG_GH_MIRROR_STUCK {
                ? < . told ts oldest {
                    : String t ( string_from `github mirror: tasks have waited over 30 minutes to reach GitHub — ` )
                    ( string_push_str t ( string_data ( gh_line ( string_clone . e text ) 160 ) ) )
                    : String mbox ( ag_mailbox ( string_data . m alert ) )
                    : i _id ( _ag_post_on db ( string_data mbox ) `agora` ( string_data t ) 0 now )
                    ( _gh_health_set_on db `mirror_stuck` now `` )
                } {}
            } {}
        }
    }
}

@ ag_gh_mirror_health AgStore st → GhMirrorHealth {
    : ~ i q 0
    : ~ i oldest 0
    ?? ( _ag_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT COUNT(*), COALESCE(MIN(created), 0) FROM gh_outbox WHERE done = 0` ) {
                F _ → {}
                T qq → { ? ( _ag_row qq ) { = q ( sqlite_column_int qq 0 ) = oldest ( sqlite_column_int qq 1 ) } {} }
            }
        }
    }
    : GhHealth w ( ag_gh_health_get st `mirror_write` )
    : GhHealth e ( ag_gh_health_get st `mirror_error` )
    ^ @ GhMirrorHealth { ( __ghm_setting st `gh_mirror_mode` 0 ) q oldest . w ts ( string_clone . e text ) . e ts }
}

// ── The web page ─────────────────────────────────────────────────────

// GET /m/github?repo= — the repository's GitHub connection: whether it is
// connected, the mirror's mode and queue, and the newest requests a dry
// run logged (what would be written, redaction applied).
@ ag_h_github HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : Json o ( json_obj_new )
    : b on ( ag_gh_connected ( string_data . w repo ) )
    ( json_obj_set o `connected` ( json_bool on ) )
    ? on {} { ^ ( _ag_json_ok o ) }
    : GhMirrorHealth hh ( ag_gh_mirror_health . w rs )
    : Json mj ( json_obj_new )
    ( json_obj_set mj `mode` ( json_str_lit ? == . hh mode 2 `live` ? == . hh mode 1 `dry run` `off` ) )
    ( json_obj_set mj `queue` ( json_int . hh queue ) )
    ( json_obj_set mj `oldest` ( json_int . hh oldest ) )
    ( json_obj_set mj `last_write` ( json_int . hh last_write ) )
    ( json_obj_set mj `error` ( json_str_lit ( string_data . hh error ) ) )
    ( json_obj_set mj `error_at` ( json_int . hh error_at ) )
    ( json_obj_set o `mirror` mj )
    : GhHealth hr ( ag_gh_health_get . w rs `receipt` )
    : GhHealth hc ( ag_gh_health_get . w rs `reconcile` )
    ( json_obj_set o `last_event` ( json_int . hr ts ) )
    ( json_obj_set o `last_reconcile` ( json_int . hc ts ) )
    : i limit ( _ag_query_int req `limit` 50 1 500 )
    : Json arr ( json_arr_new )
    ?? ( _ag_conn . w rs ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT ts, task, method, path, body FROM gh_dry ORDER BY id DESC LIMIT ?1` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_i q 1 limit )
                    ~ ( _ag_row q ) {
                        : Json e ( json_obj_new )
                        ( json_obj_set e `ts` ( json_int ( sqlite_column_int q 0 ) ) )
                        ( json_obj_set e `task` ( json_int ( sqlite_column_int q 1 ) ) )
                        : String m ( sqlite_column_text q 2 )
                        : String pa ( sqlite_column_text q 3 )
                        : String bo ( sqlite_column_text q 4 )
                        ( json_obj_set e `method` ( json_str_lit ( string_data m ) ) )
                        ( json_obj_set e `path` ( json_str_lit ( string_data pa ) ) )
                        ?? ( json_parse ( string_data bo ) ) { T j → { ( json_obj_set e `body` j ) } F _ → {} }
                        ( json_arr_push arr e )
                    }
                }
            }
        }
    }
    ( json_obj_set o `dry` arr )
    ^ ( _ag_json_ok o )
}

// ── The worker ───────────────────────────────────────────────────────

// One round over every connected repository: apply what arrived, tidy
// now and then, look at new watches at once and at all of them every
// AG_GH_RECONCILE_EVERY seconds; mirror the task board where it is.
: AgGhRound {
    i last_tidy
    i last_full
}

@ ag_gh_round AgGhRound r i now → AgGhRound {
    : AgGhConf c ( _gh_conf )
    ? . c on {} { ^ r }
    : b tidy >= - now . r last_tidy AG_GH_TIDY_EVERY
    : b full >= - now . r last_full AG_GH_RECONCILE_EVERY
    : GhRoute rt ( _gh_route c )
    : i n ( vec_len [String] . c repos )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] . c repos k ) {
            T full_name → {
                : AgStore st ( _gh_store c ( string_data full_name ) )
                ? . st ok {
                    : i _n ( ag_gh_process st rt now )
                    ? tidy { ( ag_gh_tidy st now ) ( __ghm_stuck st now ) } {}
                    : b _ok ( ag_gh_reconcile c ( string_data full_name ) ! full now )
                    : i _w ( ag_gh_mirror_round st c ( string_data full_name ) now )
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ @ AgGhRound { ? tidy now . r last_tidy ? full now . r last_full }
}

@ __gh_worker → v {
    // The first full look comes a minute after start: the server is up
    // and events that arrived while it was down are asked about.
    : ~ AgGhRound r @ AgGhRound { 0 - ( now_seconds ) - AG_GH_RECONCILE_EVERY 60 }
    ~ T {
        = r ( ag_gh_round r ( now_seconds ) )
        ( sleep_ms 1000 )
    }
}

// Start the worker (once, when GitHub is configured), the mirror set up
// from the configuration first.
@ ag_gh_start → b {
    : AgGhConf c ( _gh_conf )
    ? . c on {} { ^ F }
    ( ag_gh_mirror_setup ( now_seconds ) )
    ?? ( thread_spawn \ → v { ( __gh_worker ) } ) {
        T t → { ( thread_detach t ) ^ T }
        F _ → { ^ F }
    }
}
