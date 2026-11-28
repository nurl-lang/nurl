// coreir.nu — nurlc's core IR (`nurlc --emit-core`) read into records.
//
// The text is docs/dev/CORE_IR.md §2: tab-separated header lines and one
// statement a line.
//
//   fn    <name> <return type> <parameters> <line> <file> <flags> <template>
//   v     <id> <kind> <depth> <flags> <line> <value block> <name> <type>
//   <statements>
//   endfn
//   ty    <type> <class> <drops> <base> A <n> <type>… F <n> (<field> <type>)… V <n> (<variant> <n> <type>…)…
//   virt  <virtual callee> <impl function>…
//   sum   <function> <parameters> (<key>=<words>)…
//
// One reader for every tool that reads the IR (the certificate's
// translator, tolean.nu, first). It keeps what the text says and decides
// nothing: a function's variables in the order of their `v` lines, its
// statements as lines and as words, each `ty`, `sum` and `virt` line as a
// record. Where a name has more than one record (a `sum` or a `ty` line
// printed twice), the lookups answer the last one, and a variable's id
// its last `v` line.
//
// Lines are split as Python's `str.splitlines` splits ASCII text, and a
// statement's words at ASCII whitespace, so a reader written against the
// Python prototypes (tools/ncore) sees the same lines and words.
//
// A text that is not such an IR is refused (`internal: line N …`), never
// read as something else: a column a record needs that is not an integer
// (as Python's `int()` reads one, within 64 bits; a variable's id within
// core_id_max), a `ty` line with fewer fields than it counts, an `endfn`
// with no function open. So is, deliberately stricter than the retired
// Python prototype was (it read these), what is malformed in shape
// (`internal: line N of the core IR: malformed: …`): a count below 0 (a
// parameter, field, type-argument, variant or payload count), a type
// argument, variant or payload count past what the line holds (or, for
// the type arguments, short of it), columns after its variants, a variable
// id below 0 or a kind outside 0–3, an `fn` line while a function is
// open, and the input ending inside a function. An informative column that
// is not an integer (a source line, a depth, a value block, a function's
// flags, a sum's parameter count) is noted in `CoreIR.bad`, which
// core_read_strict refuses. Variable ids are indexed sparsely: an id costs what its record
// costs, whatever its size.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/hashmap.nu`

// A variable of a function (a `v` line).
: CoreVar {
    i id
    i kind
    i depth
    i flags
    i line
    i vblock
    String name
    String ty
}

// A function (`fn` … `endfn`).
: CoreFn {
    String name
    String ret
    i np
    i line
    String file
    i flags
    String template
    ( Vec CoreVar ) vars
    // the variables' ids, sorted, each once, and each one's record in
    // `vars` (its last `v` line): a sparse index (ids need not be dense)
    ( Vec i ) vids
    ( Vec i ) vrec
    // every statement's words (a statement is a line: its count is
    // wstart's length less 1 once the function is sealed), line after line: line k's are
    // words[wstart[k] .. wstart[k + 1])
    ( Vec String ) words
    ( Vec i ) wstart
}

// A type (`ty`): its columns, its fields and its variants.
: CoreTy {
    String name
    String cls
    String drops
    String base
    ( Vec String ) targs
    ( Vec String ) fnames
    ( Vec String ) ftys
    ( Vec String ) vnames
    // variant k's payload types are vtys[vstart[k] .. vstart[k + 1])
    ( Vec i ) vstart
    ( Vec String ) vtys
}

// What the walk's summary holds for a function (`sum`): key=value pairs,
// in the line's order.
: CoreSum {
    String name
    i np
    ( Vec String ) keys
    ( Vec String ) vals
}

// The impl functions a `dyn` method call may run (`virt`).
: CoreVirt {
    String callee
    ( Vec String ) impls
}

: CoreIR {
    ( Vec CoreFn ) fns
    ( Vec CoreTy ) tys
    ( Vec CoreSum ) sums
    ( Vec CoreVirt ) virts
    ( HashMap String i ) ty_of
    ( HashMap String i ) sum_of
    // the informative columns that were not integers (each read as 0, a
    // value block as -1): a reader that relies on them refuses the IR
    // when this is not empty (`core_read_strict`)
    ( Vec String ) bad
}

