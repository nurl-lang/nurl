// Regression: inbound QoS 2 de-duplication policy (stdlib/ext/mqtt.nu).
// A QoS 2 receiver must hand each PUBLISH to the application exactly once
// even when the broker retransmits it (DUP). __mqtt_qos2_seen_or_add
// records a packet id and reports whether it was already pending;
// __mqtt_qos2_forget drops it on clean handshake completion; the set is
// bounded (cap 256, oldest evicted) so a stuck exchange can't grow it.
//
// Pure-logic test over the id set directly — no broker needed. Output is
// deterministic and baselined.

$ `stdlib/core/vec.nu`
$ `stdlib/ext/mqtt.nu`

@ yn b x → s { ^ ? x `T` `F` }

@ main → i {
    : ( Vec i ) s ( vec_new [i] )
    // First sighting of pid 5 → not a duplicate.
    ( nurl_print `first=` ) ( nurl_print ( yn ( __mqtt_qos2_seen_or_add s 5 ) ) ) ( nurl_print `\n` )
    // Same pid again → duplicate.
    ( nurl_print `dup=` ) ( nurl_print ( yn ( __mqtt_qos2_seen_or_add s 5 ) ) ) ( nurl_print `\n` )
    // A different pid → not a duplicate.
    ( nurl_print `other=` ) ( nurl_print ( yn ( __mqtt_qos2_seen_or_add s 6 ) ) ) ( nurl_print `\n` )
    ( nurl_print `len=` ) ( nurl_print ( nurl_str_int ( vec_len [i] s ) ) ) ( nurl_print `\n` )
    // Forget pid 5 (handshake completed) → set shrinks, and a later
    // sighting of 5 is treated as new again.
    ( __mqtt_qos2_forget s 5 )
    ( nurl_print `forgot_len=` ) ( nurl_print ( nurl_str_int ( vec_len [i] s ) ) ) ( nurl_print `\n` )
    ( nurl_print `readd=` ) ( nurl_print ( yn ( __mqtt_qos2_seen_or_add s 5 ) ) ) ( nurl_print `\n` )

    // Bounded capacity: fill to the cap, confirm an early id is still
    // tracked, then push one past the cap and confirm the oldest was
    // evicted (so it is no longer recognised).
    : ( Vec i ) s2 ( vec_new [i] )
    : ~ i j 1
    ~ <= j 256 { ( __mqtt_qos2_seen_or_add s2 j ) = j + j 1 }
    ( nurl_print `cap_len=` ) ( nurl_print ( nurl_str_int ( vec_len [i] s2 ) ) ) ( nurl_print `\n` )
    ( nurl_print `has1=` ) ( nurl_print ( yn ( __mqtt_qos2_seen_or_add s2 1 ) ) ) ( nurl_print `\n` )
    ( __mqtt_qos2_seen_or_add s2 257 )
    ( nurl_print `after257_len=` ) ( nurl_print ( nurl_str_int ( vec_len [i] s2 ) ) ) ( nurl_print `\n` )
    ( nurl_print `has1_after=` ) ( nurl_print ( yn ( __mqtt_qos2_seen_or_add s2 1 ) ) ) ( nurl_print `\n` )
    ( vec_free [i] s )
    ( vec_free [i] s2 )
    ^ 0
}
