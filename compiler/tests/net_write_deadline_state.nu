// The freestanding socket provider keeps an absolute write budget under
// an injected clock, without changing its read/idle timeout or fd reuse.
$ `stdlib/net/socket.nu`

@ main → i {
    : *NetStack net ( stack_new 2199023255553 2130706433 4278190080 0 )
    : *TcpStack tcp ( tstack_new net 1000 )
    : *SockTab sockets ( sock_new tcp 2130706433 )
    : i fd ( sock_listen sockets 0 0 4 )
    : ~ i failures 0
    ? != ( sock_write_wait_ms sockets fd 1000000 ) -1 { = failures + failures 1 } {}
    ( sock_set_timeout sockets fd 1000 )
    ( sock_set_write_deadline sockets fd 101000001 )
    ? != ( sock_write_deadline sockets fd ) 101000001 { = failures + failures 1 } {}
    ? != ( sock_write_wait_ms sockets fd 1000000 ) 101 { = failures + failures 1 } {}
    ? != ( sock_write_wait_ms sockets fd 101000000 ) 1 { = failures + failures 1 } {}
    ? != ( sock_write_wait_ms sockets fd 101000001 ) 0 { = failures + failures 1 } {}
    ? != ( sock_err sockets fd ) ( sock_err_again ) { = failures + failures 1 } {}
    ? != ( sock_timeout sockets fd ) 1000 { = failures + failures 1 } {}
    ( sock_set_write_deadline sockets fd 0 )
    ? != ( sock_write_wait_ms sockets fd 500000000 ) 1000 { = failures + failures 1 } {}
    ( sock_set_write_deadline sockets fd 500000001 )
    ( sock_set_timeout sockets fd 20 )
    ? != ( sock_write_wait_ms sockets fd 0 ) 20 { = failures + failures 1 } {}
    ( sock_close sockets fd 0 )
    : i reused ( sock_listen sockets 0 0 4 )
    ? != ( sock_write_deadline sockets reused ) 0 { = failures + failures 1 } {}
    ( sock_close sockets reused 0 )
    ( sock_free sockets )
    ( tstack_free tcp )
    ( stack_free net )
    ( nurl_print ? == failures 0 `write deadline state: ok\n` `write deadline state: FAIL\n` )
    ^ ? == failures 0 0 1
}