// ── Characters and words ─────────────────────────────────────────────

// ASCII whitespace as Python's str.split / str.strip take it.
@ core_is_ws i c → b { ^ | | == c 32 & >= c 9 <= c 13 & >= c 28 <= c 31 }

// A line break as Python's str.splitlines takes it (\n, \r, \v, \f, \x1c–\x1e).
@ __cr_is_nl i c → b { ^ | | | == c 10 == c 13 | == c 11 == c 12 & >= c 28 <= c 30 }

// The whitespace-separated words of t[a, z), pushed onto `out`.
@ core_split_words ( Slice u ) t i a i z ( Vec String ) out → v {
    : ~ i k a
    ~ < k z {
        ~ & < k z ( core_is_ws ( slice_byte t k ) ) { = k + k 1 }
        ? < k z {
            : ~ i e k
            ~ & < e z ! ( core_is_ws ( slice_byte t e ) ) { = e + e 1 }
            : String w ( string_new )
            ( string_push_window w t k - e k )
            ( vec_push [String] out w )
            = k e
        } {}
    }
}

// The tab-separated columns of t[a, z) (an empty one kept).
@ __cr_split_tabs ( Slice u ) t i a i z → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : ~ i k a
    : ~ b more T
    ~ more {
        : ~ i e k
        ~ & < e z != ( slice_byte t e ) 9 { = e + e 1 }
        : String w ( string_new )
        ( string_push_window w t k - e k )
        ( vec_push [String] out w )
        ? < e z { = k + e 1 } { = more F }
    }
    ^ out
}

// The integer `text` is, read as Python's `int()` reads a decimal: ASCII
// whitespace around it, an optional sign, digits with single `_` between
// them. `mode` says what a number past 64 bits is: 0 none, 1 its value
// modulo 2^64 (two's complement: what a test of its bits sees), 2 the
// largest (smallest) 64-bit one. None when `text` is not a number.
@ core_parse_int_mode s text i mode → ?i {
    : ( Slice u ) t ( slice_of_str text )
    : ~ i n ( slice_len [u] t )
    : ~ i k 0
    ~ & < k n ( core_is_ws ( slice_byte t k ) ) { = k + k 1 }
    ~ & > n k ( core_is_ws ( slice_byte t - n 1 ) ) { = n - n 1 }
    : ~ b neg F
    ? & < k n | == ( slice_byte t k ) 45 == ( slice_byte t k ) 43 {
        = neg == ( slice_byte t k ) 45
        = k + k 1
    } {}
    ? >= k n { ^ @ ?i { F 0 } } {}
    : i lim 9223372036854775807
    : ~ i v 0
    : ~ b over F
    : ~ b prev_digit F
    ~ < k n {
        : i c ( slice_byte t k )
        ? == c 95 {
            // `_` only between two digits
            ? | ! prev_digit >= + k 1 n { ^ @ ?i { F 0 } } {}
            = prev_digit F
        } {
            ? | < c 48 > c 57 { ^ @ ?i { F 0 } } {}
            : i d - c 48
            ? > v / - lim d 10 { = over T } {}
            // (wraps past 64 bits: the value modulo 2^64)
            = v + * v 10 d
            = prev_digit T
        }
        = k + k 1
    }
    ? ! prev_digit { ^ @ ?i { F 0 } } {}
    ? & over == mode 0 { ^ @ ?i { F 0 } } {}
    ? & over == mode 2 { ^ @ ?i { T ? neg - - 0 lim 1 lim } } {}
    ^ @ ?i { T ? neg - 0 v v }
}

// The integer `text` is (Python's `int()`), none past 64 bits.
@ core_parse_int s text → ?i { ^ ( core_parse_int_mode text 0 ) }

// The bound on a variable's id: nurlc numbers a function's variables from
// 0; one past 2^62 is not an IR it prints, and A2's numbering of it would
// not fit 64 bits.
@ core_id_max → i { ^ 4611686018427387904 }

