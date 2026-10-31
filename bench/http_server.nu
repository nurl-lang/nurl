// bench/http_server.nu — the NURL side of the HTTP peer benchmark (Tier
// D #3), built on the packages/http facade (the unified HTTP server
// interface — what a real NURL service would use), so the bench measures
// the surface users actually deploy.
//
// Two modes, one binary — the bench harness runs both:
//   * No arguments  → plaintext HTTP on 127.0.0.1:18080 (the default;
//                     unchanged from the original single-mode server).
//   * `<port> <cert.pem> <key.pem>` → HTTPS/TLS on that port, via the
//                     same HttpApp facade's `http_app_listen_tls`. cert
//                     and key are PEM paths (EC or RSA leaf).
//
// Routes (bench/run_http.sh measures `/` in its plaintext and TLS suites
// and the rest in its `db` suite):
//
//   /                  "Hello, World!\n" (14 bytes, text/plain)
//   /plaintext         "Hello, World!" (TechEmpower plaintext)
//   /json              {"message":"Hello, World!"}, serialised per request
//
// and, when DATABASE_URL names a Postgres (schema: bench/http_db_schema.sql),
// the TechEmpower database tests plus HttpArena's async-db profile:
//
//   /db                one random World row as JSON
//   /queries?queries=N N random World rows (N absent or bad → 1, clamped to 1..500),
//                      one query each, all N pipelined in one round trip
//   /fortunes          the Fortune table plus one row added at request time,
//                      sorted by message, as an escaped HTML table
//   /updates?queries=N N random World rows, each given a new random number
//                      (one UPDATE for the lot), the updated rows as JSON
//   /async-db?min=&max=&limit=
//                      items with min <= price <= max (no index: a scan),
//                      at most `limit` (1..50) of them, as {"items":[…],"count":n}
//
// The database side is one pipelined connection (packages/psql shares a
// connection between fibers: requests queue on the one socket and their
// answers come back in order), the same shape as the Rust peer's
// tokio-postgres client. No metrics, no access log — apples-to-apples
// with the Rust/Node sibling files in this directory. Ctrl+C (or
// SIGTERM) shuts down cleanly.
//
// Run: ./bench/run_http.sh  (compiles + starts every mode; see that
//                            script for the bench driver glue).

