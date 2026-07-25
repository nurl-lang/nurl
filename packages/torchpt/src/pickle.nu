// packages/torchpt/src/pickle.nu — a pickle protocol 0–5 reader, restricted
// to data.
//
// Unpickling is famously arbitrary code execution: the format is a stack
// machine whose REDUCE opcode means "call this callable". This reader
// never calls anything. GLOBAL pushes the *name* of a callable, and
// REDUCE consults a fixed table of shapes it knows how to build as data
// — `torch._utils._rebuild_tensor_v2`, `collections.OrderedDict` and a
// couple of siblings. Everything else becomes an opaque PK_OTHER node.
// A hostile pickle can therefore make this reader produce a confusing
// tree, and nothing else.
//
// The result is a value tree in flat arrays (no per-node allocation):
//
//   ( pk_parse * u p i n )     → !*Pk String
//   ( pk_free k )              → v
//   ( pk_root k )              → i    root node id
//   ( pk_kind k id )           → i    PK_*
//   ( pk_int k id )            → i    PK_INT / PK_BOOL value
//   ( pk_float k id )          → f    PK_FLOAT value
//   ( pk_str k id )            → s    PK_STR text (BORROWED)
//   ( pk_len k id )            → i    items (seq) or pairs (dict)
//   ( pk_item k id j )         → i    j-th item of a tuple/list
//   ( pk_key k id j )          → i    j-th key of a dict
//   ( pk_val k id j )          → i    j-th value of a dict
//   ( pk_dict_get k id s key ) → i    value node, -1 when absent
//
// Tensors reduce to PK_TENSOR nodes; their fields come out through
//   ( pk_tensor_storage k id )  → i   storage id
//   ( pk_tensor_offset k id )   → i   element offset into the storage
//   ( pk_tensor_ndim k id )     → i
//   ( pk_tensor_dim k id j )    → i
//   ( pk_tensor_stride k id j ) → i
// and a storage id resolves through
//   ( pk_storage_dtype k sid )  → i   PKS_* storage class
//   ( pk_storage_key k sid )    → s   the `data/<key>` filename (BORROWED)
//   ( pk_storage_numel k sid )  → i
//
// Everything is bounded before it is believed: a length read from the
// stream is checked against the bytes that remain, memo ids and stack
// depths are checked before use, and the opcode loop has a step budget
// proportional to the input, so a crafted pickle cannot spin, over-read
// or allocate on a number it merely claims.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`

// ── node kinds ──────────────────────────────────────────────────────
: i PK_NONE 0
: i PK_BOOL 1
: i PK_INT 2
: i PK_FLOAT 3
: i PK_STR 4
: i PK_BYTES 5
: i PK_TUPLE 6
: i PK_LIST 7
: i PK_DICT 8
: i PK_TENSOR 9
: i PK_GLOBAL 10
: i PK_PERSID 11
: i PK_OTHER 12
: i PK_MARK 13  // internal: stack sentinel, never reachable from the root

@ pk_kind_name i kd → s {
    ? == kd PK_NONE { ^ `none` } {}
    ? == kd PK_BOOL { ^ `bool` } {}
    ? == kd PK_INT { ^ `int` } {}
    ? == kd PK_FLOAT { ^ `float` } {}
    ? == kd PK_STR { ^ `str` } {}
    ? == kd PK_BYTES { ^ `bytes` } {}
    ? == kd PK_TUPLE { ^ `tuple` } {}
    ? == kd PK_LIST { ^ `list` } {}
    ? == kd PK_DICT { ^ `dict` } {}
    ? == kd PK_TENSOR { ^ `tensor` } {}
    ? == kd PK_GLOBAL { ^ `global` } {}
    ? == kd PK_PERSID { ^ `persid` } {}
    ^ `other`
}

// ── torch storage classes ───────────────────────────────────────────
: i PKS_UNKNOWN 0
: i PKS_F64 1
: i PKS_F32 2
: i PKS_F16 3
: i PKS_BF16 4
: i PKS_I64 5
: i PKS_I32 6
: i PKS_I16 7
: i PKS_I8 8
: i PKS_U8 9
: i PKS_BOOL 10

@ pk_storage_class s name → i {
    ? ( nurl_str_eq name `DoubleStorage` ) { ^ PKS_F64 } {}
    ? ( nurl_str_eq name `FloatStorage` ) { ^ PKS_F32 } {}
    ? ( nurl_str_eq name `HalfStorage` ) { ^ PKS_F16 } {}
    ? ( nurl_str_eq name `BFloat16Storage` ) { ^ PKS_BF16 } {}
    ? ( nurl_str_eq name `LongStorage` ) { ^ PKS_I64 } {}
    ? ( nurl_str_eq name `IntStorage` ) { ^ PKS_I32 } {}
    ? ( nurl_str_eq name `ShortStorage` ) { ^ PKS_I16 } {}
    ? ( nurl_str_eq name `CharStorage` ) { ^ PKS_I8 } {}
    ? ( nurl_str_eq name `ByteStorage` ) { ^ PKS_U8 } {}
    ? ( nurl_str_eq name `BoolStorage` ) { ^ PKS_BOOL } {}
    ^ PKS_UNKNOWN
}

