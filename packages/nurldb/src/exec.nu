// packages/nurldb/src/exec.nu — statements, run.
//
// A SELECT becomes a tree of operators, each a `% Op` with one method,
// `next inout self → ?( Vec Value )`: pull a row from below, hand one up
// (the Volcano model). The tree is built from the bottom:
//
//   scan          SeqScan, page by page under the transaction's snapshot,
//                 or IndexScan over a range of an index whose leading
//                 columns the WHERE pins down (col = const, then a range)
//   join          HashJoin on an equality between the two tables, or a
//                 nested loop over the right side otherwise
//   Filter        WHERE
//   aggregation   HashAgg (GROUP BY and the aggregates) — or, over a plain
//                 scan of one table, ParAgg: the table's pages dealt out to
//                 worker threads, each aggregating its own, merged after
//   Filter        HAVING
//   Sort          ORDER BY (an alias of the select list may be named)
//   Project       the select list
//   Distinct, Limit
//
// Expressions are evaluated over the row at hand by index into the
// statement's arena (sql.nu); a column is bound to its position before
// the tree is built. NULL follows SQL: arithmetic and comparisons with a
// NULL are NULL, AND / OR are three-valued, WHERE keeps a row only when
// its condition is TRUE.
//
// Writes (INSERT / UPDATE / DELETE) find their rows the way a SELECT
// would, all of them first — the statement does not see its own changes —
// then change them one by one through db.nu.
//
// A session runs SQL text: one statement at a time, in an explicit
// transaction (BEGIN … COMMIT / ROLLBACK) or in one of its own. A
// statement that fails panics — a serialization failure, a deadlock, a
// duplicate key, a type error — and its transaction is rolled back by
// abort: every version it made becomes invisible, and the page latches,
// locks and memory the statement held go with the unwind.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/sort.nu`
$ `db.nu`
$ `sql.nu`

// ── shared expressions ─────────────────────────────────────────────────

: Exprs { ( Arc ( Vec Ex ) ) a }

@ Exprs_share Exprs x → Exprs { ^ @ Exprs { ( arc_clone [( Vec Ex )] . x a ) } }

@ Exprs_drop sink Exprs x → v {}

@ ex_at Exprs x i e → Ex { ^ ( vec_at [Ex] ( arc_get [( Vec Ex )] . x a ) e ) }

@ __fail String why → v { ( panic_with ( string_concat ( string_from `nurldb: ` ) why ) ) }

@ __fails s why → v { ( __fail ( string_from why ) ) }

// ── evaluation ─────────────────────────────────────────────────────────

@ val_true Value v → b { ^ ?? v { VBool y → y _ → F } }

@ __vb b x → Value { ^ @ Value { VBool x } }

@ __is_real Value v → b { ^ ?? v { VReal _ → T _ → F } }

