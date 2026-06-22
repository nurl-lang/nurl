// transport_policy.nu — offline test for stdlib/net/transport.nu path-policy
// state machine. Deterministic, no sockets: drives a PeerPath through the
// start-relayed → promote-to-direct → demote-when-quiet lifecycle and checks
// transport_pick at each step.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/net/transport.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ new_path i mode → s {
    : *PeerPath p # *PeerPath ( nurl_alloc Z PeerPath )
    = . p pubkey ( vec_new [u] )
    = . p mode mode
    = . p direct_known 0
    = . p idle 0
    ^ # s p
}

@ free_path s pp → v { : *PeerPath p # *PeerPath pp ( vec_free [u] . p pubkey ) ( nurl_free # s p ) }

@ main → i {
    // peer starts on the relay leg (has_relay = 1)
    : s pp ( new_path ( mode_relay ) )
    : *PeerPath p # *PeerPath pp
    ( pb `starts relayed: ` == ( transport_pick p 1 ) ( mode_relay ) )

    // a direct datagram arrives → promote to direct
    ( transport_note_direct p )
    ( pb `promoted to direct: ` == ( transport_pick p 1 ) ( mode_direct ) )
    ( pb `direct_known set: ` == . p direct_known 1 )

    // direct traffic keeps it direct
    ( transport_tick p 1 3 )
    ( pb `stays direct while active: ` == ( transport_pick p 1 ) ( mode_direct ) )

    // three silent ticks (idle_limit = 3) → demote back to relay
    ( transport_tick p 0 3 )
    ( pb `still direct after 1 idle: ` == ( transport_pick p 1 ) ( mode_direct ) )
    ( transport_tick p 0 3 )
    ( transport_tick p 0 3 )
    ( pb `demoted to relay after idle_limit: ` == ( transport_pick p 1 ) ( mode_relay ) )
    ( pb `direct_known cleared: ` == . p direct_known 0 )

    // re-promote works after a later direct datagram
    ( transport_note_direct p )
    ( pb `re-promote after demotion: ` == ( transport_pick p 1 ) ( mode_direct ) )

    // a peer with no relay configured and no direct path picks 'none'
    : s qq ( new_path ( mode_none ) )
    : *PeerPath q # *PeerPath qq
    ( pb `no relay + no direct → none: ` == ( transport_pick q 0 ) ( mode_none ) )

    ( free_path pp )
    ( free_path qq )
    ^ 0
}
