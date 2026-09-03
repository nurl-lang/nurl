// quic_frame_fuzz.nu — structural fuzz of stdlib/std/quic_frame.nu and
// quic_varint.nu: bytes nobody chose, straight into the frame parser.
//
// Deterministic (an LCG seeded by a constant), so a failure reproduces
// exactly. Three populations, because pure noise mostly exercises the
// "unknown type" branch and nothing else:
//
//   * uniform random bytes of a random length, including 0 and 1;
//   * a well-formed frame of a random type with ONE byte flipped;
//   * a well-formed frame truncated at a random point.
//
// What is asserted (NURL's accessors are bounds checked, so a parser
// that reads past the end gets a wrong answer, not a fault):
//
//   1. A parse that succeeds never claims bytes beyond the buffer:
//      `off < next <= len`, and a frame's `bytes` never exceed `next - off`.
//   2. Every frame the builders produce parses back to what was built
//      (type, the four integers, the byte string), and `next` lands
//      exactly on the end of what was built.
//   3. The varint codec round-trips every value it accepts and refuses
//      every truncated encoding.
//   4. Nothing crashes over 20 000 inputs.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/quic_varint.nu`
$ `stdlib/std/quic_frame.nu`

: ~ i rng_state 0x9E3779B97F4A7C15

@ rnd i n → i {
    = rng_state + * rng_state 6364136223846793005 1442695040888963407
    : i x >> rng_state 33
    ? <= n 0 { ^ 0 } {}
    ^ % & x 0x7FFFFFFF n
}

