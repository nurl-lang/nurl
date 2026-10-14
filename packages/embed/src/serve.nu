// packages/embed/src/serve.nu — the embedding model as a service.
//
//   embed serve <model-dir> [--addr 0.0.0.0:8000] [--token T] [--maxseq N]
//
// The HTTP surface mirrors the reference FastAPI embedding service, so
// existing clients work unchanged:
//
//   POST /create_embedding   {"text": "..." | ["...", …], "normalize": true}
//                            {"texts": ["...", …]}          (same thing)
//                            → {"embeddings": [[…]], "model": "…", "dimension": N}
//   GET  /create_embedding?text=…&normalize=true      (single text)
//   GET  /health             {"status":"healthy", "model", "model_loaded",
//                             "device": "cuda"|"cpu", …}
//   GET  /                   the same (a browser poking the port should
//                            learn something, not get a 404)
//
// Auth: no --token → open server (bind loopback!). With a token, requests
// must carry `Authorization: Bearer <t>` (or `?token=<t>` for clients that
// cannot set headers); the compare is constant-time over the configured
// token.
//
// Concurrency. One model on one device can run one forward at a time —
// that part is not a choice. Everything ELSE about a request is: reading
// the socket, parsing the JSON, tokenizing (the Unigram engine is
// read-only, so it is re-entrant), and serialising a few thousand floats
// back out, which for a batch is the larger half of the work. So the
// server is fiber-per-connection on the async runtime, and the forward
// is handed to ONE dedicated model thread over a queue — one job per
// REQUEST, so a request's texts reach the model together and run as a
// few padded batched forwards (embed_encode_batch), not text by text. A
// single worker used to mean a slow or idle client stalled every other
// client behind it; now it does not, and a batch's tokenizing and JSON
// overlap with another request's arithmetic.
//
// The forward runs on a thread rather than on the requesting fiber for
// a hard reason, not a stylistic one: async fibers get 64 KB stacks, and
// NVRTC — which the first forward at a new sequence length still calls —
// wants far more than that. Compiling a kernel on a fiber segfaults
// inside libnvrtc. One model thread with an ordinary 8 MB stack also
// keeps every CUDA call on one thread, which is where a context wants
// to be.
//
// Handlers are top-level functions over globals set at start: the
// queue (a Channel) and the server's state (a Locked), reached from every
// fiber and thread in safe code.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/option.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/url.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/json.nu`
$ `deps/http/src/http.nu`
$ `model.nu`
$ `stdlib/core/slice.nu`

// The server's state: the served model while serving, the request count
// and the weights' lease clock — a Locked global set at start, so the
// handlers, the model thread and the ticker all reach it in safe code.
: EmServe {
    ? Embed model  // one owner of the served model, while serving
    i reqs
    // ── the weights as a lease: --unload-after ──
    // The model thread is the only thread that touches the device, so it
    // is the one that lets the weights go and brings them back: a job
    // arriving at an unloaded engine reloads it first (embed_reload — the
    // tokenizer and config never left, so the request was already
    // tokenized on its own fiber); a tick with the idle clock past the
    // limit unloads (embed_unload — the arena, the pool, the kernels, the
    // CUDA context). The ticks come from a ticker thread, five a second
    // while the limit is on; without them the model thread sleeps until
    // a job and the limit could never fire.
    i unload_ms  // 0 = the weights stay for the process's life
    i idle_since  // monotonic_ns at the end of the last job
    i loads  // 1 is the load before the port opened
    i unloads
    i load_ms  // the last load's wall time
    b serving
}

@ __em_serve_blank → ( Locked EmServe ) {
    ^ ( locked_new [EmServe] @ EmServe { @ ?Embed { F } 0 0 0 0 0 0 F } )
}

: ( Locked EmServe ) g_em ( __em_serve_blank )

: ~ s g_em_token ``
: ~ s g_em_name ``