@ __cr_col ( Vec String ) f i k → s {
    ? < k ( vec_len [String] f ) { ^ ( string_data ( vec_at [String] f k ) ) } {}
    ^ ``
}

@ __cr_is ( Vec String ) f i k s want → b { ^ != 0 ( nurl_str_eq ( __cr_col f k ) want ) }

@ __cr_hash String x → i { ^ ( hash_string ( string_data x ) ) }

@ __cr_eq String a String b → b { ^ ( eq_string ( string_data a ) ( string_data b ) ) }

// ── The reader ───────────────────────────────────────────────────────
//
// A line that does not say what its kind says (a column missing or not an
// integer where one is needed, fewer fields than it counts, an `endfn` with
// no function open) stops the read: the IR is not one nurlc prints, and
// what it would mean is not guessed.

@ __cr_bad i line s what → String {
    : String o ( string_from `internal: line ` )
    ( string_push_int o line )
    ( string_push_str o ` of the core IR: ` )
    ( string_push_str o what )
    ^ o
}

// A line that is malformed where the retired Python prototype read it anyway
// (a count below 0, a function left open, …): refused all the same, and
// named `malformed` (deliberately stricter than the prototype).
@ __cr_mal i line s what → String {
    : String w ( string_from `malformed: ` )
    ( string_push_str w what )
    ^ ( __cr_bad line ( string_data w ) )
}

// A count the retired Python prototype never read (a type's argument, variant
// and payload counts), as an integer: one that is not is malformed.
@ __cr_count ( Vec String ) f i k i line s what → !i String {
    ?? ( core_parse_int ( __cr_col f k ) ) {
        T v → { ^ @ !i String { T v } }
        F → {}
    }
    : String w ( string_from what )
    ( string_push_str w ` is not an integer: ` )
    ( string_push_str w ( __cr_col f k ) )
    ^ @ !i String { F ( __cr_mal line ( string_data w ) ) }
}

// Column k of `f` as an integer (core_parse_int_mode's `mode`).
@ __cr_num ( Vec String ) f i k i mode i line s what → !i String {
    ?? ( core_parse_int_mode ( __cr_col f k ) mode ) {
        T v → { ^ @ !i String { T v } }
        F → {}
    }
    : String w ( string_from what )
    ( string_push_str w ` is not an integer: ` )
    ( string_push_str w ( __cr_col f k ) )
    ^ @ !i String { F ( __cr_bad line ( string_data w ) ) }
}

// An informative column (a source line, a depth, a count no reader
// relies on): a value that is not an integer is noted in `bad` (the line
// and the column) and read as `dflt`.
@ __cr_info ( Vec String ) f i k i dflt i line s what ( Vec String ) bad → i {
    ?? ( core_parse_int ( __cr_col f k ) ) {
        T v → { ^ v }
        F → {}
    }
    : String w ( string_from what )
    ( string_push_str w ` is not an integer: ` )
    ( string_push_str w ( __cr_col f k ) )
    ( vec_push [String] bad ( __cr_bad line ( string_data w ) ) )
    ^ dflt
}