@ pk_storage_name i c → s {
    ? == c PKS_F64 { ^ `f64` } {}
    ? == c PKS_F32 { ^ `f32` } {}
    ? == c PKS_F16 { ^ `f16` } {}
    ? == c PKS_BF16 { ^ `bf16` } {}
    ? == c PKS_I64 { ^ `i64` } {}
    ? == c PKS_I32 { ^ `i32` } {}
    ? == c PKS_I16 { ^ `i16` } {}
    ? == c PKS_I8 { ^ `i8` } {}
    ? == c PKS_U8 { ^ `u8` } {}
    ? == c PKS_BOOL { ^ `bool` } {}
    ^ `?`
}

// Bytes per element of a storage class; 0 when unknown.
@ pk_storage_esize i c → i {
    ? | == c PKS_F64 == c PKS_I64 { ^ 8 } {}
    ? | == c PKS_F32 == c PKS_I32 { ^ 4 } {}
    ? | | == c PKS_F16 == c PKS_BF16 == c PKS_I16 { ^ 2 } {}
    ? | | == c PKS_I8 == c PKS_U8 == c PKS_BOOL { ^ 1 } {}
    ^ 0
}

// ── the tree, in flat arrays ────────────────────────────────────────
//
// Every field is a Vec, never a scalar: a NURL struct passed by value
// copies its scalar fields, so a counter living in the struct would
// silently not mutate. Vec handles are shared, so pushes are seen by
// the caller — which is why even the root id and the error live in
// one-element Vecs.
: Pk {
    ( Vec i ) kind  // per node
    ( Vec i ) va  // per node: int / str-idx / kids-start / tensor-idx / storage-idx
    ( Vec i ) vb  // per node: item or pair count, or byte length
    ( Vec i ) kids  // child node ids, addressed by (va, vb)
    ( Vec String ) strs
    ( Vec u ) blob  // BYTES payloads, addressed by (va, vb)
    ( Vec i ) stack
    ( Vec i ) memo
    ( Vec i ) stor  // 3 per storage: class, key str-idx, numel
    ( Vec i ) tens  // 4 per tensor: storage id, elem offset, ndim, dims-start
    ( Vec i ) dims  // ndim dims then ndim strides, per tensor
    ( Vec i ) root  // slot 0: root node id
    ( Vec String ) errs
}

@ pk_new → *Pk {
    : *Pk k # *Pk ( nurl_alloc Z Pk )
    = . k kind ( vec_new [i] )
    = . k va ( vec_new [i] )
    = . k vb ( vec_new [i] )
    = . k kids ( vec_new [i] )
    = . k strs ( vec_new [String] )
    = . k blob ( vec_new [u] )
    = . k stack ( vec_new [i] )
    = . k memo ( vec_new [i] )
    = . k stor ( vec_new [i] )
    = . k tens ( vec_new [i] )
    = . k dims ( vec_new [i] )
    = . k root ( vec_new [i] )
    = . k errs ( vec_new [String] )
    ( vec_push [i] . k root -1 )
    ^ k
}