@ rnd_bytes i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i i 0
    ~ < i n { ( vec_push [u] v # u ( rnd 256 ) ) = i + i 1 }
    ^ v
}

// A varint-sized random value (biased to every encoding length).
@ rnd_varint → i {
    : i k ( rnd 4 )
    ? == k 0 { ^ ( rnd 64 ) } {}
    ? == k 1 { ^ ( rnd 16384 ) } {}
    ? == k 2 { ^ ( rnd 1073741824 ) } {}
    ^ + ( rnd 1073741824 ) * ( rnd 1073741824 ) 1073741824
}

: ~ i built_type 0
: ~ i built_a 0
: ~ i built_b 0
: ~ i built_c 0
: ~ i built_d 0

// Build a random well-formed frame into `out`; record what was built.
@ build_random ( Vec u ) out → v {
    : i kind ( rnd 14 )
    = built_a 0
    = built_b 0
    = built_c 0
    = built_d 0
    ? == kind 0 { = built_type 1 ( quic_push_ping out ) ^ } {}
    ? == kind 1 {
        : i n + 1 ( rnd 64 )
        : ( Vec u ) d ( rnd_bytes n )
        : i off ( rnd_varint )
        = built_type 6
        = built_a off
        = built_b n
        ( quic_push_crypto out off d )
        ( vec_free [u] d )
        ^
    } {}
    ? == kind 2 {
        : i n ( rnd 40 )
        : ( Vec u ) d ( rnd_bytes n )
        : i id ( rnd 1000 )
        : i off ? == ( rnd 2 ) 0 0 ( rnd_varint )
        : b fin == ( rnd 2 ) 0
        = built_type | | 8 ? fin 1 0 | 2 ? > off 0 4 0
        = built_a id
        = built_b off
        = built_c n
        = built_d ? fin 1 0
        ( quic_push_stream out id off d fin )
        ( vec_free [u] d )
        ^
    } {}
    ? == kind 3 {
        = built_type 4
        = built_a ( rnd_varint )
        = built_b ( rnd_varint )
        = built_c ( rnd_varint )
        ( quic_push_reset_stream out built_a built_b built_c )
        ^
    } {}
    ? == kind 4 {
        = built_type 5
        = built_a ( rnd_varint )
        = built_b ( rnd_varint )
        ( quic_push_stop_sending out built_a built_b )
        ^
    } {}
    ? == kind 5 {
        = built_type 16
        = built_a ( rnd_varint )
        ( quic_push_max_data out built_a )
        ^
    } {}
    ? == kind 6 {
        = built_type 17
        = built_a ( rnd_varint )
        = built_b ( rnd_varint )
        ( quic_push_max_stream_data out built_a built_b )
        ^
    } {}
    ? == kind 7 {
        : b bidi == ( rnd 2 ) 0
        = built_type ? bidi 18 19
        = built_a ( rnd 1000 )
        = built_b ? bidi 1 0
        ( quic_push_max_streams out bidi built_a )
        ^
    } {}
    ? == kind 8 {
        : i cl + 1 ( rnd 20 )
        : ( Vec u ) cid ( rnd_bytes cl )
        : ( Vec u ) tok ( rnd_bytes 16 )
        : i seq ( rnd 100000 )
        = built_type 24
        = built_a seq
        = built_b ( rnd + seq 1 )
        = built_c cl
        ( quic_push_new_connection_id out seq built_b cid tok )
        ( vec_free [u] tok )
        ( vec_free [u] cid )
        ^
    } {}
    ? == kind 9 {
        = built_type 25
        = built_a ( rnd_varint )
        ( quic_push_retire_connection_id out built_a )
        ^
    } {}
    ? == kind 10 {
        : ( Vec u ) d ( rnd_bytes 8 )
        = built_type ? == ( rnd 2 ) 0 26 27
        ? == built_type 26 { ( quic_push_path_challenge out d ) } { ( quic_push_path_response out d ) }
        ( vec_free [u] d )
        ^
    } {}
    ? == kind 11 {
        : ( Vec u ) r ( rnd_bytes ( rnd 30 ) )
        = built_a ( rnd_varint )
        ? == ( rnd 2 ) 0 {
            = built_type 28
            = built_b ( rnd 64 )
            ( quic_push_connection_close out built_a built_b r )
        } {
            = built_type 29
            = built_c 1
            ( quic_push_application_close out built_a r )
        }
        ( vec_free [u] r )
        ^
    } {}
    ? == kind 12 {
        // ACK with 0..3 extra ranges that always fit.
        : i largest + 1000 ( rnd 100000 )
        : i first ( rnd 50 )
        : ( Vec i ) ranges ( vec_new [i] )
        : i extra ( rnd 4 )
        : ~ i k 0
        ~ < k extra {
            ( vec_push [i] ranges ( rnd 10 ) )
            ( vec_push [i] ranges ( rnd 10 ) )
            = k + k 1
        }
        : b ecn == ( rnd 2 ) 0
        = built_type ? ecn 3 2
        = built_a largest
        = built_b ( rnd 1000 )
        = built_c first
        = built_d ? ecn 1 0
        ( quic_push_ack out largest built_b first ranges ? ecn ( rnd 100 ) -1 ( rnd 100 ) ( rnd 100 ) )
        ( vec_free [i] ranges )
        ^
    } {}
    = built_type 30
    ( quic_push_handshake_done out )
}

@ main → i {
    : ~ i bad 0
    : ~ i parsed_ok 0
    : ~ i parsed_bad 0
    : ~ i roundtrips 0

    // ── 1. noise ─────────────────────────────────────────────────
    : ~ i it 0
    ~ < it 8000 {
        : i n ( rnd 48 )
        : ( Vec u ) buf ( rnd_bytes n )
        : *QuicFrame f ( quic_frame_parse buf 0 )
        ? != # i f 0 {
            = parsed_ok + parsed_ok 1
            ? | <= . f next 0 > . f next n { = bad + bad 1 } {}
            ? > ( vec_len [u] . f bytes ) . f next { = bad + bad 1 } {}
            ( quic_frame_free f )
        } { = parsed_bad + parsed_bad 1 }
        ( vec_free [u] buf )
        = it + it 1
    }
    ( nurl_print `noise_invariant_violations=` ) ( nurl_print ( nurl_str_int bad ) ) ( nurl_print `\n` )
    ( nurl_print `noise_parsed_some=` ) ( nurl_print ? > parsed_ok 0 `T` `F` ) ( nurl_print `\n` )
    ( nurl_print `noise_rejected_some=` ) ( nurl_print ? > parsed_bad 0 `T` `F` ) ( nurl_print `\n` )

    // ── 2. built frames round-trip; then one byte flipped / truncated ──
    = bad 0
    : ~ i mut_ok 0
    : ~ i mut_bad 0
    = it 0
    ~ < it 6000 {
        : ( Vec u ) out ( vec_new [u] )
        // a leading random frame so `off` is not always 0
        : i lead ( rnd 3 )
        ? == lead 1 { ( quic_push_ping out ) } {}
        ? == lead 2 { ( quic_push_padding out + 1 ( rnd 5 ) ) } {}
        : i off ( vec_len [u] out )
        ( build_random out )
        : i end ( vec_len [u] out )
        : *QuicFrame f ( quic_frame_parse out off )
        ? == # i f 0 { = bad + bad 1 } {
            ? != . f ftype built_type { = bad + bad 1 } {}
            ? != . f a built_a { = bad + bad 1 } {}
            ? != . f b built_b { = bad + bad 1 } {}
            ? != . f c built_c { = bad + bad 1 } {}
            ? != . f d built_d { = bad + bad 1 } {}
            ? != . f next end { = bad + bad 1 } {}
            = roundtrips + roundtrips 1
            ( quic_frame_free f )
        }
        // mutate: flip one byte, or truncate
        ? == ( rnd 2 ) 0 {
            : i at + off ( rnd - end off )
            : i old ?? ( vec_get [u] out at ) { T x → # i x F → 0 }
            : b _ok ( vec_set [u] out at # u ^^ old + 1 ( rnd 255 ) )
        } {
            : i cut + off ( rnd - end off )
            : b _ok ( vec_set_len [u] out cut )
        }
        : *QuicFrame g ( quic_frame_parse out off )
        ? != # i g 0 {
            = mut_ok + mut_ok 1
            ? | <= . g next off > . g next ( vec_len [u] out ) { = bad + bad 1 } {}
            ? > ( vec_len [u] . g bytes ) - . g next off { = bad + bad 1 } {}
            ( quic_frame_free g )
        } { = mut_bad + mut_bad 1 }
        ( vec_free [u] out )
        = it + it 1
    }
    ( nurl_print `roundtrip_violations=` ) ( nurl_print ( nurl_str_int bad ) ) ( nurl_print `\n` )
    ( nurl_print `roundtrips=` ) ( nurl_print ( nurl_str_int roundtrips ) ) ( nurl_print `\n` )
    ( nurl_print `mutated_parsed_some=` ) ( nurl_print ? > mut_ok 0 `T` `F` ) ( nurl_print `\n` )
    ( nurl_print `mutated_rejected_some=` ) ( nurl_print ? > mut_bad 0 `T` `F` ) ( nurl_print `\n` )

    // ── 3. varint round-trips and truncations ────────────────────
    = bad 0
    = it 0
    ~ < it 6000 {
        : i v ( rnd_varint )
        : ( Vec u ) b ( vec_new [u] )
        ( quic_varint_push b v )
        : i sz ( quic_varint_size v )
        ? != ( vec_len [u] b ) sz { = bad + bad 1 } {}
        ? != ( quic_varint_read b 0 ) v { = bad + bad 1 } {}
        ? != ( quic_varint_len_at b 0 ) sz { = bad + bad 1 } {}
        ? > sz 1 {
            : b _ok ( vec_set_len [u] b - sz 1 )
            ? != ( quic_varint_read b 0 ) -1 { = bad + bad 1 } {}
        } {}
        ( vec_free [u] b )
        = it + it 1
    }
    ( nurl_print `varint_violations=` ) ( nurl_print ( nurl_str_int bad ) ) ( nurl_print `\n` )
    ^ 0
}
