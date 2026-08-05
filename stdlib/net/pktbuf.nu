// stdlib/net/pktbuf.nu — a buffer of length-delimited packets.
//
// Two layers of this stack emit a SEQUENCE of variable-length things
// into one buffer, and neither thing carries its own length:
//
//   * a TCP segment's length comes from the enclosing IP datagram;
//   * an Ethernet frame's length comes from the wire — the device
//     delivers and accepts one frame at a time, and nothing inside the
//     frame says where it ends.
//
// Concatenating either into a flat byte buffer is therefore
// irreversible. TCP found this out first (net/tcp.nu's `TcpOut`) and
// recorded boundaries alongside the bytes; the frame path had the same
// problem and no answer, so its consumers re-derived the boundaries by
// re-parsing the headers the emitter had just written — a decoder that
// only works for the ethertypes it happens to know about, and that a
// padded frame or a new protocol silently breaks.
//
// One type for both. `bytes` holds the packets back to back; `ends`
// holds one end offset per packet, so packet k occupies
// [end(k-1), end(k)). The emitter calls `pktbuf_mark` when a packet is
// complete — it is the only party that knows.
//
// This is not a container for general use: it is deliberately
// append-and-drain. There is no remove, because both consumers (a
// device transmitting frames, the IP layer wrapping segments) walk the
// packets in order exactly once and then clear.
$ `stdlib/core/vec.nu`

: PktBuf {
    ( Vec u ) bytes
    ( Vec i ) ends  // end offset of each complete packet
}

@ pktbuf_new → *PktBuf {
    : *PktBuf p # *PktBuf ( nurl_alloc Z PktBuf )
    = . p bytes ( vec_new [u] )
    = . p ends ( vec_new [i] )
    ^ p
}

@ pktbuf_free * PktBuf p → v {
    ? == # i p 0 { ^ } {}
    ( vec_free [u] . p bytes )
    ( vec_free [i] . p ends )
    ( free p )
}

@ pktbuf_clear * PktBuf p → v {
    ( vec_clear [u] . p bytes )
    ( vec_clear [i] . p ends )
}

// How many complete packets are in here.
@ pktbuf_count * PktBuf p → i { ^ ( vec_len [i] . p ends ) }

// Total bytes, including any packet not yet marked complete.
@ pktbuf_total * PktBuf p → i { ^ ( vec_len [u] . p bytes ) }

@ pktbuf_is_empty * PktBuf p → b { ^ == 0 ( vec_len [i] . p ends ) }

@ pktbuf_end * PktBuf p i idx → i {
    ^ ?? ( vec_get [i] . p ends idx ) { T x → x F → 0 }
}

@ pktbuf_start * PktBuf p i idx → i {
    ? <= idx 0 { ^ 0 } {}
    ^ ( pktbuf_end p - idx 1 )
}

@ pktbuf_len * PktBuf p i idx → i {
    ^ - ( pktbuf_end p idx ) ( pktbuf_start p idx )
}

// Close the packet that has been accumulating since the last mark.
//
// A mark with nothing appended since the previous one is a no-op rather
// than a zero-length packet: "close the current packet" says nothing
// when there is no current packet, and an emitter that takes an early
// return after deciding not to write anything should not have to
// remember which of its exits already marked.
@ pktbuf_mark * PktBuf p → v {
    : i n ( vec_len [u] . p bytes )
    : i k ( vec_len [i] . p ends )
    : i last ? > k 0 ( pktbuf_end p - k 1 ) 0
    ? <= n last { ^ } {}
    ( vec_push [i] . p ends n )
}

// Close the current packet even when it is EMPTY.
//
// `pktbuf_mark` treats "nothing appended" as "no packet", which is
// right for a frame or a segment: an emitter that decided not to write
// anything did not emit a packet. A zero-length DATAGRAM is a
// different thing — it is a datagram, the receiver must be handed it,
// and dropping it turns "the peer sent nothing" into "the peer has
// sent nothing yet". UDP is the caller that needs this one.
@ pktbuf_mark_empty * PktBuf p → v {
    ( vec_push [i] . p ends ( vec_len [u] . p bytes ) )
}

// Append packet `idx` to `dst`. Returns how many bytes were appended.
// The consuming half of the seam: a device driver walks 0..count and
// hands each one to the hardware.
@ pktbuf_copy_to ( Vec u ) dst * PktBuf p i idx → i {
    ? || < idx 0 >= idx ( vec_len [i] . p ends ) { ^ 0 } {}
    : i s ( pktbuf_start p idx )
    : i n - ( pktbuf_end p idx ) s
    ( vec_extend_range [u] dst . p bytes s n )
    ^ n
}

// Append every complete packet of `src` to `dst`, boundaries intact.
// A partially-written packet at the tail of `src` is NOT taken: it is
// not a packet yet, and taking half of one is how a stack starts
// emitting truncated frames.
@ pktbuf_extend * PktBuf dst * PktBuf src → i {
    : i n ( vec_len [i] . src ends )
    : ~ i k 0
    ~ < k n {
        ( vec_extend_range [u] . dst bytes . src bytes ( pktbuf_start src k ) ( pktbuf_len src k ) )
        ( pktbuf_mark dst )
        = k + k 1
    }
    ^ n
}