$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/sort.nu`
$ `packages/http/src/http.nu`
$ `packages/psql/src/pg.nu`

: Fortune { i id String message }

// ── request parameters ────────────────────────────────────────────────

// The integer value of query parameter `key`, or `dflt` when it is absent
// or not an integer.
@ query_int HttpRequest req s key i dflt → i {
    : ( Vec QueryPair ) ps ( parse_query ( string_data . req query ) )
    : i n ( vec_len [QueryPair] ps )
    : ~ i k 0
    ~ < k n {
        : QueryPair p ( vec_at [QueryPair] ps k )
        ? == 1 ( nurl_str_eq ( string_data . p key ) key ) {
            ^ ?? ( string_to_int . p value ) { T x → x F _ → dflt }
        } {}
        = k + k 1
    }
    ^ dflt
}

@ clamp i x i lo i hi → i {
    ? < x lo { ^ lo } {}
    ? > x hi { ^ hi } {}
    ^ x
}

// TechEmpower's `queries`: absent or not an integer → 1, then 1..500.
@ query_count HttpRequest req → i { ^ ( clamp ( query_int req `queries` 1 ) 1 500 ) }

// ── JSON ──────────────────────────────────────────────────────────────

@ world_json i id i rn → Json {
    : ( Vec Json ) kv ( vec_with_cap [Json] 4 )
    ( vec_push [Json] kv ( json_str_lit `id` ) )
    ( vec_push [Json] kv ( json_int id ) )
    ( vec_push [Json] kv ( json_str_lit `randomNumber` ) )
    ( vec_push [Json] kv ( json_int rn ) )
    ^ ( json_obj kv )
}

@ h_json → HttpResponse {
    : ( Vec Json ) kv ( vec_with_cap [Json] 2 )
    ( vec_push [Json] kv ( json_str_lit `message` ) )
    ( vec_push [Json] kv ( json_str_lit `Hello, World!` ) )
    ^ ( response_json 200 ( json_obj kv ) )
}

@ db_error PgErr e → HttpResponse { ^ ( response_text 500 ( pg_err_name e ) ) }

// ── TechEmpower database tests ────────────────────────────────────────

// A random World id, 1..10000.
@ world_id Rng g → i { ^ + 1 ( rng_below g 10000 ) }

// One World row's randomNumber.
@ world_get PgConn c i id → !i PgErr {
    : ( Vec PgVal ) ps ( vec_with_cap [PgVal] 1 )
    ( vec_push [PgVal] ps @ PgVal { PgInt id } )
    ?? ( pg_query_params c `SELECT id, randomnumber FROM world WHERE id = $1` ps ) {
        T r → { ^ @ !i PgErr { T ?? ( pg_row_i r 0 1 ) { T v → v F → 0 } } }
        F e → { ^ @ !i PgErr { F e } }
    }
}

@ h_db PgConn c Rng g → HttpResponse {
    : i id ( world_id g )
    ?? ( world_get c id ) {
        T rn → { ^ ( response_json 200 ( world_json id rn ) ) }
        F e → { ^ ( db_error e ) }
    }
}

// `n` random World ids.
@ world_ids Rng g i n → ( Vec i ) {
    : ( Vec i ) ids ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n { ( vec_push [i] ids ( world_id g ) ) = k + k 1 }
    ^ ids
}

// Their lookups' parameters: one set of one id each.
@ world_params ( Vec i ) ids → ( Vec ( Vec PgVal ) ) {
    : i n ( vec_len [i] ids )
    : ( Vec ( Vec PgVal ) ) sets ( vec_with_cap [( Vec PgVal )] n )
    : ~ i k 0
    ~ < k n {
        : ( Vec PgVal ) ps ( vec_with_cap [PgVal] 1 )
        ( vec_push [PgVal] ps @ PgVal { PgInt ( vec_at [i] ids k ) } )
        ( vec_push [( Vec PgVal )] sets ps )
        = k + k 1
    }
    ^ sets
}

// The rows of `ids`, looked up one query each — all of them pipelined in
// one round trip (pg_query_many) — their randomNumbers in order.
@ worlds_get PgConn c ( Vec i ) ids → !( Vec i ) PgErr {
    ?? ( pg_query_many c `SELECT id, randomnumber FROM world WHERE id = $1` ( world_params ids ) ) {
        T rs → {
            : i n ( vec_len [PgResult] rs )
            : ( Vec i ) rns ( vec_with_cap [i] n )
            : ~ i k 0
            ~ < k n {
                ( vec_push [i] rns ?? ( pg_row_i ( vec_at [PgResult] rs k ) 0 1 ) { T v → v F → 0 } )
                = k + k 1
            }
            ^ @ !( Vec i ) PgErr { T rns }
        }
        F e → { ^ @ !( Vec i ) PgErr { F e } }
    }
}

@ h_queries PgConn c Rng g i n → HttpResponse {
    : ( Vec i ) ids ( world_ids g n )
    ?? ( worlds_get c ids ) {
        T rns → {
            : ( Vec Json ) rows ( vec_with_cap [Json] n )
            : ~ i k 0
            ~ < k n {
                ( vec_push [Json] rows ( world_json ( vec_at [i] ids k ) ( vec_at [i] rns k ) ) )
                = k + k 1
            }
            ^ ( response_json 200 ( json_arr rows ) )
        }
        F e → { ^ ( db_error e ) }
    }
}

// `{a,b,c}`: a Postgres array literal, sent as text and cast in the SQL.
@ pg_int_array ( Vec i ) xs → String {
    : String out ( string_with_cap + 2 * 6 ( vec_len [i] xs ) )
    ( string_push_char out 123 )
    : i n ( vec_len [i] xs )
    : ~ i k 0
    ~ < k n {
        ? > k 0 { ( string_push_char out 44 ) } {}
        ( string_push_int out ( vec_at [i] xs k ) )
        = k + k 1
    }
    ( string_push_char out 125 )
    ^ out
}

@ h_updates PgConn c Rng g i n → HttpResponse {
    : ( Vec i ) ids ( world_ids g n )
    ?? ( worlds_get c ids ) { T _ → {} F e → { ^ ( db_error e ) } }
    : ( Vec i ) rns ( world_ids g n )
    : ~ i k 0
    // One statement for the lot, its rows in id order: two requests
    // updating overlapping rows then lock them in the same order and
    // cannot deadlock each other.
    : ( Vec i ) order ( vec_with_cap [i] n )
    ~ < k n { ( vec_push [i] order k ) = k + k 1 }
    ( sort_by [i] order \ i a i b → i { ^ - ( vec_at [i] ids a ) ( vec_at [i] ids b ) } )
    : ( Vec i ) sids ( vec_with_cap [i] n )
    : ( Vec i ) srns ( vec_with_cap [i] n )
    = k 0
    ~ < k n {
        : i at ( vec_at [i] order k )
        ( vec_push [i] sids ( vec_at [i] ids at ) )
        ( vec_push [i] srns ( vec_at [i] rns at ) )
        = k + k 1
    }
    : ( Vec PgVal ) ps ( vec_with_cap [PgVal] 2 )
    ( vec_push [PgVal] ps @ PgVal { PgText ( pg_int_array sids ) } )
    ( vec_push [PgVal] ps @ PgVal { PgText ( pg_int_array srns ) } )
    ?? ( pg_query_params c `UPDATE world SET randomnumber = v.rn FROM (SELECT unnest($1::int[]) AS id, unnest($2::int[]) AS rn) AS v WHERE world.id = v.id` ps ) {
        T _ → {}
        F e → { ^ ( db_error e ) }
    }
    : ( Vec Json ) rows ( vec_with_cap [Json] n )
    = k 0
    ~ < k n {
        ( vec_push [Json] rows ( world_json ( vec_at [i] ids k ) ( vec_at [i] rns k ) ) )
        = k + k 1
    }
    ^ ( response_json 200 ( json_arr rows ) )
}

// HTML-escape `text` onto `out`: & < > " ' — enough for element content
// and quoted attribute values alike.
@ push_escaped ( Vec u ) out s text → v {
    : ( Slice u ) bv ( slice_of_str text )
    : i n ( slice_len [u] bv )
    : ~ i k 0
    ~ < k n {
        : i ch ( slice_byte bv k )
        ? == ch 38 { ( bytes_extend_str out `&amp;` ) } {
            ? == ch 60 { ( bytes_extend_str out `&lt;` ) } {
                ? == ch 62 { ( bytes_extend_str out `&gt;` ) } {
                    ? == ch 34 { ( bytes_extend_str out `&quot;` ) } {
                        ? == ch 39 { ( bytes_extend_str out `&#39;` ) } {
                            ( vec_push [u] out # u ch )
                        } } } } }
        = k + k 1
    }
}

