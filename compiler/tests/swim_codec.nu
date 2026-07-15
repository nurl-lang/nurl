// swim_codec.nu — offline round-trip test for the SWIM wire codec
// (stdlib/std/swim.nu). Encodes a PING-REQ with a 2-member gossip list,
// decodes it, and prints every field. Deliberately uses values above the
// signed thresholds — port 65535, seq 4000000001, incarnation 3000000000
// (all > 2^31) — so any u16/u32 sign-extension in the byte codec would
// corrupt the round trip and fail the golden.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/swim.nu`

@ main → i {
    : ( Vec Member ) g ( vec_new [Member] )
    ( vec_push [Member] g ( member_new `10.0.0.5` 50001 3000000000 @ MemberState { MDead } ) )
    ( vec_push [Member] g ( member_new `node-b` 65535 7 @ MemberState { MSuspect } ) )
    : SwimMsg m @ SwimMsg { @ SwimMsgType { MtPingReq } 4000000001
        ( string_from `host-a` ) 60000 ( string_from `host-t` ) 60001 g }

    : ( Vec u ) wire ( swim_msg_encode m )
    ( nurl_print `bytes=` ) ( nurl_print_int ( vec_len [u] wire ) )

    : !SwimMsg SwimErr d ( swim_msg_decode wire )
    ?? d {
        T m2 → {
            ( nurl_print `type=` ) ( nurl_print_int ( _mtype_code . m2 mtype ) )
            ( nurl_print `seq=` ) ( nurl_print_int . m2 seq )
            ( nurl_print `from=` ) ( nurl_print ( string_data . m2 from_host ) )
            ( nurl_print `:` ) ( nurl_print_int . m2 from_port )
            ( nurl_print `tgt=` ) ( nurl_print ( string_data . m2 target_host ) )
            ( nurl_print `:` ) ( nurl_print_int . m2 target_port )
            : i gn ( vec_len [Member] . m2 gossip )
            ( nurl_print `gossip=` ) ( nurl_print_int gn )
            : ~ i k 0
            ~ < k gn {
                ?? ( vec_get [Member] . m2 gossip k ) {
                    T mm → {
                        ( nurl_print `  ` ) ( nurl_print ( string_data . mm host ) )
                        ( nurl_print `:` ) ( nurl_print_int . mm port )
                        ( nurl_print ` inc=` ) ( nurl_print_int . mm incarnation )
                        ( nurl_print ` ` ) ( nurl_print ( member_state_name . mm state ) )
                        ( nurl_print `\n` )
                    }
                    F → {}
                }
                = k + k 1
            }
            ( swim_msg_free m2 )
        }
        F e → {
            : SwimErr se # SwimErr e
            ( nurl_print `decode err: ` ) ( nurl_print ( swim_err_name se ) ) ( nurl_print `\n` )
        }
    }

    // Truncated input → SwShort
    : ( Vec u ) tiny ( vec_new [u] )
    : !SwimMsg SwimErr d2 ( swim_msg_decode tiny )
    ?? d2 {
        T m3 → { ( nurl_print `unexpected ok\n` ) ( swim_msg_free m3 ) }
        F e → { : SwimErr se # SwimErr e ( nurl_print `empty → ` ) ( nurl_print ( swim_err_name se ) ) ( nurl_print `\n` ) }
    }

    ( swim_msg_free m )
    ( vec_free [u] wire )
    ( vec_free [u] tiny )
    ^ 0
}
