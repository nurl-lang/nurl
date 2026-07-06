// template — an HTML template engine for NURL.
//
// Jinja-flavoured syntax rendered against a stdlib `Json` context:
//
//   {{ user.name }}                     output, HTML-escaped by default
//   {{ body | raw }}                    filters: raw / upper / lower / length / json
//   {% if admin %} … {% elif x == 'y' %} … {% else %} … {% end %}
//   {% for item in items %} {{ loop.index }}: {{ item.title }} {% end %}
//   {% include 'partial' %}             from a TplSet (tset_* below)
//   {# comment #}
//
// Expressions are a dotted path (`user.name`, `rows.0.id`, loop vars),
// a quoted string literal ('x' or "x"), a number, or true/false —
// optionally combined with `==` / `!=` or prefixed with `not`. Inside a
// `{% for %}` body, `loop.index` (0-based), `loop.first`, `loop.last`
// and `loop.length` resolve from the innermost loop.
//
// Missing keys render as empty and are falsy (mustache-style lenient);
// malformed tags are hard errors. Rendering is an interpreter over the
// source — a `{% for %}` body is re-scanned per item, so templates
// stay data, no AST to manage.
//
// Surface:
//   ( tpl_render src ctx )              → !String String   one-shot render
//   ( tset_new ) / ( tset_add t n s )   named-template set (enables include)
//   ( tset_render t name ctx )          → !String String
//   ( tpl_render_with t src ctx )       → !String String   one-shot + includes
//   ( tset_free t )
//
// The error payload is an owned String: "template error at line L, col C: …".
// Known limits (v0.1): `}}`/`%}` inside a string literal ends the tag;
// error positions inside an included template are reported against the
// including template's source.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`

// ── Template set (named templates, include targets) ─────────────────

: TplSet {
    ( Vec String ) names
    ( Vec String ) srcs
}

@ tset_new → *TplSet {
    : *TplSet t # *TplSet ( nurl_alloc Z TplSet )
    = . t names ( vec_new [String] )
    = . t srcs ( vec_new [String] )
    ^ t
}