@ h_fortunes PgConn c → HttpResponse {
    : ( Vec PgVal ) none ( vec_new [PgVal] )
    : PgResult r ?? ( pg_query_params c `SELECT id, message FROM fortune` none ) {
        T x → x
        F e → { ^ ( db_error e ) }
    }
    : i n ( pg_result_nrows r )
    : ( Vec Fortune ) fs ( vec_with_cap [Fortune] + n 1 )
    : ~ i k 0
    ~ < k n {
        : i id ?? ( pg_row_i r k 0 ) { T v → v F → 0 }
        : String m ?? ( pg_row_s r k 1 ) { T v → v F → ( string_new ) }
        ( vec_push [Fortune] fs @ Fortune { id m } )
        = k + k 1
    }
    ( vec_push [Fortune] fs @ Fortune { 0 ( string_from `Additional fortune added at request time.` ) } )
    ( sort_by [Fortune] fs \ Fortune a Fortune b → i {
        ^ ( nurl_str_cmp ( string_data . a message ) ( string_data . b message ) )
    } )
    : HttpResponse resp ( response_new 200 )
    ( response_set_header resp `Content-Type` `text/html; charset=utf-8` )
    : ( Vec u ) out . resp body
    ( bytes_extend_str out `<!DOCTYPE html><html><head><title>Fortunes</title></head><body><table><tr><th>id</th><th>message</th></tr>` )
    = k 0
    : i m ( vec_len [Fortune] fs )
    ~ < k m {
        : Fortune f ( vec_at [Fortune] fs k )
        ( bytes_extend_str out `<tr><td>` )
        ( bytes_push_int out . f id )
        ( bytes_extend_str out `</td><td>` )
        ( push_escaped out ( string_data . f message ) )
        ( bytes_extend_str out `</td></tr>` )
        = k + k 1
    }
    ( bytes_extend_str out `</table></body></html>` )
    ^ resp
}

