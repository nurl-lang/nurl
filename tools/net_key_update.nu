// Independent OpenSSL peer drives updates through blocking and queued I/O.
$ `stdlib/std/net.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/time.nu`

: ~ i ku_port 0
: ~ i ku_role 0
: ~ i ku_mode 0
: ~ s ku_cert ``
: ~ s ku_key ``
: ~ i ku_result 2

@ ku_open → !TcpConn NetErr {
    ? == ku_role 0 { ^ ( tcp_connect_tls `127.0.0.1` ku_port `localhost` 0 ) } {}
    : TcpListener listener \ ( tcp_listen_tls `127.0.0.1` 0 ku_cert ku_key )
    : String addr ( tcp_local_addr listener )
    ( nurl_println ( string_data addr ) ) ( nurl_flush_stdout )
    ( string_free addr )
    : !TcpConn NetErr accepted ( tcp_accept listener )
    ( tcp_close_listener listener )
    ^ accepted
}

@ ku_run → i {
    : TcpConn conn ?? ( ku_open ) { T c → c F e → { ( nurl_eprintln ( net_err_name e ) ) ^ 2 } }
    ( tcp_set_timeout conn 3000 )
    ( tcp_set_write_deadline conn + ( monotonic_ns ) 5000000000 )
    : ( Vec u ) got ( vec_new [u] )
    : ( Vec u ) pending ( vec_new [u] )
    : ~ i offset 0
    : ~ i total 0
    : ~ i rc 0
    ~ & == rc 0 | < total 131072 < offset ( vec_len [u] pending ) {
        ( vec_clear [u] got )
        : !i NetErr read ? == % ku_mode 2 1 ( tcp_try_read_into conn got 16384 ) ( tcp_read_into conn got 16384 )
        ?? read {
            T count → { = total + total count }
            F e → { ( nurl_eprintln ( net_err_name e ) ) = rc 1 }
        }
        ? == rc 0 {
            ? == % ku_mode 2 0 {
                ?? ( tcp_write_all conn got ) { T _ → {} F e → { ( nurl_eprintln ( net_err_name e ) ) = rc 1 } }
            } {
                ?? ( tcp_prepare_write conn got ) {
                    T wire → { ( vec_extend [u] pending wire ) ( vec_free [u] wire ) }
                    F e → { ( nurl_eprintln ( net_err_name e ) ) = rc 1 }
                }
                ? < offset ( vec_len [u] pending ) {
                    ?? ( tcp_try_write_wire conn pending offset ) {
                        T count → { = offset + offset count }
                        F e → { ( nurl_eprintln ( net_err_name e ) ) = rc 1 }
                    }
                } {}
                ? == offset ( vec_len [u] pending ) { ( vec_clear [u] pending ) = offset 0 } {}
                ? == ( vec_len [u] got ) 0 {
                    : i ready ( tcp_wait_io conn T < offset ( vec_len [u] pending ) 100 )
                } {}
            }
        } {}
    }
    ( vec_free [u] got ) ( vec_free [u] pending )
    ( tcp_close_conn conn )
    ^ rc
}

@ main → i {
    ? != ( nurl_argv_count ) 6 { ^ 2 } {}
    = ku_port ( nurl_str_to_int ( nurl_argv_get 1 ) )
    = ku_role ( nurl_str_to_int ( nurl_argv_get 2 ) )
    = ku_mode ( nurl_str_to_int ( nurl_argv_get 3 ) )
    : s cert ( nurl_argv_get 4 ) : s key ( nurl_argv_get 5 )
    = ku_cert cert = ku_key key
    ? >= ku_mode 2 {
        ( runtime_init 1 )
        : Fiber worker ( spawn_owned \ → v { = ku_result ( ku_run ) } )
        ( runtime_run ) ( runtime_shutdown )
    } { = ku_result ( ku_run ) }
    ^ ku_result
}