@ __cr_ty ( Vec String ) f i line ( Vec String ) bad → !CoreTy String {
    : ( Vec String ) targs ( vec_new [String] )
    : ( Vec String ) fnames ( vec_new [String] )
    : ( Vec String ) ftys ( vec_new [String] )
    : ( Vec String ) vnames ( vec_new [String] )
    : ( Vec i ) vstart ( vec_new [i] )
    : ( Vec String ) vtys ( vec_new [String] )
    : i n ( vec_len [String] f )
    // ty <type> <class> <drops> <base> A <n> … F <n> … V <n> …
    // The fields are what every reader relies on: they start at the first
    // column `F` (as tools/ncore reads them), with a count and that many
    // complete pairs. The type arguments and the variants are read where
    // they are well formed, and noted in `bad` where not.
    : ~ i fi 0
    ~ & < fi n ! ( __cr_is f fi `F` ) { = fi + fi 1 }
    ? >= fi n { ^ @ !CoreTy String { F ( __cr_bad line `a ty line without its fields (F)` ) } } {}
    : i nf \ ( __cr_num f + fi 1 0 line `a ty line's field count` )
    ? < nf 0 { ^ @ !CoreTy String { F ( __cr_mal line `a ty line's field count below 0` ) } } {}
    : ~ i k + fi 2
    ? > nf / - n k 2 { ^ @ !CoreTy String { F ( __cr_bad line `a ty line with fewer fields than it counts` ) } } {}
    : ~ i j 0
    ~ < j nf {
        ( vec_push [String] fnames ( string_from ( __cr_col f k ) ) )
        ( vec_push [String] ftys ( string_from ( __cr_col f + k 1 ) ) )
        = k + k 2
        = j + j 1
    }
    : i after k
    // (the type arguments, when there is an `A`, are exactly the columns
    // between its count and `F`; with none, `F` follows the base)
    ? ( __cr_is f 5 `A` ) {
        : i na \ ( __cr_count f 6 line `a ty line's type-argument count` )
        ? < na 0 { ^ @ !CoreTy String { F ( __cr_mal line `a ty line's type-argument count below 0` ) } } {}
        ? > na - - fi 7 0 { ^ @ !CoreTy String { F ( __cr_mal line `a ty line with fewer type arguments than it counts` ) } } {}
        ? < na - - fi 7 0 { ^ @ !CoreTy String { F ( __cr_mal line `a ty line with more type arguments than it counts` ) } } {}
        = j 0
        ~ < j na {
            ( vec_push [String] targs ( string_from ( __cr_col f + 7 j ) ) )
            = j + j 1
        }
    } {
        ? != fi 5 { ^ @ !CoreTy String { F ( __cr_mal line `a ty line with columns between its base and its fields` ) } } {}
    }
    ? ( __cr_is f after `V` ) {
        : i nv \ ( __cr_count f + after 1 line `a ty line's variant count` )
        ? < nv 0 { ^ @ !CoreTy String { F ( __cr_mal line `a ty line's variant count below 0` ) } } {}
        = k + after 2
        = j 0
        ~ < j nv {
            ? >= + k 1 n { ^ @ !CoreTy String { F ( __cr_mal line `a ty line with fewer variants than it counts` ) } } {}
            ( vec_push [String] vnames ( string_from ( __cr_col f k ) ) )
            ( vec_push [i] vstart ( vec_len [String] vtys ) )
            : i np \ ( __cr_count f + k 1 line `a variant's payload count` )
            = k + k 2
            ? < np 0 { ^ @ !CoreTy String { F ( __cr_mal line `a variant's payload count below 0` ) } } {}
            ? > np - n k { ^ @ !CoreTy String { F ( __cr_mal line `a variant with fewer payloads than it counts` ) } } {}
            : ~ i q 0
            ~ < q np {
                ( vec_push [String] vtys ( string_from ( __cr_col f k ) ) )
                = k + k 1
                = q + q 1
            }
            = j + j 1
        }
        ? < k n { ^ @ !CoreTy String { F ( __cr_mal line `a ty line with columns after its variants` ) } } {}
    } {
        ? < after n { ^ @ !CoreTy String { F ( __cr_mal line `a ty line with columns after its fields` ) } } {}
    }
    ( vec_push [i] vstart ( vec_len [String] vtys ) )
    ^ @ !CoreTy String { T @ CoreTy { ( string_from ( __cr_col f 1 ) ) ( string_from ( __cr_col f 2 ) ) ( string_from ( __cr_col f 3 ) )
            ( string_from ( __cr_col f 4 ) ) targs fnames ftys vnames vstart vtys } }
}