// ── HttpArena async-db ────────────────────────────────────────────────

// One items row as {"id":…,"name":…,"category":…,"price":…,"quantity":…,
// "active":…,"tags":[…],"rating":{"score":…,"count":…}}.
@ item_json PgResult r i k → Json {
    : ( Vec Json ) kv ( vec_with_cap [Json] 16 )
    ( vec_push [Json] kv ( json_str_lit `id` ) )
    ( vec_push [Json] kv ( json_int ?? ( pg_row_i r k 0 ) { T v → v F → 0 } ) )
    ( vec_push [Json] kv ( json_str_lit `name` ) )
    ( vec_push [Json] kv ( json_str_lit ( string_data ( pg_result_cell r k 1 ) ) ) )
    ( vec_push [Json] kv ( json_str_lit `category` ) )
    ( vec_push [Json] kv ( json_str_lit ( string_data ( pg_result_cell r k 2 ) ) ) )
    ( vec_push [Json] kv ( json_str_lit `price` ) )
    ( vec_push [Json] kv ( json_int ?? ( pg_row_i r k 3 ) { T v → v F → 0 } ) )
    ( vec_push [Json] kv ( json_str_lit `quantity` ) )
    ( vec_push [Json] kv ( json_int ?? ( pg_row_i r k 4 ) { T v → v F → 0 } ) )
    ( vec_push [Json] kv ( json_str_lit `active` ) )
    ( vec_push [Json] kv ( json_bool ?? ( pg_row_b r k 5 ) { T v → v F → F } ) )
    ( vec_push [Json] kv ( json_str_lit `tags` ) )
    ( vec_push [Json] kv ?? ( json_parse ( string_data ( pg_result_cell r k 6 ) ) ) { T j → j F _ → ( json_arr_new ) } )
    : ( Vec Json ) rating ( vec_with_cap [Json] 4 )
    ( vec_push [Json] rating ( json_str_lit `score` ) )
    ( vec_push [Json] rating ( json_int ?? ( pg_row_i r k 7 ) { T v → v F → 0 } ) )
    ( vec_push [Json] rating ( json_str_lit `count` ) )
    ( vec_push [Json] rating ( json_int ?? ( pg_row_i r k 8 ) { T v → v F → 0 } ) )
    ( vec_push [Json] kv ( json_str_lit `rating` ) )
    ( vec_push [Json] kv ( json_obj rating ) )
    ^ ( json_obj kv )
}

@ items_json ( Vec Json ) items → Json {
    : i n ( vec_len [Json] items )
    : ( Vec Json ) kv ( vec_with_cap [Json] 4 )
    ( vec_push [Json] kv ( json_str_lit `items` ) )
    ( vec_push [Json] kv ( json_arr items ) )
    ( vec_push [Json] kv ( json_str_lit `count` ) )
    ( vec_push [Json] kv ( json_int n ) )
    ^ ( json_obj kv )
}

