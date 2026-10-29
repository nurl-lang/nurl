// agora_test.nu — the store, the operations, and both faces, in one
// process against a scratch file: no socket, no server.
//
//   1. store      join/post/inbox cursors, task leases and verdicts,
//                 notes, channels
//   2. operations every catalog entry dispatches; auth; the texts an
//                 agent reads; delivered-once through the op layer
//   3. REST       the router: GET /api, POST /api/<op> with a body,
//                 GET with a query, 401, 404 for an unknown op
//   4. MCP        tools/list from the catalog; tools/call with and
//                 without a context
//   5. 0.8.0      rules, skills, feedback; the web page's paging,
//                 sorting, writing and cleanup; the same signed in
//
// Prints one ok/FAIL line per check and exits non-zero if any failed.
// Run from the package directory (tests/agora_test.sh does).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/sqlite.nu`
$ `stdlib/ext/mcp_server.nu`
$ `src/service.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` )
        ( nurl_println label )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` )
        ( nurl_println label )
        = g_fail + g_fail 1
    }
}

@ seq s a s b → b { ^ != 0 ( nurl_str_eq a b ) }

@ has String hay s needle → b { ^ ( string_contains hay needle ) }

// ── 1. store ─────────────────────────────────────────────────────────

@ test_store AgStore st → v {
    ( check . st ok `store: opens` )
    ( check ( ag_agent_create st `alice` `tests` `h-alice` 100 ) `store: alice joins` )
    ( check ( ag_agent_create st `bob` `` `h-bob` 101 ) `store: bob joins` )
    ( check ! ( ag_agent_create st `bob` `` `h-bob2` 102 ) `store: a name is taken once` )
    ?? ( ag_agent_by_token st `h-bob` 103 ) {
        T id → { ( check ( seq ( string_data id ) `bob` ) `store: token resolves bob` ) }
        F _ → { ( check F `store: token resolves bob` ) }
    }
    ?? ( ag_agent_by_token st `h-nope` 103 ) {
        T id → { ( check F `store: unknown token is nobody` ) }
        F _ → { ( check T `store: unknown token is nobody` ) }
    }
    : i m1 ( ag_post st `public` `alice` `hello all` 0 110 )
    ( check > m1 0 `store: alice posts` )
    : String bobbox ( ag_mailbox `bob` )
    : i m2 ( ag_post st ( string_data bobbox ) `alice` `hi bob` 0 111 )
    ( check == ( ag_unread st `bob` ) 2 `store: bob has 2 unread` )
    ( check == ( ag_unread st `alice` ) 0 `store: own posts are not unread` )
    : AgInbox ib ( ag_inbox st `bob` 1 )
    ( check == ( vec_len [AgMsg] . ib msgs ) 1 `store: inbox honours the limit` )
    ( check == . ib remaining 1 `store: and counts what is left` )
    : AgInbox ib2 ( ag_inbox st `bob` 10 )
    ( check == ( vec_len [AgMsg] . ib2 msgs ) 1 `store: the next drain gets the rest` )
    ( check == . ib2 remaining 0 `store: nothing remains` )
    : AgInbox ib3 ( ag_inbox st `bob` 10 )
    ( check == ( vec_len [AgMsg] . ib3 msgs ) 0 `store: a message is delivered ONCE` )

    : i t1 ( ag_task_post st `do x` `details` `,dev,` `alice` 2 120 )
    ( check > t1 0 `store: task posted` )
    ( check == ( ag_task_claim st t1 `bob` 60 121 ) AG_TASK_OK `store: bob claims` )
    ( check == ( ag_task_claim st t1 `alice` 60 122 ) AG_TASK_WRONG_STATE `store: a claimed task cannot be claimed` )
    ( check == ( ag_task_claim st 999 `alice` 60 122 ) AG_TASK_NOT_FOUND `store: no such task` )
    ( check == ( ag_unread st `alice` ) 1 `store: the poster hears of the claim` )
    : ( Vec AgTask ) mine ( ag_tasks st `mine` `bob` `` 10 123 )
    ( check == ( vec_len [AgTask] mine ) 1 `store: bob holds one` )
    ( check == ( ag_task_extend st t1 `bob` 100 150 ) AG_TASK_OK `store: bob extends` )
    : ( Vec AgTask ) still ( ag_tasks st `mine` `bob` `` 10 200 )
    ( check == ( vec_len [AgTask] still ) 1 `store: the extended lease holds at t=200` )
    : ( Vec AgTask ) open ( ag_tasks st `open` `` `dev` 10 300 )
    ( check == ( vec_len [AgTask] open ) 1 `store: an expired lease reopens the task` )
    ( check == ( ag_unread st `bob` ) 1 `store: the holder hears of the expiry` )
    : ( Vec AgTask ) none ( ag_tasks st `open` `` `ops` 10 300 )
    ( check == ( vec_len [AgTask] none ) 0 `store: tag filter is exact` )
    ( check == ( ag_task_claim st t1 `bob` 60 301 ) AG_TASK_OK `store: bob reclaims` )
    ( check == ( ag_task_release st t1 `bob` `cannot today` 302 ) AG_TASK_OK `store: bob releases` )
    ( check == ( ag_task_claim st t1 `bob` 60 303 ) AG_TASK_OK `store: and takes it again` )
    ( check == ( ag_task_done st t1 `alice` `x` 304 ) AG_TASK_WRONG_STATE `store: only the holder finishes` )
    ( check == ( ag_task_done st t1 `bob` `result text` 305 ) AG_TASK_OK `store: bob finishes` )
    ( check == ( ag_task_done st t1 `bob` `again` 306 ) AG_TASK_WRONG_STATE `store: cannot finish twice` )
    ?? ( ag_task_get st t1 307 ) {
        T t → {
            ( check ( seq ( string_data . t status ) `done` ) `store: task is done` )
            ( check ( seq ( string_data . t result ) `result text` ) `store: with its result` )
        }
        F _ → { ( check F `store: task is done` ) }
    }
    : i t2 ( ag_task_post st `cancel me` `` `` `alice` 0 310 )
    ( check == ( ag_task_cancel st t2 `bob` 311 ) AG_TASK_WRONG_STATE `store: only the poster cancels` )
    ( check == ( ag_task_cancel st t2 `alice` 312 ) AG_TASK_OK `store: the poster cancels` )
    ( check == ( ag_task_cancel st t2 `alice` 313 ) AG_TASK_WRONG_STATE `store: cancel is once` )

    ( check ( ag_note_set st `` `plan` `step 1` `alice` 400 ) `store: note set` )
    ( check ( ag_note_set st `` `plan` `step 2` `bob` 401 ) `store: note overwrite` )
    ?? ( ag_note_get st `` `plan` ) {
        T n → { ( check ( seq ( string_data . n body ) `step 2` ) `store: note reads back` ) }
        F _ → { ( check F `store: note reads back` ) }
    }
    ( check ( ag_note_set st `repo` `plan` `repo plan` `alice` 402 ) `store: same key under a project` )
    ?? ( ag_note_get st `` `plan` ) {
        T n → { ( check ( seq ( string_data . n body ) `step 2` ) `store: the global one is untouched` ) }
        F _ → { ( check F `store: the global one is untouched` ) }
    }
    : ( Vec AgNote ) only ( ag_notes st `repo` F T )
    ( check == ( vec_len [AgNote] only ) 1 `store: notes of one project` )
    : ( Vec AgNote ) every ( ag_notes st `` T F )
    ( check == ( vec_len [AgNote] every ) 2 `store: notes of every project` )
    ( check == ( ag_note_count st ) 2 `store: note count spans projects` )
    ( check ( ag_note_del st `repo` `plan` ) `store: project note deleted` )
    ( check ( ag_note_del st `` `plan` ) `store: note deleted` )
    ( check ! ( ag_note_del st `` `plan` ) `store: deleting twice fails` )

    ( check ( ag_channel_create st `dev` `dev talk` `alice` 500 ) `store: channel created` )
    ( check ! ( ag_channel_create st `dev` `` `bob` 501 ) `store: channel exists once` )
    ( ag_post st `dev` `alice` `before bob followed` 0 502 )
    ( check ( ag_follow st `bob` `dev` ) `store: bob follows dev` )
    ( ag_post st `dev` `alice` `after` 0 503 )
    : AgInbox ib4 ( ag_inbox st `bob` 10 )
    // expiry notice (mailbox) + the release note + "after": not "before"
    : ~ b saw_before F
    : ~ b saw_after F
    : i n4 ( vec_len [AgMsg] . ib4 msgs )
    : ~ i k 0
    ~ < k n4 {
        ?? ( vec_get [AgMsg] . ib4 msgs k ) {
            T m → {
                ? ( seq ( string_data . m body ) `before bob followed` ) { = saw_before T } {}
                ? ( seq ( string_data . m body ) `after` ) { = saw_after T } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( check & ! saw_before saw_after `store: following starts from now` )
    ( check ( ag_unfollow st `bob` `dev` ) `store: bob unfollows` )
    ( check ! ( ag_unfollow st `bob` `dev` ) `store: unfollow twice fails` )
    : ( Vec AgMsg ) h ( ag_history st `dev` 0 10 )
    ( check == ( vec_len [AgMsg] h ) 2 `store: history sees everything` )
}

// A 0.1.0 store (notes keyed by `key` alone) opened by 0.2.0: the rows
// move under project '' and keep working.
@ test_migration → v {
    : s path `agora_test_scratch/v1.db`
    ?? ( file_delete path ) { T _ → {} F _ → {} }
    ?? ( sqlite_open path ) {
        F _ → { ( check F `migrate: seed a 0.1.0 store` ) }
        T db → {
            ?? ( sqlite_exec db `CREATE TABLE notes (key TEXT PRIMARY KEY, body TEXT NOT NULL, author TEXT NOT NULL, updated INTEGER NOT NULL)` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `INSERT INTO notes VALUES ('old', 'from 0.1.0', 'alice', 7)` ) { T _ → { ( check T `migrate: seed a 0.1.0 store` ) } F _ → { ( check F `migrate: seed a 0.1.0 store` ) } }
        }
    }
    : AgStore st ( ag_store_open path )
    ( check . st ok `migrate: 0.2.0 opens it` )
    ?? ( ag_note_get st `` `old` ) {
        T n → { ( check ( seq ( string_data . n body ) `from 0.1.0` ) `migrate: the old note is a global note` ) }
        F _ → { ( check F `migrate: the old note is a global note` ) }
    }
    ( check ( ag_note_set st `p` `old` `new` `bob` 8 ) `migrate: the new key shape works` )
    ( check == ( ag_note_count st ) 2 `migrate: both rows` )
    : AgStore again ( ag_store_open path )
    ( check & . again ok == ( ag_note_count again ) 2 `migrate: opening again migrates nothing` )
}

// ── 2. operations ────────────────────────────────────────────────────

@ call s who s op s args_json i now → AgRes {
    : AgStore st ( ag_store )
    : AgCaller c ? > ( nurl_str_len who ) 0 ( ag_caller_local st who now ) ( ag_caller_anon )
    : ~ Json args ( json_null )
    ?? ( json_parse args_json ) { T j → { = args j } F _ → {} }
    : AgRes r ( ag_op_call st c op args now )
    ^ r
}

@ test_ops → v {
    // Every catalog entry has a handler (a 501 would mean it does not).
    : ( Vec AgOpDef ) cat ( ag_op_catalog )
    : i n ( vec_len [AgOpDef] cat )
    ( check == n 32 `ops: 32 in the catalog` )
    : ~ b all_wired T
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgOpDef] cat i ) {
            T d → {
                : AgRes r ( call `probe` ( string_data . d name ) `{}` 1000 )
                ? == . r status 501 { = all_wired F } {}
                // The fixed auth table agrees with the catalog.
                : i want ? . d needs_auth 1 0
                ? == ( ag_op_auth_kind ( string_data . d name ) ) want {} {
                    ( check F ( nurl_str_cat `ops: auth table disagrees on ` ( string_data . d name ) ) )
                }
            }
            F _ → {}
        }
        = i + i 1
    }
    ( check all_wired `ops: every catalog entry dispatches` )
    ( check == ( ag_op_auth_kind `nope` ) -1 `ops: auth table: unknown name` )
    ( check == ( ag_op_auth_kind `` ) -1 `ops: auth table: empty name` )
    ( check == ( ag_op_auth_kind `task post` ) -1 `ops: auth table: a name with a space` )
    ( check == ( ag_op_auth_kind `brief wait` ) -1 `ops: auth table: two names` )
    ( check == ( ag_op_auth_kind `notes` ) 1 `ops: auth table: the last name` )

    : AgRes u ( call `` `brief` `{}` 1000 )
    ( check == . u status 401 `ops: brief needs a caller` )
    ( check ( has . u text `join` ) `ops: and the text says how` )
    : AgRes unk ( call `` `nope` `{}` 1000 )
    ( check == . unk status 404 `ops: unknown op is 404` )

    : AgRes j ( call `` `join` `{"name":"carol","about":"tester"}` 1000 )
    ( check == . j status 200 `ops: join` )
    ( check ( has . j text `token: ` ) `ops: join shows the token` )
    : AgRes j2 ( call `` `join` `{"name":"carol"}` 1000 )
    ( check == . j2 status 409 `ops: join twice is 409` )
    : AgRes j3 ( call `` `join` `{"name":"Bad Name"}` 1000 )
    ( check == . j3 status 400 `ops: join checks the name` )

    : AgRes p ( call `dan` `post` `{"body":"hello"}` 1001 )
    ( check ( seq ( string_data . p text ) `#1 posted to public\n` ) `ops: post text` )
    : AgRes s ( call `dan` `send` `{"to":"carol","body":"psst","reply_to":1}` 1002 )
    ( check == . s status 200 `ops: send` )
    : AgRes s2 ( call `dan` `send` `{"to":"nobody","body":"psst"}` 1002 )
    ( check == . s2 status 404 `ops: send to nobody is 404` )
    : AgRes b ( call `carol` `brief` `{}` 1062 )
    ( check ( has . b text `inbox: 2 new\n#1 public dan 1m: hello\n#2 dm dan 1m re#1: psst\n` ) `ops: brief delivers both, in order, with ages` )
    ( check ( has . b text `open tasks: 0 · notes: 0` ) `ops: brief counts` )
    : AgRes b2 ( call `carol` `brief` `{}` 1063 )
    ( check ( has . b2 text `inbox: nothing new` ) `ops: brief delivers once` )
    // wait: returns at once when something is unread, at the timeout otherwise
    : AgRes s3 ( call `dan` `send` `{"to":"carol","body":"wake up"}` 1064 )
    : i w0 ( now_ms )
    : AgRes w1 ( call `carol` `wait` `{"timeout_s":5}` 1064 )
    : i w1ms - ( now_ms ) w0
    ( check & ( has . w1 text `wake up` ) < w1ms 1000 `ops: wait returns at once with the unread message` )
    : AgRes s4 ( call `dan` `send` `{"to":"carol","body":"report only"}` 1064 )
    : AgRes w3 ( call `carol` `wait` `{"timeout_s":5,"deliver":false}` 1064 )
    ( check ( has . w3 text `unread: 1 (brief delivers)` ) `ops: wait deliver=false reports, moves nothing` )
    : AgRes w4 ( call `carol` `inbox` `{}` 1064 )
    ( check ( has . w4 text `report only` ) `ops: the message is still undelivered afterwards` )
    : i w2s ( now_ms )
    : AgRes w2 ( call `carol` `wait` `{"timeout_s":1}` 1065 )
    : i w2ms - ( now_ms ) w2s
    ( check & ( has . w2 text `inbox: nothing new` ) & >= w2ms 900 < w2ms 3000 `ops: wait with nothing new returns at the timeout` )
    : AgRes hs ( call `carol` `history` `{"channel":"public"}` 1064 )
    ( check ( has . hs text `#1 public dan` ) `ops: history re-reads` )
    : AgRes hm ( call `carol` `history` `{"channel":"@dan"}` 1064 )
    ( check == . hm status 403 `ops: another's mail is 403` )
    : AgRes hm2 ( call `carol` `history` `{"channel":"@carol"}` 1064 )
    ( check == . hm2 status 200 `ops: own mail is readable` )

    : AgRes tp ( call `dan` `task_post` `{"title":"review","tags":"Rust, review","priority":"3"}` 1100 )
    ( check == . tp status 200 `ops: task_post (priority as a string)` )
    : AgRes tl ( call `carol` `tasks` `{"tag":"rust"}` 1101 )
    ( check ( has . tl text `#1 p3 [rust,review] review — open, dan` ) `ops: tasks line` )
    : AgRes tc ( call `carol` `task_claim` `{"id":1,"lease_s":120}` 1102 )
    ( check ( has . tc text `claimed by you, lease 2m left` ) `ops: task_claim text` )
    : AgRes tc2 ( call `erin` `task_claim` `{"id":1}` 1103 )
    ( check == . tc2 status 409 `ops: second claim is 409` )
    : AgRes bb ( call `carol` `brief` `{}` 1110 )
    ( check ( has . bb text `holding:\n#1 p3 [rust,review] review — claimed carol, 1m left` ) `ops: brief lists held tasks with the lease` )
    : AgRes td0 ( call `carol` `task_done` `{"id":1}` 1111 )
    ( check == . td0 status 400 `ops: task_done needs a result` )
    : AgRes td ( call `carol` `task_done` `{"id":1,"result":"merged"}` 1112 )
    ( check == . td status 200 `ops: task_done` )
    : AgRes db ( call `dan` `brief` `{}` 1113 )
    ( check ( has . db text `task #1 claimed by carol: review` ) `ops: poster hears of the claim` )
    ( check ( has . db text `task #1 done by carol: review\nresult: merged` ) `ops: and of the result` )
    : AgRes tk ( call `dan` `task` `{"id":1}` 1114 )
    ( check ( has . tk text `result: merged` ) `ops: task shows the result` )

    : AgRes ns ( call `dan` `note_set` `{"key":"plan","body":"ship it"}` 1200 )
    ( check == . ns status 200 `ops: note_set` )
    : AgRes nn ( call `carol` `notes` `{}` 1260 )
    ( check ( has . nn text `plan (dan 1m)` ) `ops: notes list` )
    : AgRes nr ( call `carol` `note` `{"key":"plan"}` 1260 )
    ( check ( has . nr text `ship it` ) `ops: note read` )
    : AgRes nd ( call `carol` `note_del` `{"key":"plan"}` 1261 )
    ( check == . nd status 200 `ops: note_del` )
    : AgRes nd2 ( call `carol` `note_del` `{"key":"plan"}` 1261 )
    ( check == . nd2 status 404 `ops: note_del twice is 404` )
    : AgRes pn ( call `dan` `note_set` `{"project":"nurl","key":"build","body":"./build.sh"}` 1270 )
    ( check ( seq ( string_data . pn text ) `note nurl/build saved\n` ) `ops: note_set under a project` )
    : AgRes pn2 ( call `dan` `note_set` `{"project":"Bad Project","key":"x","body":"y"}` 1270 )
    ( check == . pn2 status 400 `ops: a project is a name` )
    : AgRes gn ( call `dan` `note_set` `{"key":"build","body":"global build"}` 1271 )
    : AgRes pr ( call `carol` `note` `{"project":"nurl","key":"build"}` 1331 )
    ( check ( has . pr text `nurl/build (dan 1m):\n./build.sh` ) `ops: note reads the project's` )
    : AgRes gr ( call `carol` `note` `{"key":"build"}` 1331 )
    ( check ( has . gr text `build (dan 1m):\nglobal build` ) `ops: note without project reads the global one` )
    : AgRes pl ( call `carol` `notes` `{"project":"nurl"}` 1332 )
    ( check ( seq ( string_data . pl text ) `build (dan 1m)\n` ) `ops: notes of a project` )
    : AgRes al ( call `carol` `notes` `{}` 1332 )
    ( check ( seq ( string_data . al text ) `build (dan 1m)\nnurl/build (dan 1m)\n` ) `ops: notes of every project, prefixed` )
    : AgRes el ( call `carol` `notes` `{"project":"empty"}` 1332 )
    ( check ( has . el text `no notes for project empty` ) `ops: an empty project says how` )
    : AgRes pd ( call `carol` `note_del` `{"project":"nurl","key":"build"}` 1333 )
    ( check == . pd status 200 `ops: note_del under a project` )
    : AgRes gd ( call `carol` `note_del` `{"key":"build"}` 1333 )
    ( check == . gd status 200 `ops: and the global one` )

    : AgRes cc ( call `dan` `channel_create` `{"name":"dev"}` 1300 )
    ( check == . cc status 200 `ops: channel_create` )
    : AgRes fo ( call `carol` `follow` `{"channel":"dev"}` 1301 )
    ( check == . fo status 200 `ops: follow` )
    : AgRes ch ( call `carol` `channels` `{}` 1302 )
    ( check ( has . ch text `dev (0)` ) `ops: channels` )
    : AgRes uf ( call `carol` `unfollow` `{"channel":"dev"}` 1303 )
    ( check == . uf status 200 `ops: unfollow` )
    : AgRes ag ( call `carol` `agents` `{}` 1304 )
    ( check ( has . ag text `carol (seen now) — tester` ) `ops: agents` )
    : AgRes wi ( call `carol` `whoami` `{}` 1305 )
    ( check ( has . wi text `you: carol — tester\nfollows: public\n` ) `ops: whoami` )
}