@ __cr_sum ( Vec String ) f i line ( Vec String ) bad → !CoreSum String {
    : ( Vec String ) keys ( vec_new [String] )
    : ( Vec String ) vals ( vec_new [String] )
    : i n ( vec_len [String] f )
    ? < n 2 { ^ @ !CoreSum String { F ( __cr_bad line `a sum line without its function` ) } } {}
    : ~ i np 0
    ? > n 2 { = np ( __cr_info f 2 0 line `a sum line's parameter count` bad ) } {}
    : ~ i k 3
    ~ < k n {
        : String kv ( vec_at [String] f k )
        ?? ( string_index_of kv `=` ) {
            T e → {
                ( vec_push [String] keys ( string_substr kv 0 e ) )
                ( vec_push [String] vals ( string_substr kv + e 1 - - ( string_len kv ) e 1 ) )
            }
            F → {}
        }
        = k + k 1
    }
    ^ @ !CoreSum String { T @ CoreSum { ( string_from ( __cr_col f 1 ) ) np keys vals } }
}

@ __cr_empty_fn → CoreFn {
    ^ @ CoreFn { ( string_new ) ( string_new ) 0 0 ( string_new ) 0 ( string_new ) ( vec_new [CoreVar] ) ( vec_new [i] )
        ( vec_new [i] ) ( vec_new [String] ) ( vec_new [i] ) }
}

@ __cr_new_fn ( Vec String ) f i line ( Vec String ) bad → !CoreFn String {
    : i n ( vec_len [String] f )
    ? < n 6 { ^ @ !CoreFn String { F ( __cr_bad line `an fn line without its columns` ) } } {}
    : i np \ ( __cr_num f 3 0 line `an fn line's parameter count` )
    ? < np 0 { ^ @ !CoreFn String { F ( __cr_mal line `an fn line's parameter count below 0` ) } } {}
    : i ln ( __cr_info f 4 0 line `an fn line's source line` bad )
    : ~ i fl 0
    ? > n 6 { = fl ( __cr_info f 6 0 line `an fn line's flags` bad ) } {}
    ^ @ !CoreFn String { T @ CoreFn { ( string_from ( __cr_col f 1 ) ) ( string_from ( __cr_col f 2 ) ) np ln
            ( string_from ( __cr_col f 5 ) ) fl ( string_from ( __cr_col f 7 ) ) ( vec_new [CoreVar] ) ( vec_new [i] )
            ( vec_new [i] ) ( vec_new [String] ) ( vec_new [i] ) } }
}

@ __cr_var ( Vec String ) f i line ( Vec String ) bad → !CoreVar String {
    : i n ( vec_len [String] f )
    ? < n 5 { ^ @ !CoreVar String { F ( __cr_bad line `a v line without its columns` ) } } {}
    : i id \ ( __cr_num f 1 0 line `a variable's id` )
    ? > id ( core_id_max ) { ^ @ !CoreVar String { F ( __cr_bad line `a variable's id past the bound (2^62)` ) } } {}
    ? < id 0 { ^ @ !CoreVar String { F ( __cr_mal line `a variable's id below 0` ) } } {}
    // (a kind is compared, a flag word tested by its bits: past 64 bits,
    // the largest kind, the flags' low 64 bits)
    : i kind \ ( __cr_num f 2 2 line `a variable's kind` )
    ? | < kind 0 > kind 3 { ^ @ !CoreVar String { F ( __cr_mal line `a variable's kind is not 0 to 3` ) } } {}
    : i flags \ ( __cr_num f 4 1 line `a variable's flags` )
    // (a whole record: its depth, line and value block too)
    : ~ i depth 0
    : ~ i ln 0
    : ~ i vb -1
    ? >= n 9 {
        = depth ( __cr_info f 3 0 line `a variable's depth` bad )
        = ln ( __cr_info f 5 0 line `a variable's line` bad )
        = vb ( __cr_info f 6 -1 line `a variable's value block` bad )
    } {}
    : String vname ? >= n 9 ( string_from ( __cr_col f 7 ) ) ( string_new )
    ^ @ !CoreVar String { T @ CoreVar { id kind depth flags ln vb vname ( string_from ( __cr_col f - n 1 ) ) } }
}

