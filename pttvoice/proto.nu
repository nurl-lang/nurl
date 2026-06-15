// pttvoice/proto.nu — the PTT voice wire frame that rides a transport payload
// (transport_send to one peer, or transport_broadcast to a group). The body is
// an Opus packet; a small header lets the receiver order frames and ignore
// anything that isn't a voice frame.
//
//   [ 'P' 'V' ][ type:1 ][ seq:u32 BE ][ opus bytes … ]
//   type 1 = VOICE.  (transport delivers whole messages, so the opus packet is
//   simply the rest of the buffer.)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

@ proto_type_voice → i { ^ 1 }
@ __pv_magic0 → i { ^ 80 }   // 'P'
@ __pv_magic1 → i { ^ 86 }   // 'V'

: VoiceMsg {
    i mtype
    i seq
    ( Vec u ) opus
}
@ voicemsg_free VoiceMsg m → v { ( vec_free [u] . m opus ) }

// Build a VOICE frame carrying `opus` at sequence `seq`.
@ proto_voice_encode i seq ( Vec u ) opus → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u ( __pv_magic0 ) )
    ( vec_push [u] b # u ( __pv_magic1 ) )
    ( vec_push [u] b # u ( proto_type_voice ) )
    ( bytes_push_u32_be b # u32 seq )
    ( vec_extend [u] b opus )
    ^ b
}

// Decode a transport payload into a VoiceMsg, or None if it is not a valid
// PTT voice frame (wrong magic / too short / unknown type).
@ proto_decode ( Vec u ) buf → ?VoiceMsg {
    : i n ( vec_len [u] buf )
    ? < n 7 { ^ @ ?VoiceMsg { F # VoiceMsg 0 } } {}
    : i m0 ?? ( vec_get [u] buf 0 ) { T x → # i x F → 0 }
    : i m1 ?? ( vec_get [u] buf 1 ) { T x → # i x F → 0 }
    ? | != m0 ( __pv_magic0 ) != m1 ( __pv_magic1 ) { ^ @ ?VoiceMsg { F # VoiceMsg 0 } } {}
    : i ty ?? ( vec_get [u] buf 2 ) { T x → # i x F → 0 }
    ? != ty ( proto_type_voice ) { ^ @ ?VoiceMsg { F # VoiceMsg 0 } } {}
    : i seq # i ?? ( bytes_read_u32_be buf 3 ) { T x → x F → # u32 0 }
    : ( Vec u ) opus ( vec_with_cap [u] ? > - n 7 0 - n 7 1 )
    : ~ i k 7
    ~ < k n { ?? ( vec_get [u] buf k ) { T x → ( vec_push [u] opus x ) F → {} } = k + k 1 }
    ^ @ ?VoiceMsg { T @ VoiceMsg { ( proto_type_voice ) seq opus } }
}