@ __tset_find * TplSet t s name → i {
    : i n ( vec_len [String] . t names )
    : ~ i k 0
    : ~ i found - 0 1
    ~ & < k n < found 0 {
        ?? ( vec_get [String] . t names k ) {
            T nm → { ? == ( nurl_str_eq ( string_data nm ) name ) 1 { = found k } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ found
}

// Register (or replace) a named template. Copies both arguments.
@ tset_add * TplSet t s name s tsrc → v {
    : i idx ( __tset_find t name )
    ? >= idx 0 {
        ?? ( vec_get [String] . t srcs idx ) { T old → { ( string_free old ) } F _ → {} }
        : b _r ( vec_set [String] . t srcs idx ( string_from tsrc ) )
    } {
        ( vec_push [String] . t names ( string_from name ) )
        ( vec_push [String] . t srcs ( string_from tsrc ) )
    }
}

@ tset_has * TplSet t s name → b {
    ^ >= ( __tset_find t name ) 0
}

@ tset_free * TplSet t → v {
    : ( @ v String ) sdrop \ String x → v { ( string_free x ) }
    ( vec_free_with [String] . t names sdrop )
    ( vec_free_with [String] . t srcs sdrop )
    ( nurl_free # s t )
}

// ── Renderer state ───────────────────────────────────────────────────
//
// Heap-allocated so the mutually recursive block renderer can mutate
// `pos` and the scope stack without threading state through returns
// (same shape as ext/json.nu's JsonParser). One TplR lives per render.
//
// Value slots A and B hold the result of expression evaluation
// (kind: 0 null/missing, 1 bool, 2 number, 3 string, 4 array, 5 object).
// The Json node for kinds 4/5 rides in a 0/1-element Vec so the struct
// needs no bare Json field; all nodes are borrows into `ctxv[0]`.

: TplR {
    s src
    i len
    i pos
    i setp  // *TplSet as an integer; 0 = no set (include fails)
    i depth  // include nesting guard
    i tag_a  // {% elif %} expression span, handed to the if-handler
    i tag_b
    i e_end  // one-past-end of the last parsed primary expression
    b failed
    i err_pos
    String err
    String out
    String key  // scratch: NUL-terminated path segment / include name
    ( Vec Json ) ctxv  // [0] = root context (borrow)
    ( Vec String ) sc_names  // loop-variable scope stack (owned names)
    ( Vec Json ) sc_vals  // parallel values (borrows)
    ( Vec i ) lp_idx  // loop frames, innermost last
    ( Vec i ) lp_len
    i va_kind
    b va_bool
    f va_num
    b va_raw
    String va_str
    ( Vec Json ) va_node
    i vb_kind
    b vb_bool
    f vb_num
    String vb_str
    ( Vec Json ) vb_node
}

@ __tpl_new s tsrc i sp Json jctx → *TplR {
    : *TplR r # *TplR ( nurl_alloc Z TplR )
    = . r src tsrc
    = . r len ( nurl_str_len tsrc )
    = . r pos 0
    = . r setp sp
    = . r depth 0
    = . r tag_a 0
    = . r tag_b 0
    = . r e_end 0
    = . r failed F
    = . r err_pos 0
    = . r err ( string_new )
    = . r out ( string_with_cap 256 )
    = . r key ( string_with_cap 32 )
    = . r ctxv ( vec_new [Json] )
    ( vec_push [Json] . r ctxv jctx )
    = . r sc_names ( vec_new [String] )
    = . r sc_vals ( vec_new [Json] )
    = . r lp_idx ( vec_new [i] )
    = . r lp_len ( vec_new [i] )
    = . r va_kind 0
    = . r va_bool F
    = . r va_num 0.0
    = . r va_raw F
    = . r va_str ( string_with_cap 32 )
    = . r va_node ( vec_new [Json] )
    = . r vb_kind 0
    = . r vb_bool F
    = . r vb_num 0.0
    = . r vb_str ( string_with_cap 32 )
    = . r vb_node ( vec_new [Json] )
    ^ r
}

@ __tpl_free * TplR r b free_out → v {
    ( string_free . r err )
    ( string_free . r key )
    ( string_free . r va_str )
    ( string_free . r vb_str )
    ? free_out { ( string_free . r out ) } {}
    : ( @ v String ) sdrop \ String x → v { ( string_free x ) }
    ( vec_free_with [String] . r sc_names sdrop )
    ( vec_free [Json] . r sc_vals )
    ( vec_free [Json] . r ctxv )
    ( vec_free [Json] . r va_node )
    ( vec_free [Json] . r vb_node )
    ( vec_free [i] . r lp_idx )
    ( vec_free [i] . r lp_len )
    ( nurl_free # s r )
}

// Record the first failure; later ones are ignored (the first is the cause).
@ __tpl_fail * TplR r i fpos s msg → v {
    ? . r failed {} {
        = . r failed T
        = . r err_pos fpos
        ( string_push_str . r err msg )
    }
}

@ __tpl_errmsg * TplR r → String {
    : ~ i p . r err_pos
    ? > p . r len { = p . r len } {}
    : ~ i line 1
    : ~ i col 1
    : *u bp # *u . r src
    : ~ i k 0
    ~ < k p {
        ? == & 255 # i . bp k 10 { = line + line 1 = col 1 } { = col + col 1 }
        = k + k 1
    }
    : String m ( string_with_cap 64 )
    ( string_push_str m `template error at line ` )
    ( string_push_int m line )
    ( string_push_str m `, col ` )
    ( string_push_int m col )
    ( string_push_str m `: ` )
    ( string_push_str m ( string_data . r err ) )
    ^ m
}

// ── Byte helpers ─────────────────────────────────────────────────────

@ __tpl_at * TplR r i k → i {
    ? | < k 0 >= k . r len { ^ - 0 1 } {}
    : *u bp # *u . r src
    ^ & 255 # i . bp k
}

@ __tpl_is_ws i c → b {
    ^ | | | == c 32 == c 9 == c 10 == c 13
}

@ __tpl_is_identb i c → b {
    ? & >= c 97 <= c 122 { ^ T } {}
    ? & >= c 65 <= c 90 { ^ T } {}
    ? & >= c 48 <= c 57 { ^ T } {}
    ^ == c 95
}

// Path token bytes: identifier chars plus '.'
@ __tpl_is_pathb i c → b {
    ? ( __tpl_is_identb c ) { ^ T } {}
    ^ == c 46
}

// Number token bytes: digits, '-', '.', exponent chars.
@ __tpl_is_numb i c → b {
    ? & >= c 48 <= c 57 { ^ T } {}
    ? | | | | == c 45 == c 46 == c 43 == c 101 == c 69 { ^ T } {}
    ^ F
}

@ __tpl_ws * TplR r i k i bnd → i {
    : ~ i j k
    ~ & < j bnd ( __tpl_is_ws ( __tpl_at r j ) ) { = j + j 1 }
    ^ j
}

// First index >= from where src[j] == c1 and src[j+1] == c2; -1 if none.
@ __tpl_find2 * TplR r i from i c1 i c2 → i {
    : ~ i j from
    : ~ i found - 0 1
    ~ & < j - . r len 1 < found 0 {
        ? & == ( __tpl_at r j ) c1 == ( __tpl_at r + j 1 ) c2 { = found j } { = j + j 1 }
    }
    ^ found
}

// Does span [a,b) equal the literal `lit`?
@ __tpl_kw_is * TplR r i a i bnd s lit → b {
    : i n ( nurl_str_len lit )
    ? != - bnd a n { ^ F } {}
    : *u lp # *u lit
    : ~ i k 0
    : ~ b same T
    ~ & same < k n {
        ? != ( __tpl_at r + a k ) & 255 # i . lp k { = same F } { = k + k 1 }
    }
    ^ same
}

// Does span [a,b) begin with the literal `lit`?
@ __tpl_span_starts * TplR r i a i bnd s lit → b {
    : i n ( nurl_str_len lit )
    ? < - bnd a n { ^ F } {}
    ^ ( __tpl_kw_is r a + a n lit )
}

// Does span [a,a+n) equal the String `nm`?
@ __tpl_seg_eq * TplR r i a i n String nm → b {
    ? != ( string_len nm ) n { ^ F } {}
    : s nd ( string_data nm )
    : *u np # *u nd
    : ~ i k 0
    : ~ b same T
    ~ & same < k n {
        ? != ( __tpl_at r + a k ) & 255 # i . np k { = same F } { = k + k 1 }
    }
    ^ same
}

// scratch key := src[a, a+n)
@ __tpl_key_set * TplR r i a i n → v {
    ( string_clear . r key )
    : ~ i k 0
    ~ < k n {
        ( string_push_char . r key ( __tpl_at r + a k ) )
        = k + k 1
    }
}

// Parse span [a,b) as a non-negative decimal integer; -1 when not one.
@ __tpl_span_int * TplR r i a i bnd → i {
    ? >= a bnd { ^ - 0 1 } {}
    : ~ i k a
    : ~ i acc 0
    : ~ b ok T
    ~ & ok < k bnd {
        : i c ( __tpl_at r k )
        ? & >= c 48 <= c 57 { = acc + * acc 10 - c 48 = k + k 1 } { = ok F }
    }
    ? ok { ^ acc } { ^ - 0 1 }
}

// HTML-escape a NUL-terminated string into `out`.
@ __tpl_push_escaped String outbuf s raw → v {
    : i n ( nurl_str_len raw )
    : *u bp # *u raw
    : ~ i k 0
    ~ < k n {
        : i c & 255 # i . bp k
        ? == c 38 { ( string_push_str outbuf `&amp;` ) } {
            ? == c 60 { ( string_push_str outbuf `&lt;` ) } {
                ? == c 62 { ( string_push_str outbuf `&gt;` ) } {
                    ? == c 34 { ( string_push_str outbuf `&quot;` ) } {
                        ? == c 39 { ( string_push_str outbuf `&#39;` ) } {
                            ( string_push_char outbuf c )
                        } } } } }
        = k + k 1
    }
}

// ── Path resolution ──────────────────────────────────────────────────
//
// Dotted path over the scope stack (innermost loop var first) and the
// root context object. Numeric segments index into arrays. Returns a
// BORROW into the context; F = missing anywhere along the path.

@ __tpl_resolve * TplR r i pa i pb → ?Json {
    : ~ i sp pa
    : ~ Json cur ( json_null )
    : ~ b have F
    : ~ b dead F
    : ~ b first T
    ~ & == dead F < sp pb {
        : ~ i se sp
        ~ & < se pb != ( __tpl_at r se ) 46 { = se + se 1 }
        : i slen - se sp
        ? == slen 0 { = dead T } {
            ? first {
                = first F
                : i ns ( vec_len [String] . r sc_names )
                : ~ i si - ns 1
                ~ & == have F >= si 0 {
                    ?? ( vec_get [String] . r sc_names si ) {
                        T nm → {
                            ? ( __tpl_seg_eq r sp slen nm ) {
                                ?? ( vec_get [Json] . r sc_vals si ) {
                                    T jv → { = cur jv = have T }
                                    F _ → {}
                                }
                            } {}
                        }
                        F _ → {}
                    }
                    = si - si 1
                }
                ? == have F {
                    ?? ( vec_get [Json] . r ctxv 0 ) {
                        T root → {
                            ? ( json_is_obj root ) {
                                ( __tpl_key_set r sp slen )
                                ?? ( json_obj_get root ( string_data . r key ) ) {
                                    T child → { = cur child = have T }
                                    F _ → { = dead T }
                                }
                            } { = dead T }
                        }
                        F _ → { = dead T }
                    }
                } {}
            } {
                ? ( json_is_obj cur ) {
                    ( __tpl_key_set r sp slen )
                    ?? ( json_obj_get cur ( string_data . r key ) ) {
                        T child → { = cur child }
                        F _ → { = dead T }
                    }
                } {
                    ? ( json_is_arr cur ) {
                        : i idx ( __tpl_span_int r sp se )
                        ? >= idx 0 {
                            ?? ( json_arr_get cur idx ) {
                                T child → { = cur child }
                                F _ → { = dead T }
                            }
                        } { = dead T }
                    } { = dead T }
                }
            }
        }
        = sp + se 1
    }
    ? | dead == have F { ^ @ ?Json { F } } {}
    ^ @ ?Json { T cur }
}

// ── Expression evaluation (value slots) ──────────────────────────────

@ __tpl_slot_reset * TplR r → v {
    = . r va_kind 0
    = . r va_bool F
    = . r va_num 0.0
    = . r va_raw F
    ( string_clear . r va_str )
    ( vec_clear [Json] . r va_node )
}

@ __tpl_slot_a_to_b * TplR r → v {
    = . r vb_kind . r va_kind
    = . r vb_bool . r va_bool
    = . r vb_num . r va_num
    ( string_clear . r vb_str )
    ( string_push_str . r vb_str ( string_data . r va_str ) )
    ( vec_clear [Json] . r vb_node )
    ?? ( vec_get [Json] . r va_node 0 ) {
        T nd → { ( vec_push [Json] . r vb_node nd ) }
        F _ → {}
    }
}

@ __tpl_slot_from_node * TplR r Json node → v {
    ? ( json_is_null node ) { = . r va_kind 0 } {
        ? ( json_is_bool node ) {
            = . r va_kind 1
            = . r va_bool ( json_bool_val node )
        } {
            ? ( json_is_num node ) {
                = . r va_kind 2
                ?? node { JNum nr → { ( string_push_str . r va_str ( string_data nr ) ) } _ → {} }
                ?? ( json_num_as_f node ) { T x → { = . r va_num x } F _ → {} }
            } {
                ? ( json_is_str node ) {
                    = . r va_kind 3
                    ( string_push_str . r va_str ( json_str_data node ) )
                } {
                    ? ( json_is_arr node ) {
                        = . r va_kind 4
                        ( vec_push [Json] . r va_node node )
                    } {
                        = . r va_kind 5
                        ( vec_push [Json] . r va_node node )
                    } } } } }
}

// Evaluate one primary (path / literal / loop.*) from span [a,bnd) into
// slot A. Sets e_end to one past the consumed token.
@ __tpl_eval_primary * TplR r i a i bnd → v {
    ( __tpl_slot_reset r )
    : i k ( __tpl_ws r a bnd )
    ? >= k bnd { ( __tpl_fail r a `empty expression` ) } {
        : i c ( __tpl_at r k )
        ? | == c 39 == c 34 {
            // string literal
            : ~ i e - 0 1
            : ~ i j + k 1
            ~ & < j bnd < e 0 {
                ? == ( __tpl_at r j ) c { = e j } { = j + j 1 }
            }
            ? < e 0 { ( __tpl_fail r k `unterminated string literal` ) } {
                = . r va_kind 3
                : ~ i q + k 1
                ~ < q e {
                    ( string_push_char . r va_str ( __tpl_at r q ) )
                    = q + q 1
                }
                = . r e_end + e 1
            }
        } {
            ? | == c 45 & >= c 48 <= c 57 {
                // number literal
                : ~ i te k
                ~ & < te bnd ( __tpl_is_numb ( __tpl_at r te ) ) { = te + te 1 }
                = . r va_kind 2
                : ~ i q2 k
                ~ < q2 te {
                    ( string_push_char . r va_str ( __tpl_at r q2 ) )
                    = q2 + q2 1
                }
                ?? ( string_to_float . r va_str ) {
                    T x → { = . r va_num x }
                    F _ → { ( __tpl_fail r k `malformed number` ) }
                }
                = . r e_end te
            } {
                ? ( __tpl_is_identb c ) {
                    : ~ i te2 k
                    ~ & < te2 bnd ( __tpl_is_pathb ( __tpl_at r te2 ) ) { = te2 + te2 1 }
                    = . r e_end te2
                    ? ( __tpl_kw_is r k te2 `true` ) { = . r va_kind 1 = . r va_bool T } {
                        ? ( __tpl_kw_is r k te2 `false` ) { = . r va_kind 1 = . r va_bool F } {
                            ? & > ( vec_len [i] . r lp_idx ) 0 ( __tpl_span_starts r k te2 `loop.` ) {
                                : i nf ( vec_len [i] . r lp_idx )
                                : ~ i li 0
                                : ~ i ln 0
                                ?? ( vec_get [i] . r lp_idx - nf 1 ) { T x2 → { = li x2 } F _ → {} }
                                ?? ( vec_get [i] . r lp_len - nf 1 ) { T x3 → { = ln x3 } F _ → {} }
                                ? ( __tpl_kw_is r k te2 `loop.index` ) {
                                    = . r va_kind 2
                                    = . r va_num # f li
                                    ( string_push_int . r va_str li )
                                } {
                                    ? ( __tpl_kw_is r k te2 `loop.first` ) {
                                        = . r va_kind 1
                                        = . r va_bool == li 0
                                    } {
                                        ? ( __tpl_kw_is r k te2 `loop.last` ) {
                                            = . r va_kind 1
                                            = . r va_bool == li - ln 1
                                        } {
                                            ? ( __tpl_kw_is r k te2 `loop.length` ) {
                                                = . r va_kind 2
                                                = . r va_num # f ln
                                                ( string_push_int . r va_str ln )
                                            } {
                                                ( __tpl_fail r k `unknown loop attribute (index/first/last/length)` )
                                            } } } }
                            } {
                                ?? ( __tpl_resolve r k te2 ) {
                                    T node → { ( __tpl_slot_from_node r node ) }
                                    F _ → {}
                                }
                            } } }
                } {
                    ( __tpl_fail r k `bad expression` )
                } } }
    }
}

@ __tpl_truthy_a * TplR r → b {
    : i kd . r va_kind
    ? == kd 1 { ^ . r va_bool } {}
    ? == kd 2 { ^ != . r va_num 0.0 } {}
    ? == kd 3 { ^ > ( string_len . r va_str ) 0 } {}
    ? == kd 4 {
        : ~ i n 0
        ?? ( vec_get [Json] . r va_node 0 ) { T nd → { = n ( json_arr_len nd ) } F _ → {} }
        ^ > n 0
    } {}
    ^ == kd 5
}

@ __tpl_eq_ab * TplR r → b {
    ? != . r va_kind . r vb_kind { ^ F } {}
    : i kd . r va_kind
    ? == kd 0 { ^ T } {}
    ? == kd 1 { ^ == . r va_bool . r vb_bool } {}
    ? == kd 2 { ^ == . r va_num . r vb_num } {}
    ? == kd 3 { ^ ( string_eq . r va_str . r vb_str ) } {}
    ^ F
}

// Full condition: [not] primary [(==|!=) primary]
@ __tpl_truth * TplR r i a i bnd → b {
    : i k ( __tpl_ws r a bnd )
    : ~ i tn k
    ~ & < tn bnd ( __tpl_is_pathb ( __tpl_at r tn ) ) { = tn + tn 1 }
    ? ( __tpl_kw_is r k tn `not` ) {
        : b inner ( __tpl_truth r tn bnd )
        ^ == inner F
    } {}
    ( __tpl_eval_primary r k bnd )
    ? . r failed { ^ F } {}
    : i k2 ( __tpl_ws r . r e_end bnd )
    ? >= k2 bnd { ^ ( __tpl_truthy_a r ) } {}
    : i o1 ( __tpl_at r k2 )
    : i o2 ( __tpl_at r + k2 1 )
    : ~ b want T
    ? & == o1 61 == o2 61 {} {
        ? & == o1 33 == o2 61 { = want F } {
            ( __tpl_fail r k2 `unsupported operator (only == and !=)` )
        }
    }
    ? . r failed { ^ F } {}
    ( __tpl_slot_a_to_b r )
    ( __tpl_eval_primary r + k2 2 bnd )
    ? . r failed { ^ F } {}
    : b eq ( __tpl_eq_ab r )
    ? want { ^ eq } { ^ == eq F }
}

// ── Output tag: {{ expr | filters }} ─────────────────────────────────

@ __tpl_apply_filter * TplR r i fa i fe → v {
    ? ( __tpl_kw_is r fa fe `raw` ) { = . r va_raw T } {
        ? ( __tpl_kw_is r fa fe `upper` ) {
            ? | == . r va_kind 3 == . r va_kind 2 {
                : String u ( string_to_upper . r va_str )
                ( string_free . r va_str )
                = . r va_str u
            } {}
        } {
            ? ( __tpl_kw_is r fa fe `lower` ) {
                ? | == . r va_kind 3 == . r va_kind 2 {
                    : String l ( string_to_lower . r va_str )
                    ( string_free . r va_str )
                    = . r va_str l
                } {}
            } {
                ? ( __tpl_kw_is r fa fe `length` ) {
                    : ~ i n 0
                    ? == . r va_kind 3 { = n ( string_len . r va_str ) } {
                        ? == . r va_kind 4 {
                            ?? ( vec_get [Json] . r va_node 0 ) { T nd → { = n ( json_arr_len nd ) } F _ → {} }
                        } {}
                    }
                    = . r va_kind 2
                    = . r va_num # f n
                    ( string_clear . r va_str )
                    ( string_push_int . r va_str n )
                    ( vec_clear [Json] . r va_node )
                } {
                    ? ( __tpl_kw_is r fa fe `json` ) {
                        ? | == . r va_kind 4 == . r va_kind 5 {
                            ?? ( vec_get [Json] . r va_node 0 ) {
                                T nd → {
                                    : String js ( json_stringify nd )
                                    ( string_clear . r va_str )
                                    ( string_push_str . r va_str ( string_data js ) )
                                    ( string_free js )
                                    = . r va_kind 3
                                    ( vec_clear [Json] . r va_node )
                                }
                                F _ → {}
                            }
                        } {}
                    } {
                        ( __tpl_fail r fa `unknown filter (raw/upper/lower/length/json)` )
                    } } } } }
}

@ __tpl_emit_a * TplR r → v {
    : i kd . r va_kind
    ? == kd 1 {
        ? . r va_bool { ( string_push_str . r out `true` ) } { ( string_push_str . r out `false` ) }
    } {
        ? == kd 2 { ( string_push_str . r out ( string_data . r va_str ) ) } {
            ? == kd 3 {
                ? . r va_raw { ( string_push_str . r out ( string_data . r va_str ) ) }
                { ( __tpl_push_escaped . r out ( string_data . r va_str ) ) }
            } {
                ? | == kd 4 == kd 5 {
                    ?? ( vec_get [Json] . r va_node 0 ) {
                        T nd → {
                            : String js ( json_stringify nd )
                            ? . r va_raw { ( string_push_str . r out ( string_data js ) ) }
                            { ( __tpl_push_escaped . r out ( string_data js ) ) }
                            ( string_free js )
                        }
                        F _ → {}
                    }
                } {} } } }
}

@ __tpl_out_tag * TplR r i a i bnd → v {
    ( __tpl_eval_primary r a bnd )
    ? . r failed {} {
        : ~ i k . r e_end
        : ~ b more T
        ~ & more == . r failed F {
            = k ( __tpl_ws r k bnd )
            ? & < k bnd == ( __tpl_at r k ) 124 {
                : i fa ( __tpl_ws r + k 1 bnd )
                : ~ i fe fa
                ~ & < fe bnd ( __tpl_is_identb ( __tpl_at r fe ) ) { = fe + fe 1 }
                ? == fe fa { ( __tpl_fail r k `empty filter` ) } {
                    ( __tpl_apply_filter r fa fe )
                    = k fe
                }
            } {
                ? < k bnd { ( __tpl_fail r k `trailing characters in expression` ) } {}
                = more F
            }
        }
        ? . r failed {} { ( __tpl_emit_a r ) }
    }
}

// ── Control tags ─────────────────────────────────────────────────────

// {% if e %} … {% elif e %} … {% else %} … {% end %}
// Skipping is rendering with emit=F, so nesting stays balanced.
@ __tpl_do_if * TplR r i ea i eb b emit → v {
    : ~ b cond F
    ? emit { = cond ( __tpl_truth r ea eb ) } {}
    : ~ b handled cond
    : ~ i term ( __tpl_run r & emit cond )
    ~ & == term 3 == . r failed F {
        : i xa . r tag_a
        : i xb . r tag_b
        : ~ b c2 F
        ? & emit == handled F { = c2 ( __tpl_truth r xa xb ) } {}
        ? c2 { = handled T } {}
        = term ( __tpl_run r & emit c2 )
    }
    ? & == term 2 == . r failed F {
        = term ( __tpl_run r & emit == handled F )
    } {}
    ? & != term 1 == . r failed F {
        ( __tpl_fail r . r pos `'{% if %}' without matching '{% end %}'` )
    } {}
}

// {% for NAME in PATH %} … {% end %}
// The body span is re-scanned once per item; the loop variable and a
// loop frame (index/len) are pushed for the duration.
@ __tpl_do_for * TplR r i ea i eb b emit → v {
    ? == emit F {
        : i t ( __tpl_run r F )
        ? & != t 1 == . r failed F {
            ( __tpl_fail r . r pos `'{% for %}' without matching '{% end %}'` )
        } {}
    } {
        : i va ( __tpl_ws r ea eb )
        : ~ i ve va
        ~ & < ve eb ( __tpl_is_identb ( __tpl_at r ve ) ) { = ve + ve 1 }
        : i k1 ( __tpl_ws r ve eb )
        : ~ i ke k1
        ~ & < ke eb ( __tpl_is_pathb ( __tpl_at r ke ) ) { = ke + ke 1 }
        : ~ b ok T
        ? == ve va { = ok F } {}
        ? ( __tpl_kw_is r k1 ke `in` ) {} { = ok F }
        ? == ok F {
            ( __tpl_fail r ea `malformed '{% for %}': expected 'for NAME in PATH'` )
        } {
            : i pa ( __tpl_ws r ke eb )
            : ~ i pb eb
            ~ & > pb pa ( __tpl_is_ws ( __tpl_at r - pb 1 ) ) { = pb - pb 1 }
            : ~ Json seq ( json_null )
            ?? ( __tpl_resolve r pa pb ) { T node → { = seq node } F _ → {} }
            : ~ i n 0
            ? ( json_is_arr seq ) { = n ( json_arr_len seq ) } {
                ? ( json_is_null seq ) {} {
                    ( __tpl_fail r pa `'{% for %}' over a non-array value` )
                }
            }
            ? . r failed {} {
                ? == n 0 {
                    : i t2 ( __tpl_run r F )
                    ? & != t2 1 == . r failed F {
                        ( __tpl_fail r . r pos `'{% for %}' without matching '{% end %}'` )
                    } {}
                } {
                    : i body . r pos
                    ( __tpl_key_set r va - ve va )
                    ( vec_push [String] . r sc_names ( string_clone . r key ) )
                    : Json seed ( json_null )
                    ( vec_push [Json] . r sc_vals seed )
                    ( vec_push [i] . r lp_idx 0 )
                    ( vec_push [i] . r lp_len n )
                    : i vslot - ( vec_len [Json] . r sc_vals ) 1
                    : i lslot - ( vec_len [i] . r lp_idx ) 1
                    : ~ i it 0
                    ~ & < it n == . r failed F {
                        = . r pos body
                        ?? ( json_arr_get seq it ) {
                            T item → { : b _s1 ( vec_set [Json] . r sc_vals vslot item ) }
                            F _ → {}
                        }
                        : b _s2 ( vec_set [i] . r lp_idx lslot it )
                        : i t3 ( __tpl_run r T )
                        ? & != t3 1 == . r failed F {
                            ( __tpl_fail r . r pos `'{% for %}' without matching '{% end %}'` )
                        } {}
                        = it + it 1
                    }
                    ?? ( vec_pop [String] . r sc_names ) { T nm → { ( string_free nm ) } F _ → {} }
                    ?? ( vec_pop [Json] . r sc_vals ) { T _ → {} F _ → {} }
                    ?? ( vec_pop [i] . r lp_idx ) { T _ → {} F _ → {} }
                    ?? ( vec_pop [i] . r lp_len ) { T _ → {} F _ → {} }
                }
            }
        }
    }
}

// {% include 'name' %} — renders a set member in the current context and
// scope. Only reached with emit=T (skip mode skips the tag wholesale).
@ __tpl_do_include * TplR r i a i bnd → v {
    : i k ( __tpl_ws r a bnd )
    : i qc ( __tpl_at r k )
    ? | == qc 39 == qc 34 {
        : ~ i e - 0 1
        : ~ i j + k 1
        ~ & < j bnd < e 0 {
            ? == ( __tpl_at r j ) qc { = e j } { = j + j 1 }
        }
        ? < e 0 { ( __tpl_fail r k `unterminated template name` ) } {
            ? == . r setp 0 {
                ( __tpl_fail r k `'{% include %}' needs a template set (use tset_render / tpl_render_with)` )
            } {
                ? >= . r depth 16 {
                    ( __tpl_fail r k `include depth limit exceeded (cycle?)` )
                } {
                    ( __tpl_key_set r + k 1 - e + k 1 )
                    : *TplSet t # *TplSet . r setp
                    : i idx ( __tset_find t ( string_data . r key ) )
                    ? < idx 0 { ( __tpl_fail r k `include: template not found` ) } {
                        : ~ s isrc # s 0
                        ?? ( vec_get [String] . t srcs idx ) {
                            T sv → { = isrc ( string_data sv ) }
                            F _ → {}
                        }
                        : s osrc . r src
                        : i olen . r len
                        : i opos . r pos
                        = . r src isrc
                        = . r len ( nurl_str_len isrc )
                        = . r pos 0
                        = . r depth + . r depth 1
                        : i t2 ( __tpl_run r T )
                        ? & != t2 0 == . r failed F {
                            ( __tpl_fail r . r pos `unbalanced block tag in included template` )
                        } {}
                        = . r src osrc
                        = . r len olen
                        = . r pos opos
                        = . r depth - . r depth 1
                    }
                }
            }
        }
    } {
        ( __tpl_fail r k `'{% include %}' expects a quoted template name` )
    }
}

// ── Block renderer ───────────────────────────────────────────────────
//
// Renders (emit=T) or skips (emit=F) from `pos` until EOF or a block
// terminator. Returns 0 = EOF, 1 = {% end %}, 2 = {% else %},
// 3 = {% elif %} (expression span left in tag_a/tag_b).

@ __tpl_run * TplR r b emit → i {
    : ~ i term - 0 1
    ~ & == term - 0 1 == . r failed F {
        : i p0 . r pos
        ? >= p0 . r len { = term 0 } {
            : i c ( __tpl_at r p0 )
            : i c1 ( __tpl_at r + p0 1 )
            ? & == c 123 == c1 123 {
                // {{ expr }}
                : i close ( __tpl_find2 r + p0 2 125 125 )
                ? < close 0 { ( __tpl_fail r p0 `unclosed '{{'` ) } {
                    ? emit { ( __tpl_out_tag r + p0 2 close ) } {}
                    = . r pos + close 2
                }
            } {
                ? & == c 123 == c1 35 {
                    // {# comment #}
                    : i close ( __tpl_find2 r + p0 2 35 125 )
                    ? < close 0 { ( __tpl_fail r p0 `unclosed '{#'` ) } {
                        = . r pos + close 2
                    }
                } {
                    ? & == c 123 == c1 37 {
                        // {% tag %}
                        : i close ( __tpl_find2 r + p0 2 37 125 )
                        ? < close 0 { ( __tpl_fail r p0 `unclosed '{%'` ) } {
                            : i ta ( __tpl_ws r + p0 2 close )
                            : ~ i te ta
                            ~ & < te close ( __tpl_is_identb ( __tpl_at r te ) ) { = te + te 1 }
                            = . r pos + close 2
                            ? ( __tpl_kw_is r ta te `if` ) { ( __tpl_do_if r te close emit ) } {
                                ? ( __tpl_kw_is r ta te `for` ) { ( __tpl_do_for r te close emit ) } {
                                    ? ( __tpl_kw_is r ta te `include` ) {
                                        ? emit { ( __tpl_do_include r te close ) } {}
                                    } {
                                        ? | | ( __tpl_kw_is r ta te `end` ) ( __tpl_kw_is r ta te `endif` ) ( __tpl_kw_is r ta te `endfor` ) {
                                            = term 1
                                        } {
                                            ? ( __tpl_kw_is r ta te `else` ) { = term 2 } {
                                                ? ( __tpl_kw_is r ta te `elif` ) {
                                                    = . r tag_a te
                                                    = . r tag_b close
                                                    = term 3
                                                } {
                                                    ( __tpl_fail r ta `unknown tag (if/elif/else/for/include/end)` )
                                                } } } } } }
                        }
                    } {
                        // plain text: emit until the next tag opener or EOF
                        : ~ i k p0
                        : ~ b scan T
                        ~ & scan < k . r len {
                            : i tc ( __tpl_at r k )
                            ? == tc 123 {
                                : i tn ( __tpl_at r + k 1 )
                                ? | | == tn 123 == tn 37 == tn 35 { = scan F } { = k + k 1 }
                            } { = k + k 1 }
                        }
                        ? emit {
                            : ~ i q p0
                            ~ < q k {
                                ( string_push_char . r out ( __tpl_at r q ) )
                                = q + q 1
                            }
                        } {}
                        = . r pos k
                    } } }
        }
    }
    ^ term
}

// ── Entry points ─────────────────────────────────────────────────────

@ __tpl_render_ptr i sp s tsrc Json jctx → !String String {
    : *TplR r ( __tpl_new tsrc sp jctx )
    : i term ( __tpl_run r T )
    ? & != term 0 == . r failed F {
        ( __tpl_fail r . r pos `'{% end %}' or '{% else %}' without an open block` )
    } {}
    ? . r failed {
        : String m ( __tpl_errmsg r )
        ( __tpl_free r T )
        ^ @ !String String { F m }
    } {}
    : String rendered . r out
    ( __tpl_free r F )
    ^ @ !String String { T rendered }
}

// Render template source against a Json context. The error payload is
// an owned String ("template error at line L, col C: …").
@ tpl_render s tsrc Json jctx → !String String {
    ^ ( __tpl_render_ptr 0 tsrc jctx )
}

// Same, with a TplSet so `{% include 'name' %}` resolves.
@ tpl_render_with * TplSet t s tsrc Json jctx → !String String {
    ^ ( __tpl_render_ptr # i t tsrc jctx )
}

// Render a named member of the set.
@ tset_render * TplSet t s name Json jctx → !String String {
    : i idx ( __tset_find t name )
    ? < idx 0 {
        : String m ( string_from `template not found: ` )
        ( string_push_str m name )
        ^ @ !String String { F m }
    } {}
    : ~ s tsrc # s 0
    ?? ( vec_get [String] . t srcs idx ) {
        T sv → { = tsrc ( string_data sv ) }
        F _ → {}
    }
    ^ ( __tpl_render_ptr # i t tsrc jctx )
}
