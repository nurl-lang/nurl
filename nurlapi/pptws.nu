// nurlapi/pptws.nu — WebSocket voice relay for the PTT-Chat demo.
//
// The browser cannot reach the native pubkey overlay (raw UDP/TCP), so this is
// the browser-facing leg: a WebSocket endpoint at /pptws/<channel> served on
// the SAME port as the playground via the HTTP server's upgrade hook
// (server_set_upgrade). It is the exact group-multicast shape of net/relay.nu's
// GSEND — a channel is a group, and a binary frame from one member is forwarded
// to every OTHER member of the same channel (relay-when-direct-isn't-possible,
// which is always true from a browser). Text frames carry presence (member
// count) so clients see who is on the channel.
//
// Each connection runs the WS frame loop synchronously on its serving worker
// (the upgrade hook took over the conn); a shared, mutex-protected registry
// lets one member's loop write to the others, each conn guarded by its own
// write mutex.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/ext/http_full.nu`
$ `stdlib/core/rcbox.nu`

: PptMemberImpl {
    TcpConn conn  // the server's; the upgrade hook's caller closes it
    Mutex wlock  // serialise concurrent writes to this conn
    String channel
    i alive  // 1 = connected, 0 = gone / write failed
}
// One member, shared by its connection's loop and the registry: the last
// copy releases it (its write mutex and channel name with it).
: PptMember { s ctl }