// Merge sort of positions `ix` by (key, position): stable, so the last of
// equal keys stays last.
@ __cr_msort ( Vec i ) keys ( Vec i ) ix → ( Vec i ) {
    : i n ( vec_len [i] ix )
    ? <= n 1 { ^ ( vec_clone [i] ix ) } {}
    : i h / n 2
    : ( Vec i ) lo ( vec_new [i] )
    : ( Vec i ) hi ( vec_new [i] )
    : ~ i k 0
    ~ < k n {
        ? < k h { ( vec_push [i] lo ( vec_at [i] ix k ) ) } { ( vec_push [i] hi ( vec_at [i] ix k ) ) }
        = k + k 1
    }
    : ( Vec i ) a ( __cr_msort keys lo )
    : ( Vec i ) b ( __cr_msort keys hi )
    : ( Vec i ) out ( vec_with_cap [i] n )
    : ~ i x 0
    : ~ i y 0
    : i na ( vec_len [i] a )
    : i nb ( vec_len [i] b )
    ~ | < x na < y nb {
        ? | >= y nb & < x na <= ( vec_at [i] keys ( vec_at [i] a x ) ) ( vec_at [i] keys ( vec_at [i] b y ) ) {
            ( vec_push [i] out ( vec_at [i] a x ) )
            = x + x 1
        } {
            ( vec_push [i] out ( vec_at [i] b y ) )
            = y + y 1
        }
    }
    ^ out
}

// A function's record finished: its variables' ids, sorted (each with its
// last record), and the words' end.
@ __cr_seal inout CoreFn fn → v {
    : i nv ( vec_len [CoreVar] . fn vars )
    : ( Vec i ) keys ( vec_new [i] )
    : ( Vec i ) ix ( vec_new [i] )
    : ~ b sorted T
    : ~ i k 0
    ~ < k nv {
        : i id . ( vec_at [CoreVar] . fn vars k ) id
        ? & > k 0 < id ( vec_at [i] keys - k 1 ) { = sorted F } {}
        ( vec_push [i] keys id )
        ( vec_push [i] ix k )
        = k + k 1
    }
    : ( Vec i ) ord ? sorted ix ( __cr_msort keys ix )
    = k 0
    ~ < k nv {
        : i r ( vec_at [i] ord k )
        : i id ( vec_at [i] keys r )
        : i m ( vec_len [i] . fn vids )
        ? & > m 0 == ( vec_at [i] . fn vids - m 1 ) id {
            ( vec_put [i] . fn vrec - m 1 r )
        } {
            ( vec_push [i] . fn vids id )
            ( vec_push [i] . fn vrec r )
        }
        = k + k 1
    }
    ( vec_push [i] . fn wstart ( vec_len [String] . fn words ) )
}

// Statement line t[sa, sz) of function `fn`: its words.
@ __cr_stmt inout CoreFn fn ( Slice u ) t i sa i sz → v {
    ( vec_push [i] . fn wstart ( vec_len [String] . fn words ) )
    ( core_split_words t sa sz . fn words )
}

// The kind of line t[a, z) by its first tab-separated column, read in
// place: 1 `endfn`, 2 `fn`, 3 `v`, 4 `sum`, 5 `ty`, 6 `virt`, 0 any other
// (a statement).
@ __cr_head ( Slice u ) t i a i z → i {
    : ~ i e a
    ~ & < e z != ( slice_byte t e ) 9 { = e + e 1 }
    : i n - e a
    : i c0 ? > n 0 ( slice_byte t a ) 0
    : i c1 ? > n 1 ( slice_byte t + a 1 ) 0
    ? == n 1 { ^ ? == c0 118 3 0 } {}
    ? == n 2 {
        ? & == c0 102 == c1 110 { ^ 2 } {}
        ? & == c0 116 == c1 121 { ^ 5 } {}
        ^ 0
    } {}
    ? == n 3 { ^ ? & & == c0 115 == c1 117 == ( slice_byte t + a 2 ) 109 4 0 } {}
    ? == n 4 { ^ ? & & & == c0 118 == c1 105 == ( slice_byte t + a 2 ) 114 == ( slice_byte t + a 3 ) 116 6 0 } {}
    ? == n 5 {
        ^ ? & & & & == c0 101 == c1 110 == ( slice_byte t + a 2 ) 100 == ( slice_byte t + a 3 ) 102 == ( slice_byte t + a 4 ) 110 1 0
    } {}
    ^ 0
}