// One more owner of the served model (only while serving).
@ __em_model → Embed {
    : EmServe sv ( locked_take [EmServe] g_em )
    : ~ ? Embed out @ ?Embed { F }
    ?? . sv model { T e → { = out @ ?Embed { T ( Embed_share e ) } } F → {} }
    ( locked_restore [EmServe] g_em sv )
    ?? out {
        T e → { ^ e }
        F → { ( nurl_panic `embed: no model is being served` ) }
    }
}

// ── The model queue ───────────────────────────────────────────────────
//
// One job per waiting request on a channel the model thread drains; the
// job carries the channel its answer goes back on, and the submitting
// fiber waits on that. A tick (the unload timer) and a stop travel the
// same queue, so the model thread waits on one thing.
: i EM_JOB 0
: i EM_TICK 1
: i EM_STOP 2

: EmJob {
    i kind
    ( Vec i ) ids  // flat tokens for the whole request
    ( Vec i ) offs  // B+1 offsets into ids
    i nout  // B*dim floats come back
    b normalize
    ( Channel ( Vec f ) ) reply  // the embeddings, or an empty Vec on failure
}

@ __em_queue_new → ( Channel EmJob ) { ^ ( chan_new [EmJob] ) }

: ( Channel EmJob ) g_q ( __em_queue_new )

@ __em_signal i kind → v {
    : b _s ( chan_send [EmJob] g_q @ EmJob { kind ( vec_new [i] ) ( vec_new [i] ) 0 F ( chan_new [( Vec f )] ) } )
}

// Run one request's forward — the WHOLE batch, one job — on the model
// thread and wait for it. The job takes `ids` and `offs`; what comes
// back is the `nout` floats of the batch's embeddings, or an empty Vec
// when the forward failed.
@ __em_submit sink ( Vec i ) ids sink ( Vec i ) offs i nout b normalize → ( Vec f ) {
    : ( Channel ( Vec f ) ) reply ( chan_new [( Vec f )] )
    ? ( chan_send [EmJob] g_q @ EmJob { EM_JOB ids offs nout normalize ( Channel_share [( Vec f )] reply ) } ) {} { ^ ( vec_new [f] ) }
    ?? ( chan_recv [( Vec f )] reply ) {
        T out → { ^ out }
        F → { ^ ( vec_new [f] ) }
    }
}

// A tick while nothing is queued: is it time to let the weights go?
@ __em_maybe_unload Embed e → v {
    : ~ EmServe sv ( locked_take [EmServe] g_em )
    ? & > . sv unload_ms 0 ( embed_loaded e ) {
        ? >= ( elapsed_ms_since . sv idle_since ) . sv unload_ms {
            ( embed_unload e )
            = . sv unloads + . sv unloads 1
            : String m ( string_from `embed: idle for ` )
            ( string_push_int m / . sv unload_ms 1000 )
            ( string_push_str m ` s — weights unloaded (device memory released; the next request reloads them)` )
            ( nurl_eprintln ( string_data m ) )
        } {}
    } {}
    ( locked_restore [EmServe] g_em sv )
}

// Bring the weights back for a job: F when they would not load.
@ __em_ensure_loaded Embed e → b {
    ? ( embed_loaded e ) { ^ T } {}
    : i t0 ( monotonic_ns )
    ?? ( embed_reload e ) {
        T _ → {
            : i ms / - ( monotonic_ns ) t0 1000000
            : ~ EmServe sv ( locked_take [EmServe] g_em )
            = . sv loads + . sv loads 1
            = . sv load_ms ms
            ( locked_restore [EmServe] g_em sv )
            : String m ( string_from `embed: weights loaded in ` )
            ( string_push_int m ms )
            ( string_push_str m ` ms` )
            ( nurl_eprintln ( string_data m ) )
            ^ T
        }
        F le → {
            ( nurl_eprintln ( string_data le ) )
            ^ F
        }
    }
}