@ PptMember_drop sink PptMember h → v {
    ( mem_forget h )
    ( rcbox_release [PptMemberImpl] # i . h ctl )
}

unsafe @ PptMember_share PptMember h → PptMember { ^ @ PptMember { # s ( rcbox_share # i . h ctl ) } }

unsafe @ __ppt_m PptMember h → *PptMemberImpl { ^ ( rcbox_ptr [PptMemberImpl] # i . h ctl ) }

: PptReg {
    ( Vec PptMember ) members
    Mutex lock  // guards the member list + all fan-out writes
}
: ~ i g_ppt_reg 0  // *PptReg as int (set once in ppt_install)

unsafe @ __ppt_reg → *PptReg { ^ # *PptReg g_ppt_reg }

// channel id from "/pptws/<id>"  ("/pptws/" is 7 chars) → "<id>", default public
@ __ppt_chan String path → String {
    : i plen ( string_len path )
    ? <= plen 7 { ^ ( string_from `public` ) } {}
    : String c ( string_substr path 7 - plen 7 )
    ? == ( string_len c ) 0 { ^ ( string_from `public` ) } {}
    ^ c
}

@ __ppt_same String a String b → b { ^ != 0 ( nurl_str_eq ( string_data a ) ( string_data b ) ) }

// write under the per-conn write lock; mark the member dead on any write error
unsafe @ __ppt_send_bin * PptMemberImpl m ( Vec u ) payload → v {
    ? != . m alive 1 { ^ v } {}
    ( mutex_lock . m wlock )
    : !v WsErr wr ( ws_send_binary . m conn payload )
    ?? wr { T _ → {} F _ → { = . m alive 0 } }
    ( mutex_unlock . m wlock )
}

unsafe @ __ppt_send_text * PptMemberImpl m s text → v {
    ? != . m alive 1 { ^ v } {}
    ( mutex_lock . m wlock )
    : !v WsErr wr ( ws_send_text . m conn text )
    ?? wr { T _ → {} F _ → { = . m alive 0 } }
    ( mutex_unlock . m wlock )
}

unsafe @ __ppt_count * PptReg reg String chan → i {
    : i n ( vec_len [PptMember] . reg members )
    : ~ i c 0 : ~ i k 0
    ~ < k n {
        ?? ( vec_get [PptMember] . reg members k ) {
            T x → { : *PptMemberImpl m ( __ppt_m x ) ? & == . m alive 1 ( __ppt_same . m channel chan ) { = c + c 1 } {} }
            F → {}
        }
        = k + k 1
    }
    ^ c
}

// presence: tell everyone on `chan` the current member count
unsafe @ __ppt_presence * PptReg reg String chan → v {
    ( mutex_lock . reg lock )
    : i cnt ( __ppt_count reg chan )
    : String js ( string_from `{"type":"presence","count":` )
    ( string_push_int js cnt )
    ( string_push_str js `}` )
    : i n ( vec_len [PptMember] . reg members )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [PptMember] . reg members k ) {
            T x → { : *PptMemberImpl m ( __ppt_m x ) ? ( __ppt_same . m channel chan ) { ( __ppt_send_text m ( string_data js ) ) } {} }
            F → {}
        }
        = k + k 1
    }
    ( mutex_unlock . reg lock )
}

// forward one voice frame to every OTHER member on the sender's channel
unsafe @ __ppt_forward * PptReg reg * PptMemberImpl from ( Vec u ) payload → v {
    ( mutex_lock . reg lock )
    : i n ( vec_len [PptMember] . reg members )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [PptMember] . reg members k ) {
            T x → {
                : *PptMemberImpl m ( __ppt_m x )
                ? & != # i m # i from ( __ppt_same . m channel . from channel ) { ( __ppt_send_bin m payload ) } {}
            }
            F → {}
        }
        = k + k 1
    }
    ( mutex_unlock . reg lock )
}

unsafe @ __ppt_join * PptReg reg TcpConn conn String chan → PptMember {
    : PptMember h @ PptMember { # s ( rcbox_new [PptMemberImpl] @ PptMemberImpl { conn ( mutex_new ) ( string_from ( string_data chan ) ) 1 } ) }
    ( mutex_lock . reg lock )
    ( vec_push [PptMember] . reg members ( PptMember_share h ) )
    ( mutex_unlock . reg lock )
    ^ h
}

// The registry's copy goes; the connection's own goes with its scope.
unsafe @ __ppt_leave * PptReg reg PptMember h → v {
    ( mutex_lock . reg lock )
    : i n ( vec_len [PptMember] . reg members )
    : ~ i k 0
    : ~ b removed F
    ~ & ! removed < k n {
        : ~ b hit F
        ?? ( vec_get [PptMember] . reg members k ) { T x → { = hit == # i . x ctl # i . h ctl } F → {} }
        ? hit { ?? ( vec_remove [PptMember] . reg members k ) { T _ → {} F → {} } = removed T } {}
        = k + k 1
    }
    ( mutex_unlock . reg lock )
}

// per-connection frame loop: forward binary (voice), answer ping, end on close
unsafe @ __ppt_loop * PptReg reg * PptMemberImpl me TcpConn conn → v {
    : WsLimits lim @ WsLimits { 262144 1048576 30000 64 }
    : ~ b done F
    ~ ! done {
        : !WsFrame WsErr fr ( ws_read_frame conn lim )
        ?? fr {
            T f → {
                : i op . f opcode
                ? == op ( ws_opcode_binary ) { ( __ppt_forward reg me . f payload ) } {}
                ? == op ( ws_opcode_close ) { = done T } {}
                ? == op ( ws_opcode_ping ) {
                    ( mutex_lock . me wlock )
                    : !v WsErr _p ( ws_send_pong conn . f payload )
                    ?? _p { T _ → {} F _ → {} }
                    ( mutex_unlock . me wlock )
                } {}
            }
            F _ → { = done T }
        }
        ? != . me alive 1 { = done T } {}
    }
}

// Install the /pptws/<channel> WebSocket relay as the server's upgrade hook.
// Call once before server_run.
unsafe @ ppt_install → v {
    : *PptReg reg # *PptReg ( nurl_alloc Z PptReg )
    = . reg members ( vec_new [PptMember] )
    = . reg lock ( mutex_new )
    = g_ppt_reg # i reg
    ( server_set_upgrade \ TcpConn conn HttpRequest req → b {
        ? ! ( string_starts_with . req path `/pptws/` ) { ^ F } {}
        ? ! ( ws_is_upgrade req ) { ^ F } {}
        : !v WsErr hr ( ws_perform_handshake conn req )
        : ~ b ok F
        ?? hr { T _ → { = ok T } F _ → {} }
        ? ! ok { ^ T } {}
        : String chan ( __ppt_chan . req path )
        ( tcp_set_timeout conn 30000 )
        : *PptReg r ( __ppt_reg )
        : PptMember me ( __ppt_join r conn chan )
        ( __ppt_presence r chan )
        ( __ppt_loop r ( __ppt_m me ) conn )
        ( __ppt_leave r me )
        ( __ppt_presence r chan )
        ^ T
    } )
}