// The core IR in `text`, or (`internal: …`) the line that is not one.
@ core_read s text → !CoreIR String {
    : ( Vec CoreFn ) fns ( vec_new [CoreFn] )
    : ( Vec CoreTy ) tys ( vec_new [CoreTy] )
    : ( Vec CoreSum ) sums ( vec_new [CoreSum] )
    : ( Vec CoreVirt ) virts ( vec_new [CoreVirt] )
    : ( HashMap String i ) ty_of ( map_new [String i] )
    : ( HashMap String i ) sum_of ( map_new [String i] )
    : ( Vec String ) bad ( vec_new [String] )
    : ( Slice u ) t ( slice_of_str text )
    : i n ( slice_len [u] t )
    : ~ CoreFn cur ( __cr_empty_fn )
    : ~ b in_fn F
    : ~ i a 0
    : ~ i lno 0
    ~ < a n {
        = lno + lno 1
        : ~ i z a
        ~ & < z n ! ( __cr_is_nl ( slice_byte t z ) ) { = z + z 1 }
        // (`\r\n` is one break)
        : i nxt ? & & < + z 1 n == ( slice_byte t z ) 13 == ( slice_byte t + z 1 ) 10 + z 2 + z 1
        // the line without the whitespace around it
        : ~ i sa a
        ~ & < sa z ( core_is_ws ( slice_byte t sa ) ) { = sa + sa 1 }
        : ~ i sz z
        ~ & > sz sa ( core_is_ws ( slice_byte t - sz 1 ) ) { = sz - sz 1 }
        // (the line's kind from its first column, read in place: a
        // statement line, most of them, is split into its words only)
        : i hd ? < sa sz ( __cr_head t a z ) 0
        ? & < sa sz | ! in_fn != hd 0 {
            : ( Vec String ) f ? == hd 0 ( vec_new [String] ) ( __cr_split_tabs t a z )
            : s f0 ? == hd 0 `` ( __cr_col f 0 )
            ? != 0 ( nurl_str_eq f0 `endfn` ) {
                ? ! in_fn { ^ @ !CoreIR String { F ( __cr_bad lno `an endfn with no function open` ) } } {}
                ( __cr_seal cur )
                ( vec_push [CoreFn] fns cur )
                = cur ( __cr_empty_fn )
                = in_fn F
            } {
                ? != 0 ( nurl_str_eq f0 `fn` ) {
                    ? in_fn {
                        : String w ( string_from `an fn line while function ` )
                        ( string_push_str w ( string_data . cur name ) )
                        ( string_push_str w ` is open (no endfn)` )
                        ^ @ !CoreIR String { F ( __cr_mal lno ( string_data w ) ) }
                    } {}
                    = cur \ ( __cr_new_fn f lno bad )
                    = in_fn T
                } {
                    ? & in_fn != 0 ( nurl_str_eq f0 `v` ) {
                        : CoreVar cv \ ( __cr_var f lno bad )
                        ( vec_push [CoreVar] . cur vars cv )
                    } {
                        ? & ! in_fn != 0 ( nurl_str_eq f0 `sum` ) {
                            : CoreSum sm \ ( __cr_sum f lno bad )
                            : ?i _o ( map_set [String i] sum_of ( string_clone . sm name ) ( vec_len [CoreSum] sums ) \ String x → i { ^ ( __cr_hash x ) } \ String p String q → b { ^ ( __cr_eq p q ) } )
                            ( vec_push [CoreSum] sums sm )
                        } {
                            ? & ! in_fn != 0 ( nurl_str_eq f0 `ty` ) {
                                : CoreTy ct \ ( __cr_ty f lno bad )
                                : ?i _o ( map_set [String i] ty_of ( string_clone . ct name ) ( vec_len [CoreTy] tys ) \ String x → i { ^ ( __cr_hash x ) } \ String p String q → b { ^ ( __cr_eq p q ) } )
                                ( vec_push [CoreTy] tys ct )
                            } {
                                ? & ! in_fn != 0 ( nurl_str_eq f0 `virt` ) {
                                    : ( Vec String ) impls ( vec_new [String] )
                                    : ~ i k 2
                                    ~ < k ( vec_len [String] f ) { ( vec_push [String] impls ( string_from ( __cr_col f k ) ) ) = k + k 1 }
                                    ( vec_push [CoreVirt] virts @ CoreVirt { ( string_from ( __cr_col f 1 ) ) impls } )
                                } {
                                    ? in_fn { ( __cr_stmt cur t sa sz ) } {}
                                }
                            }
                        }
                    }
                }
            }
        } {
            ? & < sa sz in_fn { ( __cr_stmt cur t sa sz ) } {}
        }
        = a nxt
    }
    ? in_fn {
        : String w ( string_from `the input ends inside function ` )
        ( string_push_str w ( string_data . cur name ) )
        ( string_push_str w ` (no endfn)` )
        ^ @ !CoreIR String { F ( __cr_mal lno ( string_data w ) ) }
    } {}
    ^ @ !CoreIR String { T @ CoreIR { fns tys sums virts ty_of sum_of bad } }
}