// The model thread: take jobs, run them, answer the waiter.
@ __em_model_loop → v {
    : Embed e ( __em_model )
    : ~ b run T
    ~ run {
        ?? ( chan_recv [EmJob] g_q ) {
            F → { = run F }
            T j → {
                ? == . j kind EM_STOP { = run F } {
                    ? == . j kind EM_TICK { ( __em_maybe_unload e ) } {
                        : ( Vec f ) out ( vec_zeroed [f] . j nout )
                        : ~ b r ( __em_ensure_loaded e )
                        ? r { = r ( embed_encode_batch e . j ids . j offs out . j normalize ) } {}
                        : ~ EmServe sv ( locked_take [EmServe] g_em )
                        = . sv idle_since ( monotonic_ns )
                        ( locked_restore [EmServe] g_em sv )
                        : b _a ( chan_send [( Vec f )] . j reply ? r out ( vec_new [f] ) )
                    }
                }
            }
        }
    }
}

// Five ticks a second for the model thread while serving with
// --unload-after.
@ __em_ticker → v {
    ~ . ( locked_get [EmServe] g_em ) serving {
        ( sleep_ms 200 )
        ( __em_signal EM_TICK )
    }
}

// Constant-time-ish token compare (every byte of the CONFIGURED token is
// examined; a length mismatch folds in).
@ __em_tok_eq s got s want → b {
    : ( Slice u ) got_v ( slice_of_str got )
    : ( Slice u ) want_v ( slice_of_str want )
    : i lg ( nurl_str_len got )
    : i lw ( nurl_str_len want )
    : ~ i diff ^^ lg lw
    : ~ i k 0
    ~ < k lw {
        : i cw ( slice_byte want_v k )
        : i cg ? < k lg ( slice_byte got_v k ) 0
        = diff | diff ^^ cw cg
        = k + k 1
    }
    ^ == diff 0
}

