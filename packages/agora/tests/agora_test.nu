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
$ `stdlib/ext/json.nu`
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
        T id → { ( check ( seq ( string_data id ) `bob` ) `store: token resolves bob` ) ( string_free id ) }
        F _ → { ( check F `store: token resolves bob` ) }
    }
    ?? ( ag_agent_by_token st `h-nope` 103 ) {
        T id → { ( check F `store: unknown token is nobody` ) ( string_free id ) }
        F _ → { ( check T `store: unknown token is nobody` ) }
    }
    : i m1 ( ag_post st `public` `alice` `hello all` 0 110 )
    ( check > m1 0 `store: alice posts` )
    : String bobbox ( ag_mailbox `bob` )
    : i m2 ( ag_post st ( string_data bobbox ) `alice` `hi bob` 0 111 )
    ( string_free bobbox )
    ( check == ( ag_unread st `bob` ) 2 `store: bob has 2 unread` )
    ( check == ( ag_unread st `alice` ) 0 `store: own posts are not unread` )
    : AgInbox ib ( ag_inbox st `bob` 1 )
    ( check == ( vec_len [AgMsg] . ib msgs ) 1 `store: inbox honours the limit` )
    ( check == . ib remaining 1 `store: and counts what is left` )
    ( ag_inbox_free ib )
    : AgInbox ib2 ( ag_inbox st `bob` 10 )
    ( check == ( vec_len [AgMsg] . ib2 msgs ) 1 `store: the next drain gets the rest` )
    ( check == . ib2 remaining 0 `store: nothing remains` )
    ( ag_inbox_free ib2 )
    : AgInbox ib3 ( ag_inbox st `bob` 10 )
    ( check == ( vec_len [AgMsg] . ib3 msgs ) 0 `store: a message is delivered ONCE` )
    ( ag_inbox_free ib3 )

    : i t1 ( ag_task_post st `do x` `details` `,dev,` `alice` 2 120 )
    ( check > t1 0 `store: task posted` )
    ( check == ( ag_task_claim st t1 `bob` 60 121 ) AG_TASK_OK `store: bob claims` )
    ( check == ( ag_task_claim st t1 `alice` 60 122 ) AG_TASK_WRONG_STATE `store: a claimed task cannot be claimed` )
    ( check == ( ag_task_claim st 999 `alice` 60 122 ) AG_TASK_NOT_FOUND `store: no such task` )
    ( check == ( ag_unread st `alice` ) 1 `store: the poster hears of the claim` )
    : ( Vec AgTask ) mine ( ag_tasks st `mine` `bob` `` 10 123 )
    ( check == ( vec_len [AgTask] mine ) 1 `store: bob holds one` )
    ( ag_tasks_free mine )
    ( check == ( ag_task_extend st t1 `bob` 100 150 ) AG_TASK_OK `store: bob extends` )
    : ( Vec AgTask ) still ( ag_tasks st `mine` `bob` `` 10 200 )
    ( check == ( vec_len [AgTask] still ) 1 `store: the extended lease holds at t=200` )
    ( ag_tasks_free still )
    : ( Vec AgTask ) open ( ag_tasks st `open` `` `dev` 10 300 )
    ( check == ( vec_len [AgTask] open ) 1 `store: an expired lease reopens the task` )
    ( ag_tasks_free open )
    ( check == ( ag_unread st `bob` ) 1 `store: the holder hears of the expiry` )
    : ( Vec AgTask ) none ( ag_tasks st `open` `` `ops` 10 300 )
    ( check == ( vec_len [AgTask] none ) 0 `store: tag filter is exact` )
    ( ag_tasks_free none )
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
            ( ag_task_free t )
        }
        F _ → { ( check F `store: task is done` ) }
    }
    : i t2 ( ag_task_post st `cancel me` `` `` `alice` 0 310 )
    ( check == ( ag_task_cancel st t2 `bob` 311 ) AG_TASK_WRONG_STATE `store: only the poster cancels` )
    ( check == ( ag_task_cancel st t2 `alice` 312 ) AG_TASK_OK `store: the poster cancels` )
    ( check == ( ag_task_cancel st t2 `alice` 313 ) AG_TASK_WRONG_STATE `store: cancel is once` )

    ( check ( ag_note_set st `plan` `step 1` `alice` 400 ) `store: note set` )
    ( check ( ag_note_set st `plan` `step 2` `bob` 401 ) `store: note overwrite` )
    ?? ( ag_note_get st `plan` ) {
        T n → { ( check ( seq ( string_data . n body ) `step 2` ) `store: note reads back` ) ( ag_note_free n ) }
        F _ → { ( check F `store: note reads back` ) }
    }
    ( check ( ag_note_del st `plan` ) `store: note deleted` )
    ( check ! ( ag_note_del st `plan` ) `store: deleting twice fails` )

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
    ( ag_inbox_free ib4 )
    ( check ( ag_unfollow st `bob` `dev` ) `store: bob unfollows` )
    ( check ! ( ag_unfollow st `bob` `dev` ) `store: unfollow twice fails` )
    : ( Vec AgMsg ) h ( ag_history st `dev` 0 10 )
    ( check == ( vec_len [AgMsg] h ) 2 `store: history sees everything` )
    ( ag_msgs_free h )
}

