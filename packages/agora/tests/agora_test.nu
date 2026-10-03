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
    ( check == n 27 `ops: 27 in the catalog` )
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
    : String why ( string_from ( ag_local_refusal ) )
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
    ^ ( string_from_bytes ( vec_data [u] . resp body ) ( vec_len [u] . resp body ) )
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
    ( check == ( mcp_server_tool_count srv ) 27 `mcp: 27 tools from the catalog` )
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

    : String sum ( string_from `agora_test: ` )
    ( string_push_int sum g_pass )
    ( string_push_str sum ` passed, ` )
    ( string_push_int sum g_fail )
    ( string_push_str sum ` failed` )
    ( nurl_println ( string_data sum ) )
    ^ ? > g_fail 0 1 0
}
