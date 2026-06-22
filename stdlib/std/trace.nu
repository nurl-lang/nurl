// stdlib/std/trace.nu — distributed tracing context (W3C traceparent).
//
// **Phase 2 (TODO §7.2) observability:** propagate a trace id across RPC
// hops so logs from every node in a fan-out can be correlated — without a
// collector like Jaeger. A node sets a "current" trace; ext/cluster.nu
// injects it into outgoing calls as a W3C `traceparent` header and, on the
// server, restores it for the handler's duration so nested calls carry the
// SAME trace id (with fresh child spans).
//
// Ids are 64-bit here (rendered as the low half of a 128-bit W3C trace id;
// the high half is zero-padded), kept in process-global i64s so there is no
// String-global to manage. NOTE the current context is process-wide — fine
// for a worker handling one request at a time; per-fiber context is a
// follow-up.
//
//   ( trace_start )                 → v    begin a fresh root trace
//   ( trace_set i tid i sid )       → v    adopt an (incoming) context
//   ( trace_clear )                 → v
//   ( trace_active )                → b
//   ( trace_current_trace )         → i
//   ( trace_current_span )          → i
//   ( trace_new_span )              → i    a fresh span id (for one hop)
//   ( trace_hex16 i v )             → String   16 lowercase hex digits
//   ( traceparent_format i t i s )  → String   "00-<32hex>-<16hex>-01"
//   ( traceparent_parse s hdr )     → TraceParsed

$ `stdlib/core/string.nu`
$ `stdlib/std/random.nu`

: ~ i g_cur_trace 0
: ~ i g_cur_span 0

@ trace_active → b { ^ != g_cur_trace 0 }

@ trace_current_trace → i { ^ g_cur_trace }

@ trace_current_span → i { ^ g_cur_span }

@ trace_new_span → i { ^ ( rand_u64 ) }

@ trace_start → v {
    = g_cur_trace ( rand_u64 )
    = g_cur_span ( rand_u64 )
}

@ trace_set i tid i sid → v {
    = g_cur_trace tid
    = g_cur_span sid
}

@ trace_clear → v {
    = g_cur_trace 0
    = g_cur_span 0
}

@ __tr_hex_digit i n → i {
    ? < n 10 { ^ + 48 n } {}
    ^ + 87 n
}

// 16 lowercase hex digits of `v` (treated as a 64-bit pattern — the shift
// is on u64 so a set top bit zero-fills instead of sign-extending).
@ trace_hex16 i v → String {
    : u64 uv # u64 v
    : String s ( string_with_cap 16 )
    : ~ i shift 60
    ~ >= shift 0 {
        : i nib # i & >> uv shift 15
        ( string_push_char s ( __tr_hex_digit nib ) )
        = shift - shift 4
    }
    ^ s
}

// W3C traceparent value: 00-<32hex trace-id>-<16hex span-id>-01. The
// trace-id's high 64 bits are zero (we carry a 64-bit id in the low half).
@ traceparent_format i tid i sid → String {
    : String s ( string_from `00-0000000000000000` )
    : String th ( trace_hex16 tid )
    ( string_push_str s ( string_data th ) )
    ( string_free th )
    ( string_push_char s 45 )  // '-'
    : String sh ( trace_hex16 sid )
    ( string_push_str s ( string_data sh ) )
    ( string_free sh )
    ( string_push_str s `-01` )
    ^ s
}

: TraceParsed {
    i ok
    i trace
    i span
}

@ __tr_hex_val i c → i {
    ? & >= c 48 <= c 57 { ^ - c 48 } {}  // 0-9
    ? & >= c 97 <= c 102 { ^ - c 87 } {}  // a-f
    ? & >= c 65 <= c 70 { ^ - c 55 } {}  // A-F
    ^ - 0 1
}

@ __tr_is_hex i c → b {
    ^ | | & >= c 48 <= c 57 & >= c 97 <= c 102 & >= c 65 <= c 70
}

// Are the `n` bytes of `src` from `off` all hex digits?
@ __tr_all_hex s src i off i n → b {
    : *u p # *u src
    : ~ b ok T
    : ~ i k 0
    ~ & ok < k n {
        ? ! ( __tr_is_hex # i . p + off k ) { = ok F } {}
        = k + k 1
    }
    ^ ok
}

// Parse `n` hex digits of `src` from `off` → value. Assumes the span is
// already validated as hex (the result may legitimately be a NEGATIVE i64
// when the top bit is set — a 64-bit id, NOT an error; that is why parse
// validity is checked separately, never via the sign).
@ __tr_hex_parse s src i off i n → i {
    : *u p # *u src
    : ~ i v 0
    : ~ i k 0
    ~ < k n {
        = v + * v 16 ( __tr_hex_val # i . p + off k )
        = k + k 1
    }
    ^ v
}

// Parse a W3C traceparent header. Expects "00-<32hex>-<16hex>-01" (≥ 55
// bytes); reads the trace id's LOW 16 hex (offset 19) and the 16-hex span
// (offset 36). ok=0 when malformed (length or non-hex fields).
@ traceparent_parse s hdr → TraceParsed {
    : i n ( nurl_str_len hdr )
    ? < n 55 { ^ @ TraceParsed { 0 0 0 } } {}
    ? ! ( __tr_all_hex hdr 19 16 ) { ^ @ TraceParsed { 0 0 0 } } {}
    ? ! ( __tr_all_hex hdr 36 16 ) { ^ @ TraceParsed { 0 0 0 } } {}
    : i tid ( __tr_hex_parse hdr 19 16 )
    : i sid ( __tr_hex_parse hdr 36 16 )
    ^ @ TraceParsed { 1 tid sid }
}
