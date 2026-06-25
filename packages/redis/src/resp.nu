// packages/redis/src/resp.nu — RESP (REdis Serialization Protocol, RESP2)
// codec, pure and I/O-free so it can be unit-tested without a server.
//
// A request is an array of bulk strings:
//   *<n>\r\n  ( $<len>\r\n<arg>\r\n ) x n
//
// A reply is one of: simple string (+), error (-), integer (:), bulk
// string ($, with $-1 = nil) or array (*, with *-1 = nil). Arrays nest
// arbitrarily (pub/sub, XRANGE, COMMAND, …), so a reply is decoded into a
// flat node arena — a `Vec RNode` where array nodes hold the pool indices
// of their children. One Vec plus one String per node: no nested Vecs in
// structs beyond the child-index list, and a single linear free.
//
//   ( resp_encode args )            → ( Vec u )      request bytes
//   ( resp_parse buf start )        → RespParse      one reply (or Incomplete)
//   ( resp_reply_free reply )       → v              free a parsed reply
//
// Node walking (power users):
//   resp_reply_root / resp_node_kind / resp_node_int / resp_node_str /
//   resp_node_is_nil / resp_node_arr_len / resp_node_arr_at

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// RNode.kind: 0 nil · 1 integer · 2 string (simple or bulk) · 3 error · 4 array
: RNode {
    i kind
    i ival          // integer value; for arrays, the element count
    String sval     // string / error text (empty otherwise)
    ( Vec i ) kids   // child node indices (only populated for arrays)
}

// A decoded reply: the node arena plus the index of the root node.
: RedisReply {
    ( Vec RNode ) nodes
    i root
}

// Result of one parse attempt over a byte buffer.
//   status: 0 ok · 1 incomplete (need more bytes) · 2 malformed
//   consumed: bytes consumed from `start` when status == 0
: RespParse {
    i status
    RedisReply reply
    i consumed
}

// Mutable parse state threaded through the recursive descent (heap so the
// recursion shares one cursor / status / arena).
: RespBuilder {
    ( Vec RNode ) nodes
    i status
    i cur
}

// ── encoding ───────────────────────────────────────────────────────

@ __resp_push_crlf ( Vec u ) v → v {
    ( vec_push [u] v # u 13 ) ( vec_push [u] v # u 10 )
}

@ __resp_push_s ( Vec u ) v s raw i n → v {
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u ( nurl_str_get raw k ) ) = k + k 1 }
}