@ __as_f Value v → f { ^ ?? v { VInt x → # f x VReal x → x _ → 0.0 } }

@ __as_i Value v → i { ^ ?? v { VInt x → x _ → 0 } }

@ __numeric Value v → b { ^ ?? v { VInt _ → T VReal _ → T _ → F } }

@ __arith i op Value l Value r → Value {
    ? | ( val_is_null l ) ( val_is_null r ) { ^ @ Value { VNull } } {}
    ? | ! ( __numeric l ) ! ( __numeric r ) { ( __fails `arithmetic on a value that is not a number` ) } {}
    ? | ( __is_real l ) ( __is_real r ) {
        : f x ( __as_f l )
        : f y ( __as_f r )
        ? == op OP_ADD { ^ @ Value { VReal + x y } } {}
        ? == op OP_SUB { ^ @ Value { VReal - x y } } {}
        ? == op OP_MUL { ^ @ Value { VReal * x y } } {}
        ? == y 0.0 { ( __fails `division by zero` ) } {}
        ? == op OP_DIV { ^ @ Value { VReal / x y } } {}
        ^ @ Value { VReal - x * y # f # i / x y }
    } {}
    : i x ( __as_i l )
    : i y ( __as_i r )
    ? == op OP_ADD { ^ @ Value { VInt + x y } } {}
    ? == op OP_SUB { ^ @ Value { VInt - x y } } {}
    ? == op OP_MUL { ^ @ Value { VInt * x y } } {}
    ? == y 0 { ( __fails `division by zero` ) } {}
    ? == op OP_DIV { ^ @ Value { VInt / x y } } {}
    ^ @ Value { VInt % x y }
}

@ __compare i op Value l Value r → Value {
    ? | ( val_is_null l ) ( val_is_null r ) { ^ @ Value { VNull } } {}
    : i c ( val_cmp l r )
    ? == c -2 { ( __fail ( string_concat ( string_from `cannot compare ` ) ( string_concat ( string_from ( ty_name ( val_type l ) ) ) ( string_concat ( string_from ` with ` ) ( string_from ( ty_name ( val_type r ) ) ) ) ) ) ) } {}
    ? == op OP_EQ { ^ ( __vb == c 0 ) } {}
    ? == op OP_NE { ^ ( __vb != c 0 ) } {}
    ? == op OP_LT { ^ ( __vb < c 0 ) } {}
    ? == op OP_LE { ^ ( __vb <= c 0 ) } {}
    ? == op OP_GT { ^ ( __vb > c 0 ) } {}
    ^ ( __vb >= c 0 )
}

// SQL LIKE: % any run, _ any one character (bytewise).
@ __like ( Slice u ) s i si ( Slice u ) p i pi → b {
    : ~ i a si
    : ~ i k pi
    ~ < k ( slice_len [u] p ) {
        : i c ( slice_byte p k )
        ? == c 37 {
            : ~ i t a
            ~ <= t ( slice_len [u] s ) {
                ? ( __like s t p + k 1 ) { ^ T } {}
                = t + t 1
            }
            ^ F
        } {}
        ? >= a ( slice_len [u] s ) { ^ F } {}
        ? & != c 95 != c ( slice_byte s a ) { ^ F } {}
        = a + a 1
        = k + k 1
    }
    ^ == a ( slice_len [u] s )
}

@ __not3 Value v → Value { ^ ?? v { VBool y → @ Value { VBool ! y } _ → @ Value { VNull } } }

// The value of expression `e` over `row`.
@ eval Exprs x i e ( Vec Value ) row → Value {
    : Ex n ( ex_at x e )
    : i k . n kind
    ? == k EX_LIT { ^ ( val_clone . n lit ) } {}
    ? | == k EX_COL == k EX_AGG { ^ ( val_clone ( vec_at [Value] row . n col ) ) } {}
    ? == k EX_UN {
        : Value v ( eval x . n a row )
        ? == . n op OP_NOT { ^ ( __not3 v ) } {}
        ^ ?? v {
            VNull → @ Value { VNull }
            VInt y → @ Value { VInt - 0 y }
            VReal y → @ Value { VReal - 0.0 y }
            _ → { ( __fails `negation of a value that is not a number` ) ^ @ Value { VNull } }
        }
    } {}
    ? == k EX_BIN {
        : i op . n op
        ? == op OP_AND {
            : Value l ( eval x . n a row )
            ? & ! ( val_is_null l ) ! ( val_true l ) { ^ ( __vb F ) } {}
            : Value r ( eval x . n b row )
            ? & ! ( val_is_null r ) ! ( val_true r ) { ^ ( __vb F ) } {}
            ? | ( val_is_null l ) ( val_is_null r ) { ^ @ Value { VNull } } {}
            ^ ( __vb T )
        } {}
        ? == op OP_OR {
            : Value l ( eval x . n a row )
            ? ( val_true l ) { ^ ( __vb T ) } {}
            : Value r ( eval x . n b row )
            ? ( val_true r ) { ^ ( __vb T ) } {}
            ? | ( val_is_null l ) ( val_is_null r ) { ^ @ Value { VNull } } {}
            ^ ( __vb F )
        } {}
        : Value l ( eval x . n a row )
        : Value r ( eval x . n b row )
        ? == op OP_CONCAT {
            ? | ( val_is_null l ) ( val_is_null r ) { ^ @ Value { VNull } } {}
            ^ @ Value { VText ( string_concat ( val_text l ) ( val_text r ) ) }
        } {}
        ? <= op OP_MOD { ^ ( __arith op l r ) } {}
        ^ ( __compare op l r )
    } {}
    ? == k EX_ISNULL {
        : b isn ( val_is_null ( eval x . n a row ) )
        ^ ( __vb ? . n neg ! isn isn )
    } {}
    ? == k EX_LIKE {
        : Value s ( eval x . n a row )
        : Value p ( eval x . n b row )
        ? | ( val_is_null s ) ( val_is_null p ) { ^ @ Value { VNull } } {}
        : String ss ( val_text s )
        : String ps ( val_text p )
        : b m ( __like ( string_bytes ss ) 0 ( string_bytes ps ) 0 )
        ^ ( __vb ? . n neg ! m m )
    } {}
    ? == k EX_BETWEEN {
        : Value v ( eval x . n a row )
        : Value lo ( __compare OP_GE v ( eval x . n b row ) )
        : Value hi ( __compare OP_LE v ( eval x . n c row ) )
        : Value both ?? lo {
            VBool y → ? y ( val_clone hi ) ( __vb F )
            _ → ? & ! ( val_is_null hi ) ! ( val_true hi ) ( __vb F ) @ Value { VNull }
        }
        ^ ? . n neg ( __not3 both ) both
    } {}
    ? == k EX_IN {
        : Value v ( eval x . n a row )
        ? ( val_is_null v ) { ^ @ Value { VNull } } {}
        : ~ b any_null F
        ~ it . n list {
            : Value w ( eval x it row )
            ? ( val_is_null w ) { = any_null T } {
                ? == ( val_cmp v w ) 0 { ^ ( __vb ! . n neg ) } {}
            }
        }
        ? any_null { ^ @ Value { VNull } } {}
        ^ ( __vb . n neg )
    } {}
    ( __fails `an expression it cannot evaluate` )
    ^ @ Value { VNull }
}

@ eval_true Exprs x i e ( Vec Value ) row → b { ^ ( val_true ( eval x e row ) ) }

// ── binding names to positions ─────────────────────────────────────────

// The columns a row has, in order: each one's table (or alias) and name.
: Scope {
    ( Vec String ) quals
    ( Vec String ) names
}

@ scope_new → Scope { ^ @ Scope { ( vec_new [String] ) ( vec_new [String] ) } }

@ scope_add inout Scope sc TableMeta m String qual → v {
    ~ c . m cols {
        ( vec_push [String] . sc quals ( string_clone qual ) )
        ( vec_push [String] . sc names ( string_clone . c name ) )
    }
}

@ __find_in_scope Scope sc String qual String name → i {
    : ~ i found -1
    : ~ i k 0
    ~ < k ( vec_len [String] . sc names ) {
        ? ( string_eq ( vec_at [String] . sc names k ) name ) {
            ? | == 0 ( string_len qual ) ( string_eq ( vec_at [String] . sc quals k ) qual ) {
                ? >= found 0 { ( __fail ( string_concat ( string_from `the column name is ambiguous: ` ) ( string_clone name ) ) ) } {}
                = found k
            } {}
        } {}
        = k + k 1
    }
    ^ found
}

@ __set_col inout ( Vec Ex ) ex i e i col → v { ( vec_update [Ex] ex e \ inout Ex n → v { = . n col col } ) }

// Bind every column under `e` to its position in `sc` (aggregates' too).
@ bind_expr inout ( Vec Ex ) ex i e Scope sc → v {
    ? < e 0 { ^ } {}
    : i kind . ( vec_at [Ex] ex e ) kind
    : i a . ( vec_at [Ex] ex e ) a
    : i b . ( vec_at [Ex] ex e ) b
    : i c . ( vec_at [Ex] ex e ) c
    ? == kind EX_COL {
        : i k ( __find_in_scope sc . ( vec_at [Ex] ex e ) qual . ( vec_at [Ex] ex e ) name )
        ? < k 0 {
            : Ex n ( vec_at [Ex] ex e )
            : String shown ? == 0 ( string_len . n qual ) ( string_clone . n name ) ( string_concat ( string_concat ( string_clone . n qual ) ( string_from `.` ) ) ( string_clone . n name ) )
            ( __fail ( string_concat ( string_from `no such column: ` ) shown ) )
        } {}
        ( __set_col ex e k )
        ^
    } {}
    ( bind_expr ex a sc )
    ( bind_expr ex b sc )
    ( bind_expr ex c sc )
    : ( Vec i ) items ( vec_clone [i] . ( vec_at [Ex] ex e ) list )
    ~ it items { ( bind_expr ex it sc ) }
}

// The aggregates under `e`, in the order met (not inside one another).
@ collect_aggs ( Vec Ex ) ex i e inout ( Vec i ) out → v {
    ? < e 0 { ^ } {}
    : Ex n ( vec_at [Ex] ex e )
    ? == . n kind EX_AGG {
        ? ! ( __has out e ) { ( vec_push [i] out e ) } {}
        ^
    } {}
    ( collect_aggs ex . n a out )
    ( collect_aggs ex . n b out )
    ( collect_aggs ex . n c out )
    ~ it . n list { ( collect_aggs ex it out ) }
}

@ __has ( Vec i ) xs i x → b {
    ~ y xs { ? == y x { ^ T } {} }
    ^ F
}

// After aggregation a row is the GROUP BY values and then the aggregates'.
// Bind `e` to that row: a column must be one grouped by (`gcols`: the
// base position of each GROUP BY column, -1 for an expression), an
// aggregate is at its slot.
@ bind_post inout ( Vec Ex ) ex i e Scope sc ( Vec i ) gcols ( Vec i ) aggs → v {
    ? < e 0 { ^ } {}
    : i kind . ( vec_at [Ex] ex e ) kind
    ? == kind EX_AGG {
        : ~ i slot 0
        ~ < slot ( vec_len [i] aggs ) { ? == ( vec_at [i] aggs slot ) e { break } {} = slot + slot 1 }
        ( __set_col ex e + ( vec_len [i] gcols ) slot )
        ^
    } {}
    ? == kind EX_COL {
        : i base ( __find_in_scope sc . ( vec_at [Ex] ex e ) qual . ( vec_at [Ex] ex e ) name )
        : ~ i g -1
        : ~ i k 0
        ~ < k ( vec_len [i] gcols ) { ? & >= base 0 == ( vec_at [i] gcols k ) base { = g k } {} = k + k 1 }
        ? < g 0 {
            ( __fail ( string_concat ( string_from `the column must appear in GROUP BY or be used in an aggregate: ` ) ( string_clone . ( vec_at [Ex] ex e ) name ) ) )
        } {}
        ( __set_col ex e g )
        ^
    } {}
    : i a . ( vec_at [Ex] ex e ) a
    : i b . ( vec_at [Ex] ex e ) b
    : i c . ( vec_at [Ex] ex e ) c
    ( bind_post ex a sc gcols aggs )
    ( bind_post ex b sc gcols aggs )
    ( bind_post ex c sc gcols aggs )
    : ( Vec i ) items ( vec_clone [i] . ( vec_at [Ex] ex e ) list )
    ~ it items { ( bind_post ex it sc gcols aggs ) }
}

// ── operators ──────────────────────────────────────────────────────────

% Op [T] {
    @ next inout T self → ?( Vec Value )
}

// Rows are handed out of a batch from its end: fill it reversed.
@ __push_reversed inout ( Vec ( Vec Value ) ) buf inout ( Vec ( Vec Value ) ) rows → v {
    ~ T {
        ?? ( vec_pop [( Vec Value )] rows ) { T r → { ( vec_push [( Vec Value )] buf r ) } F → { break } }
    }
}

: SeqScan {
    Store st
    TxnMgr tm
    Snapshot snap
    Table t
    i next
    ( Vec ( Vec Value ) ) buf
}

% Op SeqScan {
    @ next inout SeqScan s → ?( Vec Value ) {
        ~ T {
            ?? ( vec_pop [( Vec Value )] . s buf ) { T r → { ^ @ ?( Vec Value ) { T r } } F → {} }
            ? == . s next NO_PAGE { ^ @ ?( Vec Value ) { F } } {}
            : ~ ( Vec ( Vec Value ) ) rows ( vec_new [( Vec Value )] )
            : ~ ( Vec i ) tids ( vec_new [i] )
            = . s next ( tbl_page_rows . s st . s tm . s snap . s t . s next rows tids )
            ( __push_reversed . s buf rows )
        }
    }
}

: IndexScan {
    Store st
    TxnMgr tm
    Snapshot snap
    Table t
    Index ix
    ( Vec u ) lo
    ( Vec u ) hi
    BtCursor cur
    ( Vec u ) key
}

% Op IndexScan {
    @ next inout IndexScan s → ?( Vec Value ) {
        ~ ( bt_cursor_next . s st . s ix . s cur ( slice_from_vec [u] . s lo ) ( slice_from_vec [u] . s hi ) . s key ) {
            ?? ( tbl_fetch . s st . s tm . s snap . s t ( key_tid ( slice_from_vec [u] . s key ) ) ) {
                T r → { ^ @ ?( Vec Value ) { T r } }
                F → {}
            }
        }
        ^ @ ?( Vec Value ) { F }
    }
}

// One empty row (a SELECT with no FROM).
: OneRow { b done }

% Op OneRow {
    @ next inout OneRow s → ?( Vec Value ) {
        ? . s done { ^ @ ?( Vec Value ) { F } } {}
        = . s done T
        ^ @ ?( Vec Value ) { T ( vec_new [Value] ) }
    }
}

: Filter {
    % Op src
    Exprs x
    i pred
}

% Op Filter {
    @ next inout Filter s → ?( Vec Value ) {
        ~ T {
            : ?( Vec Value ) r ( next . s src )
            ?? r {
                T row → { ? ( eval_true . s x . s pred row ) { ^ @ ?( Vec Value ) { T row } } {} }
                F → { ^ @ ?( Vec Value ) { F } }
            }
        }
    }
}

: Project {
    % Op src
    Exprs x
    ( Vec i ) items  // expression per output column; -1 - k: input column k
}

% Op Project {
    @ next inout Project s → ?( Vec Value ) {
        ?? ( next . s src ) {
            T row → {
                : ( Vec Value ) out ( vec_with_cap [Value] ( vec_len [i] . s items ) )
                ~ it . s items {
                    ? < it 0 { ( vec_push [Value] out ( val_clone ( vec_at [Value] row - -1 it ) ) ) } {
                        ( vec_push [Value] out ( eval . s x it row ) )
                    }
                }
                ^ @ ?( Vec Value ) { T out }
            }
            F → { ^ @ ?( Vec Value ) { F } }
        }
    }
}

: Limit {
    % Op src
    i limit  // -1: none
    i offset
    i seen
}

% Op Limit {
    @ next inout Limit s → ?( Vec Value ) {
        ~ < . s seen . s offset {
            ?? ( next . s src ) { T _ → { = . s seen + . s seen 1 } F → { ^ @ ?( Vec Value ) { F } } }
        }
        ? & >= . s limit 0 >= - . s seen . s offset . s limit { ^ @ ?( Vec Value ) { F } } {}
        ?? ( next . s src ) {
            T row → { = . s seen + . s seen 1 ^ @ ?( Vec Value ) { T row } }
            F → { ^ @ ?( Vec Value ) { F } }
        }
    }
}

// Every row of `src`.
@ drain inout %Op src → ( Vec ( Vec Value ) ) {
    : ( Vec ( Vec Value ) ) out ( vec_new [( Vec Value )] )
    ~ T {
        ?? ( next src ) { T r → { ( vec_push [( Vec Value )] out r ) } F → { break } }
    }
    ^ out
}

: Sort {
    % Op src
    Exprs x
    ( Vec OrderItem ) keys
    ( Vec ( Vec Value ) ) out
    b loaded
}

@ __row_order ( Vec Value ) a ( Vec Value ) b ( Vec b ) desc → i {
    : ~ i k 0
    ~ < k ( vec_len [b] desc ) {
        : i c ( val_order ( vec_at [Value] a k ) ( vec_at [Value] b k ) )
        ? != c 0 { ^ ? ( vec_at [b] desc k ) - 0 c c } {}
        = k + k 1
    }
    ^ 0
}

% Op Sort {
    @ next inout Sort s → ?( Vec Value ) {
        ? ! . s loaded {
            = . s loaded T
            : ( Vec ( Vec Value ) ) rows ( drain . s src )
            : i nk ( vec_len [OrderItem] . s keys )
            : ( Vec b ) desc ( vec_new [b] )
            ~ o . s keys { ( vec_push [b] desc . o desc ) }
            // Each row behind its keys, sorted by them, the keys taken off.
            : ( Vec ( Vec Value ) ) keyed ( vec_with_cap [( Vec Value )] ( vec_len [( Vec Value )] rows ) )
            ~ r rows {
                : ( Vec Value ) kr ( vec_with_cap [Value] + nk ( vec_len [Value] r ) )
                ~ o . s keys { ( vec_push [Value] kr ( eval . s x . o e r ) ) }
                ~ cell r { ( vec_push [Value] kr ( val_clone cell ) ) }
                ( vec_push [( Vec Value )] keyed kr )
            }
            ( sort_by [( Vec Value )] keyed \ ( Vec Value ) a ( Vec Value ) b → i { ^ ( __row_order a b desc ) } )
            // Handed out from the end: reversed.
            : ~ i k - ( vec_len [( Vec Value )] keyed ) 1
            ~ >= k 0 {
                : ( Vec Value ) kr ( vec_at [( Vec Value )] keyed k )
                : ( Vec Value ) row ( vec_with_cap [Value] - ( vec_len [Value] kr ) nk )
                : ~ i j nk
                ~ < j ( vec_len [Value] kr ) { ( vec_push [Value] row ( val_clone ( vec_at [Value] kr j ) ) ) = j + j 1 }
                ( vec_push [( Vec Value )] . s out row )
                = k - k 1
            }
        } {}
        ?? ( vec_pop [( Vec Value )] . s out ) { T r → { ^ @ ?( Vec Value ) { T r } } F → { ^ @ ?( Vec Value ) { F } } }
    }
}

// ── grouping ───────────────────────────────────────────────────────────

// Rows by a key — the first `nkeys` values of each — in a hash table
// (chained through `next`).
: GroupMap {
    ( Vec ( Vec Value ) ) rows
    ( Vec i ) heads
    ( Vec i ) chain
    i nkeys
}

@ gmap_new i nkeys → GroupMap {
    : ( Vec i ) heads ( vec_new [i] )
    : ~ i k 0
    ~ < k 256 { ( vec_push [i] heads -1 ) = k + k 1 }
    ^ @ GroupMap { ( vec_new [( Vec Value )] ) heads ( vec_new [i] ) nkeys }
}

@ __key_hash_of ( Vec Value ) key i n → i {
    : ~ i h 0
    : ~ i k 0
    ~ < k n { = h ^^ * h 1099511628211 ( val_hash ( vec_at [Value] key k ) ) = k + k 1 }
    ^ h
}

@ __same_key ( Vec Value ) a ( Vec Value ) b i n → b {
    : ~ i k 0
    ~ < k n { ? != ( val_order ( vec_at [Value] a k ) ( vec_at [Value] b k ) ) 0 { ^ F } {} = k + k 1 }
    ^ T
}

@ __gmap_grow inout GroupMap m → v {
    : i cap * ( vec_len [i] . m heads ) 2
    ( vec_clear [i] . m heads )
    : ~ i k 0
    ~ < k cap { ( vec_push [i] . m heads -1 ) = k + k 1 }
    = k 0
    ~ < k ( vec_len [( Vec Value )] . m rows ) {
        : i b & ( __key_hash_of ( vec_at [( Vec Value )] . m rows k ) . m nkeys ) - cap 1
        ( vec_put [i] . m chain k ( vec_at [i] . m heads b ) )
        ( vec_put [i] . m heads b k )
        = k + k 1
    }
}

// The row of `key`'s group: found, or made from `fresh` (key and initial
// state).
@ gmap_slot inout GroupMap m ( Vec Value ) key ( @ ( Vec Value ) ) fresh → i {
    : i n . m nkeys
    : i h ( __key_hash_of key n )
    : ~ i k ( vec_at [i] . m heads & h - ( vec_len [i] . m heads ) 1 )
    ~ >= k 0 {
        ? ( __same_key ( vec_at [( Vec Value )] . m rows k ) key n ) { ^ k } {}
        = k ( vec_at [i] . m chain k )
    }
    ? > * ( vec_len [( Vec Value )] . m rows ) 2 ( vec_len [i] . m heads ) { ( __gmap_grow m ) } {}
    : i idx ( vec_len [( Vec Value )] . m rows )
    ( vec_push [( Vec Value )] . m rows ( fresh ) )
    : i b & h - ( vec_len [i] . m heads ) 1
    ( vec_push [i] . m chain ( vec_at [i] . m heads b ) )
    ( vec_put [i] . m heads b idx )
    ^ idx
}

// What an aggregation computes: the GROUP BY expressions, then per
// aggregate four state values — count, sum, min, max — turned into the
// aggregate's value at the end.
: AggSpec {
    Exprs x
    ( Vec i ) group
    ( Vec i ) aggs
}

@ __agg_fresh AggSpec sp ( Vec Value ) key → ( Vec Value ) {
    : ( Vec Value ) r ( vec_with_cap [Value] + ( vec_len [i] . sp group ) * 4 ( vec_len [i] . sp aggs ) )
    ~ cell key { ( vec_push [Value] r ( val_clone cell ) ) }
    ~ _a . sp aggs {
        ( vec_push [Value] r @ Value { VInt 0 } )
        ( vec_push [Value] r @ Value { VNull } )
        ( vec_push [Value] r @ Value { VNull } )
        ( vec_push [Value] r @ Value { VNull } )
    }
    ^ r
}

@ __sum Value acc Value v → Value {
    ? ( val_is_null acc ) { ^ ( val_clone v ) } {}
    ^ ( __arith OP_ADD acc v )
}

@ __min Value acc Value v i sign → Value {
    ? ( val_is_null acc ) { ^ ( val_clone v ) } {}
    : i c ( val_cmp v acc )
    ? == c -2 { ( __fails `MIN / MAX over values that do not compare` ) } {}
    ^ ? == c sign ( val_clone v ) ( val_clone acc )
}

// Fold row `row` into the state of its group (row `g` of the map).
@ __agg_step AggSpec sp inout GroupMap m i g ( Vec Value ) row → v {
    : i ng ( vec_len [i] . sp group )
    : ~ i k 0
    ~ < k ( vec_len [i] . sp aggs ) {
        : Ex a ( ex_at . sp x ( vec_at [i] . sp aggs k ) )
        : i base + ng * 4 k
        : b star < . a a 0
        : Value v ? star @ Value { VInt 1 } ( eval . sp x . a a row )
        ? ! ( val_is_null v ) {
            : i op . a op
            ( vec_update [( Vec Value )] . m rows g \ inout ( Vec Value ) st → v {
                ( vec_put [Value] st base @ Value { VInt + 1 ( __as_i ( vec_at [Value] st base ) ) } )
                ? | == op AG_SUM == op AG_AVG { ( vec_put [Value] st + base 1 ( __sum ( vec_at [Value] st + base 1 ) v ) ) } {}
                ? == op AG_MIN { ( vec_put [Value] st + base 2 ( __min ( vec_at [Value] st + base 2 ) v -1 ) ) } {}
                ? == op AG_MAX { ( vec_put [Value] st + base 3 ( __min ( vec_at [Value] st + base 3 ) v 1 ) ) } {}
            } )
        } {}
        = k + k 1
    }
}

// Fold a group's state from another map's (a worker's) into `g`.
@ __agg_merge AggSpec sp inout GroupMap m i g ( Vec Value ) other → v {
    : i ng ( vec_len [i] . sp group )
    : ~ i k 0
    ~ < k ( vec_len [i] . sp aggs ) {
        : i base + ng * 4 k
        ( vec_update [( Vec Value )] . m rows g \ inout ( Vec Value ) st → v {
            ( vec_put [Value] st base @ Value { VInt + ( __as_i ( vec_at [Value] st base ) ) ( __as_i ( vec_at [Value] other base ) ) } )
            ? ! ( val_is_null ( vec_at [Value] other + base 1 ) ) { ( vec_put [Value] st + base 1 ( __sum ( vec_at [Value] st + base 1 ) ( vec_at [Value] other + base 1 ) ) ) } {}
            ? ! ( val_is_null ( vec_at [Value] other + base 2 ) ) { ( vec_put [Value] st + base 2 ( __min ( vec_at [Value] st + base 2 ) ( vec_at [Value] other + base 2 ) -1 ) ) } {}
            ? ! ( val_is_null ( vec_at [Value] other + base 3 ) ) { ( vec_put [Value] st + base 3 ( __min ( vec_at [Value] st + base 3 ) ( vec_at [Value] other + base 3 ) 1 ) ) } {}
        } )
        = k + k 1
    }
}

// A group's output row: its key, then each aggregate's value.
@ __agg_final AggSpec sp ( Vec Value ) st → ( Vec Value ) {
    : i ng ( vec_len [i] . sp group )
    : ( Vec Value ) out ( vec_with_cap [Value] + ng ( vec_len [i] . sp aggs ) )
    : ~ i k 0
    ~ < k ng { ( vec_push [Value] out ( val_clone ( vec_at [Value] st k ) ) ) = k + k 1 }
    = k 0
    ~ < k ( vec_len [i] . sp aggs ) {
        : i op . ( ex_at . sp x ( vec_at [i] . sp aggs k ) ) op
        : i base + ng * 4 k
        : i cnt ( __as_i ( vec_at [Value] st base ) )
        ? == op AG_COUNT { ( vec_push [Value] out @ Value { VInt cnt } ) } {}
        ? == op AG_SUM { ( vec_push [Value] out ( val_clone ( vec_at [Value] st + base 1 ) ) ) } {}
        ? == op AG_AVG {
            ? == cnt 0 { ( vec_push [Value] out @ Value { VNull } ) } {
                ( vec_push [Value] out @ Value { VReal / ( __as_f ( vec_at [Value] st + base 1 ) ) # f cnt } )
            }
        } {}
        ? == op AG_MIN { ( vec_push [Value] out ( val_clone ( vec_at [Value] st + base 2 ) ) ) } {}
        ? == op AG_MAX { ( vec_push [Value] out ( val_clone ( vec_at [Value] st + base 3 ) ) ) } {}
        = k + k 1
    }
    ^ out
}

@ __group_key AggSpec sp ( Vec Value ) row → ( Vec Value ) {
    : ( Vec Value ) key ( vec_with_cap [Value] ( vec_len [i] . sp group ) )
    ~ g . sp group { ( vec_push [Value] key ( eval . sp x g row ) ) }
    ^ key
}

@ __agg_add AggSpec sp inout GroupMap m ( Vec Value ) row → v {
    : ( Vec Value ) key ( __group_key sp row )
    : i g ( gmap_slot m key \ → ( Vec Value ) { ^ ( __agg_fresh sp key ) } )
    ( __agg_step sp m g row )
}

// The aggregation's output rows, from the map (a query without GROUP BY
// over no rows still has its one row).
@ __agg_output AggSpec sp inout GroupMap m → ( Vec ( Vec Value ) ) {
    ? & == 0 ( vec_len [i] . sp group ) == 0 ( vec_len [( Vec Value )] . m rows ) {
        : i _g ( gmap_slot m ( vec_new [Value] ) \ → ( Vec Value ) { ^ ( __agg_fresh sp ( vec_new [Value] ) ) } )
    } {}
    : ( Vec ( Vec Value ) ) out ( vec_with_cap [( Vec Value )] ( vec_len [( Vec Value )] . m rows ) )
    : ~ i k - ( vec_len [( Vec Value )] . m rows ) 1
    ~ >= k 0 { ( vec_push [( Vec Value )] out ( __agg_final sp ( vec_at [( Vec Value )] . m rows k ) ) ) = k - k 1 }
    ^ out
}

: HashAgg {
    % Op src
    AggSpec sp
    ( Vec ( Vec Value ) ) out
    b loaded
}

% Op HashAgg {
    @ next inout HashAgg s → ?( Vec Value ) {
        ? ! . s loaded {
            = . s loaded T
            : ~ GroupMap m ( gmap_new ( vec_len [i] . . s sp group ) )
            ~ T {
                ?? ( next . s src ) { T row → { ( __agg_add . s sp m row ) } F → { break } }
            }
            = . s out ( __agg_output . s sp m )
        } {}
        ?? ( vec_pop [( Vec Value )] . s out ) { T r → { ^ @ ?( Vec Value ) { T r } } F → { ^ @ ?( Vec Value ) { F } } }
    }
}

// The same aggregation over a table's pages dealt out to `workers`
// threads: each scans every workers-th page under the statement's
// snapshot, keeps the rows WHERE (`pred`, -1 none) keeps, and aggregates
// them into a map of its own; the maps are merged when all are done.
: ParAgg {
    Store st
    TxnMgr tm
    Snapshot snap
    Table t
    i pred
    AggSpec sp
    i workers
    ( Vec ( Vec Value ) ) out
    b loaded
}

@ __par_worker Store st TxnMgr tm Snapshot snap Table t i pred AggSpec sp ( Vec i ) pages i me i n → GroupMap {
    : ~ GroupMap m ( gmap_new ( vec_len [i] . sp group ) )
    : ~ i k me
    ~ < k ( vec_len [i] pages ) {
        : ~ ( Vec ( Vec Value ) ) rows ( vec_new [( Vec Value )] )
        : ~ ( Vec i ) tids ( vec_new [i] )
        : i _nx ( tbl_page_rows st tm snap t ( vec_at [i] pages k ) rows tids )
        ~ row rows {
            ? | < pred 0 ( eval_true . sp x pred row ) { ( __agg_add sp m row ) } {}
        }
        = k + k n
    }
    ^ m
}

% Op ParAgg {
    @ next inout ParAgg s → ?( Vec Value ) {
        ? ! . s loaded {
            = . s loaded T
            : ( Vec i ) pages ( tbl_pages . s st . s t )
            : ( Locked ( Vec GroupMap ) ) parts ( locked_new [( Vec GroupMap )] ( vec_new [GroupMap] ) )
            : ( Vec Thread ) ts ( vec_new [Thread] )
            : ~ i w 0
            ~ < w . s workers {
                : i me w
                : Store st . s st
                : TxnMgr tm . s tm
                : Snapshot snap @ Snapshot { . . s snap xid . . s snap cid . . s snap xmin . . s snap xmax ( vec_clone [i] . . s snap active ) }
                : Table t . s t
                : AggSpec sp @ AggSpec { ( Exprs_share . . s sp x ) ( vec_clone [i] . . s sp group ) ( vec_clone [i] . . s sp aggs ) }
                : i pred . s pred
                : i n . s workers
                : ( Vec i ) pg ( vec_clone [i] pages )
                : !Thread ThreadErr r ( thread_spawn \ → v {
                    : GroupMap m ( __par_worker st tm snap t pred sp pg me n )
                    ( locked_update [( Vec GroupMap )] parts \ inout ( Vec GroupMap ) ps → v { ( vec_push [GroupMap] ps m ) } )
                } )
                ?? r { T h → { ( vec_push [Thread] ts h ) } F _ → { ( __fails `cannot start a scan thread` ) } }
                = w + w 1
            }
            ~ h ts { ( thread_join h ) }
            : ( Vec GroupMap ) got ( locked_take [( Vec GroupMap )] parts )
            ? != ( vec_len [GroupMap] got ) . s workers { ( __fails `a scan thread failed` ) } {}
            : AggSpec spec @ AggSpec { ( Exprs_share . . s sp x ) ( vec_clone [i] . . s sp group ) ( vec_clone [i] . . s sp aggs ) }
            : i ng ( vec_len [i] . spec group )
            : ~ GroupMap m ( gmap_new ng )
            ~ part got {
                ~ prow . part rows {
                    : i g ( gmap_slot m prow \ → ( Vec Value ) { ^ ( __agg_fresh spec ( __key_prefix_of prow ng ) ) } )
                    ( __agg_merge spec m g prow )
                }
            }
            = . s out ( __agg_output spec m )
        } {}
        ?? ( vec_pop [( Vec Value )] . s out ) { T r → { ^ @ ?( Vec Value ) { T r } } F → { ^ @ ?( Vec Value ) { F } } }
    }
}

@ __key_prefix_of ( Vec Value ) row i n → ( Vec Value ) {
    : ( Vec Value ) out ( vec_with_cap [Value] n )
    : ~ i k 0
    ~ < k n { ( vec_push [Value] out ( val_clone ( vec_at [Value] row k ) ) ) = k + k 1 }
    ^ out
}

: Distinct {
    % Op src
    GroupMap seen
}

% Op Distinct {
    @ next inout Distinct s → ?( Vec Value ) {
        ~ T {
            ?? ( next . s src ) {
                T row → {
                    : i before ( vec_len [( Vec Value )] . . s seen rows )
                    : i g ( gmap_slot . s seen row \ → ( Vec Value ) { ^ ( vec_clone_with [Value] row \ Value v → Value { ^ ( val_clone v ) } ) } )
                    ? == g before { ^ @ ?( Vec Value ) { T row } } {}
                }
                F → { ^ @ ?( Vec Value ) { F } }
            }
        }
    }
}

// ── joins ──────────────────────────────────────────────────────────────

// Left rows joined to the right rows `on` holds for — the right side read
// once, into memory.
: NestLoop {
    % Op left
    ( Vec ( Vec Value ) ) right
    Exprs x
    i on
    ( Vec ( Vec Value ) ) out
}

@ __concat ( Vec Value ) a ( Vec Value ) b → ( Vec Value ) {
    : ( Vec Value ) r ( vec_with_cap [Value] + ( vec_len [Value] a ) ( vec_len [Value] b ) )
    ~ cell a { ( vec_push [Value] r ( val_clone cell ) ) }
    ~ cell b { ( vec_push [Value] r ( val_clone cell ) ) }
    ^ r
}

% Op NestLoop {
    @ next inout NestLoop s → ?( Vec Value ) {
        ~ T {
            ?? ( vec_pop [( Vec Value )] . s out ) { T r → { ^ @ ?( Vec Value ) { T r } } F → {} }
            ?? ( next . s left ) {
                T l → {
                    : ~ ( Vec ( Vec Value ) ) hits ( vec_new [( Vec Value )] )
                    ~ r . s right {
                        : ( Vec Value ) j ( __concat l r )
                        ? ( eval_true . s x . s on j ) { ( vec_push [( Vec Value )] hits j ) } {}
                    }
                    ( __push_reversed . s out hits )
                }
                F → { ^ @ ?( Vec Value ) { F } }
            }
        }
    }
}

// An equality join: the right rows in a hash table by their join column,
// each left row probing it with its own.
: HashJoin {
    % Op left
    GroupMap right  // key: the right join value; then the right row
    ( Vec ( Vec Value ) ) rrows
    ( Vec i ) heads
    i lcol
    Exprs x
    i on
    ( Vec ( Vec Value ) ) out
}

% Op HashJoin {
    @ next inout HashJoin s → ?( Vec Value ) {
        ~ T {
            ?? ( vec_pop [( Vec Value )] . s out ) { T r → { ^ @ ?( Vec Value ) { T r } } F → {} }
            ?? ( next . s left ) {
                T l → {
                    : Value key ( val_clone ( vec_at [Value] l . s lcol ) )
                    ? ( val_is_null key ) { continue } {}
                    : ~ ( Vec ( Vec Value ) ) hits ( vec_new [( Vec Value )] )
                    : ( Vec Value ) probe ( vec_new [Value] )
                    ( vec_push [Value] probe key )
                    : i h ( __key_hash_of probe 1 )
                    : ~ i k ( vec_at [i] . . s right heads & h - ( vec_len [i] . . s right heads ) 1 )
                    ~ >= k 0 {
                        : ( Vec Value ) kr ( vec_at [( Vec Value )] . . s right rows k )
                        ? == ( val_order ( vec_at [Value] kr 0 ) ( vec_at [Value] probe 0 ) ) 0 {
                            : ( Vec Value ) j ( __concat l ( vec_at [( Vec Value )] . s rrows ( __as_i ( vec_at [Value] kr 1 ) ) ) )
                            ? ( eval_true . s x . s on j ) { ( vec_push [( Vec Value )] hits j ) } {}
                        } {}
                        = k ( vec_at [i] . . s right chain k )
                    }
                    ( __push_reversed . s out hits )
                }
                F → { ^ @ ?( Vec Value ) { F } }
            }
        }
    }
}

// The right side's rows indexed by column `rcol`: rows with the same key
// share a chain (entries are the key and the row's position).
@ __hash_build ( Vec ( Vec Value ) ) rows i rcol → GroupMap {
    : ~ GroupMap m ( gmap_new 1 )
    : ~ i k 0
    ~ < k ( vec_len [( Vec Value )] rows ) {
        : Value key ( vec_at [Value] ( vec_at [( Vec Value )] rows k ) rcol )
        ? ! ( val_is_null key ) {
            // Not deduplicated: every row its own entry (gmap_slot would
            // merge equal keys), chained by hand.
            : ( Vec Value ) e ( vec_new [Value] )
            ( vec_push [Value] e ( val_clone key ) )
            ( vec_push [Value] e @ Value { VInt k } )
            : i h ( __key_hash_of e 1 )
            ? > * ( vec_len [( Vec Value )] . m rows ) 2 ( vec_len [i] . m heads ) { ( __gmap_grow m ) } {}
            : i b & h - ( vec_len [i] . m heads ) 1
            : i idx ( vec_len [( Vec Value )] . m rows )
            ( vec_push [( Vec Value )] . m rows e )
            ( vec_push [i] . m chain ( vec_at [i] . m heads b ) )
            ( vec_put [i] . m heads b idx )
        } {}
        = k + k 1
    }
    ^ m
}

// ── plans ──────────────────────────────────────────────────────────────

// The conjuncts of a WHERE (its top-level ANDs).
@ __conjuncts ( Vec Ex ) ex i e inout ( Vec i ) out → v {
    ? < e 0 { ^ } {}
    : Ex n ( vec_at [Ex] ex e )
    ? & == . n kind EX_BIN == . n op OP_AND {
        ( __conjuncts ex . n a out )
        ( __conjuncts ex . n b out )
        ^
    } {}
    ( vec_push [i] out e )
}

// `col op const` (or `const op col`) on column `col` of the row: the
// constant's node, and the operator as if the column were on the left; -1
// when the conjunct is not of that shape.
: Pinned { i lit i op }

@ __flip i op → i { ^ ? == op OP_LT OP_GT ? == op OP_GT OP_LT ? == op OP_LE OP_GE ? == op OP_GE OP_LE op }

@ __pinned ( Vec Ex ) ex i e i col → Pinned {
    : Ex n ( vec_at [Ex] ex e )
    ? | != . n kind EX_BIN | < . n op OP_EQ > . n op OP_GE { ^ @ Pinned { -1 0 } } {}
    ? == . n op OP_NE { ^ @ Pinned { -1 0 } } {}
    : Ex l ( vec_at [Ex] ex . n a )
    : Ex r ( vec_at [Ex] ex . n b )
    ? & & == . l kind EX_COL == . l col col == . r kind EX_LIT { ^ @ Pinned { . n b . n op } } {}
    ? & & == . r kind EX_COL == . r col col == . l kind EX_LIT { ^ @ Pinned { . n a ( __flip . n op ) } } {}
    ^ @ Pinned { -1 0 }
}

// Can `v` go into a key of a column of type `ty`?
@ __keyable Value v i ty → b {
    : i vt ( val_type v )
    ? == vt 0 { ^ F } {}
    ? == vt ty { ^ T } {}
    ^ & == vt TY_INT == ty TY_REAL
}

// The index scan a WHERE allows on table `m` (its rows at positions
// [0, n) of the scope): which index, and the key range. -1: none.
: Access {
    i index
    ( Vec u ) lo
    ( Vec u ) hi
    i eqcols
}

@ __pick_access TableMeta m ( Vec Ex ) ex i where_e → Access {
    : ~ ( Vec i ) cj ( vec_new [i] )
    ( __conjuncts ex where_e cj )
    : ~ Access best @ Access { -1 ( vec_new [u] ) ( vec_new [u] ) 0 }
    : ~ i score 0
    : ~ i k 0
    ~ < k ( vec_len [IndexDef] . m indexes ) {
        : IndexDef idef ( vec_at [IndexDef] . m indexes k )
        : IndexImpl ixi ( arc_get [IndexImpl] . . idef ix a )
        : ( Vec u ) pre ( vec_new [u] )
        : ~ i eq 0
        : ~ b more T
        ~ & more < eq ( vec_len [i] . ixi cols ) {
            : i col ( vec_at [i] . ixi cols eq )
            : ~ i found -1
            ~ c cj {
                : Pinned pn ( __pinned ex c col )
                ? & & < found 0 >= . pn lit 0 == . pn op OP_EQ {
                    ? ( __keyable . ( vec_at [Ex] ex . pn lit ) lit ( vec_at [i] . ixi types eq ) ) { = found . pn lit } {}
                } {}
            }
            ? >= found 0 {
                ( key_put pre . ( vec_at [Ex] ex found ) lit ( vec_at [i] . ixi types eq ) )
                = eq + eq 1
            } { = more F }
        }
        : ~ ( Vec u ) lo ( key_lo ( slice_from_vec [u] pre ) )
        : ~ ( Vec u ) hi ( key_hi ( slice_from_vec [u] pre ) )
        : ~ i sc * eq 10
        // A range on the next column narrows it further.
        ? < eq ( vec_len [i] . ixi cols ) {
            : i col ( vec_at [i] . ixi cols eq )
            : i ty ( vec_at [i] . ixi types eq )
            ~ c cj {
                : Pinned pn ( __pinned ex c col )
                ? & >= . pn lit 0 != . pn op OP_EQ {
                    : Value v . ( vec_at [Ex] ex . pn lit ) lit
                    ? ( __keyable v ty ) {
                        : ( Vec u ) kb ( vec_clone [u] pre )
                        ( key_put kb v ty )
                        ? | == . pn op OP_GT == . pn op OP_GE {
                            = lo ? == . pn op OP_GT ( key_hi ( slice_from_vec [u] kb ) ) ( key_lo ( slice_from_vec [u] kb ) )
                        } {
                            = hi ? == . pn op OP_LT ( key_lo ( slice_from_vec [u] kb ) ) ( key_hi ( slice_from_vec [u] kb ) )
                        }
                        = sc + sc 3
                    } {}
                } {}
            }
        } {}
        ? > sc score {
            = score sc
            = best @ Access { k lo hi eq }
        } {}
        = k + k 1
    }
    ^ best
}

@ __snap_copy Snapshot s → Snapshot { ^ @ Snapshot { . s xid . s cid . s xmin . s xmax ( vec_clone [i] . s active ) } }

// The scan of table `m` a statement reads through.
@ __scan Db d Txn x TableMeta m ( Vec Ex ) ex i where_e → %Op {
    : Access acc ( __pick_access m ex where_e )
    ? >= . acc index 0 {
        : IndexDef idef ( vec_at [IndexDef] . m indexes . acc index )
        ^ ( dyn Op @ IndexScan {
            ( db_store d ) ( db_txnmgr d ) ( __snap_copy . x snap ) ( Table_share . m t ) ( Index_share . idef ix )
            ( vec_clone [u] . acc lo ) ( vec_clone [u] . acc hi ) ( bt_cursor ) ( vec_new [u] )
        } )
    } {}
    ^ ( dyn Op @ SeqScan { ( db_store d ) ( db_txnmgr d ) ( __snap_copy . x snap ) ( Table_share . m t ) ( table_root . m t ) ( vec_new [( Vec Value )] ) } )
}

@ __scan_name Db d TableMeta m ( Vec Ex ) ex i where_e → String {
    : Access acc ( __pick_access m ex where_e )
    ? >= . acc index 0 {
        : IndexDef idef ( vec_at [IndexDef] . m indexes . acc index )
        ^ ( string_concat ( string_concat ( string_from `Index Scan using ` ) ( string_clone . idef name ) ) ( string_concat ( string_from ` on ` ) ( string_clone . m name ) ) )
    } {}
    ^ ( string_concat ( string_from `Seq Scan on ` ) ( string_clone . m name ) )
}

@ __table_or_fail Db d String name → TableInfo {
    ^ ?? ( db_table d name ) {
        T t → t
        F → { ( __fail ( string_concat ( string_from `no such table: ` ) ( string_clone name ) ) ) ^ ( __table_or_fail d name ) }
    }
}

// How many threads an aggregation over a seq scan uses.
: ~ i g_par_workers 4

// ── results ────────────────────────────────────────────────────────────

: Result {
    ( Vec String ) cols
    ( Vec ( Vec Value ) ) rows
    i affected
    String tag  // what the statement did: SELECT 3, INSERT 2, BEGIN …
}

@ __result s tag i n → Result {
    : String t ( string_from tag )
    ? >= n 0 { ( string_push_char t 32 ) ( string_push_int t n ) } {}
    ^ @ Result { ( vec_new [String] ) ( vec_new [( Vec Value )] ) ? < n 0 0 n t }
}

@ __col_name ( Vec Ex ) ex SelItem it → String {
    ? > ( string_len . it alias ) 0 { ^ ( string_clone . it alias ) } {}
    : Ex n ( vec_at [Ex] ex . it e )
    ? == . n kind EX_COL { ^ ( string_clone . n name ) } {}
    ? == . n kind EX_AGG {
        : i op . n op
        ^ ( string_from ? == op AG_COUNT `count` ? == op AG_SUM `sum` ? == op AG_AVG `avg` ? == op AG_MIN `min` `max` )
    } {}
    ^ ( string_from `?column?` )
}

// ORDER BY a name of the select list, or its position (`ORDER BY 2`):
// that item's expression.
@ __order_alias ( Vec Ex ) ex ( Vec SelItem ) items i e → i {
    : Ex n ( vec_at [Ex] ex e )
    ? == . n kind EX_LIT {
        : i k ?? . n lit { VInt x → x _ → 0 }
        ? & >= k 1 <= k ( vec_len [SelItem] items ) {
            : i ie . ( vec_at [SelItem] items - k 1 ) e
            ? >= ie 0 { ^ ie } {}
        } {}
        ^ e
    } {}
    ? | != . n kind EX_COL > ( string_len . n qual ) 0 { ^ e } {}
    ~ it items {
        ? & >= . it e 0 ( string_eq . it alias . n name ) { ^ . it e } {}
    }
    ^ e
}

// The plan so far (its top line first) under a new top operator `name`.
@ __plan_wrap inout ( Vec String ) plan s name → v {
    : ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out ( string_from name ) )
    : ~ i k 0
    ~ line plan {
        : String l ( string_from ? == k 0 `  -> ` `     ` )
        ( string_push_str l ( string_data line ) )
        ( vec_push [String] out l )
        = k + k 1
    }
    = plan out
}

// ── SELECT ─────────────────────────────────────────────────────────────

@ exec_select Db d Txn x inout Stmt st → Result {
    : ~ Scope sc ( scope_new )
    : ~ % Op src ( dyn Op @ OneRow { F } )
    : ~ ( Vec String ) plan ( vec_new [String] )
    : ~ b single F
    : ~ i lwidth 0
    ? > ( string_len . st table ) 0 {
        : TableInfo ti ( __table_or_fail d . st table )
        : TableMeta m ( ti_meta ti )
        ( scope_add sc m ? > ( string_len . st alias ) 0 . st alias . st table )
        = lwidth ( vec_len [ColDef] . m cols )
        ? > ( string_len . st jtable ) 0 {
            : TableInfo tj ( __table_or_fail d . st jtable )
            : TableMeta mj ( ti_meta tj )
            ( scope_add sc mj ? > ( string_len . st jalias ) 0 . st jalias . st jtable )
            ( bind_expr . st ex . st on sc )
            ( bind_expr . st ex . st where_e sc )
            // The left table's own conditions pick its scan.
            : ~ Scope ls ( scope_new )
            ( scope_add ls m ? > ( string_len . st alias ) 0 . st alias . st table )
            = src ( __scan d x m . st ex -1 )
            : ~ % Op rsrc ( __scan d x mj . st ex -1 )
            : ( Vec ( Vec Value ) ) rrows ( drain rsrc )
            // An equality between a left and a right column: hash join.
            : ~ ( Vec i ) cj ( vec_new [i] )
            ( __conjuncts . st ex . st on cj )
            : ~ i lcol -1
            : ~ i rcol -1
            ~ c cj {
                : Ex n ( vec_at [Ex] . st ex c )
                ? & & < lcol 0 == . n kind EX_BIN == . n op OP_EQ {
                    : Ex l ( vec_at [Ex] . st ex . n a )
                    : Ex r ( vec_at [Ex] . st ex . n b )
                    ? & == . l kind EX_COL == . r kind EX_COL {
                        ? & < . l col lwidth >= . r col lwidth { = lcol . l col = rcol - . r col lwidth } {}
                        ? & < . r col lwidth >= . l col lwidth { = lcol . r col = rcol - . l col lwidth } {}
                    } {}
                } {}
            }
            : Exprs jx @ Exprs { ( arc_new [( Vec Ex )] ( vec_clone_with [Ex] . st ex \ Ex e → Ex { ^ ( mem_dup e ) } ) ) }
            ? >= lcol 0 {
                : GroupMap hm ( __hash_build rrows rcol )
                = src ( dyn Op @ HashJoin { src hm rrows ( vec_new [i] ) lcol jx . st on ( vec_new [( Vec Value )] ) } )
                ( vec_push [String] plan ( string_from `Hash Join` ) )
            } {
                = src ( dyn Op @ NestLoop { src rrows jx . st on ( vec_new [( Vec Value )] ) } )
                ( vec_push [String] plan ( string_from `Nested Loop` ) )
            }
            : String lsc ( string_from `  -> ` )
            ( string_push_str lsc ( string_data ( __scan_name d m . st ex -1 ) ) )
            ( vec_push [String] plan lsc )
            : String rsc ( string_from `  -> Seq Scan on ` )
            ( string_push_str rsc ( string_data . mj name ) )
            ( vec_push [String] plan rsc )
        } {
            ( bind_expr . st ex . st where_e sc )
            = single T
            = src ( __scan d x m . st ex . st where_e )
            ( vec_push [String] plan ( __scan_name d m . st ex . st where_e ) )
        }
    } {
        ( bind_expr . st ex . st where_e sc )
    }
    // ORDER BY may name a select item.
    : ~ i oi 0
    ~ < oi ( vec_len [OrderItem] . st order ) {
        : i oe ( __order_alias . st ex . st items . ( vec_at [OrderItem] . st order oi ) e )
        ( vec_update [OrderItem] . st order oi \ inout OrderItem o → v { = . o e oe } )
        = oi + oi 1
    }
    // Aggregation?
    : ~ ( Vec i ) aggs ( vec_new [i] )
    ~ it . st items { ( collect_aggs . st ex . it e aggs ) }
    ( collect_aggs . st ex . st having aggs )
    ~ o . st order { ( collect_aggs . st ex . o e aggs ) }
    : b grouped | > ( vec_len [i] aggs ) 0 > ( vec_len [i] . st group ) 0
    ? grouped {
        // Aggregate arguments and GROUP BY see the scanned rows.
        ~ ag aggs { ( bind_expr . st ex . ( vec_at [Ex] . st ex ag ) a sc ) }
        : ( Vec i ) gcols ( vec_new [i] )
        ~ g . st group {
            ( bind_expr . st ex g sc )
            : Ex gn ( vec_at [Ex] . st ex g )
            ( vec_push [i] gcols ? == . gn kind EX_COL . gn col -1 )
        }
        // The rest sees the groups.
        ~ it . st items {
            ? < . it e 0 { ( __fails `SELECT * with GROUP BY or an aggregate` ) } {}
            ( bind_post . st ex . it e sc gcols aggs )
        }
        ( bind_post . st ex . st having sc gcols aggs )
        ~ o . st order { ( bind_post . st ex . o e sc gcols aggs ) }
    } {
        ~ it . st items { ( bind_expr . st ex . it e sc ) }
        ~ o . st order { ( bind_expr . st ex . o e sc ) }
    }
    : Exprs xs @ Exprs { ( arc_new [( Vec Ex )] ( vec_clone_with [Ex] . st ex \ Ex e → Ex { ^ ( mem_dup e ) } ) ) }
    ? & ! grouped >= . st where_e 0 {
        = src ( dyn Op @ Filter { src ( Exprs_share xs ) . st where_e } )
        ( __plan_wrap plan `Filter` )
    } {}
    ? grouped {
        : AggSpec sp @ AggSpec { ( Exprs_share xs ) ( vec_clone [i] . st group ) ( vec_clone [i] aggs ) }
        ? & single & > g_par_workers 1 ! ( __is_index_scan d x st ) {
            : TableInfo ti ( __table_or_fail d . st table )
            = src ( dyn Op @ ParAgg {
                ( db_store d ) ( db_txnmgr d ) ( __snap_copy . x snap ) ( Table_share . ( ti_meta ti ) t ) . st where_e sp g_par_workers ( vec_new [( Vec Value )] ) F
            } )
            ( vec_clear [String] plan )
            : String pa ( string_from `Parallel Aggregate, workers: ` )
            ( string_push_int pa g_par_workers )
            ( vec_push [String] plan pa )
            : String ps ( string_from `  -> Parallel Seq Scan on ` )
            ( string_push_str ps ( string_data . ( ti_meta ti ) name ) )
            ( vec_push [String] plan ps )
        } {
            ? >= . st where_e 0 {
                = src ( dyn Op @ Filter { src ( Exprs_share xs ) . st where_e } )
                ( __plan_wrap plan `Filter` )
            } {}
            = src ( dyn Op @ HashAgg { src sp ( vec_new [( Vec Value )] ) F } )
            ( __plan_wrap plan `Hash Aggregate` )
        }
        ? >= . st having 0 {
            = src ( dyn Op @ Filter { src ( Exprs_share xs ) . st having } )
            ( __plan_wrap plan `Filter (HAVING)` )
        } {}
    } {}
    ? > ( vec_len [OrderItem] . st order ) 0 {
        = src ( dyn Op @ Sort { src ( Exprs_share xs ) ( vec_clone_with [OrderItem] . st order \ OrderItem o → OrderItem { ^ @ OrderItem { . o e . o desc } } ) ( vec_new [( Vec Value )] ) F } )
        ( __plan_wrap plan `Sort` )
    } {}
    // The select list.
    : ( Vec i ) proj ( vec_new [i] )
    : ( Vec String ) cols ( vec_new [String] )
    ~ it . st items {
        ? < . it e 0 {
            : ~ i k 0
            ~ < k ( vec_len [String] . sc names ) {
                ( vec_push [i] proj - -1 k )
                ( vec_push [String] cols ( string_clone ( vec_at [String] . sc names k ) ) )
                = k + k 1
            }
        } {
            ( vec_push [i] proj . it e )
            ( vec_push [String] cols ( __col_name . st ex it ) )
        }
    }
    = src ( dyn Op @ Project { src ( Exprs_share xs ) proj } )
    ? . st distinct {
        = src ( dyn Op @ Distinct { src ( gmap_new ( vec_len [String] cols ) ) } )
        ( __plan_wrap plan `Distinct` )
    } {}
    ? | >= . st limit 0 > . st offset 0 {
        = src ( dyn Op @ Limit { src . st limit . st offset 0 } )
        ( __plan_wrap plan `Limit` )
    } {}
    ? . st explain {
        : ( Vec ( Vec Value ) ) rows ( vec_new [( Vec Value )] )
        ~ line plan {
            : ( Vec Value ) r ( vec_new [Value] )
            ( vec_push [Value] r @ Value { VText ( string_clone line ) } )
            ( vec_push [( Vec Value )] rows r )
        }
        : ( Vec String ) pc ( vec_new [String] )
        ( vec_push [String] pc ( string_from `QUERY PLAN` ) )
        ^ @ Result { pc rows 0 ( string_from `EXPLAIN` ) }
    } {}
    : ( Vec ( Vec Value ) ) rows ( drain src )
    : i n ( vec_len [( Vec Value )] rows )
    : String tag ( string_from `SELECT ` )
    ( string_push_int tag n )
    ^ @ Result { cols rows n tag }
}

@ __is_index_scan Db d Txn x Stmt st → b {
    : TableInfo ti ( __table_or_fail d . st table )
    ^ >= . ( __pick_access ( ti_meta ti ) . st ex . st where_e ) index 0
}

// ── writes ─────────────────────────────────────────────────────────────

// The rows a write changes: their TIDs and current values, found under the
// statement's snapshot before anything changes.
: Targets {
    ( Vec i ) tids
    ( Vec ( Vec Value ) ) rows
}

@ __targets Db d Txn x TableMeta m inout Stmt st → Targets {
    : ~ Scope sc ( scope_new )
    ( scope_add sc m . st table )
    ( bind_expr . st ex . st where_e sc )
    : Exprs xs @ Exprs { ( arc_new [( Vec Ex )] ( vec_clone_with [Ex] . st ex \ Ex e → Ex { ^ ( mem_dup e ) } ) ) }
    : ( Vec i ) tids ( vec_new [i] )
    : ( Vec ( Vec Value ) ) rows ( vec_new [( Vec Value )] )
    : i we . st where_e
    : Access acc ( __pick_access m . st ex we )
    ? >= . acc index 0 {
        : IndexDef idef ( vec_at [IndexDef] . m indexes . acc index )
        : ~ BtCursor cur ( bt_cursor )
        : ~ ( Vec u ) key ( vec_new [u] )
        ~ ( bt_cursor_next ( db_store d ) . idef ix cur ( slice_from_vec [u] . acc lo ) ( slice_from_vec [u] . acc hi ) key ) {
            : i tid ( key_tid ( slice_from_vec [u] key ) )
            ?? ( tbl_fetch ( db_store d ) ( db_txnmgr d ) . x snap . m t tid ) {
                T r → { ? | < we 0 ( eval_true xs we r ) { ( vec_push [i] tids tid ) ( vec_push [( Vec Value )] rows r ) } {} }
                F → {}
            }
        }
    } {
        ( tbl_scan ( db_store d ) ( db_txnmgr d ) . x snap . m t \ i tid ( Vec Value ) row → b {
            ? | < we 0 ( eval_true xs we row ) {
                ( vec_push [i] tids tid )
                ( vec_push [( Vec Value )] rows ( vec_clone_with [Value] row \ Value v → Value { ^ ( val_clone v ) } ) )
            } {}
            ^ T
        } )
    }
    ^ @ Targets { tids rows }
}

@ exec_insert Db d inout Txn x inout Stmt st → Result {
    : TableInfo ti ( __table_or_fail d . st table )
    : TableMeta m ( ti_meta ti )
    : i ncols ( vec_len [ColDef] . m cols )
    // Where each value goes.
    : ( Vec i ) pos ( vec_new [i] )
    ? == 0 ( vec_len [String] . st cols ) {
        : ~ i k 0
        ~ < k ncols { ( vec_push [i] pos k ) = k + k 1 }
    } {
        ~ cn . st cols {
            : i k ( db_find_col m cn )
            ? < k 0 { ( __fail ( string_concat ( string_from `no such column: ` ) ( string_clone cn ) ) ) } {}
            ( vec_push [i] pos k )
        }
    }
    : Exprs xs @ Exprs { ( arc_new [( Vec Ex )] ( vec_clone_with [Ex] . st ex \ Ex e → Ex { ^ ( mem_dup e ) } ) ) }
    : ( Vec Value ) empty ( vec_new [Value] )
    : ~ i n 0
    ~ vals . st rows {
        ? != ( vec_len [i] vals ) ( vec_len [i] pos ) { ( __fails `INSERT has a different number of values than columns` ) } {}
        : ( Vec Value ) row ( vec_with_cap [Value] ncols )
        : ~ i k 0
        ~ < k ncols { ( vec_push [Value] row @ Value { VNull } ) = k + k 1 }
        = k 0
        ~ < k ( vec_len [i] vals ) {
            ( vec_put [Value] row ( vec_at [i] pos k ) ( eval xs ( vec_at [i] vals k ) empty ) )
            = k + k 1
        }
        : i _t ( db_insert d x ti ( db_coerce_row m row ) )
        = n + n 1
    }
    ^ ( __result `INSERT 0` n )
}

@ exec_update Db d inout Txn x inout Stmt st → Result {
    : TableInfo ti ( __table_or_fail d . st table )
    : TableMeta m ( ti_meta ti )
    : Targets tg ( __targets d x m st )
    : ~ Scope sc ( scope_new )
    ( scope_add sc m . st table )
    ~ se . st sets { ( bind_expr . st ex se sc ) }
    : ( Vec i ) pos ( vec_new [i] )
    ~ cn . st cols {
        : i k ( db_find_col m cn )
        ? < k 0 { ( __fail ( string_concat ( string_from `no such column: ` ) ( string_clone cn ) ) ) } {}
        ( vec_push [i] pos k )
    }
    : Exprs xs @ Exprs { ( arc_new [( Vec Ex )] ( vec_clone_with [Ex] . st ex \ Ex e → Ex { ^ ( mem_dup e ) } ) ) }
    : ~ i n 0
    : ~ i k 0
    ~ < k ( vec_len [i] . tg tids ) {
        : ( Vec Value ) old ( vec_at [( Vec Value )] . tg rows k )
        : ( Vec Value ) row ( vec_clone_with [Value] old \ Value v → Value { ^ ( val_clone v ) } )
        : ~ i j 0
        ~ < j ( vec_len [i] pos ) {
            ( vec_put [Value] row ( vec_at [i] pos j ) ( eval xs ( vec_at [i] . st sets j ) old ) )
            = j + j 1
        }
        ? >= ( db_update d x ti ( vec_at [i] . tg tids k ) ( db_coerce_row m row ) ) 0 { = n + n 1 } {}
        = k + k 1
    }
    ^ ( __result `UPDATE` n )
}

@ exec_delete Db d inout Txn x inout Stmt st → Result {
    : TableInfo ti ( __table_or_fail d . st table )
    : TableMeta m ( ti_meta ti )
    : Targets tg ( __targets d x m st )
    : ~ i n 0
    ~ tid . tg tids { ? ( db_delete d x ti tid ) { = n + n 1 } {} }
    ^ ( __result `DELETE` n )
}

// ── sessions ───────────────────────────────────────────────────────────

: Session {
    Db d
    b in_txn
    Txn txn
}

@ session_new Db d → Session { ^ @ Session { ( Db_share d ) F @ Txn { 0 @ Snapshot { 0 0 0 0 ( vec_new [i] ) } 0 F } } }

@ __create_table_stmt Db d Stmt st → !Result String {
    : ( Vec ColDef ) cols ( vec_new [ColDef] )
    ~ c . st defs { ( vec_push [ColDef] cols @ ColDef { ( string_clone . c name ) . c ty . c notnull } ) }
    ^ ?? ( db_create_table d . st table cols ( vec_clone_with [String] . st cols \ String s → String { ^ ( string_clone s ) } ) ) {
        T _ → @ !Result String { T ( __result `CREATE TABLE` -1 ) }
        F e → @ !Result String { F e }
    }
}

// Run one statement of SQL text: its result, or why it failed (the
// transaction it ran in is rolled back then).
@ session_exec inout Session s String sql → !Result String {
    : ~ Stmt st ( stmt_new 0 )
    : ~ String perr ( string_new )
    : !v PanicInfo pr ( recover \ → v { = st ( sql_parse sql ) } )
    ?? pr { T _ → {} F p → { = perr ( string_clone . p msg ) ( panic_info_free p ) } }
    ? > ( string_len perr ) 0 { ^ @ !Result String { F perr } } {}
    : Db d ( Db_share . s d )
    : i kind . st kind
    ? == kind ST_BEGIN {
        ? . s in_txn { ^ @ !Result String { F ( string_from `nurldb: a transaction is already in progress` ) } } {}
        = . s txn ( db_begin d )
        = . s in_txn T
        ^ @ !Result String { T ( __result `BEGIN` -1 ) }
    } {}
    ? | == kind ST_COMMIT == kind ST_ROLLBACK {
        ? ! . s in_txn { ^ @ !Result String { F ( string_from `nurldb: no transaction is in progress` ) } } {}
        = . s in_txn F
        ? == kind ST_COMMIT { ( db_commit d . s txn ) ^ @ !Result String { T ( __result `COMMIT` -1 ) } } {}
        ( db_abort d . s txn )
        ^ @ !Result String { T ( __result `ROLLBACK` -1 ) }
    } {}
    ? | | == kind ST_CREATE_TABLE == kind ST_CREATE_INDEX == kind ST_CHECKPOINT {
        ? . s in_txn { ^ @ !Result String { F ( string_from `nurldb: CREATE and CHECKPOINT run outside a transaction` ) } } {}
        ? == kind ST_CHECKPOINT { ( db_checkpoint d ) ^ @ !Result String { T ( __result `CHECKPOINT` -1 ) } } {}
        ? == kind ST_CREATE_TABLE { ^ ( __create_table_stmt d st ) } {}
        ^ ?? ( db_create_index d . st name . st table ( vec_clone_with [String] . st cols \ String c → String { ^ ( string_clone c ) } ) . st unique ) {
            T _ → @ !Result String { T ( __result `CREATE INDEX` -1 ) }
            F e → @ !Result String { F e }
        }
    } {}
    // A statement that reads or writes rows: in the session's transaction,
    // or one of its own.
    : b own ! . s in_txn
    ? own { = . s txn ( db_begin d ) } {}
    : ~ Result res ( __result `` -1 )
    : ~ String err ( string_new )
    {
        : ( RGuard i ) latch ( db_stmt_latch d )
        ( db_statement . s txn )
        : !v PanicInfo r ( recover \ → v {
            ? == kind ST_SELECT { = res ( exec_select d . s txn st ) } {}
            ? == kind ST_INSERT { = res ( exec_insert d . s txn st ) } {}
            ? == kind ST_UPDATE { = res ( exec_update d . s txn st ) } {}
            ? == kind ST_DELETE { = res ( exec_delete d . s txn st ) } {}
        } )
        ?? r { T _ → {} F p → { = err ( string_clone . p msg ) ( panic_info_free p ) } }
    }
    ? > ( string_len err ) 0 {
        ( db_abort d . s txn )
        = . s in_txn F
        ^ @ !Result String { F err }
    } {}
    ? own { ( db_commit d . s txn ) } {}
    ^ @ !Result String { T res }
}

// End the session: an open transaction is rolled back.
@ session_close inout Session s → v {
    ? . s in_txn { ( db_abort . s d . s txn ) = . s in_txn F } {}
}

// ── text ───────────────────────────────────────────────────────────────

// A result as a text table (what the shell prints).
@ result_text Result r → String {
    : String out ( string_new )
    : i nc ( vec_len [String] . r cols )
    ? == nc 0 { ( string_push_str out ( string_data . r tag ) ) ( string_push_char out 10 ) ^ out } {}
    : ( Vec i ) w ( vec_new [i] )
    ~ c . r cols { ( vec_push [i] w ( string_len c ) ) }
    : ( Vec ( Vec String ) ) cells ( vec_new [( Vec String )] )
    ~ row . r rows {
        : ( Vec String ) cs ( vec_new [String] )
        : ~ i k 0
        ~ cell row {
            : String t ( val_text cell )
            ? > ( string_len t ) ( vec_at [i] w k ) { ( vec_put [i] w k ( string_len t ) ) } {}
            ( vec_push [String] cs t )
            = k + k 1
        }
        ( vec_push [( Vec String )] cells cs )
    }
    : ~ i k 0
    ~ c . r cols {
        ? > k 0 { ( string_push_str out ` | ` ) } {}
        ( __pad out c ( vec_at [i] w k ) )
        = k + k 1
    }
    ( string_push_char out 10 )
    = k 0
    ~ < k nc {
        ? > k 0 { ( string_push_str out `-+-` ) } {}
        : ~ i j 0
        ~ < j ( vec_at [i] w k ) { ( string_push_char out 45 ) = j + j 1 }
        = k + k 1
    }
    ( string_push_char out 10 )
    ~ cs cells {
        = k 0
        ~ c cs {
            ? > k 0 { ( string_push_str out ` | ` ) } {}
            ( __pad out c ( vec_at [i] w k ) )
            = k + k 1
        }
        ( string_push_char out 10 )
    }
    ( string_push_char out 40 )
    ( string_push_int out ( vec_len [( Vec Value )] . r rows ) )
    ( string_push_str out ? == ( vec_len [( Vec Value )] . r rows ) 1 ` row)` ` rows)` )
    ( string_push_char out 10 )
    ^ out
}

@ __pad String out String s i width → v {
    ( string_push_str out ( string_data s ) )
    : ~ i k ( string_len s )
    ~ < k width { ( string_push_char out 32 ) = k + k 1 }
}