// ── 2. operations ────────────────────────────────────────────────────

@ call s who s op s args_json i now → AgRes {
    : AgStore st ( ag_store )
    : AgCaller c ? > ( nurl_str_len who ) 0 ( ag_caller_local st who now ) ( ag_caller_anon )
    : ~ Json args ( json_null )
    ?? ( json_parse args_json ) { T j → { ( json_free args ) = args j } F _ → {} }
    : AgRes r ( ag_op_call st c op args now )
    ( json_free args )
    ( ag_caller_free c )
    ^ r
}

@ test_ops → v {
    // Every catalog entry has a handler (a 501 would mean it does not).
    : ( Vec AgOpDef ) cat ( ag_op_catalog )
    : i n ( vec_len [AgOpDef] cat )
    ( check == n 24 `ops: 24 in the catalog` )
    : ~ b all_wired T
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgOpDef] cat i ) {
            T d → {
                : AgRes r ( call `probe` ( string_data . d name ) `{}` 1000 )
                ? == . r status 501 { = all_wired F } {}
                ( ag_res_free r )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( ag_catalog_free cat )
    ( check all_wired `ops: every catalog entry dispatches` )

    : AgRes u ( call `` `brief` `{}` 1000 )
    ( check == . u status 401 `ops: brief needs a caller` )
    ( check ( has . u text `join` ) `ops: and the text says how` )
    ( ag_res_free u )
    : AgRes unk ( call `` `nope` `{}` 1000 )
    ( check == . unk status 404 `ops: unknown op is 404` )
    ( ag_res_free unk )

    : AgRes j ( call `` `join` `{"name":"carol","about":"tester"}` 1000 )
    ( check == . j status 200 `ops: join` )
    ( check ( has . j text `token: ` ) `ops: join shows the token` )
    ( ag_res_free j )
    : AgRes j2 ( call `` `join` `{"name":"carol"}` 1000 )
    ( check == . j2 status 409 `ops: join twice is 409` )
    ( ag_res_free j2 )
    : AgRes j3 ( call `` `join` `{"name":"Bad Name"}` 1000 )
    ( check == . j3 status 400 `ops: join checks the name` )
    ( ag_res_free j3 )

    : AgRes p ( call `dan` `post` `{"body":"hello"}` 1001 )
    ( check ( seq ( string_data . p text ) `#1 posted to public\n` ) `ops: post text` )
    ( ag_res_free p )
    : AgRes s ( call `dan` `send` `{"to":"carol","body":"psst","reply_to":1}` 1002 )
    ( check == . s status 200 `ops: send` )
    ( ag_res_free s )
    : AgRes s2 ( call `dan` `send` `{"to":"nobody","body":"psst"}` 1002 )
    ( check == . s2 status 404 `ops: send to nobody is 404` )
    ( ag_res_free s2 )
    : AgRes b ( call `carol` `brief` `{}` 1062 )
    ( check ( has . b text `inbox: 2 new\n#1 public dan 1m: hello\n#2 dm dan 1m re#1: psst\n` ) `ops: brief delivers both, in order, with ages` )
    ( check ( has . b text `open tasks: 0 · notes: 0` ) `ops: brief counts` )
    ( ag_res_free b )
    : AgRes b2 ( call `carol` `brief` `{}` 1063 )
    ( check ( has . b2 text `inbox: nothing new` ) `ops: brief delivers once` )
    ( ag_res_free b2 )
    : AgRes hs ( call `carol` `history` `{"channel":"public"}` 1064 )
    ( check ( has . hs text `#1 public dan` ) `ops: history re-reads` )
    ( ag_res_free hs )
    : AgRes hm ( call `carol` `history` `{"channel":"@dan"}` 1064 )
    ( check == . hm status 403 `ops: another's mail is 403` )
    ( ag_res_free hm )
    : AgRes hm2 ( call `carol` `history` `{"channel":"@carol"}` 1064 )
    ( check == . hm2 status 200 `ops: own mail is readable` )
    ( ag_res_free hm2 )

    : AgRes tp ( call `dan` `task_post` `{"title":"review","tags":"Rust, review","priority":"3"}` 1100 )
    ( check == . tp status 200 `ops: task_post (priority as a string)` )
    ( ag_res_free tp )
    : AgRes tl ( call `carol` `tasks` `{"tag":"rust"}` 1101 )
    ( check ( has . tl text `#1 p3 [rust,review] review — open, dan` ) `ops: tasks line` )
    ( ag_res_free tl )
    : AgRes tc ( call `carol` `task_claim` `{"id":1,"lease_s":120}` 1102 )
    ( check ( has . tc text `claimed by you, lease 2m left` ) `ops: task_claim text` )
    ( ag_res_free tc )
    : AgRes tc2 ( call `erin` `task_claim` `{"id":1}` 1103 )
    ( check == . tc2 status 409 `ops: second claim is 409` )
    ( ag_res_free tc2 )
    : AgRes bb ( call `carol` `brief` `{}` 1110 )
    ( check ( has . bb text `holding:\n#1 p3 [rust,review] review — claimed carol, 1m left` ) `ops: brief lists held tasks with the lease` )
    ( ag_res_free bb )
    : AgRes td0 ( call `carol` `task_done` `{"id":1}` 1111 )
    ( check == . td0 status 400 `ops: task_done needs a result` )
    ( ag_res_free td0 )
    : AgRes td ( call `carol` `task_done` `{"id":1,"result":"merged"}` 1112 )
    ( check == . td status 200 `ops: task_done` )
    ( ag_res_free td )
    : AgRes db ( call `dan` `brief` `{}` 1113 )
    ( check ( has . db text `task #1 claimed by carol: review` ) `ops: poster hears of the claim` )
    ( check ( has . db text `task #1 done by carol: review\nresult: merged` ) `ops: and of the result` )
    ( ag_res_free db )
    : AgRes tk ( call `dan` `task` `{"id":1}` 1114 )
    ( check ( has . tk text `result: merged` ) `ops: task shows the result` )
    ( ag_res_free tk )

    : AgRes ns ( call `dan` `note_set` `{"key":"plan","body":"ship it"}` 1200 )
    ( check == . ns status 200 `ops: note_set` )
    ( ag_res_free ns )
    : AgRes nn ( call `carol` `notes` `{}` 1260 )
    ( check ( has . nn text `plan (dan 1m)` ) `ops: notes list` )
    ( ag_res_free nn )
    : AgRes nr ( call `carol` `note` `{"key":"plan"}` 1260 )
    ( check ( has . nr text `ship it` ) `ops: note read` )
    ( ag_res_free nr )
    : AgRes nd ( call `carol` `note_del` `{"key":"plan"}` 1261 )
    ( check == . nd status 200 `ops: note_del` )
    ( ag_res_free nd )
    : AgRes nd2 ( call `carol` `note_del` `{"key":"plan"}` 1261 )
    ( check == . nd2 status 404 `ops: note_del twice is 404` )
    ( ag_res_free nd2 )

    : AgRes cc ( call `dan` `channel_create` `{"name":"dev"}` 1300 )
    ( check == . cc status 200 `ops: channel_create` )
    ( ag_res_free cc )
    : AgRes fo ( call `carol` `follow` `{"channel":"dev"}` 1301 )
    ( check == . fo status 200 `ops: follow` )
    ( ag_res_free fo )
    : AgRes ch ( call `carol` `channels` `{}` 1302 )
    ( check ( has . ch text `dev (0)` ) `ops: channels` )
    ( ag_res_free ch )
    : AgRes uf ( call `carol` `unfollow` `{"channel":"dev"}` 1303 )
    ( check == . uf status 200 `ops: unfollow` )
    ( ag_res_free uf )
    : AgRes ag ( call `carol` `agents` `{}` 1304 )
    ( check ( has . ag text `carol (seen now) — tester` ) `ops: agents` )
    ( ag_res_free ag )
    : AgRes wi ( call `carol` `whoami` `{}` 1305 )
    ( check ( has . wi text `you: carol — tester\nfollows: public\n` ) `ops: whoami` )
    ( ag_res_free wi )
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
    ( request_free req )
    ^ resp
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
    ( string_free cb )
    ( http_response_free c )

    : HttpResponse u ( rest r `POST` `/api/brief` `` `` `{}` )
    ( check == . u status 401 `rest: POST /api/brief without a token is 401` )
    ( http_response_free u )

    : HttpResponse j ( rest r `POST` `/api/join` `` `` `{"name":"rest-user"}` )
    : String jb ( body_of j )
    ( check == . j status 200 `rest: join` )
    : ~ String tok ( string_new )
    ?? ( json_parse ( string_data jb ) ) {
        T jj → {
            ?? ( json_obj_get jj `token` ) { T t → { ( string_push_str tok ( json_as_str t ) ) } F _ → {} }
            ( json_free jj )
        }
        F _ → {}
    }
    ( check == ( string_len tok ) 48 `rest: the token is 48 hex chars` )
    ( string_free jb )
    ( http_response_free j )
    : String auth ( string_from `Bearer ` )
    ( string_push_str auth ( string_data tok ) )

    : HttpResponse w ( rest r `GET` `/api/whoami` `` ( string_data auth ) `` )
    : String wb ( body_of w )
    ( check == . w status 200 `rest: GET with the token` )
    ( check ( has wb `"agent":"rest-user"` ) `rest: whoami body` )
    ( string_free wb )
    ( http_response_free w )

    : HttpResponse p ( rest r `POST` `/api/post` `` ( string_data auth ) `{"body":"over rest"}` )
    : String pb ( body_of p )
    ( check ( has pb `"id":` ) `rest: post answers the id` )
    ( string_free pb )
    ( http_response_free p )

    : HttpResponse h ( rest r `GET` `/api/history` `channel=public&limit=1` ( string_data auth ) `` )
    : String hb ( body_of h )
    ( check ( has hb `"body":"over rest"` ) `rest: GET with query arguments` )
    ( string_free hb )
    ( http_response_free h )

    : HttpResponse bad ( rest r `POST` `/api/nope` `` ( string_data auth ) `{}` )
    ( check == . bad status 404 `rest: unknown op is 404` )
    ( http_response_free bad )

    : HttpResponse bt ( rest r `GET` `/api/whoami` `` `Bearer 0000` `` )
    ( check == . bt status 401 `rest: a bad token is 401` )
    ( http_response_free bt )

    ( string_free auth )
    ( string_free tok )
}

// ── 4. MCP ───────────────────────────────────────────────────────────

@ mcp McpServer srv s json Json ctx → String {
    : ~ String out ( string_new )
    ?? ( json_parse json ) {
        T req → {
            ?? ( mcp_server_dispatch_as srv req ctx ) {
                T res → { ( string_free out ) = out ( json_stringify res ) ( json_free res ) }
                F e → { ( mcp_rpc_err_free e ) }
            }
            ( json_free req )
        }
        F _ → {}
    }
    ^ out
}

@ test_mcp → v {
    : McpServer srv ( ag_mcp_server )
    ( check == ( mcp_server_tool_count srv ) 24 `mcp: 24 tools from the catalog` )
    : String tl ( mcp srv `{"jsonrpc":"2.0","id":1,"method":"tools/list"}` ( json_null ) )
    ( check ( has tl `"name":"task_claim"` ) `mcp: tools/list` )
    ( check ( has tl `"required":["id"]` ) `mcp: schemas carry required` )
    ( string_free tl )

    : String c0 ( mcp srv `{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"whoami","arguments":{}}}` ( json_null ) )
    ( check ( has c0 `"isError":true` ) `mcp: no context, no local identity → error` )
    ( string_free c0 )

    : Json ctx ( json_obj_new )
    ( json_obj_set ctx `agent` ( json_str_lit `carol` ) )
    : String c1 ( mcp srv `{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"whoami","arguments":{}}}` ctx )
    ( check ( has c1 `you: carol` ) `mcp: tools/call with a context acts as it` )
    ( string_free c1 )
    : String c2 ( mcp srv `{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"post","arguments":{"body":"via mcp","channel":"dev"}}}` ctx )
    ( check ( has c2 `posted to dev` ) `mcp: post through a tool` )
    ( string_free c2 )
    ( json_free ctx )

    ( ag_state_set_local `stdio-agent` )
    : String c3 ( mcp srv `{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"whoami","arguments":{}}}` ( json_null ) )
    ( check ( has c3 `you: stdio-agent` ) `mcp: null context is the local identity` )
    ( string_free c3 )
    ( ag_state_set_local `` )
    ( mcp_server_free srv )
}

@ main → i {
    : String dir ( string_from `agora_test_scratch` )
    ( dir_create_all ( string_data dir ) )
    : String db ( string_from `agora_test_scratch/agora.db` )
    ?? ( file_delete ( string_data db ) ) { T _ → {} F _ → {} }
    ( check ( ag_state_init ( string_data db ) ) `state: init` )
    ( string_free db )
    ( string_free dir )

    // The store test gets a file of its own, so the ids and names the
    // operation tests expect start from a clean one.
    ?? ( file_delete `agora_test_scratch/store.db` ) { T _ → {} F _ → {} }
    : AgStore st ( ag_store_open `agora_test_scratch/store.db` )
    ( test_store st )
    ( ag_store_free st )
    ( test_ops )
    : *HttpApp app ( ag_build_app 1 T )
    : Router r ( http_app_router app )
    ( test_rest r )
    ( http_app_free app )
    ( test_mcp )
    ( ag_service_shutdown )

    : String sum ( string_from `agora_test: ` )
    ( string_push_int sum g_pass )
    ( string_push_str sum ` passed, ` )
    ( string_push_int sum g_fail )
    ( string_push_str sum ` failed` )
    ( nurl_println ( string_data sum ) )
    ( string_free sum )
    ^ ? > g_fail 0 1 0
}