@ h_async_db PgConn c HttpRequest req → HttpResponse {
    : i lo ( query_int req `min` 10 )
    : i hi ( query_int req `max` 50 )
    : i limit ( clamp ( query_int req `limit` 50 ) 1 50 )
    : ( Vec PgVal ) ps ( vec_with_cap [PgVal] 3 )
    ( vec_push [PgVal] ps @ PgVal { PgInt lo } )
    ( vec_push [PgVal] ps @ PgVal { PgInt hi } )
    ( vec_push [PgVal] ps @ PgVal { PgInt limit } )
    : ( Vec Json ) items ( vec_new [Json] )
    ?? ( pg_query_params c `SELECT id, name, category, price, quantity, active, tags, rating_score, rating_count FROM items WHERE price BETWEEN $1 AND $2 LIMIT $3` ps ) {
        T r → {
            : i n ( pg_result_nrows r )
            : ~ i k 0
            ~ < k n { ( vec_push [Json] items ( item_json r k ) ) = k + k 1 }
        }
        // HttpArena: a database that is down answers an empty list.
        F _ → {}
    }
    ^ ( response_json 200 ( items_json items ) )
}

// ── main ──────────────────────────────────────────────────────────────

// Serve `a` until SIGTERM: TLS when three arguments are supplied (port,
// cert, key), otherwise the original plaintext default. argv[0] is the
// program name, so a TLS invocation has argc == 4.
@ listen HttpApp a → i {
    // Fiber-per-connection on the M:N async runtime, one worker pthread
    // per core (the deployment default a scaling NURL service uses) —
    // apples-to-apples with tokio's default multi-thread runtime in the
    // Rust peer. The old 10-thread pool pinned one worker per keep-alive
    // connection, so any concurrency above 10 starved in the bench.
    ( http_app_async a 0 )
    ? >= ( nurl_argv_count ) 4 {
        : i port ( nurl_str_to_int ( nurl_argv_get 1 ) )
        ^ ( http_app_listen_tls a `127.0.0.1` port ( nurl_argv_get 2 ) ( nurl_argv_get 3 ) )
    } {}
    ^ ( http_app_listen a `127.0.0.1` 18080 )
}

@ main → i {
    : HttpApp a ( http_app_new )
    ( http_app_get a `/` \ HttpRequest req Params params → HttpResponse {
        ^ ( response_text 200 `Hello, World!\n` )
    } )
    ( http_app_get a `/plaintext` \ HttpRequest req Params params → HttpResponse {
        ^ ( response_text 200 `Hello, World!` )
    } )
    ( http_app_get a `/json` \ HttpRequest req Params params → HttpResponse { ^ ( h_json ) } )

    // The database routes exist only when a database is configured, so
    // the plaintext and TLS suites run the same binary with no Postgres.
    // The routes capture the connection, so the server runs inside its
    // scope.
    : String url ?? ( env_get `DATABASE_URL` ) { T x → x F → { ^ ( listen a ) } }
    : PgConn c ?? ( pg_connect_url ( string_data url ) ) {
        T x → x
        F e → {
            ( nurl_eprint `http_server: DATABASE_URL: ` )
            ( nurl_eprint ( pg_err_name e ) )
            ( nurl_eprint `\n` )
            ^ 1
        }
    }
    : Atomic seeds ( atomic_new 1 )
    : PgConn c1 ( PgConn_share c )
    : Atomic s1 ( Atomic_share seeds )
    ( http_app_get a `/db` \ HttpRequest req Params params → HttpResponse {
        ^ ( h_db c1 ( rng_seed ( atomic_add s1 1 ) ) )
    } )
    : PgConn c2 ( PgConn_share c )
    : Atomic s2 ( Atomic_share seeds )
    ( http_app_get a `/queries` \ HttpRequest req Params params → HttpResponse {
        ^ ( h_queries c2 ( rng_seed ( atomic_add s2 1 ) ) ( query_count req ) )
    } )
    : PgConn c3 ( PgConn_share c )
    ( http_app_get a `/fortunes` \ HttpRequest req Params params → HttpResponse {
        ^ ( h_fortunes c3 )
    } )
    : PgConn c4 ( PgConn_share c )
    : Atomic s4 ( Atomic_share seeds )
    ( http_app_get a `/updates` \ HttpRequest req Params params → HttpResponse {
        ^ ( h_updates c4 ( rng_seed ( atomic_add s4 1 ) ) ( query_count req ) )
    } )
    : PgConn c5 ( PgConn_share c )
    ( http_app_get a `/async-db` \ HttpRequest req Params params → HttpResponse {
        ^ ( h_async_db c5 req )
    } )
    ^ ( listen a )
}