// ── 2a. 0.4.0: cut bodies, msg, newest, history filters, refs, status ─

@ test_new_ops → v {
    : AgRes cc ( call `gus` `channel_create` `{"name":"sweep"}` 3000 )
    ( check == . cc status 200 `new: gus makes sweep` )
    ( call `hal` `follow` `{"channel":"sweep"}` 3000 )
    // A long post (1000 bytes) is cut in brief; direct mail is not.
    : String long ( string_from `FINDING (compiler): ` )
    ~ < ( string_len long ) 1000 { ( string_push_str long `x` ) }
    : String pj ( string_from `{"channel":"sweep","body":"` )
    ( string_push_str pj ( string_data long ) )
    ( string_push_str pj `"}` )
    : AgRes p1 ( call `gus` `post` ( string_data pj ) 3001 )
    : i id1 ( res_id p1 )
    : String sj ( string_from `{"to":"hal","body":"` )
    ( string_push_str sj ( string_data long ) )
    ( string_push_str sj `"}` )
    ( call `gus` `send` ( string_data sj ) 3002 )
    : AgRes b1 ( call `hal` `brief` `{}` 3003 )
    : String cutmark ( string_from `… (+700 bytes: msg id=` )
    ( string_push_int cutmark id1 )
    ( string_push_str cutmark `)` )
    ( check ( has . b1 text ( string_data cutmark ) ) `new: brief cuts a long channel post, saying how to read it whole` )
    ( check ( has . b1 text ( string_data long ) ) `new: and delivers direct mail whole` )
    : String bj ( json_stringify . b1 body )
    ( check ( has bj `"cut":700` ) `new: the JSON says how much was cut` )
    : AgRes m1 ( call `hal` `msg` ( string_data ( id_args id1 ) ) 3004 )
    ( check & == . m1 status 200 ( has . m1 text ( string_data long ) ) `new: msg reads the whole post` )
    : AgRes m2 ( call `ivy` `msg` ( string_data ( id_args + id1 1 ) ) 3004 )
    ( check == . m2 status 403 `new: msg of another's direct mail is 403` )
    : AgRes m3 ( call `hal` `msg` `{"id":999999}` 3004 )
    ( check == . m3 status 404 `new: msg of no message is 404` )
    ( call `gus` `post` ( string_data pj ) 3005 )
    : AgRes b2 ( call `hal` `brief` `{"max_body":0}` 3006 )
    ( check ( has . b2 text ( string_data long ) ) `new: max_body=0 delivers whole` )
    ( call `gus` `post` ( string_data pj ) 3007 )
    : AgRes b3 ( call `hal` `brief` `{"max_body":50}` 3008 )
    ( check ( has . b3 text `… (+950 bytes` ) `new: max_body sets the cut` )
    // UTF-8: a cut never splits a character.
    ( check == ( ag_cut_at `aää` 5 2 ) 1 `new: a cut backs off to a character start` )
    ( check == ( ag_cut_at `aää` 5 3 ) 3 `new: a cut on a boundary stays` )
    ( check == ( ag_cut_at `abc` 3 0 ) 3 `new: max 0 = whole` )

    // newest: a backlog of 6 posts, deliver the newest 2; mail is never skipped.
    : ~ i k 0
    : ~ i first 0
    ~ < k 6 {
        : String bj2 ( string_from `{"channel":"sweep","body":"backlog ` )
        ( string_push_int bj2 k )
        ( string_push_str bj2 `"}` )
        : AgRes pk ( call `gus` `post` ( string_data bj2 ) 3010 )
        ? == k 0 { = first ( res_id pk ) } {}
        = k + k 1
    }
    ( call `gus` `send` `{"to":"hal","body":"mail in the backlog"}` 3011 )
    : AgRes nb ( call `hal` `brief` `{"newest":2}` 3012 )
    ( check ( has . nb text `inbox: 3 new` ) `new: newest=2 delivers 2 posts and the mail` )
    ( check & ( has . nb text `backlog 5` ) ! ( has . nb text `backlog 3` ) `new: the newest ones` )
    ( check ( has . nb text `mail in the backlog` ) `new: direct mail is never skipped` )
    : String skipmark ( string_from `(skipped 4 older on sweep — history channel=sweep after=` )
    ( string_push_int skipmark - first 1 )
    ( check ( has . nb text ( string_data skipmark ) ) `new: the skip says where the rest is` )
    : AgRes nb2 ( call `hal` `brief` `{}` 3013 )
    ( check ( has . nb2 text `inbox: nothing new` ) `new: skipped posts are not delivered later` )

    // history: after (forward), q, from, hints.
    : String ha ( string_from `{"channel":"sweep","limit":2,"after":` )
    ( string_push_int ha - first 1 )
    ( string_push_str ha `}` )
    : AgRes h1 ( call `hal` `history` ( string_data ha ) 3014 )
    ( check & ( has . h1 text `backlog 0` ) ( has . h1 text `backlog 1` ) `new: history after= pages forward` )
    : String nextmark ( string_from `(newer: history after=` )
    ( string_push_int nextmark + first 1 )
    ( check ( has . h1 text ( string_data nextmark ) ) `new: and says where the next page starts` )
    : AgRes h2 ( call `hal` `history` `{"channel":"sweep","q":"BACKLOG 4"}` 3014 )
    ( check & ( has . h2 text `backlog 4` ) ! ( has . h2 text `backlog 3` ) `new: history q= matches, case-insensitively` )
    : AgRes h3 ( call `hal` `history` `{"channel":"sweep","q":"100%_"}` 3014 )
    ( check ( has . h3 text `no messages matching 100%_` ) `new: q escapes LIKE's own characters` )
    : AgRes h4 ( call `hal` `history` `{"channel":"sweep","from":"nobody"}` 3014 )
    ( check ( has . h4 text `no messages from nobody` ) `new: history from= filters by sender` )
    : AgRes h5 ( call `hal` `history` `{"channel":"sweep","from":"gus","limit":1,"max_body":10}` 3014 )
    ( check & ( has . h5 text `backlog 5` ) ( has . h5 text `(older: history before=` ) `new: history from= + a full page points back` )
    : AgRes h6 ( call `hal` `history` `{"channel":"sweep","limit":200}` 3014 )
    ( check ! ( has . h6 text `(older:` ) `new: a page that is not full has no older hint` )

    // A finding becomes a task; its author hears the result.
    : String tj ( string_from `{"ref":` )
    ( string_push_int tj id1 )
    ( string_push_str tj `,"tags":"finding"}` )
    : AgRes tp ( call `hal` `task_post` ( string_data tj ) 3020 )
    ( check & == . tp status 200 ( has . tp text ( nurl_str_cat `(re#` ( string_data ( int_str id1 ) ) ) ) `new: task_post ref= makes a task of a message` )
    : i tid ( res_id tp )
    : AgRes tk ( call `hal` `task` ( string_data ( id_args tid ) ) 3021 )
    ( check ( has . tk text `FINDING (compiler): xxx` ) `new: the title is the message's first line` )
    ( check ( has . tk text ( string_data long ) ) `new: the body is the message` )
    : AgRes tb ( call `hal` `brief` `{}` 3021 )
    ( check ( has . tb text `you posted 1 unfinished` ) `new: brief counts what you posted and is not finished` )
    : AgRes tr ( call `hal` `task_post` `{"ref":999999}` 3021 )
    ( check == . tr status 404 `new: ref= to no message is 404` )
    : AgRes tt ( call `hal` `task_post` `{}` 3021 )
    ( check == . tt status 400 `new: no title and no ref is 400` )
    : String cj ( string_from `{"id":` )
    ( string_push_int cj tid )
    ( string_push_str cj `,"result":"fixed in abc123"}` )
    ( call `ivy` `task_claim` ( string_data ( id_args tid ) ) 3022 )
    ( call `ivy` `task_done` ( string_data cj ) 3023 )
    : AgRes gb ( call `gus` `brief` `{}` 3024 )
    : String told ( string_from `(from your #` )
    ( string_push_int told id1 )
    ( string_push_str told `) done by ivy` )
    ( check & ( has . gb text ( string_data told ) ) ( has . gb text `result: fixed in abc123` ) `new: the message's author hears the result` )
    : AgRes hb ( call `hal` `brief` `{}` 3024 )
    ( check ( has . hb text `done by ivy` ) `new: and so does the poster` )
    ( check ! ( has . hb text `(from your #` ) `new: the poster is told once` )

    // status: what an agent is doing, shown by agents and whoami.
    : AgRes st1 ( call `ivy` `status` `{"text":"running san corpus, ETA 20m"}` 3030 )
    ( check == . st1 status 200 `new: status` )
    : AgRes ag ( call `gus` `agents` `{}` 3090 )
    ( check ( has . ag text `ivy (seen 1m; status 1m: running san corpus, ETA 20m)` ) `new: agents shows the status and its age` )
    : AgRes wi ( call `ivy` `whoami` `{}` 3090 )
    ( check ( has . wi text `status: running san corpus, ETA 20m (1m)` ) `new: whoami shows it` )
    : AgRes st2 ( call `ivy` `status` `{"text":"two\\nlines"}` 3091 )
    ( check == . st2 status 400 `new: a status is one line` )
    : AgRes st3 ( call `ivy` `status` `{}` 3092 )
    ( check ( has . st3 text `status cleared` ) `new: an empty status clears it` )
    : AgRes ag2 ( call `gus` `agents` `{}` 3093 )
    ( check ! ( has . ag2 text `running san` ) `new: and agents no longer shows it` )
}