// Append the decimal ASCII of `n` (handles negatives, for completeness).
@ __resp_push_int_ascii ( Vec u ) v i n → v {
    ? == n 0 { ( vec_push [u] v # u 48 ) } {
        : ~ i x n
        ? < x 0 { ( vec_push [u] v # u 45 ) = x - 0 x } {}
        : ( Vec u ) tmp ( vec_new [u] )
        ~ > x 0 { ( vec_push [u] tmp # u + 48 % x 10 ) = x / x 10 }
        : ~ i k ( vec_len [u] tmp )
        ~ > k 0 {
            = k - k 1
            ( vec_push [u] v ?? ( vec_get [u] tmp k ) { T b → b F _ → # u 48 } )
        }
        ( vec_free [u] tmp )
    }
}

// Encode a command — an array of bulk strings — into RESP request bytes.
@ resp_encode ( Vec String ) args → ( Vec u ) {
    : i n ( vec_len [String] args )
    : ( Vec u ) out ( vec_new [u] )
    ( vec_push [u] out # u 42 )           // '*'
    ( __resp_push_int_ascii out n )
    ( __resp_push_crlf out )
    : ~ i k 0
    ~ < k n {
        : String a ?? ( vec_get [String] args k ) { T x → x F _ → ( string_new ) }
        : i alen ( string_len a )
        ( vec_push [u] out # u 36 )       // '$'
        ( __resp_push_int_ascii out alen )
        ( __resp_push_crlf out )
        ( __resp_push_s out ( string_data a ) alen )
        ( __resp_push_crlf out )
        = k + k 1
    }
    ^ out
}

// ── decoding ───────────────────────────────────────────────────────

@ __rbget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

// Index of a '\r' at k with '\n' at k+1, scanning [from,end). -1 if the
// line is not yet complete in the buffer.
@ __resp_find_crlf ( Vec u ) buf i from i end → i {
    : ~ i k from
    ~ < k - end 1 {
        ? & == ( __rbget buf k ) 13 == ( __rbget buf + k 1 ) 10 { ^ k } {}
        = k + k 1
    }
    ^ -1
}

@ __resp_slice ( Vec u ) buf i from i to → String {
    : String out ( string_with_cap ? > - to from 0 - to from 1 )
    : ~ i k from
    ~ < k to { ( string_push_char out ( __rbget buf k ) ) = k + k 1 }
    ^ out
}

// Signed decimal integer from buf[from,to).
@ __resp_parse_int ( Vec u ) buf i from i to → i {
    : ~ i v 0
    : ~ i neg 0
    : ~ i k from
    ? & < from to == ( __rbget buf from ) 45 { = neg 1 = k + from 1 } {}
    ~ < k to {
        : i c ( __rbget buf k )
        ? & >= c 48 <= c 57 { = v + * v 10 - c 48 } {}
        = k + k 1
    }
    ? == neg 1 { ^ - 0 v } { ^ v }
}

// Append a leaf node to the arena; returns its index.
@ __rb_push *RespBuilder b i kind i ival String sval → i {
    : RNode nd @ RNode { kind ival sval ( vec_new [i] ) }
    : i idx ( vec_len [RNode] . b nodes )
    ( vec_push [RNode] . b nodes nd )
    ^ idx
}

// Append an array node (kids already collected); returns its index.
@ __rb_push_arr *RespBuilder b i n ( Vec i ) kids → i {
    : RNode nd @ RNode { 4 n ( string_new ) kids }
    : i idx ( vec_len [RNode] . b nodes )
    ( vec_push [RNode] . b nodes nd )
    ^ idx
}

// Parse one value at the builder's cursor. Returns its node index, or -1
// with b.status set to 1 (incomplete) or 2 (malformed).
@ __resp_val *RespBuilder b ( Vec u ) buf i end → i {
    ? != . b status 0 { ^ -1 } {}
    : i pos . b cur
    ? >= pos end { = . b status 1 ^ -1 } {}
    : i tb ( __rbget buf pos )
    : i ls + pos 1
    : i le ( __resp_find_crlf buf ls end )
    ? < le 0 { = . b status 1 ^ -1 } {}

    ? == tb 43 {                                   // '+' simple string
        : String s ( __resp_slice buf ls le )
        = . b cur + le 2
        ^ ( __rb_push b 2 0 s )
    } {}
    ? == tb 45 {                                   // '-' error
        : String s ( __resp_slice buf ls le )
        = . b cur + le 2
        ^ ( __rb_push b 3 0 s )
    } {}
    ? == tb 58 {                                   // ':' integer
        : i v ( __resp_parse_int buf ls le )
        = . b cur + le 2
        ^ ( __rb_push b 1 v ( string_new ) )
    } {}
    ? == tb 36 {                                   // '$' bulk string
        : i blen ( __resp_parse_int buf ls le )
        ? < blen 0 {                               // $-1 → nil
            = . b cur + le 2
            ^ ( __rb_push b 0 0 ( string_new ) )
        } {}
        : i dstart + le 2
        : i dend + dstart blen
        ? > + dend 2 end { = . b status 1 ^ -1 } {}  // need data + CRLF
        : String s ( __resp_slice buf dstart dend )
        = . b cur + dend 2
        ^ ( __rb_push b 2 0 s )
    } {}
    ? == tb 42 {                                   // '*' array
        : i n ( __resp_parse_int buf ls le )
        ? < n 0 {                                  // *-1 → nil
            = . b cur + le 2
            ^ ( __rb_push b 0 0 ( string_new ) )
        } {}
        = . b cur + le 2
        : ( Vec i ) kids ( vec_new [i] )
        : ~ i k 0
        ~ < k n {
            : i ci ( __resp_val b buf end )
            ? != . b status 0 { ( vec_free [i] kids ) ^ -1 } {}
            ( vec_push [i] kids ci )
            = k + k 1
        }
        ^ ( __rb_push_arr b n kids )
    } {}

    = . b status 2                                 // unknown type byte
    ^ -1
}

// Parse one reply from buf starting at `start`. On Incomplete (status 1)
// the returned reply still owns a (partial) arena and must be freed by the
// caller before retrying with more bytes.
@ resp_parse ( Vec u ) buf i start → RespParse {
    : *RespBuilder b # *RespBuilder ( nurl_alloc Z RespBuilder )
    = . b nodes ( vec_new [RNode] )
    = . b status 0
    = . b cur start
    : i root ( __resp_val b buf ( vec_len [u] buf ) )
    : i st . b status
    : i cur . b cur
    : RedisReply rep @ RedisReply { . b nodes root }
    ( nurl_free # s b )
    ^ @ RespParse { st rep cur }
}

@ resp_reply_free RedisReply r → v {
    : i n ( vec_len [RNode] . r nodes )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [RNode] . r nodes k ) {
            T nd → { ( string_free . nd sval ) ( vec_free [i] . nd kids ) }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [RNode] . r nodes )
}

// ── node accessors ─────────────────────────────────────────────────

@ resp_reply_root RedisReply r → i { ^ . r root }

@ resp_node_kind RedisReply r i node → i {
    ?? ( vec_get [RNode] . r nodes node ) { T n → ^ . n kind F _ → ^ -1 }
}

@ resp_node_int RedisReply r i node → i {
    ?? ( vec_get [RNode] . r nodes node ) { T n → ^ . n ival F _ → ^ 0 }
}

// Borrowed view of a string/error node's text (lifetime tied to `r`).
@ resp_node_str RedisReply r i node → s {
    ?? ( vec_get [RNode] . r nodes node ) { T n → ^ ( string_data . n sval ) F _ → ^ `` }
}

@ resp_node_is_nil RedisReply r i node → b {
    ^ == ( resp_node_kind r node ) 0
}

@ resp_node_arr_len RedisReply r i node → i {
    ?? ( vec_get [RNode] . r nodes node ) {
        T n → { ? == . n kind 4 { ^ ( vec_len [i] . n kids ) } { ^ 0 } }
        F _ → ^ 0
    }
}

@ resp_node_arr_at RedisReply r i node i k → i {
    ?? ( vec_get [RNode] . r nodes node ) {
        T n → ?? ( vec_get [i] . n kids k ) { T ci → ^ ci F _ → ^ -1 }
        F _ → ^ -1
    }
}
