// examples/pg_advanced.nu — the four advanced libpq capabilities NURL's
// postgres binding now covers end to end:
//
//   1. Binary result protocol  — request resultFormat = 1 and decode the
//      raw network-byte-order cells with the pg_get_*_bin accessors.
//   2. Asynchronous queries    — pg_send + pg_await dispatch a command
//      without blocking on its reply.
//   3. LISTEN / NOTIFY         — pg_listen + pg_notify_send + (after
//      pg_consume_input) pg_notifies for async pub/sub.
//   4. COPY                    — pg_put_copy_* to bulk-load and
//      pg_get_copy_data to bulk-dump rows.
//
// Build:  ./nurl.sh examples/pg_advanced.nu pg_advanced
// Run:    ./pg_advanced "host=127.0.0.1 port=5433 user=wau dbname=postgres"
//         (or set $PG_CONNINFO; falls back to libpq's PG* defaults)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/postgres.nu`

@ say s msg → v { ( nurl_print msg ) ( nurl_print `\n` ) }

@ sayi s label i n → v {
    ( nurl_print label ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
}

// Print the connection's error text, then exit non-zero.
@ die Connection c s ctx → v {
    : String em ( pg_err_msg c )
    ( nurl_print `FAIL [` ) ( nurl_print ctx ) ( nurl_print `]: ` )
    ( nurl_print ( string_data em ) ) ( nurl_print `\n` )
    ( string_free em )
    ( pg_close c )
    ( nurl_exit 1 )
}

// Unwrap a !PgResult, returning the live result (caller clears it).
@ must Connection c ! PgResult PgErr r s ctx → PgResult {
    ?? r {
        T res → ^ res
        F e → { ( die c ctx ) ^ @ PgResult { # s 0 } }
    }
}

// Run a !PgResult command for effect: unwrap, then clear the result.
@ okc Connection c ! PgResult PgErr r s ctx → v {
    ( pg_clear ( must c r ctx ) )
}

// Unwrap a !i command (pg_send / copy / notify family) for effect.
@ oki Connection c ! i PgErr r s ctx → v {
    ?? r { T _ → {} F e → ( die c ctx ) }
}

// ── 1. Binary result protocol ────────────────────────────────────
@ demo_binary Connection c → v {
    ( say `── 1. binary protocol ──` )
    // Text params in, binary columns out. We exercise int2/int4/int8,
    // bool, and float8 so every decoder runs.
    : PgParams ps ( pg_params 1 )
    ( pg_bind_int ps 1000000 )
    : !PgResult PgErr rr ( pg_exec_params_binary c
    `SELECT ($1::int8 * 1000)::int8, 42::int4, 7::int2, true, 3.5::float8` ps )
    : PgResult r ( must c rr `binary select` )
    ( nurl_print `  binary columns? ` )
    ( say ? ( pg_binary_tuples r ) `yes` `no` )
    ( sayi `  int8  = ` ( pg_get_i64_bin r 0 0 ) )
    ( sayi `  int4  = ` ( pg_get_i32_bin r 0 1 ) )
    ( sayi `  int2  = ` ( pg_get_i16_bin r 0 2 ) )
    ( nurl_print `  bool  = ` ) ( say ? ( pg_get_bool_bin r 0 3 ) `true` `false` )
    ( nurl_print `  f64   = ` )
    : s fs ( float_to_string ( pg_get_f64_bin r 0 4 ) )
    ( nurl_print fs ) ( nurl_print `\n` )
    ( pg_clear r )
}

// ── 2. Asynchronous queries ──────────────────────────────────────
@ demo_async Connection c → v {
    ( say `── 2. async query ──` )
    ?? ( pg_send c `SELECT count(*) FROM generate_series(1, 50000)` ) {
        F e → { ( say `  pg_send failed` ) ^ v }
        T _ → {}
    }
    ( nurl_print `  socket fd = ` ) ( nurl_print ( nurl_str_int ( pg_socket c ) ) ) ( nurl_print `\n` )
    : !PgResult PgErr rr ( pg_await c )
    : PgResult r ( must c rr `async await` )
    : String v0 ( pg_get_value r 0 0 )
    ( nurl_print `  count = ` ) ( nurl_print ( string_data v0 ) ) ( nurl_print `\n` )
    ( string_free v0 )
    ( pg_clear r )
}

// ── 3. LISTEN / NOTIFY ───────────────────────────────────────────
@ demo_notify Connection c → v {
    ( say `── 3. LISTEN / NOTIFY ──` )
    ( oki c ( pg_listen c `chan` ) `listen` )  // LISTEN chan
    ( oki c ( pg_notify_send c `chan` `hello-from-nurl` ) `notify` )
    // Server delivers async notifications on the next socket read.
    ( oki c ( pg_consume_input c ) `consume` )
    : ~ i got 0
    : ?PgNotify n ( pg_notifies c )
    ?? n {
        T note → {
            = got 1
            ( nurl_print `  notify on "` ) ( nurl_print ( string_data . note relname ) )
            ( nurl_print `" payload "` ) ( nurl_print ( string_data . note extra ) )
            ( nurl_print `" from pid ` ) ( nurl_print ( nurl_str_int . note be_pid ) )
            ( nurl_print `\n` )
            ( pg_notify_free note )
        }
        F _ → ( say `  (no notification received)` )
    }
}

// ── 4. COPY ──────────────────────────────────────────────────────
@ demo_copy Connection c → v {
    ( say `── 4. COPY ──` )
    ( okc c ( pg_exec c `CREATE TEMP TABLE pts (id int, label text)` ) `create temp` )

    // COPY FROM STDIN — bulk load three rows.
    ( oki c ( pg_copy_start c `COPY pts FROM STDIN` ) `copy in start` )
    ( oki c ( pg_put_copy_str c ( string_from `1\talpha\n` ) ) `put row 1` )
    ( oki c ( pg_put_copy_str c ( string_from `2\tbeta\n` ) ) `put row 2` )
    ( oki c ( pg_put_copy_str c ( string_from `3\tgamma\n` ) ) `put row 3` )
    ( oki c ( pg_put_copy_end c ) `copy end` )
    ( okc c ( pg_await c ) `copy in result` )  // COMMAND_OK
    ( say `  loaded 3 rows via COPY FROM STDIN` )

    // COPY TO STDOUT — bulk dump them back.
    ( oki c ( pg_copy_start c `COPY pts TO STDOUT` ) `copy out start` )
    : ~ i nrows 0
    : ~ i more 1
    ~ != 0 more {
        : ?String row ( pg_get_copy_data c )
        ?? row {
            T line → {
                = nrows + nrows 1
                ( nurl_print `  out: ` ) ( nurl_print ( string_data line ) )
                ( string_free line )
            }
            F _ → = more 0
        }
    }
    ( okc c ( pg_await c ) `copy out result` )  // COMMAND_OK
    ( sayi `  dumped rows = ` nrows )
}

@ main → i {
    : ( Vec String ) args ( env_args_list )
    : ~ s conninfo ``
    ?? ( vec_get [String] args 1 ) {
        T av → = conninfo ( string_data av )
        F _ → {
            ?? ( env_get `PG_CONNINFO` ) {
                T ev → = conninfo ( string_data ev )
                F _ → {}
            }
        }
    }

    : Connection c ( pg_connect conninfo )
    ? ! ( pg_ok c ) {
        : String em ( pg_err_msg c )
        ( nurl_print `connect error: ` ) ( nurl_print ( string_data em ) )
        ( string_free em )
        ( pg_close c )
        ^ 1
    } {}

    ( demo_binary c )
    ( demo_async c )
    ( demo_notify c )
    ( demo_copy c )

    ( pg_close c )
    ( say `\nAll four advanced Postgres capabilities exercised.` )
    ^ 0
}