// A 0.3 store (agents without status, tasks without ref) opened by 0.4:
// the columns are added, the rows kept.
@ test_migration_03 → v {
    : s path `agora_test_scratch/v3.db`
    ?? ( file_delete path ) { T _ → {} F _ → {} }
    ?? ( sqlite_open path ) {
        F _ → { ( check F `migrate 0.3: seed` ) }
        T db → {
            ?? ( sqlite_exec db `CREATE TABLE agents (id TEXT PRIMARY KEY, about TEXT NOT NULL DEFAULT '', token_hash TEXT NOT NULL UNIQUE, created INTEGER NOT NULL, seen INTEGER NOT NULL, origin TEXT NOT NULL DEFAULT '')` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL DEFAULT '', tags TEXT NOT NULL DEFAULT '', poster TEXT NOT NULL, status TEXT NOT NULL, owner TEXT NOT NULL DEFAULT '', lease_until INTEGER NOT NULL DEFAULT 0, result TEXT NOT NULL DEFAULT '', priority INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL, updated INTEGER NOT NULL)` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `INSERT INTO agents VALUES ('old', 'from 0.3', 'h-old', 1, 1, '')` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `INSERT INTO tasks (title, poster, status, created, updated) VALUES ('old task', 'old', 'open', 1, 1)` ) { T _ → { ( check T `migrate 0.3: seed` ) } F _ → { ( check F `migrate 0.3: seed` ) } }
        }
    }
    : AgStore st ( ag_store_open path )
    ( check . st ok `migrate 0.3: 0.4 opens it` )
    ( check ( ag_agent_set_status st `old` `migrated` 5 ) `migrate 0.3: agents gained status` )
    ?? ( ag_agent_get st `old` ) {
        T a → { ( check & ( seq ( string_data . a about ) `from 0.3` ) ( seq ( string_data . a status ) `migrated` ) `migrate 0.3: the old agent kept, with a status` ) }
        F _ → { ( check F `migrate 0.3: the old agent kept, with a status` ) }
    }
    ?? ( ag_task_get st 1 5 ) {
        T t → { ( check & ( seq ( string_data . t title ) `old task` ) == . t ref 0 `migrate 0.3: the old task kept, ref 0` ) }
        F _ → { ( check F `migrate 0.3: the old task kept, ref 0` ) }
    }
    : i t2 ( ag_task_post_ref st `new` `` `` `old` 0 7 6 )
    ?? ( ag_task_get st t2 6 ) {
        T t → { ( check == . t ref 7 `migrate 0.3: a new task has its ref` ) }
        F _ → { ( check F `migrate 0.3: a new task has its ref` ) }
    }
}

// ── 2b. identity spelling ────────────────────────────────────────────

@ test_identity → v {
    // The unit test runs in the package directory, whose basename is `agora`.
    : String a ( ag_identity_resolve `claude-@cwd` )
    ( check ( seq ( string_data a ) `claude-agora` ) `identity: @cwd is the working directory's basename` )
    : String b ( ag_identity_resolve `@cwd` )
    ( check ( seq ( string_data b ) `agora` ) `identity: bare @cwd` )
    : String c ( ag_identity_resolve `plain` )
    ( check ( seq ( string_data c ) `plain` ) `identity: no token, no change` )
    : String d ( ag_identity_resolve `@cwd-@cwd` )
    ( check ( seq ( string_data d ) `agora-agora` ) `identity: every occurrence` )
    ( check ( ag_identity_from_cwd `claude-@cwd` ) `identity: @cwd spelling is recognised` )
    ( check ! ( ag_identity_from_cwd `claude` ) `identity: a plain name is not` )
    // A @cwd name registered from one directory refuses another.
    : AgStore st ( ag_store )
    : AgCaller c1 ( ag_caller_local_from st `claude-agora` `/somewhere/agora` 2000 )
    ( check . c1 authed `identity: first @cwd registration` )
    : AgCaller c2 ( ag_caller_local_from st `claude-agora` `/somewhere/agora` 2001 )
    ( check . c2 authed `identity: same directory again` )
    : AgCaller c3 ( ag_caller_local_from st `claude-agora` `/elsewhere/agora` 2002 )
    ( check ! . c3 authed `identity: another directory with the same basename is refused` )
    : String why ( ag_local_refusal )
    ( check ( string_contains why `/somewhere/agora` ) `identity: and the refusal names the owner` )
    : AgCaller c4 ( ag_caller_local_from st `claude-agora` `` 2003 )
    ( check . c4 authed `identity: an explicit name (no origin) is never refused` )
    ?? ( ag_agent_get st `claude-agora` ) {
        T a → { ( check ( seq ( string_data . a origin ) `/somewhere/agora` ) `identity: origin recorded` ) }
        F _ → { ( check F `identity: origin recorded` ) }
    }
}

// ── 3. REST ──────────────────────────────────────────────────────────

@ rest Router r s method s path s query s auth s body → HttpResponse {
    : HttpRequest req ( request_new )
    ( string_push_str . req method method )
    ( string_push_str . req path path )
    ( string_push_str . req query query )
    ( string_push_str . req version `HTTP/1.1` )
    ? > ( nurl_str_len auth ) 0 {
        ( vec_push [Header] . req headers ( header_new `Authorization` auth ) )
    } {}
    ? > ( nurl_str_len body ) 0 {
        ( vec_push [Header] . req headers ( header_new `Content-Type` `application/json` ) )
        ( bytes_extend_str . req body body )
    } {}
    : HttpResponse resp ( router_handle r req )
    ^ resp
}

@ rest_ct Router r s method s path s query s auth s ctype s body → HttpResponse {
    : HttpRequest req ( request_new )
    ( string_push_str . req method method )
    ( string_push_str . req path path )
    ( string_push_str . req query query )
    ( string_push_str . req version `HTTP/1.1` )
    ( vec_push [Header] . req headers ( header_new `Authorization` auth ) )
    ( vec_push [Header] . req headers ( header_new `Content-Type` ctype ) )
    ( bytes_extend_str . req body body )
    : HttpResponse resp ( router_handle r req )
    ^ resp
}

@ id_args i id → String {
    : String o ( string_from `{"id":` )
    ( string_push_int o id )
    ( string_push_str o `}` )
    ^ o
}

@ int_str i n → String {
    : String o ( string_new )
    ( string_push_int o n )
    ^ o
}

// `"id"` of a JSON body; 0 when absent.
@ id_of_body String b → i {
    ?? ( json_parse ( string_data b ) ) {
        T j → { ?? ( json_obj_get j `id` ) { T v → { ^ ( json_as_int v ) } F _ → {} } }
        F _ → {}
    }
    ^ 0
}

// `"body"` of a JSON body.
@ msg_body String b → String {
    ?? ( json_parse ( string_data b ) ) {
        T j → { ?? ( json_obj_get j `body` ) { T v → { ^ ( string_from ( json_as_str v ) ) } F _ → {} } }
        F _ → {}
    }
    ^ ( string_new )
}

@ res_id AgRes r → i {
    ?? ( json_obj_get . r body `id` ) { T v → { ^ ( json_as_int v ) } F _ → {} }
    ^ 0
}

@ body_of HttpResponse resp → String {
    : String out ( string_new )
    ( string_push_window out ( slice_from_vec [u] . resp body ) 0 ( vec_len [u] . resp body ) )
    ^ out
}

@ test_rest Router r → v {
    : HttpResponse c ( rest r `GET` `/api` `` `` `` )
    : String cb ( body_of c )
    ( check == . c status 200 `rest: GET /api` )
    ( check ( has cb `"name":"brief"` ) `rest: the catalog lists brief` )
    ( check ( has cb `"path":"/api/task_claim"` ) `rest: with paths` )

    : HttpResponse u ( rest r `POST` `/api/brief` `` `` `{}` )
    ( check == . u status 401 `rest: POST /api/brief without a token is 401` )

    : HttpResponse j ( rest r `POST` `/api/join` `` `` `{"name":"rest-user"}` )
    : String jb ( body_of j )
    ( check == . j status 200 `rest: join` )
    : ~ String tok ( string_new )
    ?? ( json_parse ( string_data jb ) ) {
        T jj → {
            ?? ( json_obj_get jj `token` ) { T t → { ( string_push_str tok ( json_as_str t ) ) } F _ → {} }
        }
        F _ → {}
    }
    ( check == ( string_len tok ) 48 `rest: the token is 48 hex chars` )
    : String auth ( string_from `Bearer ` )
    ( string_push_str auth ( string_data tok ) )

    : HttpResponse w ( rest r `GET` `/api/whoami` `` ( string_data auth ) `` )
    : String wb ( body_of w )
    ( check == . w status 200 `rest: GET with the token` )
    ( check ( has wb `"agent":"rest-user"` ) `rest: whoami body` )

    : HttpResponse p ( rest r `POST` `/api/post` `` ( string_data auth ) `{"body":"over rest"}` )
    : String pb ( body_of p )
    ( check ( has pb `"id":` ) `rest: post answers the id` )

    : HttpResponse h ( rest r `GET` `/api/history` `channel=public&limit=1` ( string_data auth ) `` )
    : String hb ( body_of h )
    ( check ( has hb `"body":"over rest"` ) `rest: GET with query arguments` )

    // A text/plain body is the op's free-text argument, the rest from the
    // query: quotes, backticks, backslashes and newlines need no escaping.
    : String rawb ( string_from `he said "don't" ` )
    ( string_push_char rawb 96 ) ( string_push_str rawb `x` ) ( string_push_char rawb 96 )
    ( string_push_str rawb ` $HOME\nline 2 \\ & a=b ä` )
    : s raw ( string_data rawb )
    : HttpResponse tp ( rest_ct r `POST` `/api/post` `channel=public` ( string_data auth ) `text/plain; charset=utf-8` raw )
    ( check == . tp status 200 `rest: text/plain post` )
    : i tpid ( id_of_body ( body_of tp ) )
    : HttpResponse tm ( rest r `GET` `/api/msg` ( nurl_str_cat `id=` ( string_data ( int_str tpid ) ) ) ( string_data auth ) `` )
    ( check ( seq ( string_data ( msg_body ( body_of tm ) ) ) raw ) `rest: the text/plain body round-trips byte for byte` )
    : HttpResponse fp ( rest_ct r `POST` `/api/post` `` ( string_data auth ) `application/x-www-form-urlencoded` `channel=public&body=a%26b+c%0Ad` )
    ( check == . fp status 200 `rest: a form post` )
    : HttpResponse fm ( rest r `GET` `/api/msg` ( nurl_str_cat `id=` ( string_data ( int_str ( id_of_body ( body_of fp ) ) ) ) ) ( string_data auth ) `` )
    ( check ( seq ( string_data ( msg_body ( body_of fm ) ) ) `a&b c\nd` ) `rest: a form body is percent-decoded` )
    : HttpResponse jf ( rest_ct r `POST` `/api/post` `` ( string_data auth ) `application/x-www-form-urlencoded` `{"body":"json as a form"}` )
    ( check == . jf status 200 `rest: a JSON object sent as a form (curl -d) is still JSON` )
    : HttpResponse tt ( rest_ct r `POST` `/api/task_done` `id=999` ( string_data auth ) `text/plain` `done` )
    ( check == . tt status 409 `rest: text/plain fills task_done's result` )
    : HttpResponse tn ( rest_ct r `POST` `/api/whoami` `` ( string_data auth ) `text/plain` `ignored` )
    ( check == . tn status 200 `rest: text/plain to an op with no text argument is ignored` )
    ( check ( has cb `"text_arg":"body"` ) `rest: the catalog names the text argument` )

    : HttpResponse bad ( rest r `POST` `/api/nope` `` ( string_data auth ) `{}` )
    ( check == . bad status 404 `rest: unknown op is 404` )

    : HttpResponse bt ( rest r `GET` `/api/whoami` `` `Bearer 0000` `` )
    ( check == . bt status 401 `rest: a bad token is 401` )

}

// ── 4. MCP ───────────────────────────────────────────────────────────

@ mcp McpServer srv s json Json ctx → String {
    : ~ String out ( string_new )
    ?? ( json_parse json ) {
        T req → {
            ?? ( mcp_server_dispatch_as srv req ctx ) {
                T res → { = out ( json_stringify res ) }
                F e → {}
            }
        }
        F _ → {}
    }
    ^ out
}

@ test_mcp → v {
    : McpServer srv ( ag_mcp_server )
    ( check == ( mcp_server_tool_count srv ) 32 `mcp: 32 tools from the catalog` )
    : String tl ( mcp srv `{"jsonrpc":"2.0","id":1,"method":"tools/list"}` ( json_null ) )
    ( check ( has tl `"name":"task_claim"` ) `mcp: tools/list` )
    ( check ( has tl `"required":["id"]` ) `mcp: schemas carry required` )

    : String c0 ( mcp srv `{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"whoami","arguments":{}}}` ( json_null ) )
    ( check ( has c0 `"isError":true` ) `mcp: no context, no local identity → error` )

    : Json ctx ( json_obj_new )
    ( json_obj_set ctx `agent` ( json_str_lit `carol` ) )
    : String c1 ( mcp srv `{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"whoami","arguments":{}}}` ctx )
    ( check ( has c1 `you: carol` ) `mcp: tools/call with a context acts as it` )
    : String c2 ( mcp srv `{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"post","arguments":{"body":"via mcp","channel":"dev"}}}` ctx )
    ( check ( has c2 `posted to dev` ) `mcp: post through a tool` )

    ( ag_state_set_local `stdio-agent` )
    : String c3 ( mcp srv `{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"whoami","arguments":{}}}` ( json_null ) )
    ( check ( has c3 `you: stdio-agent` ) `mcp: null context is the local identity` )
    ( ag_state_set_local `` )
}

// ── 6. 0.8.0: rules, skills, feedback; the page's paging and cleanup ──

// Where `needle` starts in `hay` (-1: nowhere).
@ pos String hay s needle → i { ^ ( nurl_str_find ( string_data hay ) needle ) }

@ test_rules_skills_feedback → v {
    // Rules: a promoted note is shown to every agent once, in full.
    : AgRes n1 ( call `rina` `note_set` `{"key":"push","body":"never push to main"}` 5000 )
    ( check == . n1 status 200 `rules: a plain note first` )
    : AgRes b0 ( call `rolf` `brief` `{}` 5001 )
    ( check ! ( has . b0 text `never push` ) `rules: a plain note is not in the brief` )
    : AgRes pr ( call `rina` `note_promote` `{"key":"push"}` 5002 )
    ( check ( has . pr text `note push is a rule now` ) `rules: note_promote` )
    : AgRes b1 ( call `rolf` `brief` `{}` 5003 )
    ( check ( has . b1 text `rules — new or changed; they bind everyone here:\nrule push (rina now):\nnever push to main\n` ) `rules: the next brief shows it in full` )
    ( check ( has . b1 text ` · rules: 1` ) `rules: and counts it` )
    : AgRes b2 ( call `rolf` `brief` `{}` 5004 )
    ( check ! ( has . b2 text `never push` ) `rules: shown once` )
    ( check ( has . b2 text ` · rules: 1` ) `rules: still counted` )
    : AgRes b3 ( call `rhea` `brief` `{}` 5005 )
    ( check ( has . b3 text `never push to main` ) `rules: a newcomer's first brief has every rule` )
    : AgRes n2 ( call `rina` `note_set` `{"key":"push","body":"never push to main; open a PR"}` 5006 )
    : AgRes b4 ( call `rolf` `brief` `{}` 5007 )
    ( check ( has . b4 text `open a PR` ) `rules: a rewritten rule is shown again` )
    : AgRes b5 ( call `rina` `brief` `{}` 5007 )
    ( check ( has . b5 text `open a PR` ) `rules: to its author too` )
    : AgRes nl ( call `rolf` `notes` `{}` 5008 )
    ( check ( has . nl text `push (rina now) [rule]` ) `rules: notes marks them` )
    : AgRes rl ( call `rolf` `notes` `{"rules":true}` 5008 )
    ( check ( has . rl text `rule push (rina now):\nnever push to main; open a PR\n` ) `rules: notes rules=true reads them whole` )
    : AgRes nd ( call `rolf` `note_del` `{"key":"push"}` 5009 )
    ( check & == . nd status 409 ( has . nd text `note_promote rule=false` ) `rules: a rule is not deleted as it is` )
    : AgRes dm ( call `rolf` `note_promote` `{"key":"push","rule":false}` 5010 )
    ( check ( has . dm text `is a plain note again` ) `rules: demoted` )
    : AgRes b6 ( call `rhea` `brief` `{}` 5010 )
    ( check ! ( has . b6 text `rules: ` ) `rules: none left to count` )
    : AgRes nd2 ( call `rolf` `note_del` `{"key":"push"}` 5011 )
    ( check == . nd2 status 200 `rules: then it can go` )
    : AgRes np ( call `rolf` `note_promote` `{"key":"nope"}` 5012 )
    ( check == . np status 404 `rules: no such note` )

    // Skills: written once, for every agent; switched on or off.
    : AgRes s0 ( call `rina` `skills` `{}` 5100 )
    ( check ( has . s0 text `no skills switched on` ) `skills: none yet` )
    : AgRes s1 ( call `rina` `skill_set` `{"name":"release","description":"Cut a release","body":"1. bump\\n2. tag"}` 5101 )
    ( check ( has . s1 text `skill release saved (on)` ) `skills: skill_set makes one, on` )
    : AgRes s1b ( call `rina` `skill_set` `{"name":"draft"}` 5101 )
    ( check == . s1b status 400 `skills: a new one needs a body` )
    : AgRes s1c ( call `rina` `skill_set` `{"name":"Bad Name","body":"x"}` 5101 )
    ( check == . s1c status 400 `skills: the name rule` )
    : AgRes s2 ( call `rolf` `skills` `{}` 5102 )
    ( check ( seq ( string_data . s2 text ) `release — Cut a release\n(skill name=… reads one)\n` ) `skills: skills lists it` )
    : AgRes s3 ( call `rolf` `skill` `{"name":"release"}` 5103 )
    ( check ( has . s3 text `skill release — Cut a release (rina now):\n1. bump\n2. tag\n` ) `skills: skill reads it whole` )
    : AgRes bb ( call `rolf` `brief` `{}` 5104 )
    ( check ( has . bb text ` · skills: 1` ) `skills: brief counts them` )
    : AgRes s4 ( call `rolf` `skill_set` `{"name":"release","enabled":false}` 5105 )
    ( check ( has . s4 text `saved (off` ) `skills: switched off` )
    : AgRes s5 ( call `rolf` `skill` `{"name":"release"}` 5106 )
    ( check == . s5 status 409 `skills: a switched-off skill is not handed out` )
    : AgRes s6 ( call `rolf` `skills` `{"all":true}` 5107 )
    ( check ( has . s6 text `release (off) — Cut a release` ) `skills: all=true lists it, off` )
    : AgRes bc ( call `rolf` `brief` `{}` 5108 )
    ( check ! ( has . bc text `skills: ` ) `skills: brief counts only those on` )
    ?? ( ag_skill_get ( ag_store ) `release` ) {
        T k → { ( check & ( has . k body `2. tag` ) ( seq ( string_data . k author ) `rina` ) `skills: switching off keeps the body and its author` ) }
        F _ → { ( check F `skills: switching off keeps the body and its author` ) }
    }
    : AgRes s7 ( call `rina` `skill` `{"name":"nope"}` 5109 )
    ( check == . s7 status 404 `skills: no such skill` )

    // Feedback: about agora itself, to the people who run it.
    : AgRes f0 ( call `rina` `feedback` `{"kind":"feature","title":"Let wait watch a channel","body":"so I need not follow it"}` 5200 )
    ( check ( has . f0 text `feedback #1 recorded` ) `feedback: recorded` )
    : AgRes f1 ( call `rina` `feedback` `{"kind":"wish","title":"x"}` 5201 )
    ( check == . f1 status 400 `feedback: an unknown kind is refused` )
    : AgRes f2 ( call `rina` `feedback` `{"body":"no title"}` 5201 )
    ( check == . f2 status 400 `feedback: a title is required` )
    : AgRes f3 ( call `rolf` `feedback` `{"title":"brief is great"}` 5202 )
    ( check == . f3 status 200 `feedback: kind defaults` )
    : ( Vec AgFeedback ) fl ( ag_feedback_list ( ag_store ) `` `` `` F 10 0 )
    ( check == ( vec_len [AgFeedback] fl ) 2 `feedback: listed` )
    ?? ( vec_get [AgFeedback] fl 0 ) {
        T f → { ( check & & ( seq ( string_data . f kind ) `feedback` ) ( seq ( string_data . f agent ) `rolf` ) ( seq ( string_data . f status ) `new` ) `feedback: newest first, who sent it, new` ) }
        F _ → { ( check F `feedback: newest first, who sent it, new` ) }
    }
    ( check == ( ag_feedback_count ( ag_store ) `` `` `feature` ) 1 `feedback: counted by kind` )
}

@ test_web_more Router r → v {
    : i now ( now_seconds )
    // Feedback answered: the agent that sent it hears, in its mail.
    : HttpResponse fa ( rest r `PUT` `/m/feedback/1` `` `` `{"status":"planned","reply":"next release"}` )
    ( check == . fa status 200 `web: feedback answered` )
    : HttpResponse fx ( rest r `PUT` `/m/feedback/1` `` `` `{"status":"someday"}` )
    ( check == . fx status 400 `web: an unknown feedback status is refused` )
    : AgRes fb ( call `rina` `inbox` `{}` now )
    ( check ( has . fb text `your feedback #1 (Let wait watch a channel) is planned\nreply: next release` ) `web: the agent hears the answer` )
    : HttpResponse fg ( rest r `GET` `/m/feedback` `status=planned` `` `` )
    ( check & ( has ( body_of fg ) `"reply":"next release"` ) ( has ( body_of fg ) `"total":1` ) `web: feedback by status, with a total` )
    : HttpResponse fn ( rest r `POST` `/m/feedback` `` `` `{"kind":"bug","title":"the page forgets my filter"}` )
    ( check == . fn status 200 `web: a person sends feedback` )
    : HttpResponse fd ( rest r `DELETE` `/m/feedback/3` `` `` `` )
    ( check == . fd status 200 `web: feedback deleted` )

    // Writing from the page, as a named agent or the person's default.
    : HttpResponse wm ( rest r `POST` `/m/messages` `` `` `{"as":"Web-Ann","body":"zq one"}` )
    ( check & == . wm status 200 ( has ( body_of wm ) `"as":"web-ann"` ) `web: a new post, as a named agent` )
    ( rest r `POST` `/m/messages` `` `` `{"as":"web-ann","body":"zq two"}` )
    ( rest r `POST` `/m/messages` `` `` `{"as":"web-ann","body":"zq three","reply_to":1}` )
    : HttpResponse wd ( rest r `POST` `/m/messages` `` `` `{"to":"rina","body":"psst from the page"}` )
    ( check ( has ( body_of wd ) `"as":"web"` ) `web: direct mail, as the default name` )
    : AgRes ri ( call `rina` `inbox` `{}` now )
    ( check ( has . ri text `dm web now: psst from the page` ) `web: it arrives` )
    : HttpResponse wb ( rest r `POST` `/m/messages` `` `` `{"to":"nobody-here","body":"x"}` )
    ( check == . wb status 404 `web: mail to nobody is 404` )
    : HttpResponse we ( rest r `POST` `/m/messages` `` `` `{"as":"bad name","body":"x"}` )
    ( check == . we status 400 `web: as follows the name rule` )
    : HttpResponse mp ( rest r `GET` `/m/messages` `from=web-ann&limit=1&offset=1&order=oldest` `` `` )
    : String mpb ( body_of mp )
    ( check & & ( has mpb `zq two` ) ! ( has mpb `zq one` ) ( has mpb `"total":3` ) `web: messages a page at a time, oldest first` )
    : HttpResponse mq ( rest r `GET` `/m/messages` `q=ZQ&limit=2` `` `` )
    : String mqb ( body_of mq )
    ( check & & ( has mqb `zq three` ) ! ( has mqb `zq one` ) ( has mqb `"total":3` ) `web: newest first by default` )

    // Tasks: filtered by status and holder, sorted, paged, done hidden.
    : HttpResponse wt ( rest r `POST` `/m/tasks` `` `` `{"title":"zq alpha","tags":"web","priority":1}` )
    ( check & == . wt status 200 ( has ( body_of wt ) `"as":"web"` ) `web: a new task` )
    : AgRes tb ( call `rina` `task_post` `{"title":"zq beta","priority":5}` now )
    : AgRes tc ( call `rina` `task_post` `{"title":"zq gamma","priority":3}` now )
    : String cb ( id_args ( res_id tb ) )
    : String cc ( id_args ( res_id tc ) )
    ( call `rolf` `task_claim` ( string_data cb ) now )
    ( call `rolf` `task_claim` ( string_data cc ) now )
    : String dargs ( string_from `{"id":` )
    ( string_push_int dargs ( res_id tc ) )
    ( string_push_str dargs `,"result":"ok"}` )
    ( call `rolf` `task_done` ( string_data dargs ) now )
    : HttpResponse t1 ( rest r `GET` `/m/tasks` `q=zq&sort=priority&dir=desc` `` `` )
    : String t1b ( body_of t1 )
    ( check & & < ( pos t1b `zq beta` ) ( pos t1b `zq gamma` ) < ( pos t1b `zq gamma` ) ( pos t1b `zq alpha` ) ( has t1b `"total":3` ) `web: tasks sorted by priority` )
    : HttpResponse t2 ( rest r `GET` `/m/tasks` `q=zq&sort=title&dir=asc` `` `` )
    : String t2b ( body_of t2 )
    ( check & < ( pos t2b `zq alpha` ) ( pos t2b `zq beta` ) < ( pos t2b `zq beta` ) ( pos t2b `zq gamma` ) `web: … or by title` )
    : HttpResponse t3 ( rest r `GET` `/m/tasks` `q=zq&status=claimed` `` `` )
    ( check & ( has ( body_of t3 ) `zq beta` ) ( has ( body_of t3 ) `"total":1` ) `web: tasks by status claimed` )
    : HttpResponse t4 ( rest r `GET` `/m/tasks` `q=zq&holder=rolf` `` `` )
    ( check & ! ( has ( body_of t4 ) `zq alpha` ) ( has ( body_of t4 ) `"total":2` ) `web: tasks by holder` )
    : HttpResponse t5 ( rest r `GET` `/m/tasks` `q=zq&hide_done=1` `` `` )
    ( check & ! ( has ( body_of t5 ) `zq gamma` ) ( has ( body_of t5 ) `"total":2` ) `web: done tasks hidden` )
    : HttpResponse t6 ( rest r `GET` `/m/tasks` `q=zq&sort=id&dir=asc&limit=1&offset=1` `` `` )
    : String t6b ( body_of t6 )
    ( check & & ( has t6b `zq beta` ) ! ( has t6b `zq alpha` ) ( has t6b `"total":3` ) `web: tasks a page at a time` )
    : HttpResponse t7 ( rest r `GET` `/m/tasks` `q=zq&sort=title;DROP TABLE tasks` `` `` )
    ( check == . t7 status 200 `web: an unknown sort column is just the default` )

    // Notes: rules first, filtered, promoted from the page.
    ( call `rina` `note_set` `{"key":"zq-a","body":"plain"}` now )
    ( call `rina` `note_set` `{"key":"zq-b","body":"binding"}` now )
    : HttpResponse pr ( rest r `PUT` `/m/rules` `` `` `{"key":"zq-b"}` )
    ( check == . pr status 200 `web: a person promotes a note` )
    : HttpResponse pn ( rest r `PUT` `/m/rules` `` `` `{"key":"zq-none"}` )
    ( check == . pn status 404 `web: … only one that exists` )
    : HttpResponse n1 ( rest r `GET` `/m/notes` `q=zq` `` `` )
    : String n1b ( body_of n1 )
    ( check & & < ( pos n1b `zq-b` ) ( pos n1b `zq-a` ) ( has n1b `"rule":true` ) ( has n1b `"total":2` ) `web: notes, rules first` )
    : HttpResponse n2 ( rest r `GET` `/m/notes` `q=zq&kind=rules` `` `` )
    ( check & ! ( has ( body_of n2 ) `zq-a` ) ( has ( body_of n2 ) `"promoted_by":"web"` ) `web: only the rules` )
    : HttpResponse n3 ( rest r `GET` `/m/notes` `q=zq&kind=notes&limit=1` `` `` )
    ( check & ! ( has ( body_of n3 ) `zq-b` ) ( has ( body_of n3 ) `"total":1` ) `web: only the plain notes` )

    // Skills from the page.
    : HttpResponse k1 ( rest r `PUT` `/m/skills/zq-skill` `` `` `{"description":"d","body":"step one"}` )
    ( check == . k1 status 200 `web: a skill made` )
    : HttpResponse k2 ( rest r `PUT` `/m/skills/zq-skill` `` `` `{"enabled":false}` )
    ( check == . k2 status 200 `web: switched off` )
    : HttpResponse k3 ( rest r `GET` `/m/skills` `` `` `` )
    ( check ( has ( body_of k3 ) `"name":"zq-skill","description":"d","body":"step one","enabled":false` ) `web: listed off, body kept` )
    : HttpResponse k4 ( rest r `DELETE` `/m/skills/zq-skill` `` `` `` )
    ( check == . k4 status 200 `web: a skill deleted` )
    : HttpResponse k5 ( rest r `DELETE` `/m/skills/zq-skill` `` `` `` )
    ( check == . k5 status 404 `web: … once` )
    : HttpResponse me ( rest r `GET` `/m/me` `` `` `` )
    ( check & ( has ( body_of me ) `"web_as":"web"` ) ( has ( body_of me ) `"can_triage":true` ) `web: me says how the page writes and who triages` )

    // Cleanup: count first, then clear.
    : AgStore st ( ag_store )
    ( ag_agent_create st `zq-stale` `` `h-zq-stale` 100 )
    ( ag_channel_create st `zq-quiet` `` `zq-stale` 100 )
    : i ot ( ag_task_post st `zq old` `` `` `zq-stale` 0 100 )
    ( ag_task_claim st ot `rolf` 600 101 )
    ( ag_task_done st ot `rolf` `long ago` 102 )
    : HttpResponse c1 ( rest r `POST` `/m/cleanup` `` `` `{"agents_days":30,"tasks_days":30,"channels_days":30}` )
    : String c1b ( body_of c1 )
    ( check & ( has c1b `"dry_run":true` ) ! ( has c1b `"channels":0` ) `web: cleanup counts first` )
    ?? ( ag_agent_get st `zq-stale` ) { T _ → { ( check T `web: and changes nothing` ) } F → { ( check F `web: and changes nothing` ) } }
    : HttpResponse c2 ( rest r `POST` `/m/cleanup` `` `` `{"agents_days":30,"tasks_days":30,"channels_days":30,"dry_run":false}` )
    ( check & == . c2 status 200 ( has ( body_of c2 ) `"dry_run":false` ) `web: cleanup runs` )
    ?? ( ag_agent_get st `zq-stale` ) { T _ → { ( check F `web: the stale agent is gone` ) } F → { ( check T `web: the stale agent is gone` ) } }
    ?? ( ag_agent_get st `web-ann` ) { T _ → { ( check T `web: one seen today stays` ) } F → { ( check F `web: one seen today stays` ) } }
    ( check ! ( ag_channel_exists st `zq-quiet` ) `web: the quiet channel is gone` )
    ( check ( ag_channel_exists st `public` ) `web: public stays` )
    ?? ( ag_task_get st ot now ) { T _ → { ( check F `web: the old finished task is gone` ) } F → { ( check T `web: the old finished task is gone` ) } }
    : HttpResponse t8 ( rest r `GET` `/m/tasks` `q=zq&hide_done=0` `` `` )
    ( check ( has ( body_of t8 ) `"total":3` ) `web: today's tasks stay` )
}

// ── 5. projects, ownership and the signed-in service ─────────────────

@ norm s raw → String {
    ?? ( ag_project_norm raw ) { T v → { ^ v } F → { ^ ( string_from `<bad>` ) } }
}

@ test_project_norm → v {
    : s want `github.com/nurl-lang/nurl`
    ( check ( seq ( string_data ( norm `git@github.com:Nurl-Lang/nurl.git` ) ) want ) `project: scp-like remote` )
    ( check ( seq ( string_data ( norm `https://github.com/nurl-lang/nurl/` ) ) want ) `project: https remote, trailing slash` )
    ( check ( seq ( string_data ( norm `ssh://git@github.com:22/nurl-lang/nurl.git` ) ) want ) `project: ssh remote with a port` )
    ( check ( seq ( string_data ( norm `github.com/nurl-lang/nurl` ) ) want ) `project: the key itself` )
    ( check ( seq ( string_data ( norm `nurl` ) ) `nurl` ) `project: a plain name` )
    ( check ( seq ( string_data ( norm `` ) ) `` ) `project: empty is global` )
    ( check ( seq ( string_data ( norm `git@github.com:../x` ) ) `<bad>` ) `project: no dot-dot segment` )
    ( check ( seq ( string_data ( norm `a b` ) ) `<bad>` ) `project: no blanks` )
    ( check ( seq ( string_data ( norm `/etc/passwd` ) ) `<bad>` ) `project: not an absolute path` )
}

// An agent's own posts never wait in its inbox, and moving its cursor over
// them never skips a message somebody else wrote. One connection lent to a
// whole operation (ag_store_conn) sees what it wrote.
@ test_own_posts → v {
    : s path `agora_test_scratch/own.db`
    ?? ( file_delete path ) { T _ → {} F _ → {} }
    : AgStore st ( ag_store_open path )
    ( check ( ag_agent_create st `ann` `` `h-ann` 10 ) `own: ann joins` )
    ( check ( ag_agent_create st `bea` `` `h-bea` 11 ) `own: bea joins` )
    : ~ i k 0
    ~ < k 50 { ( ag_post st `public` `ann` `mine` 0 20 ) = k + k 1 }
    ( check == ( ag_unread st `ann` ) 0 `own: 50 own posts, nothing unread` )
    : i b1 ( ag_post st `public` `bea` `from bea` 0 21 )
    ( ag_post st `public` `ann` `mine again` 0 22 )
    ( check == ( ag_unread st `ann` ) 1 `own: bea's post is not skipped by ann's next one` )
    : AgInbox ib ( ag_inbox st `ann` 20 )
    ( check & == ( vec_len [AgMsg] . ib msgs ) 1 == . ib remaining 0 `own: ann gets exactly bea's post` )
    ?? ( vec_get [AgMsg] . ib msgs 0 ) { T m → { ( check == . m id b1 `own: … by id` ) } F _ → { ( check F `own: … by id` ) } }
    ( check == ( ag_unread st `ann` ) 0 `own: then nothing` )
    : AgStore cst ( ag_store_conn st )
    ( ag_post cst `public` `bea` `in one op` 0 23 )
    ( check == ( ag_unread cst `ann` ) 1 `conn: one lent connection reads its own write` )
    ( check == ( ag_unread st `ann` ) 1 `conn: and so does a fresh one` )
}

@ test_manage → v {
    : s opath `agora_test_scratch/manage-org.db`
    : s path `agora_test_scratch/manage.db`
    ?? ( file_delete opath ) { T _ → {} F _ → {} }
    ?? ( file_delete path ) { T _ → {} F _ → {} }
    // The organisation's people: a file of their own.
    : AgStore os ( ag_orgdb_open opath )
    ( check . os ok `manage: the organisation's file opens` )
    ( check ( seq ( string_data ( ag_user_touch os `sub-a` `a@x` `A` 10 ) ) `admin` ) `users: the first person is admin` )
    ( check ( seq ( string_data ( ag_user_touch os `sub-b` `b@x` `B` 11 ) ) `member` ) `users: the second is a member` )
    ( check ( seq ( string_data ( ag_user_touch os `sub-a` `a@x` `A` 12 ) ) `admin` ) `users: a return keeps the role` )
    ( check ! ( ag_user_set_role os `sub-a` `member` ) `users: the last admin stays` )
    ( check ! ( ag_user_delete os `sub-a` ) `users: the last admin cannot be removed` )
    ( check ( ag_user_set_role os `sub-b` `admin` ) `users: promote b` )
    ( check ( ag_user_set_role os `sub-a` `member` ) `users: now a can step down` )
    ( check ( ag_user_delete os `sub-a` ) `users: a member can be removed` )
    ( check == ( vec_len [AgUser] ( ag_users os ) ) 1 `users: one left` )
    // A repository's agora: agents are names, made on first use.
    : AgStore st ( ag_store_open path )
    ( check . st ok `manage: opens` )
    ( check ( ag_agent_ensure st `a-bot` 20 ) `agents: a-bot is made on first use` )
    ( check ( ag_agent_ensure st `a-bot` 21 ) `agents: and is the same agent again` )
    ( check ( ag_agent_ensure st `b-bot` 22 ) `agents: b-bot` )
    // One shared room: everybody sees everything, mail too.
    : i m1 ( ag_post st `public` `a-bot` `hello` 0 40 )
    : i m2 ( ag_post st `@b-bot` `a-bot` `psst` 0 41 )
    : i m3 ( ag_post st `@a-bot` `b-bot` `re` 0 42 )
    : ( Vec AgMsg ) va ( ag_messages_list st `` `` 0 50 )
    ( check == ( vec_len [AgMsg] va ) 3 `messages: posts and mail alike` )
    : ( Vec AgMsg ) vq ( ag_messages_list st `` `PSS` 0 50 )
    ( check == ( vec_len [AgMsg] vq ) 1 `messages: text search, any case` )
    : ( Vec AgMsg ) vc ( ag_messages_list st `public` `` 0 50 )
    ( check == ( vec_len [AgMsg] vc ) 1 `messages: one channel` )
    ( check ( ag_msg_set_body st m1 `hello, edited` ) `msg: edit` )
    ( check ( ag_msg_delete st m3 ) `msg: delete` )
    ( check ! ( ag_msg_delete st m3 ) `msg: deleted once` )
    // Tasks.
    : i t1 ( ag_task_post st `t` `` `,x,` `a-bot` 0 50 )
    ( check == ( ag_task_claim st t1 `b-bot` 600 51 ) AG_TASK_OK `task: b claims` )
    ( check ( ag_task_edit st t1 `t2` `body` `,y,` 5 `open` 52 ) `task: edit back to open` )
    ?? ( ag_task_get st t1 53 ) {
        T t → { ( check & & ( seq ( string_data . t status ) `open` ) == ( string_len . t owner ) 0 == . t priority 5 `task: open again, unheld, p5` ) }
        F _ → { ( check F `task: open again, unheld, p5` ) }
    }
    ( check ! ( ag_task_edit st t1 `t2` `` `` 0 `weird` 54 ) `task: an unknown status is refused` )
    ( check ( ag_task_delete st t1 ) `task: delete` )
    // Channels and agents.
    ( check ( ag_channel_create st `c1` `` `a-bot` 60 ) `channel: create` )
    ( ag_post st `c1` `a-bot` `in c1` 0 61 )
    ( check ( ag_channel_delete st `c1` ) `channel: delete with its posts` )
    ( check ! ( ag_channel_delete st `public` ) `channel: public stays` )
    ( check ( ag_agent_delete st `b-bot` 70 ) `agent: delete` )
    ?? ( ag_agent_get st `b-bot` ) { T _ → { ( check F `agent: gone` ) } F → { ( check T `agent: gone` ) } }
    : AgTotals tt ( ag_totals st )
    ( check & == . tt agents 1 == . tt messages 1 `totals: 1 agent, 1 channel post` )
}

// A request with one extra header.
@ rest_h Router r s method s path s query s auth s hname s hval s body → HttpResponse {
    : HttpRequest req ( request_new )
    ( string_push_str . req method method )
    ( string_push_str . req path path )
    ( string_push_str . req query query )
    ( string_push_str . req version `HTTP/1.1` )
    ( vec_push [Header] . req headers ( header_new `Authorization` auth ) )
    ? > ( nurl_str_len hname ) 0 { ( vec_push [Header] . req headers ( header_new hname hval ) ) } {}
    ? > ( nurl_str_len body ) 0 {
        ( vec_push [Header] . req headers ( header_new `Content-Type` `application/json` ) )
        ( bytes_extend_str . req body body )
    } {}
    : HttpResponse resp ( router_handle r req )
    ^ resp
}

@ seed s token s org s sub s email → v {
    : AgStore st ( ag_org_store org )
    : String role ( ag_user_touch st sub email `` 1 )
    : AgPrincipal p @ AgPrincipal { T ( string_from org ) ( string_from sub ) ( string_from email ) ( string_new ) role ( string_new ) }
    ( _ag_auth_seed token p + ( now_seconds ) 3600 )
}

@ test_signed_in → v {
    ( ag_auth_set_home `agora_test_scratch/web` )
    ( ag_auth_configure T T `https://idp.invalid/organizations/v2.0` `cid` `https://agora.test/mcp` `org-a` `` `https://agora.test` )
    ( seed `tok-a1` `org-a` `sub-a1` `ann@a.example` )
    ( seed `tok-a2` `org-a` `sub-a2` `bob@a.example` )
    ( seed `tok-b1` `org-b` `sub-b1` `ann@b.example` )
    : HttpApp app ( ag_build_app 1 T )
    : Router r ( http_app_router app )
    // No token: 401 with where to sign in.
    : HttpResponse r0 ( rest_h r `POST` `/mcp` `` `` `` `` `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}` )
    ( check == . r0 status 401 `oidc: /mcp without a token is 401` )
    : HttpResponse md ( rest_h r `GET` `/.well-known/oauth-protected-resource/mcp` `` `` `` `` `` )
    ( check ( has ( body_of md ) `https://agora.test/mcp` ) `oidc: resource metadata names /mcp` )
    : HttpResponse rbad ( rest_h r `POST` `/api/whoami` `` `Bearer tok-nope` `` `` `{}` )
    ( check == . rbad status 401 `oidc: an unknown token is 401` )
    // Every call names its repository and who it is there.
    : HttpResponse w0 ( rest_h r `POST` `/api/whoami` `` `Bearer tok-a1` `` `` `{}` )
    ( check & == . w0 status 400 ( has ( body_of w0 ) `repo is required` ) `oidc: no repo is 400, and says what to send` )
    : HttpResponse w0b ( rest_h r `POST` `/api/whoami` `` `Bearer tok-a1` `` `` `{"repo":"git@github.com:o/r.git"}` )
    ( check & == . w0b status 400 ( has ( body_of w0b ) `as is required` ) `oidc: no as is 400` )
    : HttpResponse w0c ( rest_h r `POST` `/api/whoami` `` `Bearer tok-a1` `` `` `{"repo":"nurl","as":"x"}` )
    ( check == . w0c status 400 `oidc: a plain name is not a repository` )
    : HttpResponse w1 ( rest_h r `POST` `/api/whoami` `` `Bearer tok-a1` `` `` `{"repo":"git@github.com:O/r.git","as":"Ann-Bot"}` )
    ( check & ( has ( body_of w1 ) `"agent":"ann-bot"` ) ( has ( body_of w1 ) `"repo":"github.com/o/r"` ) `oidc: whoami names the agent and the repository` )
    // One repository = one room for the whole organisation, any spelling, any person.
    : HttpResponse p1 ( rest_h r `POST` `/api/post` `` `Bearer tok-a1` `` `` `{"repo":"git@github.com:o/r.git","as":"ann-bot","body":"from a"}` )
    ( check == . p1 status 200 `oidc: ann's agent posts` )
    : HttpResponse h2 ( rest_h r `POST` `/api/history` `` `Bearer tok-a2` `` `` `{"repo":"https://github.com/o/r","as":"bob-bot","channel":"public"}` )
    ( check ( has ( body_of h2 ) `from a` ) `oidc: bob's agent of the same org reads it` )
    : HttpResponse hx ( rest_h r `POST` `/api/history` `` `Bearer tok-a2` `` `` `{"repo":"github.com/o/other","as":"bob-bot","channel":"public"}` )
    ( check ! ( has ( body_of hx ) `from a` ) `oidc: another repository is another room` )
    : HttpResponse hb ( rest_h r `POST` `/api/history` `` `Bearer tok-b1` `` `` `{"repo":"github.com/o/r","as":"ann-bot","channel":"public"}` )
    ( check ! ( has ( body_of hb ) `from a` ) `oidc: the other organisation does not see it` )
    // A name is nobody's: anybody of the organisation may speak as it.
    : HttpResponse x1 ( rest_h r `POST` `/api/whoami` `` `Bearer tok-a2` `` `` `{"repo":"github.com/o/r","as":"ann-bot"}` )
    ( check ( has ( body_of x1 ) `"agent":"ann-bot"` ) `oidc: bob may act as ann-bot` )
    : HttpResponse s1 ( rest_h r `POST` `/api/send` `` `Bearer tok-a1` `` `` `{"repo":"github.com/o/r","as":"ann-bot","to":"bob-bot","body":"psst"}` )
    ( check == . s1 status 200 `oidc: mail between the people's agents` )
    : HttpResponse b1 ( rest_h r `POST` `/api/brief` `` `Bearer tok-a2` `` `` `{"repo":"github.com/o/r","as":"bob-bot"}` )
    ( check ( has ( body_of b1 ) `psst` ) `oidc: bob-bot's brief delivers it` )
    // MCP: stateless — no session; every tool call carries repo and as.
    : HttpResponse i1 ( rest_h r `POST` `/mcp` `` `Bearer tok-a1` `` `` `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}` )
    ( check == . i1 status 200 `oidc: initialize answers` )
    ?? ( header_get . i1 headers `Mcp-Session-Id` ) { T _ → { ( check F `oidc: no session id is handed out` ) } F _ → { ( check T `oidc: no session id is handed out` ) } }
    : HttpResponse tl1 ( rest_h r `POST` `/mcp` `` `Bearer tok-a1` `` `` `{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}` )
    : String tls ( body_of tl1 )
    ( check & ( has tls `"repo"` ) ( has tls `"as"` ) `oidc: every tool takes repo and as` )
    ( check ! ( has tls `"project"` ) `oidc: notes take no project: the repository is it` )
    : HttpResponse k1 ( rest_h r `POST` `/mcp` `` `Bearer tok-a1` `` `` `{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"whoami","arguments":{"repo":"git@github.com:o/r.git","as":"ann-claude"}}}` )
    ( check & ( has ( body_of k1 ) `you: ann-claude` ) ( has ( body_of k1 ) `repo: github.com/o/r` ) `oidc: a tool call acts as its as, in its repo` )
    : HttpResponse k2 ( rest_h r `POST` `/mcp` `` `Bearer tok-a1` `` `` `{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"whoami","arguments":{}}}` )
    ( check & ( has ( body_of k2 ) `"isError":true` ) ( has ( body_of k2 ) `repo is required` ) `oidc: a tool call without repo is a tool error that says why` )
    : HttpResponse j1 ( rest_h r `POST` `/mcp` `` `Bearer tok-a1` `` `` `{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"join","arguments":{"repo":"github.com/o/r","as":"ann-claude","about":"reviews"}}}` )
    ( check ( has ( body_of j1 ) `you are ann-claude in github.com/o/r` ) `oidc: join says where and as whom` )
    : HttpResponse n1 ( rest_h r `POST` `/mcp` `` `Bearer tok-a2` `` `` `{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"note_set","arguments":{"repo":"github.com/o/r","as":"bob-bot","key":"build","body":"make"}}}` )
    ( check ( has ( body_of n1 ) `note build saved` ) `oidc: a note goes to the repository` )
    // The web page's API.
    : HttpResponse me ( rest_h r `GET` `/m/me` `` `Bearer tok-a1` `` `` `` )
    ( check & ( has ( body_of me ) `"role":"admin"` ) ( has ( body_of me ) `"is_owner_admin":true` ) `web: ann is admin of the owner org` )
    : HttpResponse meb ( rest_h r `GET` `/m/me` `repo=github.com%2Fo%2Fr` `Bearer tok-a2` `` `` `` )
    ( check & ( has ( body_of meb ) `"role":"member"` ) ( has ( body_of meb ) `"notes":1` ) `web: bob is a member; the repo's counts` )
    : HttpResponse ub ( rest_h r `GET` `/m/users` `` `Bearer tok-a2` `` `` `` )
    ( check == . ub status 403 `web: a member cannot list people` )
    : HttpResponse tb ( rest_h r `GET` `/m/tenants` `` `Bearer tok-b1` `` `` `` )
    ( check == . tb status 403 `web: org b's admin is not the service's` )
    : HttpResponse rp ( rest_h r `GET` `/m/repos` `` `Bearer tok-a2` `` `` `` )
    ( check & ( has ( body_of rp ) `"github.com/o/other","github.com/o/r"` ) ! ( has ( body_of rp ) `local` ) `web: the organisation's repositories, sorted` )
    : HttpResponse mq ( rest_h r `GET` `/m/messages` `` `Bearer tok-a2` `` `` `` )
    ( check == . mq status 400 `web: messages need a repo` )
    : HttpResponse ms ( rest_h r `GET` `/m/messages` `repo=github.com%2Fo%2Fr` `Bearer tok-a2` `` `` `` )
    ( check & ( has ( body_of ms ) `psst` ) ( has ( body_of ms ) `"may_change":true` ) `web: the room's messages, mail too, for any member` )
    : HttpResponse ed ( rest_h r `PUT` `/m/messages/1` `repo=github.com%2Fo%2Fr` `Bearer tok-a2` `` `` `{"body":"from a, edited"}` )
    ( check == . ed status 200 `web: a member edits a post` )
    : HttpResponse nl ( rest_h r `GET` `/m/notes` `repo=git%40github.com%3Ao%2Fr.git` `Bearer tok-a1` `` `` `` )
    ( check ( has ( body_of nl ) `"key":"build"` ) `web: the repository's notes, any spelling` )
    : HttpResponse nb ( rest_h r `PUT` `/m/notes` `repo=github.com%2Fo%2Fr` `Bearer tok-a2` `` `` `{"key":"k2","body":"v"}` )
    ( check == . nb status 200 `web: any member writes a note` )
    : HttpResponse nlb ( rest_h r `GET` `/m/notes` `repo=github.com%2Fo%2Fr` `Bearer tok-b1` `` `` `` )
    ( check ! ( has ( body_of nlb ) `build` ) `web: org b has no such note` )
    : HttpResponse ag ( rest_h r `GET` `/m/agents` `repo=github.com%2Fo%2Fr` `Bearer tok-a1` `` `` `` )
    ( check & ( has ( body_of ag ) `"id":"ann-claude"` ) ( has ( body_of ag ) `reviews` ) `web: the repository's agents` )
    : HttpResponse cd ( rest_h r `DELETE` `/m/channels` `repo=github.com%2Fo%2Fr&name=public` `Bearer tok-a1` `` `` `` )
    ( check == . cd status 400 `web: public cannot be deleted` )
    // Organisations: a stranger knocks and waits.
    ( check ( ag_tenant_admitted `org-a` `` 100 ) `tenants: the owner is admitted` )
    ( check ! ( ag_tenant_admitted `org-c` `c@c` 100 ) `tenants: a newcomer is pending` )
    : HttpResponse tl ( rest_h r `GET` `/m/tenants` `` `Bearer tok-a1` `` `` `` )
    ( check ( has ( body_of tl ) `"tenant":"org-c"` ) `tenants: the owner's admin sees the knock` )
    : HttpResponse ta ( rest_h r `PUT` `/m/tenants/org-c` `` `Bearer tok-a1` `` `` `{"state":"allowed"}` )
    ( check == . ta status 200 `tenants: allow org-c` )
    ( check ( ag_tenant_admitted `org-c` `` 101 ) `tenants: org-c is admitted now` )
    ( check ( seq ( string_data ( ag_org_key `../../etc` ) ) ( string_data ( ag_org_key `../../etc` ) ) ) `org key: deterministic` )
    ( check ! ( string_contains ( ag_org_key `../../etc` ) `/` ) `org key: no path in it` )
    ( check ! ( string_contains ( ag_repo_path `org-a` `github.com/o/r` ) `github.com/o` ) `repo file: no '/' from the key` )
    // A tenant decision forgets every cached verdict: sign in again, and
    // let org b in.
    ( ag_tenant_set_state `org-b` `allowed` `test` 102 )
    ( seed `tok-a1` `org-a` `sub-a1` `ann@a.example` )
    ( seed `tok-a2` `org-a` `sub-a2` `bob@a.example` )
    ( seed `tok-b1` `org-b` `sub-b1` `ann@b.example` )
    // Feedback leaves the organisation: the owner organisation reads it.
    : HttpResponse fb1 ( rest_h r `POST` `/api/feedback` `` `Bearer tok-b1` `` `` `{"repo":"github.com/o/r","as":"ann-bot","kind":"improvement","title":"b wants more","body":"details"}` )
    ( check & == . fb1 status 200 ( has ( body_of fb1 ) `"id":1` ) `oidc: org b's agent sends feedback` )
    ( rest_h r `POST` `/api/feedback` `` `Bearer tok-a1` `` `` `{"repo":"github.com/o/r","as":"ann-bot","title":"a's own"}` )
    : HttpResponse fl1 ( rest_h r `GET` `/m/feedback` `` `Bearer tok-a2` `` `` `` )
    : String fl1b ( body_of fl1 )
    ( check & & ( has fl1b `"org":"org-b"` ) ( has fl1b `"person":"ann@b.example"` ) ( has fl1b `"can_triage":true` ) `oidc: the owner organisation's members read everyone's feedback` )
    ( check ( has fl1b `"total":2` ) `oidc: … all of it` )
    : HttpResponse fl2 ( rest_h r `GET` `/m/feedback` `` `Bearer tok-b1` `` `` `` )
    : String fl2b ( body_of fl2 )
    ( check & & ( has fl2b `b wants more` ) ! ( has fl2b `a's own` ) ( has fl2b `"can_triage":false` ) `oidc: another organisation reads only its own` )
    : HttpResponse fp1 ( rest_h r `PUT` `/m/feedback/1` `` `Bearer tok-b1` `` `` `{"status":"done"}` )
    ( check == . fp1 status 403 `oidc: only the owner organisation answers` )
    : HttpResponse fp2 ( rest_h r `PUT` `/m/feedback/1` `` `Bearer tok-a2` `` `` `{"status":"accepted","reply":"on it"}` )
    ( check == . fp2 status 200 `oidc: a member of the owner organisation answers` )
    : HttpResponse fb2 ( rest_h r `POST` `/api/brief` `` `Bearer tok-b1` `` `` `{"repo":"github.com/o/r","as":"ann-bot"}` )
    ( check & ( has ( body_of fb2 ) `your feedback #1 (b wants more) is accepted` ) ( has ( body_of fb2 ) `reply: on it` ) `oidc: the answer reaches the agent in its own organisation's room` )
    : HttpResponse fb3 ( rest_h r `POST` `/api/brief` `` `Bearer tok-a1` `` `` `{"repo":"github.com/o/r","as":"ann-bot"}` )
    ( check ! ( has ( body_of fb3 ) `b wants more` ) `oidc: and not in the owner's room of the same name` )
    // Skills are the organisation's: every repository's agents, no other organisation's.
    : HttpResponse sk1 ( rest_h r `POST` `/api/skill_set` `` `Bearer tok-a1` `` `` `{"repo":"github.com/o/r","as":"ann-bot","name":"review","description":"How we review","body":"read the diff"}` )
    ( check == . sk1 status 200 `oidc: a skill set from one repository` )
    : HttpResponse sk2 ( rest_h r `POST` `/api/skills` `` `Bearer tok-a2` `` `` `{"repo":"github.com/o/other","as":"bob-bot"}` )
    ( check ( has ( body_of sk2 ) `"name":"review"` ) `oidc: is the organisation's, seen from another repository` )
    : HttpResponse sk3 ( rest_h r `POST` `/api/skills` `` `Bearer tok-b1` `` `` `{"repo":"github.com/o/r","as":"ann-bot"}` )
    ( check ! ( has ( body_of sk3 ) `review` ) `oidc: and not by another organisation` )
    : HttpResponse sk4 ( rest_h r `POST` `/api/brief` `` `Bearer tok-a2` `` `` `{"repo":"github.com/o/other","as":"bob-bot"}` )
    ( check ( has ( body_of sk4 ) `"skills":1` ) `oidc: brief counts the organisation's skills` )
    : HttpResponse sk5 ( rest_h r `GET` `/m/skills` `` `Bearer tok-a2` `` `` `` )
    ( check ( has ( body_of sk5 ) `"author":"ann-bot"` ) `oidc: the page lists the organisation's skills` )
    : HttpResponse sk6 ( rest_h r `PUT` `/m/skills/review` `` `Bearer tok-a2` `` `` `{"enabled":false}` )
    ( check == . sk6 status 200 `oidc: a member switches one off` )
    : HttpResponse sk7 ( rest_h r `POST` `/api/skills` `` `Bearer tok-a1` `` `` `{"repo":"github.com/o/r","as":"ann-bot"}` )
    ( check ! ( has ( body_of sk7 ) `"name":"review"` ) `oidc: then agents are not shown it` )
    : HttpResponse sk8 ( rest_h r `GET` `/m/skills` `` `Bearer tok-b1` `` `` `` )
    ( check ! ( has ( body_of sk8 ) `review` ) `oidc: another organisation's page has none of it` )
    // The page writes into a repository as a name made from the e-mail.
    : HttpResponse wn ( rest_h r `POST` `/m/messages` `repo=github.com%2Fo%2Fr` `Bearer tok-a2` `` `` `{"body":"from bob's page"}` )
    ( check ( has ( body_of wn ) `"as":"bob"` ) `oidc: the page writes as the e-mail's name` )
    ( ag_auth_configure F F `` `` `` `` `` `` )
}

@ main → i {
    : String dir ( string_from `agora_test_scratch` )
    ( dir_create_all ( string_data dir ) )
    : String db ( string_from `agora_test_scratch/agora.db` )
    ?? ( file_delete ( string_data db ) ) { T _ → {} F _ → {} }
    ( check ( ag_state_init ( string_data db ) ) `state: init` )

    // The store test gets a file of its own, so the ids and names the
    // operation tests expect start from a clean one.
    ?? ( file_delete `agora_test_scratch/store.db` ) { T _ → {} F _ → {} }
    : AgStore st ( ag_store_open `agora_test_scratch/store.db` )
    ( test_store st )
    ( test_migration )
    ( test_ops )
    ( test_identity )
    ( test_new_ops )
    ( test_migration_03 )
    : HttpApp app ( ag_build_app 1 T )
    : Router r ( http_app_router app )
    ( test_rest r )
    ( test_mcp )
    ( test_rules_skills_feedback )
    ( test_web_more r )
    ( test_project_norm )
    ( test_own_posts )
    ( test_manage )
    ?? ( dir_remove_all `agora_test_scratch/web` ) { T _ → {} F _ → {} }
    ( test_signed_in )

    : String sum ( string_from `agora_test: ` )
    ( string_push_int sum g_pass )
    ( string_push_str sum ` passed, ` )
    ( string_push_int sum g_fail )
    ( string_push_str sum ` failed` )
    ( nurl_println ( string_data sum ) )
    ^ ? > g_fail 0 1 0
}
