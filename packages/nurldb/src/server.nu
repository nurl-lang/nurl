// packages/nurldb/src/server.nu — the database over TCP.
//
// One thread per connection, each with a session of its own (exec.nu);
// a checkpointer thread writes the dirty pages out every 30 seconds.
//
// The protocol is lines. The client sends one statement per line; the
// server answers
//
//   OK <n>        then n lines: the result as text (result_text)
//   ERR <reason>
//
// A connection ends when the client closes it; a transaction it left open
// is rolled back.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/time.nu`
$ `exec.nu`

// Lines out of a byte stream: what has arrived but not been read yet.
: LineReader {
    TcpConn c
    ( Vec u ) buf
    b eof
}

@ line_reader TcpConn c → LineReader { ^ @ LineReader { c ( vec_new [u] ) F } }

// The next line (without its newline); none at the end of the stream.
@ read_line_from inout LineReader r → ?String {
    ~ T {
        : ( Slice u ) b ( slice_from_vec [u] . r buf )
        : ~ i k 0
        ~ & < k ( slice_len [u] b ) != ( slice_byte b k ) 10 { = k + k 1 }
        ? < k ( slice_len [u] b ) {
            : String line ( string_new )
            ( string_push_window line b 0 ? & > k 0 == ( slice_byte b - k 1 ) 13 - k 1 k )
            : ( Vec u ) rest ( slice_to_vec [u] ( slice_window [u] b + k 1 - - ( slice_len [u] b ) k 1 ) )
            = . r buf rest
            ^ @ ?String { T line }
        } {}
        ? . r eof {
            ? == 0 ( vec_len [u] . r buf ) { ^ @ ?String { F } } {}
            : String line ( string_new )
            ( string_push_window line b 0 ( slice_len [u] b ) )
            = . r buf ( vec_new [u] )
            ^ @ ?String { T line }
        } {}
        ?? ( tcp_read_chunk . r c 65536 ) {
            T chunk → {
                ? == 0 ( vec_len [u] chunk ) { = . r eof T } { ( vec_extend [u] . r buf chunk ) }
            }
            F _ → { = . r eof T }
        }
    }
}

@ __count_lines String t → i {
    : ~ i n 0
    : ( Slice u ) b ( string_bytes t )
    : ~ i k 0
    ~ < k ( slice_len [u] b ) { ? == ( slice_byte b k ) 10 { = n + n 1 } {} = k + k 1 }
    ^ n
}

// Answer one statement on `c`.
@ __reply TcpConn c inout Session s String sql → b {
    : String out ?? ( session_exec s sql ) {
        T r → {
            : String body ( result_text r )
            : String head ( string_from `OK ` )
            ( string_push_int head ( __count_lines body ) )
            ( string_push_char head 10 )
            ( string_concat head body )
        }
        F e → {
            : String head ( string_from `ERR ` )
            ( string_push_str head ( string_data e ) )
            ( string_push_char head 10 )
            head
        }
    }
    ^ ?? ( tcp_write_all c ( slice_to_vec [u] ( string_bytes out ) ) ) { T _ → T F _ → F }
}

@ __serve_conn Db d TcpConn c → v {
    : ~ Session s ( session_new d )
    : ~ LineReader r ( line_reader ( mem_dup c ) )
    ~ T {
        ?? ( read_line_from r ) {
            T line → {
                ? > ( string_len ( string_trim line ) ) 0 {
                    ? ! ( __reply c s line ) { break } {}
                } {}
            }
            F → { break }
        }
    }
    ( session_close s )
    ( tcp_close_conn c )
}

// Serve `d` on `port` until the process is stopped.
@ serve Db d s host i port → !v String {
    : TcpListener l ?? ( tcp_listen host port ) { T x → x F e → { ^ @ !v String { F ( string_concat ( string_from `nurldb: cannot listen: ` ) ( string_from ( net_err_name e ) ) ) } } }
    : Atomic stop ( atomic_new 0 )
    : !Thread ThreadErr ck ( thread_spawn \ → v {
        ~ == ( atomic_load stop ) 0 {
            : ~ i k 0
            ~ & < k 300 == ( atomic_load stop ) 0 { ( sleep_ms 100 ) = k + k 1 }
            ( db_checkpoint d )
        }
    } )
    ~ T {
        ?? ( tcp_accept l ) {
            T c → {
                : !Thread ThreadErr t ( thread_spawn \ → v { ( __serve_conn d c ) } )
                ?? t { T h → { ( thread_detach h ) } F _ → {} }
            }
            F _ → { break }
        }
    }
    ( atomic_store stop 1 )
    ?? ck { T h → { ( thread_join h ) } F _ → {} }
    ^ @ !v String { T 0 }
}

// ── the client side ────────────────────────────────────────────────────

: Client {
    TcpConn c
    LineReader r
}

@ client_connect s host i port → !Client String {
    : TcpConn c ?? ( tcp_connect host port ) { T x → x F e → { ^ @ !Client String { F ( string_concat ( string_from `nurldb: cannot connect: ` ) ( string_from ( net_err_name e ) ) ) } } }
    ^ @ !Client String { T @ Client { ( mem_dup c ) ( line_reader c ) } }
}

// Send one statement; the server's answer as text, or its error.
@ client_exec inout Client cl String sql → !String String {
    : String line ( string_clone sql )
    ( string_push_char line 10 )
    ?? ( tcp_write_all . cl c ( slice_to_vec [u] ( string_bytes line ) ) ) { T _ → {} F _ → { ^ @ !String String { F ( string_from `nurldb: the connection is gone` ) } } }
    : String head ?? ( read_line_from . cl r ) { T h → h F → { ^ @ !String String { F ( string_from `nurldb: the connection is gone` ) } } }
    : s hs ( string_data head )
    ? & >= ( string_len head ) 4 != 0 ( nurl_str_eq ( nurl_str_slice hs 0 4 ) `ERR ` ) {
        ^ @ !String String { F ( string_from ( nurl_str_slice hs 4 - ( string_len head ) 4 ) ) }
    } {}
    : i n ? > ( string_len head ) 3 ( nurl_str_to_int ( nurl_str_slice hs 3 - ( string_len head ) 3 ) ) 0
    : String out ( string_new )
    : ~ i k 0
    ~ < k n {
        ?? ( read_line_from . cl r ) { T l → { ( string_push_str out ( string_data l ) ) ( string_push_char out 10 ) } F → { break } }
        = k + k 1
    }
    ^ @ !String String { T out }
}

@ client_close inout Client cl → v { ( tcp_close_conn . cl c ) }