// core_read, refusing as well an IR with an informative column that is
// not an integer.
@ core_read_strict s text → !CoreIR String {
    : CoreIR ir \ ( core_read text )
    ? > ( vec_len [String] . ir bad ) 0 { ^ @ !CoreIR String { F ( string_clone ( vec_at [String] . ir bad 0 ) ) } } {}
    ^ @ !CoreIR String { T ir }
}

// ── Lookups ──────────────────────────────────────────────────────────

// The record of type `name`, or -1.
@ core_ty_index CoreIR ir s name → i {
    ^ ?? ( map_get_with [String i s] . ir ty_of name \ s x → i { ^ ( hash_string x ) } \ String p s q → b { ^ ( eq_string ( string_data p ) q ) } ) {
        T k → k
        F → -1
    }
}

// The summary of function `name`, or -1.
@ core_sum_index CoreIR ir s name → i {
    ^ ?? ( map_get_with [String i s] . ir sum_of name \ s x → i { ^ ( hash_string x ) } \ String p s q → b { ^ ( eq_string ( string_data p ) q ) } ) {
        T k → k
        F → -1
    }
}

// The value of `key` in a summary (the last pair with that key), or -1.
@ core_sum_key CoreSum sm s key → i {
    : ~ i k - ( vec_len [String] . sm keys ) 1
    ~ >= k 0 {
        ? != 0 ( nurl_str_eq ( string_data ( vec_at [String] . sm keys k ) ) key ) { ^ k } {}
        = k - k 1
    }
    ^ -1
}

// The number of words of statement k.
@ core_nwords CoreFn fn i k → i { ^ - ( vec_at [i] . fn wstart + k 1 ) ( vec_at [i] . fn wstart k ) }

// Word j of statement k ("" past its last).
@ core_word CoreFn fn i k i j → s {
    ? | < j 0 >= j ( core_nwords fn k ) { ^ `` } {}
    ^ ( string_data ( vec_at [String] . fn words + ( vec_at [i] . fn wstart k ) j ) )
}

// The position of `x` in the sorted `v`, or -1.
@ core_bsearch ( Vec i ) v i x → i {
    : ~ i lo 0
    : ~ i hi ( vec_len [i] v )
    ~ < lo hi {
        : i mid + lo / - hi lo 2
        : i y ( vec_at [i] v mid )
        ? == y x { ^ mid } {}
        ? < y x { = lo + mid 1 } { = hi mid }
    }
    ^ -1
}

// The position of variable `id` in `vids` (and `vrec`), or -1.
@ core_var_pos CoreFn fn i id → i { ^ ( core_bsearch . fn vids id ) }

// The record in `vars` of variable `id` (its last `v` line), or -1.
@ core_var CoreFn fn i id → i {
    : i k ( core_var_pos fn id )
    ? < k 0 { ^ -1 } {}
    ^ ( vec_at [i] . fn vrec k )
}
