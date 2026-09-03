// stdlib/std/quic_rxbuf.nu — ordered reassembly of an offset-addressed
// byte stream (CRYPTO frames per encryption level, STREAM frames per
// stream): chunks arrive at any offset, in any order, possibly
// overlapping or repeated; the reader takes the contiguous prefix.
//
//   ( quic_rxbuf_new cap )              → *QuicRxBuf   refuse data past `cap` bytes of stream offset
//   ( quic_rxbuf_free r )               → v
//   ( quic_rxbuf_add r off data )       → b            F when off+len exceeds the cap
//   ( quic_rxbuf_avail r )              → i            bytes contiguous from the read position
//   ( quic_rxbuf_read r n )             → ( Vec u )    OWNED, up to n bytes from the read position
//   ( quic_rxbuf_peek_u8 r k )          → i            byte k past the read position (0 if absent)
//   ( quic_rxbuf_consumed r )           → i            the read position (stream offset)
//   ( quic_rxbuf_highest r )            → i            one past the highest offset received
//   ( quic_rxbuf_set_cap r cap )        → v            raise the cap (flow-control window grows)
//
// Storage is one byte buffer grown to the highest offset seen plus a
// sorted, merged list of [start,end) ranges. The read position is kept
// with the buffer: bytes before it are dead and reclaimed when the
// buffer is compacted (every time the dead prefix exceeds 16 KB), so a
// long-lived stream does not grow without bound.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

: QuicRxBuf {
    ( Vec u ) buf
    i base
    ( Vec i ) ranges
    i consumed
    i cap
    i highest
}

@ quic_rxbuf_new i cap → *QuicRxBuf {
    : *QuicRxBuf r # *QuicRxBuf ( nurl_alloc Z QuicRxBuf )
    = . r buf ( vec_new [u] )
    = . r base 0
    = . r ranges ( vec_new [i] )
    = . r consumed 0
    = . r cap cap
    = . r highest 0
    ^ r
}

@ quic_rxbuf_free * QuicRxBuf r → v {
    ? == # i r 0 { ^ } {}
    ( vec_free [u] . r buf )
    ( vec_free [i] . r ranges )
    ( nurl_free # s r )
}

@ quic_rxbuf_consumed * QuicRxBuf r → i { ^ . r consumed }

@ quic_rxbuf_highest * QuicRxBuf r → i { ^ . r highest }

@ quic_rxbuf_set_cap * QuicRxBuf r i cap → v { = . r cap cap }

@ __qrb_ri ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → ^ x F → ^ 0 }
}

@ __qrb_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

@ quic_rxbuf_add * QuicRxBuf r i off ( Vec u ) data → b {
    : i n ( vec_len [u] data )
    : i end + off n
    ? | < off 0 > end . r cap { ^ F } {}
    ? > end . r highest { = . r highest end } {}
    ? == n 0 { ^ T } {}
    // Bytes already consumed are a retransmission of what was read.
    ? <= end . r consumed { ^ T } {}
    : ~ i s off
    : ~ i copy_from 0
    ? < s . r consumed { = copy_from - . r consumed s = s . r consumed } {}
    : i rel - s . r base
    : i rel_end - end . r base
    ? > rel_end ( vec_len [u] . r buf ) { : b _g ( vec_resize_zeroed [u] . r buf rel_end ) } {}
    : *u dst ( vec_data [u] . r buf )
    : *u src ( vec_data [u] data )
    ( nurl_memcpy # s + # i dst rel # s + # i src copy_from - end s )
    // Merge [s,end) into the sorted range list.
    : ( Vec i ) merged ( vec_new [i] )
    : ~ i e end
    : ~ b placed F
    : ~ i k 0
    : i cnt ( vec_len [i] . r ranges )
    ~ < k cnt {
        : i rs ( __qrb_ri . r ranges k )
        : i re ( __qrb_ri . r ranges + k 1 )
        ? < re s {
            ( vec_push [i] merged rs ) ( vec_push [i] merged re )
        } {
            ? > rs e {
                ? ! placed { ( vec_push [i] merged s ) ( vec_push [i] merged e ) = placed T } {}
                ( vec_push [i] merged rs ) ( vec_push [i] merged re )
            } {
                // overlap or adjacency: absorb
                ? < rs s { = s rs } {}
                ? > re e { = e re } {}
            }
        }
        = k + k 2
    }
    ? ! placed { ( vec_push [i] merged s ) ( vec_push [i] merged e ) } {}
    ( vec_free [i] . r ranges )
    = . r ranges merged
    ^ T
}

@ quic_rxbuf_avail * QuicRxBuf r → i {
    ? == ( vec_len [i] . r ranges ) 0 { ^ 0 } {}
    : i rs ( __qrb_ri . r ranges 0 )
    : i re ( __qrb_ri . r ranges 1 )
    ? > rs . r consumed { ^ 0 } {}
    ? <= re . r consumed { ^ 0 } {}
    ^ - re . r consumed
}

@ quic_rxbuf_peek_u8 * QuicRxBuf r i k → i {
    ? >= k ( quic_rxbuf_avail r ) { ^ 0 } {}
    ^ ( __qrb_bget . r buf - + . r consumed k . r base )
}

// Drop the dead prefix once it is worth a copy.
@ __qrb_compact * QuicRxBuf r → v {
    : i dead - . r consumed . r base
    ? < dead 16384 { ^ } {}
    : ( Vec u ) keep ( bytes_slice . r buf dead ( vec_len [u] . r buf ) )
    ( vec_free [u] . r buf )
    = . r buf keep
    = . r base . r consumed
    // the first range starts at or before consumed by construction;
    // ranges are absolute offsets, nothing to shift.
    ? > ( vec_len [i] . r ranges ) 0 {
        ? < ( __qrb_ri . r ranges 0 ) . r consumed {
            : b _ok ( vec_set [i] . r ranges 0 . r consumed )
        } {}
    } {}
}

@ quic_rxbuf_read * QuicRxBuf r i n → ( Vec u ) {
    : i avail ( quic_rxbuf_avail r )
    : i take ? < n avail n avail
    ? <= take 0 { ^ ( vec_new [u] ) } {}
    : i rel - . r consumed . r base
    : ( Vec u ) out ( bytes_slice . r buf rel + rel take )
    = . r consumed + . r consumed take
    ( __qrb_compact r )
    ^ out
}