@ pk_free * Pk k → v {
    ( vec_free [i] . k kind )
    ( vec_free [i] . k va )
    ( vec_free [i] . k vb )
    ( vec_free [i] . k kids )
    ( vec_free_with [String] . k strs \ String s → v { ( string_free s ) } )
    ( vec_free [u] . k blob )
    ( vec_free [i] . k stack )
    ( vec_free [i] . k memo )
    ( vec_free [i] . k stor )
    ( vec_free [i] . k tens )
    ( vec_free [i] . k dims )
    ( vec_free [i] . k root )
    ( vec_free_with [String] . k errs \ String s → v { ( string_free s ) } )
    ( nurl_free # s k )
}

// ── accessors ───────────────────────────────────────────────────────

@ __pk_geti ( Vec i ) v i idx → i {
    ?? ( vec_get [i] v idx ) { T x → ^ x F → ^ 0 }
}

@ pk_root * Pk k → i { ^ ( __pk_geti . k root 0 ) }

@ pk_n_nodes * Pk k → i { ^ ( vec_len [i] . k kind ) }

@ pk_kind * Pk k i id → i {
    ? | < id 0 >= id ( vec_len [i] . k kind ) { ^ PK_OTHER } {}
    ^ ( __pk_geti . k kind id )
}

@ pk_int * Pk k i id → i {
    ? | < id 0 >= id ( vec_len [i] . k kind ) { ^ 0 } {}
    ^ ( __pk_geti . k va id )
}

@ pk_float * Pk k i id → f {
    ? | < id 0 >= id ( vec_len [i] . k kind ) { ^ 0.0 } {}
    ^ ( bits_to_f64 ( __pk_geti . k va id ) )
}

@ pk_str * Pk k i id → s {
    ? != ( pk_kind k id ) PK_STR { ^ `` } {}
    : i si ( __pk_geti . k va id )
    ?? ( vec_get [String] . k strs si ) { T s → ^ ( string_data s ) F → ^ `` }
}

// Items in a tuple/list, pairs in a dict, bytes in a byte string.
@ pk_len * Pk k i id → i {
    : i kd ( pk_kind k id )
    ? | | | == kd PK_TUPLE == kd PK_LIST == kd PK_DICT == kd PK_BYTES
    { ^ ( __pk_geti . k vb id ) } {}
    ^ 0
}

@ pk_item * Pk k i id i j → i {
    : i kd ( pk_kind k id )
    ? & != kd PK_TUPLE != kd PK_LIST { ^ -1 } {}
    ? | < j 0 >= j ( __pk_geti . k vb id ) { ^ -1 } {}
    ^ ( __pk_geti . k kids + ( __pk_geti . k va id ) j )
}

@ pk_key * Pk k i id i j → i {
    ? != ( pk_kind k id ) PK_DICT { ^ -1 } {}
    ? | < j 0 >= j ( __pk_geti . k vb id ) { ^ -1 } {}
    ^ ( __pk_geti . k kids + ( __pk_geti . k va id ) * j 2 )
}

@ pk_val * Pk k i id i j → i {
    ? != ( pk_kind k id ) PK_DICT { ^ -1 } {}
    ? | < j 0 >= j ( __pk_geti . k vb id ) { ^ -1 } {}
    ^ ( __pk_geti . k kids + + ( __pk_geti . k va id ) * j 2 1 )
}

@ pk_dict_get * Pk k i id s key → i {
    : i n ( pk_len k id )
    : ~ i j 0
    ~ < j n {
        : i kid ( pk_key k id j )
        ? ( nurl_str_eq ( pk_str k kid ) key ) { ^ ( pk_val k id j ) } {}
        = j + j 1
    }
    ^ -1
}

@ pk_tensor_storage * Pk k i id → i {
    ? != ( pk_kind k id ) PK_TENSOR { ^ -1 } {}
    ^ ( __pk_geti . k tens * ( __pk_geti . k va id ) 4 )
}

@ pk_tensor_offset * Pk k i id → i {
    ? != ( pk_kind k id ) PK_TENSOR { ^ 0 } {}
    ^ ( __pk_geti . k tens + * ( __pk_geti . k va id ) 4 1 )
}

@ pk_tensor_ndim * Pk k i id → i {
    ? != ( pk_kind k id ) PK_TENSOR { ^ 0 } {}
    ^ ( __pk_geti . k tens + * ( __pk_geti . k va id ) 4 2 )
}

@ pk_tensor_dim * Pk k i id i j → i {
    ? != ( pk_kind k id ) PK_TENSOR { ^ 0 } {}
    : i t * ( __pk_geti . k va id ) 4
    ? | < j 0 >= j ( __pk_geti . k tens + t 2 ) { ^ 0 } {}
    ^ ( __pk_geti . k dims + ( __pk_geti . k tens + t 3 ) j )
}

@ pk_tensor_stride * Pk k i id i j → i {
    ? != ( pk_kind k id ) PK_TENSOR { ^ 0 } {}
    : i t * ( __pk_geti . k va id ) 4
    : i nd ( __pk_geti . k tens + t 2 )
    ? | < j 0 >= j nd { ^ 0 } {}
    ^ ( __pk_geti . k dims + + ( __pk_geti . k tens + t 3 ) nd j )
}

@ pk_n_storages * Pk k → i { ^ / ( vec_len [i] . k stor ) 3 }

@ pk_storage_dtype * Pk k i sid → i {
    ? | < sid 0 >= sid ( pk_n_storages k ) { ^ PKS_UNKNOWN } {}
    ^ ( __pk_geti . k stor * sid 3 )
}

@ pk_storage_key * Pk k i sid → s {
    ? | < sid 0 >= sid ( pk_n_storages k ) { ^ `` } {}
    : i si ( __pk_geti . k stor + * sid 3 1 )
    ?? ( vec_get [String] . k strs si ) { T s → ^ ( string_data s ) F → ^ `` }
}

@ pk_storage_numel * Pk k i sid → i {
    ? | < sid 0 >= sid ( pk_n_storages k ) { ^ 0 } {}
    ^ ( __pk_geti . k stor + * sid 3 2 )
}

// ── construction helpers ────────────────────────────────────────────

@ __pk_node * Pk k i kd i a i b → i {
    : i id ( vec_len [i] . k kind )
    ( vec_push [i] . k kind kd )
    ( vec_push [i] . k va a )
    ( vec_push [i] . k vb b )
    ^ id
}

@ __pk_intern * Pk k s text → i {
    : i idx ( vec_len [String] . k strs )
    ( vec_push [String] . k strs ( string_from text ) )
    ^ idx
}

@ __pk_push * Pk k i id → v { ( vec_push [i] . k stack id ) }

@ __pk_depth * Pk k → i { ^ ( vec_len [i] . k stack ) }

@ __pk_pop * Pk k → i {
    : i n ( vec_len [i] . k stack )
    ? <= n 0 { ^ -1 } {}
    : i id ( __pk_geti . k stack - n 1 )
    : b _t ( vec_set_len [i] . k stack - n 1 )
    ^ id
}

@ __pk_peek * Pk k i back → i {
    : i n ( vec_len [i] . k stack )
    ? | < back 0 >= back n { ^ -1 } {}
    ^ ( __pk_geti . k stack - - n 1 back )
}

// Stack index of the topmost MARK, or -1.
@ __pk_find_mark * Pk k → i {
    : ~ i j - ( vec_len [i] . k stack ) 1
    ~ >= j 0 {
        ? == ( __pk_geti . k kind ( __pk_geti . k stack j ) ) PK_MARK { ^ j } {}
        = j - j 1
    }
    ^ -1
}

@ __pk_memo_put * Pk k i slot i id → v {
    ? | < slot 0 > slot 16777216 { ^ v } {}
    ~ <= ( vec_len [i] . k memo ) slot { ( vec_push [i] . k memo -1 ) }
    : b _s ( vec_set [i] . k memo slot id )
}

@ __pk_memo_get * Pk k i slot → i {
    ? | < slot 0 >= slot ( vec_len [i] . k memo ) { ^ -1 } {}
    ^ ( __pk_geti . k memo slot )
}

// Record the first error and return the sentinel the step loop stops on.
@ __pk_fail * Pk k s msg → i {
    ? == 0 ( vec_len [String] . k errs )
    { ( vec_push [String] . k errs ( string_from msg ) ) } {}
    ^ -1
}

@ pk_error * Pk k → s {
    ?? ( vec_get [String] . k errs 0 ) { T s → ^ ( string_data s ) F → ^ `` }
}

// ── little-endian scalar reads ──────────────────────────────────────

@ __pk_u8 * u p i off → i { ^ # i . p off }

@ __pk_u16 * u p i off → i { ^ + ( __pk_u8 p off ) * ( __pk_u8 p + off 1 ) 256 }

@ __pk_u32 * u p i off → i { ^ + ( __pk_u16 p off ) * ( __pk_u16 p + off 2 ) 65536 }

@ __pk_i32 * u p i off → i {
    : i v ( __pk_u32 p off )
    ^ ? >= v 2147483648 - v 4294967296 v
}

@ __pk_pow256 i len → i {
    : ~ i r 1
    : ~ i j 0
    ~ < j len { = r * r 256 = j + j 1 }
    ^ r
}

// LONG1/LONG4 payload: little-endian two's-complement, arbitrary length.
// Anything wider than 8 bytes cannot be a real dimension or count; it
// reads as 0 rather than silently wrapping into a plausible number.
@ __pk_long * u p i off i len → i {
    ? | <= len 0 > len 8 { ^ 0 } {}
    : ~ i acc 0
    : ~ i j - len 1
    ~ >= j 0 { = acc + * acc 256 ( __pk_u8 p + off j ) = j - j 1 }
    : i top ( __pk_u8 p + off - len 1 )
    ? & < len 8 >= top 128 { ^ - acc ( __pk_pow256 len ) } {}
    ^ acc
}

// BINFLOAT is IEEE-754 double, BIG-endian — the one big-endian field in
// an otherwise little-endian protocol.
@ __pk_f64be * u p i off → i {
    : ~ i bits 0
    : ~ i j 0
    ~ < j 8 { = bits + * bits 256 ( __pk_u8 p + off j ) = j + j 1 }
    ^ bits
}

// ── reductions ──────────────────────────────────────────────────────

// Build a PK_TENSOR from `torch._utils._rebuild_tensor_v2` arguments:
//   (storage, storage_offset, size, stride, requires_grad, backward_hooks)
// Returns the node id, or -1 when the argument shapes are not what the
// name promises.
@ __pk_build_tensor * Pk k i args → i {
    ? < ( pk_len k args ) 4 { ^ -1 } {}
    : i sn ( pk_item k args 0 )
    ? != ( pk_kind k sn ) PK_PERSID { ^ -1 } {}
    : i offn ( pk_item k args 1 )
    ? != ( pk_kind k offn ) PK_INT { ^ -1 } {}
    : i size ( pk_item k args 2 )
    : i stride ( pk_item k args 3 )
    ? | != ( pk_kind k size ) PK_TUPLE != ( pk_kind k stride ) PK_TUPLE { ^ -1 } {}
    : i nd ( pk_len k size )
    ? != ( pk_len k stride ) nd { ^ -1 } {}
    : i dstart ( vec_len [i] . k dims )
    : ~ i j 0
    ~ < j nd {
        : i dn ( pk_item k size j )
        ? != ( pk_kind k dn ) PK_INT { ^ -1 } {}
        ( vec_push [i] . k dims ( __pk_geti . k va dn ) )
        = j + j 1
    }
    = j 0
    ~ < j nd {
        : i s2 ( pk_item k stride j )
        ? != ( pk_kind k s2 ) PK_INT { ^ -1 } {}
        ( vec_push [i] . k dims ( __pk_geti . k va s2 ) )
        = j + j 1
    }
    : i tidx / ( vec_len [i] . k tens ) 4
    ( vec_push [i] . k tens ( __pk_geti . k va sn ) )
    ( vec_push [i] . k tens ( __pk_geti . k va offn ) )
    ( vec_push [i] . k tens nd )
    ( vec_push [i] . k tens dstart )
    ^ ( __pk_node k PK_TENSOR tidx 0 )
}

// REDUCE / NEWOBJ: `callable` is a PK_GLOBAL naming a class we either
// know how to represent as data, or do not. Nothing is ever invoked.
@ __pk_reduce * Pk k i callable i args → i {
    ? != ( pk_kind k callable ) PK_GLOBAL { ^ ( __pk_node k PK_OTHER 0 0 ) } {}
    : s nm ( pk_str_of_global k callable )
    ? | ( nurl_str_eq nm `torch._utils._rebuild_tensor_v2` )
    ( nurl_str_eq nm `torch._utils._rebuild_tensor_v3` ) {
        : i t ( __pk_build_tensor k args )
        ? >= t 0 { ^ t } {}
        ^ ( __pk_node k PK_OTHER 0 0 )
    } {}
    ? ( nurl_str_eq nm `torch._utils._rebuild_parameter` ) {
        ? >= ( pk_len k args ) 1 { ^ ( pk_item k args 0 ) } {}
        ^ ( __pk_node k PK_OTHER 0 0 )
    } {}
    ? | ( nurl_str_eq nm `collections.OrderedDict` ) ( nurl_str_eq nm `builtins.dict` ) {
        ^ ( __pk_node k PK_DICT ( vec_len [i] . k kids ) 0 )
    } {}
    ^ ( __pk_node k PK_OTHER 0 0 )
}

// A GLOBAL's dotted name. Kept separate from pk_str so PK_STR stays the
// only kind that reads as text to callers.
@ pk_str_of_global * Pk k i id → s {
    ? != ( pk_kind k id ) PK_GLOBAL { ^ `` } {}
    : i si ( __pk_geti . k va id )
    ?? ( vec_get [String] . k strs si ) { T s → ^ ( string_data s ) F → ^ `` }
}

@ __pk_global * Pk k s modname s qname → i {
    : String full ( string_from modname )
    ( string_push_char full 46 )
    ( string_push_str full qname )
    : i si ( vec_len [String] . k strs )
    ( vec_push [String] . k strs full )
    ^ ( __pk_node k PK_GLOBAL si 0 )
}

// Collapse everything above the topmost MARK into one container node.
@ __pk_collapse * Pk k i kd i mark → i {
    : i n ( vec_len [i] . k stack )
    : i count - - n mark 1
    : i start ( vec_len [i] . k kids )
    : ~ i j + mark 1
    ~ < j n { ( vec_push [i] . k kids ( __pk_geti . k stack j ) ) = j + j 1 }
    : b _t ( vec_set_len [i] . k stack mark )
    ^ ( __pk_node k kd start ? == kd PK_DICT / count 2 count )
}

// Make `target`'s children the last run in the kids arena, so more can
// simply be pushed. A container is created empty and filled later, and
// nested containers land in the arena in between — so the run usually
// has to be relocated once, on the first extend. Costs a copy of what
// the container already holds, which for the build-then-fill shape that
// pickle actually emits is a copy of nothing.
@ __pk_make_room * Pk k i target i pair → v {
    : i kstart ( __pk_geti . k va target )
    : i kcount ( __pk_geti . k vb target )
    : i have ? == pair 1 * kcount 2 kcount
    ? == + kstart have ( vec_len [i] . k kids ) { ^ v } {}
    : i nstart ( vec_len [i] . k kids )
    : ~ i j 0
    ~ < j have { ( vec_push [i] . k kids ( __pk_geti . k kids + kstart j ) ) = j + j 1 }
    : b _s ( vec_set [i] . k va target nstart )
}

// Append the run above the topmost MARK to an existing list/dict node.
@ __pk_extend * Pk k i target i mark i pair → b {
    : i n ( vec_len [i] . k stack )
    : i count - - n mark 1
    ? & == pair 1 != % count 2 0 { ^ F } {}
    : i kd ( pk_kind k target )
    ? == pair 1 { ? != kd PK_DICT { ^ F } {} }
    { ? & != kd PK_LIST != kd PK_TUPLE { ^ F } {} }
    ( __pk_make_room k target pair )
    : i kcount ( __pk_geti . k vb target )
    : ~ i j + mark 1
    ~ < j n { ( vec_push [i] . k kids ( __pk_geti . k stack j ) ) = j + j 1 }
    : b _t ( vec_set_len [i] . k stack mark )
    : b _s ( vec_set [i] . k vb target + kcount ? == pair 1 / count 2 count )
    ^ T
}

// ── one opcode ──────────────────────────────────────────────────────
//
// Returns the offset just past the opcode it consumed, -1 on error
// (message recorded in the VM) or -2 on STOP.

@ __pk_step * Pk k * u p i n i at → i {
    : i op ( __pk_u8 p at )
    : i q + at 1

    // ── framing ──
    ? == op 128 {  // PROTO
        ? > + q 1 n { ^ ( __pk_fail k `pickle: truncated PROTO` ) } {}
        ^ + q 1
    } {}
    ? == op 149 {  // FRAME
        ? > + q 8 n { ^ ( __pk_fail k `pickle: truncated FRAME` ) } {}
        ^ + q 8
    } {}
    ? == op 46 {  // STOP
        : b _s ( vec_set [i] . k root 0 ( __pk_pop k ) )
        ^ -2
    } {}

    // ── constants ──
    ? == op 78 { ( __pk_push k ( __pk_node k PK_NONE 0 0 ) ) ^ q } {}  // NONE
    ? == op 136 { ( __pk_push k ( __pk_node k PK_BOOL 1 0 ) ) ^ q } {}  // NEWTRUE
    ? == op 137 { ( __pk_push k ( __pk_node k PK_BOOL 0 0 ) ) ^ q } {}  // NEWFALSE

    // ── integers ──
    ? == op 75 {  // BININT1
        ? > + q 1 n { ^ ( __pk_fail k `pickle: truncated BININT1` ) } {}
        ( __pk_push k ( __pk_node k PK_INT ( __pk_u8 p q ) 0 ) )
        ^ + q 1
    } {}
    ? == op 77 {  // BININT2
        ? > + q 2 n { ^ ( __pk_fail k `pickle: truncated BININT2` ) } {}
        ( __pk_push k ( __pk_node k PK_INT ( __pk_u16 p q ) 0 ) )
        ^ + q 2
    } {}
    ? == op 74 {  // BININT
        ? > + q 4 n { ^ ( __pk_fail k `pickle: truncated BININT` ) } {}
        ( __pk_push k ( __pk_node k PK_INT ( __pk_i32 p q ) 0 ) )
        ^ + q 4
    } {}
    ? == op 138 {  // LONG1
        ? > + q 1 n { ^ ( __pk_fail k `pickle: truncated LONG1` ) } {}
        : i ln ( __pk_u8 p q )
        ? > + + q 1 ln n { ^ ( __pk_fail k `pickle: LONG1 runs past end` ) } {}
        ( __pk_push k ( __pk_node k PK_INT ( __pk_long p + q 1 ln ) 0 ) )
        ^ + + q 1 ln
    } {}
    ? == op 139 {  // LONG4
        ? > + q 4 n { ^ ( __pk_fail k `pickle: truncated LONG4` ) } {}
        : i ln ( __pk_u32 p q )
        ? | < ln 0 > + + q 4 ln n { ^ ( __pk_fail k `pickle: LONG4 runs past end` ) } {}
        ( __pk_push k ( __pk_node k PK_INT ( __pk_long p + q 4 ln ) 0 ) )
        ^ + + q 4 ln
    } {}
    ? == op 71 {  // BINFLOAT
        ? > + q 8 n { ^ ( __pk_fail k `pickle: truncated BINFLOAT` ) } {}
        ( __pk_push k ( __pk_node k PK_FLOAT ( __pk_f64be p q ) 0 ) )
        ^ + q 8
    } {}

    // ── text and bytes ──
    ? | == op 88 == op 140 {  // BINUNICODE / SHORT_BINUNICODE
        : i hdr ? == op 140 1 4
        ? > + q hdr n { ^ ( __pk_fail k `pickle: truncated string header` ) } {}
        : i ln ? == op 140 ( __pk_u8 p q ) ( __pk_u32 p q )
        ? | < ln 0 > + + q hdr ln n { ^ ( __pk_fail k `pickle: string runs past end` ) } {}
        : i si ( vec_len [String] . k strs )
        ( vec_push [String] . k strs ( string_from_bytes # *u + # i p + q hdr ln ) )
        ( __pk_push k ( __pk_node k PK_STR si 0 ) )
        ^ + + q hdr ln
    } {}
    ? | == op 67 == op 66 {  // SHORT_BINBYTES / BINBYTES
        : i hdr ? == op 67 1 4
        ? > + q hdr n { ^ ( __pk_fail k `pickle: truncated bytes header` ) } {}
        : i ln ? == op 67 ( __pk_u8 p q ) ( __pk_u32 p q )
        ? | < ln 0 > + + q hdr ln n { ^ ( __pk_fail k `pickle: bytes run past end` ) } {}
        : i bstart ( vec_len [u] . k blob )
        : ~ i j 0
        ~ < j ln { ( vec_push [u] . k blob . p + + q hdr j ) = j + j 1 }
        ( __pk_push k ( __pk_node k PK_BYTES bstart ln ) )
        ^ + + q hdr ln
    } {}

    // ── memo ──
    ? | == op 113 == op 114 {  // BINPUT / LONG_BINPUT
        : i w ? == op 113 1 4
        ? > + q w n { ^ ( __pk_fail k `pickle: truncated BINPUT` ) } {}
        ( __pk_memo_put k ? == op 113 ( __pk_u8 p q ) ( __pk_u32 p q ) ( __pk_peek k 0 ) )
        ^ + q w
    } {}
    ? == op 148 {  // MEMOIZE
        ( __pk_memo_put k ( vec_len [i] . k memo ) ( __pk_peek k 0 ) )
        ^ q
    } {}
    ? | == op 104 == op 106 {  // BINGET / LONG_BINGET
        : i w ? == op 104 1 4
        ? > + q w n { ^ ( __pk_fail k `pickle: truncated BINGET` ) } {}
        : i id ( __pk_memo_get k ? == op 104 ( __pk_u8 p q ) ( __pk_u32 p q ) )
        ? < id 0 { ^ ( __pk_fail k `pickle: BINGET of an unset memo slot` ) } {}
        ( __pk_push k id )
        ^ + q w
    } {}

    // ── containers ──
    ? == op 40 { ( __pk_push k ( __pk_node k PK_MARK 0 0 ) ) ^ q } {}  // MARK
    ? == op 41 {  // EMPTY_TUPLE
        ( __pk_push k ( __pk_node k PK_TUPLE ( vec_len [i] . k kids ) 0 ) ) ^ q
    } {}
    ? == op 125 {  // EMPTY_DICT
        ( __pk_push k ( __pk_node k PK_DICT ( vec_len [i] . k kids ) 0 ) ) ^ q
    } {}
    ? == op 93 {  // EMPTY_LIST
        ( __pk_push k ( __pk_node k PK_LIST ( vec_len [i] . k kids ) 0 ) ) ^ q
    } {}
    ? | | == op 133 == op 134 == op 135 {  // TUPLE1 / TUPLE2 / TUPLE3
        : i cnt - op 132
        ? < ( __pk_depth k ) cnt { ^ ( __pk_fail k `pickle: TUPLEn underflows the stack` ) } {}
        : i start ( vec_len [i] . k kids )
        : ~ i j - cnt 1
        ~ >= j 0 { ( vec_push [i] . k kids ( __pk_peek k j ) ) = j - j 1 }
        : b _t ( vec_set_len [i] . k stack - ( vec_len [i] . k stack ) cnt )
        ( __pk_push k ( __pk_node k PK_TUPLE start cnt ) )
        ^ q
    } {}
    ? | | == op 116 == op 108 == op 100 {  // TUPLE / LIST / DICT
        : i m ( __pk_find_mark k )
        ? < m 0 { ^ ( __pk_fail k `pickle: container opcode with no MARK` ) } {}
        : i kd ? == op 116 PK_TUPLE ? == op 108 PK_LIST PK_DICT
        ( __pk_push k ( __pk_collapse k kd m ) )
        ^ q
    } {}
    ? | == op 117 == op 101 {  // SETITEMS / APPENDS
        : i m ( __pk_find_mark k )
        ? < m 0 { ^ ( __pk_fail k `pickle: SETITEMS/APPENDS with no MARK` ) } {}
        ? < m 1 { ^ ( __pk_fail k `pickle: SETITEMS/APPENDS with no target` ) } {}
        ? ! ( __pk_extend k ( __pk_geti . k stack - m 1 ) m ? == op 117 1 0 )
        { ^ ( __pk_fail k `pickle: cannot extend that container` ) } {}
        ^ q
    } {}
    ? | == op 115 == op 97 {  // SETITEM / APPEND
        : i pair ? == op 115 1 0
        : i need ? == pair 1 3 2
        ? < ( __pk_depth k ) need { ^ ( __pk_fail k `pickle: SETITEM/APPEND underflows` ) } {}
        : i target ( __pk_peek k - need 1 )
        : i tkd ( pk_kind k target )
        ? == pair 1 { ? != tkd PK_DICT { ^ ( __pk_fail k `pickle: SETITEM on a non-dict` ) } {} }
        { ? & != tkd PK_LIST != tkd PK_TUPLE { ^ ( __pk_fail k `pickle: APPEND to a non-list` ) } {} }
        ( __pk_make_room k target pair )
        : i kcount ( __pk_geti . k vb target )
        ? == pair 1 { ( vec_push [i] . k kids ( __pk_peek k 1 ) ) } {}
        ( vec_push [i] . k kids ( __pk_peek k 0 ) )
        : b _t ( vec_set_len [i] . k stack - ( vec_len [i] . k stack ) - need 1 )
        : b _s ( vec_set [i] . k vb target + kcount 1 )
        ^ q
    } {}

    // ── globals, persistent ids, reduction ──
    ? == op 99 {  // GLOBAL: two newline-terminated lines
        : ~ i e1 q
        ~ & < e1 n != ( __pk_u8 p e1 ) 10 { = e1 + e1 1 }
        ? >= e1 n { ^ ( __pk_fail k `pickle: unterminated GLOBAL module` ) } {}
        : ~ i e2 + e1 1
        ~ & < e2 n != ( __pk_u8 p e2 ) 10 { = e2 + e2 1 }
        ? >= e2 n { ^ ( __pk_fail k `pickle: unterminated GLOBAL name` ) } {}
        : String mods ( string_from_bytes # *u + # i p q - e1 q )
        : String qs ( string_from_bytes # *u + # i p + e1 1 - e2 + e1 1 )
        ( __pk_push k ( __pk_global k ( string_data mods ) ( string_data qs ) ) )
        ( string_free qs )
        ( string_free mods )
        ^ + e2 1
    } {}
    ? == op 147 {  // STACK_GLOBAL
        ? < ( __pk_depth k ) 2 { ^ ( __pk_fail k `pickle: STACK_GLOBAL underflows` ) } {}
        : i qn ( __pk_pop k )
        : i mn ( __pk_pop k )
        ( __pk_push k ( __pk_global k ( pk_str k mn ) ( pk_str k qn ) ) )
        ^ q
    } {}
    ? == op 81 {  // BINPERSID
        // torch's persistent id: ("storage", StorageClass, key, location, numel)
        : i t ( __pk_pop k )
        ? != ( pk_kind k t ) PK_TUPLE { ^ ( __pk_fail k `pickle: persistent id is not a tuple` ) } {}
        ? < ( pk_len k t ) 5 { ^ ( __pk_fail k `pickle: short persistent id` ) } {}
        : i cls ( pk_item k t 1 )
        : i keyn ( pk_item k t 2 )
        : i numn ( pk_item k t 4 )
        ? | != ( pk_kind k cls ) PK_GLOBAL != ( pk_kind k keyn ) PK_STR
        { ^ ( __pk_fail k `pickle: unrecognised persistent id shape` ) } {}
        // "torch.FloatStorage" → the class name after the last dot
        : s full ( pk_str_of_global k cls )
        : i fl ( nurl_str_len full )
        : ~ i dot -1
        : ~ i j 0
        ~ < j fl { ? == ( nurl_str_get full j ) 46 { = dot j } {} = j + j 1 }
        : s cname ? >= dot 0 ( nurl_str_slice full + dot 1 - - fl dot 1 ) full
        : i sid / ( vec_len [i] . k stor ) 3
        ( vec_push [i] . k stor ( pk_storage_class cname ) )
        ( vec_push [i] . k stor ( __pk_intern k ( pk_str k keyn ) ) )
        ( vec_push [i] . k stor ? == ( pk_kind k numn ) PK_INT ( pk_int k numn ) 0 )
        ( __pk_push k ( __pk_node k PK_PERSID sid 0 ) )
        ^ q
    } {}
    ? | == op 82 == op 129 {  // REDUCE / NEWOBJ
        ? < ( __pk_depth k ) 2 { ^ ( __pk_fail k `pickle: REDUCE underflows` ) } {}
        : i args ( __pk_pop k )
        : i callable ( __pk_pop k )
        ( __pk_push k ( __pk_reduce k callable args ) )
        ^ q
    } {}
    ? == op 98 {  // BUILD: obj.__setstate__(state)
        ? < ( __pk_depth k ) 2 { ^ ( __pk_fail k `pickle: BUILD underflows` ) } {}
        : i state ( __pk_pop k )
        : i obj ( __pk_pop k )
        // Nothing is invoked. An opaque object whose state is a dict
        // becomes that dict — which is what a state_dict holder amounts
        // to — otherwise the object stands.
        ? & == ( pk_kind k obj ) PK_OTHER == ( pk_kind k state ) PK_DICT
        { ( __pk_push k state ) } { ( __pk_push k obj ) }
        ^ q
    } {}

    // ── stack shuffling ──
    ? == op 48 { : i _d ( __pk_pop k ) ^ q } {}  // POP
    ? == op 50 { ( __pk_push k ( __pk_peek k 0 ) ) ^ q } {}  // DUP
    ? == op 49 {  // POP_MARK
        : i m ( __pk_find_mark k )
        ? < m 0 { ^ ( __pk_fail k `pickle: POP_MARK with no MARK` ) } {}
        : b _t ( vec_set_len [i] . k stack m )
        ^ q
    } {}

    : String m ( string_from `pickle: unsupported opcode ` )
    ( string_push_int m op )
    : i r ( __pk_fail k ( string_data m ) )
    ( string_free m )
    ^ r
}

@ pk_parse * u p i n → !*Pk String {
    : *Pk k ( pk_new )
    ? <= n 0 {
        ( pk_free k )
        ^ @ !*Pk String { F ( string_from `pickle: empty input` ) }
    } {}
    : ~ i at 0
    : ~ b stopped F
    : ~ b failed F
    // Every opcode consumes at least one byte, so the input length bounds
    // honest work; a stream that somehow fails to advance stops here
    // instead of hanging.
    : ~ i budget + n 1024
    ~ & < at n & ! stopped ! failed {
        : i nxt ( __pk_step k p n at )
        ? == nxt -2 { = stopped T } {}
        ? == nxt -1 { = failed T } {}
        ? & & ! stopped ! failed <= nxt at
        { : i _e ( __pk_fail k `pickle: opcode did not advance` ) = failed T } {}
        ? & ! stopped ! failed { = at nxt } {}
        = budget - budget 1
        ? & <= budget 0 & ! stopped ! failed
        { : i _e ( __pk_fail k `pickle: step budget exhausted` ) = failed T } {}
    }
    ? failed {
        : String em ( string_from ( pk_error k ) )
        ( pk_free k )
        ^ @ !*Pk String { F em }
    } {}
    ? ! stopped {
        ( pk_free k )
        ^ @ !*Pk String { F ( string_from `pickle: stream ended without STOP` ) }
    } {}
    ? < ( pk_root k ) 0 {
        ( pk_free k )
        ^ @ !*Pk String { F ( string_from `pickle: empty pickle` ) }
    } {}
    ^ @ !*Pk String { T k }
}