@ __em_query_val s q s name → String {
    : String out ( string_new )
    : ( Vec UrlParam ) ps ( url_query_decode q )
    : ~ i k 0
    ~ < k ( vec_len [UrlParam] ps ) {
        ?? ( vec_get [UrlParam] ps k ) {
            T p → {
                ? & != 0 ( nurl_str_eq ( string_data . p key ) name ) == ( string_len out ) 0 {
                    ( string_push_str out ( string_data . p val ) )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ out
}

@ __em_authed HttpRequest req → b {
    ? == ( nurl_str_len g_em_token ) 0 { ^ T } {}
    : ~ b ok F
    ?? ( header_get . req headers `authorization` ) {
        T hv → {
            : s h ( string_data hv )
            ? & > ( nurl_str_len h ) 7 != 0 ( nurl_str_starts h `Bearer ` ) {
                ? ( __em_tok_eq ( nurl_str_slice h 7 - ( nurl_str_len h ) 7 ) g_em_token ) { = ok T } {}
            } {}
        }
        F → {}
    }
    ? ok { ^ T } {}
    : String qt ( __em_query_val ( string_data . req query ) `token` )
    ? > ( string_len qt ) 0 {
        ? ( __em_tok_eq ( string_data qt ) g_em_token ) { = ok T } {}
    } {}
    ^ ok
}

@ __em_jerr i status s msg → HttpResponse {
    : Json o ( json_obj_new )
    : b _s ( json_obj_set o `error` ( json_str_lit msg ) )
    : HttpResponse r ( response_json status o )
    ^ r
}

// Embed `texts` → the response.
//
// Tokenizing is done outside the model lock — the Unigram engine only
// reads — and so is building the response, which for a batch of long
// vectors is thousands of float conversions. The lock covers exactly the
// device forward — and the whole request is ONE job: the model thread
// sees every text of the batch at once and runs them as a few padded
// batched forwards (embed_encode_batch), not one forward per text.
@ __em_run ( Vec String ) texts b normalize → HttpResponse {
    : Embed e ( __em_model )
    : i nt ( vec_len [String] texts )
    : i dim ( embed_dim e )
    : ~ b ok T
    // tokenize everything into one flat ids + offsets pair
    : ( Vec i ) ids ( vec_new [i] )
    : ( Vec i ) offs ( vec_new [i] )
    ( vec_push [i] offs 0 )
    : ~ i k 0
    ~ & ok < k nt {
        ?? ( vec_get [String] texts k ) {
            T t → {
                // per text into a fresh vec — embed_tokenize's maxseq
                // truncation is over the whole vec it is handed
                : ( Vec i ) tid ( vec_new [i] )
                ? ( embed_tokenize e ( string_data t ) tid ) {
                    : i tn ( vec_len [i] tid )
                    : ~ i j 0
                    ~ < j tn {
                        ?? ( vec_get [i] tid j ) { T x → { ( vec_push [i] ids x ) } F → {} }
                        = j + j 1
                    }
                    ( vec_push [i] offs ( vec_len [i] ids ) )
                } { = ok F }
            }
            F → { = ok F }
        }
        = k + k 1
    }
    ? ok {} { ^ ( __em_jerr 500 `embedding failed` ) }
    : ( Vec f ) flat ( __em_submit ids offs * nt dim normalize )
    ? > ( vec_len [f] flat ) 0 {} { ^ ( __em_jerr 500 `embedding failed` ) }
    // one per served request, not per text in a batch
    : ~ EmServe sv ( locked_take [EmServe] g_em )
    = . sv reqs + . sv reqs 1
    ( locked_restore [EmServe] g_em sv )
    // The body is built as ONE string, not a Json tree. A 64-text batch
    // is ~65k floats; as json_float nodes that is 65k allocations whose
    // frees each walk the panic-unwind journal the handler's panic→500
    // guard keeps — O(allocations²), measured at 3.8 s of a 3.9 s
    // request. The numbers go through the same nurl_str_float formatter
    // json_stringify uses, so the body is byte-identical to the tree's;
    // only the tree is gone. (json_str_lit still escapes the model
    // name — the one field that needs it.)
    : String bs ( string_from `{"embeddings":[` )
    = k 0
    ~ < k nt {
        ? > k 0 { ( string_push_char bs 44 ) } {}
        ( string_push_char bs 91 )
        : ~ i j 0
        ~ < j dim {
            ? > j 0 { ( string_push_char bs 44 ) } {}
            ?? ( vec_get [f] flat + * k dim j ) {
                T x → { ( string_push_float bs x ) }
                F → {}
            }
            = j + j 1
        }
        ( string_push_char bs 93 )
        = k + k 1
    }
    ( string_push_str bs `],"model":` )
    : Json mn ( json_str_lit g_em_name )
    : String mns ( json_stringify mn )
    ( string_push_str bs ( string_data mns ) )
    ( string_push_str bs `,"dimension":` )
    ( string_push_int bs dim )
    ( string_push_char bs 125 )
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ( response_set_body_str r ( string_data bs ) )
    ^ r
}

// Collect the strings under `key` — a bare string or an array of them —
// into `texts`. Returns T when the key was there and yielded something.
@ __em_collect Json root s key ( Vec String ) texts → b {
    : ~ b have F
    ?? ( json_obj_get root key ) {
        T tv → {
            ? ( json_is_str tv ) {
                ( vec_push [String] texts ( string_from ( json_str_data tv ) ) )
                = have T
            } {
                ? ( json_is_arr tv ) {
                    : i n ( json_arr_len tv )
                    : ~ i k 0
                    ~ < k n {
                        ?? ( json_arr_get tv k ) {
                            T el → {
                                ? ( json_is_str el ) {
                                    ( vec_push [String] texts ( string_from ( json_str_data el ) ) )
                                    = have T
                                } {}
                            }
                            F → {}
                        }
                        = k + k 1
                    }
                } {}
            }
        }
        F → {}
    }
    ^ have
}

@ __em_post HttpRequest req → HttpResponse {
    ? ( __em_authed req ) {} { ^ ( __em_jerr 401 `unauthorized — pass 'Authorization: Bearer <token>'` ) }
    // the body is raw bytes; JSON wants a NUL-terminated string
    : String bodys ( bytes_to_str . req body )
    : !Json JsonError parsed ( json_parse ( string_data bodys ) )
    ?? parsed {
        T root → {
            : ( Vec String ) texts ( vec_new [String] )
            // "text" is what this server has always taken; "texts" is
            // what the reference service (and this package's own
            // description) documents. Both, then — the plural first, so
            // a body carrying only it is not a 400.
            : ~ b have ( __em_collect root `texts` texts )
            ? ( __em_collect root `text` texts ) { = have T } {}
            : ~ b normalize T
            ?? ( json_obj_get root `normalize` ) {
                T nv → { = normalize ( json_as_bool nv ) }
                F → {}
            }
            ? & have > ( vec_len [String] texts ) 0 {} {
                ^ ( __em_jerr 400 `no text provided — body must be {"text": "..."} or {"text": ["...", ...]}` )
            }
            ^ ( __em_run texts normalize )
        }
        F je → {
            ^ ( __em_jerr 400 `request body is not valid JSON` )
        }
    }
}

@ __em_get HttpRequest req → HttpResponse {
    ? ( __em_authed req ) {} { ^ ( __em_jerr 401 `unauthorized — pass 'Authorization: Bearer <token>'` ) }
    : String txt ( __em_query_val ( string_data . req query ) `text` )
    ? > ( string_len txt ) 0 {} {
        ^ ( __em_jerr 400 `no text provided — GET /create_embedding?text=...` )
    }
    : String nq ( __em_query_val ( string_data . req query ) `normalize` )
    : b normalize ? != 0 ( nurl_str_eq ( string_data nq ) `false` ) { F } { T }
    : ( Vec String ) texts ( vec_new [String] )
    ( vec_push [String] texts txt )
    ^ ( __em_run texts normalize )
}

@ __em_health HttpRequest req → HttpResponse {
    : Embed e ( __em_model )
    : EmServe sv ( locked_get [EmServe] g_em )
    : Json o ( json_obj_new )
    // `healthy` either way: an engine whose weights are unloaded under
    // --unload-after answers the next request, it just pays the reload
    : b _s1 ( json_obj_set o `status` ( json_str_lit `healthy` ) )
    : b _s2 ( json_obj_set o `model` ( json_str_lit g_em_name ) )
    : b _s3 ( json_obj_set o `model_loaded` ( json_bool ( embed_loaded e ) ) )
    : b _u1 ( json_obj_set o `unload_after_s` ( json_int / . sv unload_ms 1000 ) )
    : b _u2 ( json_obj_set o `loads` ( json_int . sv loads ) )
    : b _u3 ( json_obj_set o `unloads` ( json_int . sv unloads ) )
    : b _u4 ( json_obj_set o `last_load_ms` ( json_int . sv load_ms ) )
    ? ! ( embed_loaded e ) {
        : b _u5 ( json_obj_set o `idle_s` ( json_int / ( elapsed_ms_since . sv idle_since ) 1000 ) )
    } {}
    : String be ( embed_backend e )
    : b _s4 ( json_obj_set o `device` ( json_str_lit ( string_data be ) ) )
    : b _s5 ( json_obj_set o `dimension` ( json_int ( embed_dim e ) ) )
    : b _s6 ( json_obj_set o `requests` ( json_int . sv reqs ) )
    : b _s7 ( json_obj_set o `max_seq` ( json_int ( embed_maxseq e ) ) )
    : String dn ( embed_device_name e )
    : b _s8 ( json_obj_set o `device_name` ( json_str_lit ( string_data dn ) ) )
    // What the device-buffer pool is holding, so "where did the VRAM go"
    // is a question the server answers instead of one an operator has to
    // reverse-engineer from nvidia-smi. Two plain integer loads while the
    // model thread may be allocating: a health report is allowed to be
    // one request stale, and nothing here dereferences the pool table.
    : b _s9 ( json_obj_set o `pool_blocks` ( json_int ( gk_pool_count ) ) )
    : b _s10 ( json_obj_set o `pool_idle_bytes` ( json_int ( gk_pool_idle_bytes ) ) )
    : HttpResponse r ( response_json 200 o )
    ^ r
}

// Serve `e` (borrowed for the server's lifetime). Blocks until stopped.
@ embed_serve Embed e s name s host i port s token i unload_s → i {
    ( locked_set [EmServe] g_em @ EmServe { @ ?Embed { T ( Embed_share e ) } 0 * unload_s 1000 ( monotonic_ns ) 1 0 0 T } )
    = g_em_token ( nurl_str_cat token `` )
    = g_em_name ( nurl_str_cat name `` )
    : ( @ v ) modelfn \ → v { ( __em_model_loop ) }
    // joined before this returns: the model thread reads the engine, and
    // the caller lets the engine go as soon as serving ends
    : !Thread ThreadErr model_th ( thread_spawn modelfn )
    ?? model_th {
        T _ → {}
        F _te → {
            ( nurl_eprint `embed: cannot start the model thread\n` )
            ^ 1
        }
    }
    ? > unload_s 0 {
        : ( @ v ) tickfn \ → v { ( __em_ticker ) }
        ?? ( thread_spawn_owned tickfn ) {
            T th → { ( thread_detach th ) }
            F _te → {
                ( nurl_eprint `embed: cannot start the unload timer — the weights stay loaded\n` )
                : ~ EmServe sv ( locked_take [EmServe] g_em )
                = . sv unload_ms 0
                ( locked_restore [EmServe] g_em sv )
            }
        }
    } {}

    : HttpApp a ( http_app_new )
    // Fiber-per-connection: connections are cheap, and the one thing
    // that must not overlap — the forward — has its own lock (__em_run).
    // Hardening: bounded bodies (16 MB of JSON text is ~2000 full-length
    // documents), a head cap, slowloris idle cut, a per-request
    // deadline, and panic → 500 (never down the server).
    ( http_app_async a 0 )
    ( http_app_body_max a 16777216 )
    ( http_app_head_max a 65536 )
    ( http_app_idle_ms a 30000 )
    ( http_app_request_timeout a 600000 )
    ( http_app_post a `/create_embedding` \ HttpRequest rq Params ps → HttpResponse { ^ ( __em_post rq ) } )
    ( http_app_get a `/create_embedding` \ HttpRequest rq Params ps → HttpResponse { ^ ( __em_get rq ) } )
    ( http_app_get a `/health` \ HttpRequest rq Params ps → HttpResponse { ^ ( __em_health rq ) } )
    ( http_app_get a `/` \ HttpRequest rq Params ps → HttpResponse { ^ ( __em_health rq ) } )

    : String msg ( string_from `embed serving on http://` )
    ( string_push_str msg host )
    ( string_push_char msg 58 )
    ( string_push_int msg port )
    ( string_push_str msg ` (POST /create_embedding, GET /health)` )
    ? == ( nurl_str_len token ) 0 { ( string_push_str msg ` — NO TOKEN, keep it on loopback` ) } {}
    ? > unload_s 0 {
        ( string_push_str msg `\nembed: the weights are released after ` )
        ( string_push_int msg unload_s )
        ( string_push_str msg ` s idle and reloaded on the next request` )
    } {}
    ( nurl_print ( string_data msg ) )
    ( nurl_print `\n` )

    : i rc ( http_app_listen a host port )
    ( __em_signal EM_STOP )
    ?? model_th { T th → { : i _j ( thread_join th ) } F _te → {} }
    : ~ EmServe sv ( locked_take [EmServe] g_em )
    = . sv model @ ?Embed { F }
    = . sv serving F
    ( locked_restore [EmServe] g_em sv )
    ^ rc
}
