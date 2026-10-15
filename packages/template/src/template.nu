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
//
// A TplSet is a handle: every copy is the same set, and its last owner
// releases it — nothing to free (`tset_free` is an optional early release).
//
// The error payload is an owned String: "template error at line L, col C: …".
// Known limits (v0.1): `}}`/`%}` inside a string literal ends the tag;
// error positions inside an included template are reported against the
// including template's source.

$ `stdlib/core/mem.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/slice.nu`

// ── Template set (named templates, include targets) ─────────────────

: TplSetImpl {
    ( Vec String ) names
    ( Vec ( Arc String ) ) srcs
}

// A TplSet is a handle on a snapshot of its names and sources: every copy
// is the same set, and the last owner releases it. A render reads one
// frozen snapshot (an Arc, no lock held while it runs); tset_add makes
// the next one — sharing every source it did not replace — so a render
// on another thread keeps reading the set it started with.
: TplSet { ( Locked ( Arc TplSetImpl ) ) l }

@ TplSet_share TplSet h → TplSet { ^ @ TplSet { ( Locked_share [( Arc TplSetImpl )] . h l ) } }

@ TplSet_drop sink TplSet h → v {}

@ __tset_empty → TplSetImpl { ^ @ TplSetImpl { ( vec_new [String] ) ( vec_new [( Arc String )] ) } }

@ tset_new → TplSet {
    ^ @ TplSet { ( locked_new [( Arc TplSetImpl )] ( arc_new [TplSetImpl] ( __tset_empty ) ) ) }
}

// The set as it is now.
@ __tset_snapshot TplSet t → ( Arc TplSetImpl ) { ^ ( locked_get [( Arc TplSetImpl )] . t l ) }

@ __tset_find TplSetImpl t s name → i {
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
@ tset_add TplSet t__h s name s tsrc → v {
    : ( Arc TplSetImpl ) cur ( locked_take [( Arc TplSetImpl )] . t__h l )
    : TplSetImpl t ( arc_get [TplSetImpl] cur )
    : i idx ( __tset_find t name )
    : i n ( vec_len [String] . t names )
    : ( Vec String ) names ( vec_with_cap [String] + n 1 )
    : ( Vec ( Arc String ) ) srcs ( vec_with_cap [( Arc String )] + n 1 )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] . t names k ) { T nm → { ( vec_push [String] names ( string_clone nm ) ) } F _ → {} }
        ? == k idx {
            ( vec_push [( Arc String )] srcs ( arc_new [String] ( string_from tsrc ) ) )
        } {
            ?? ( vec_get [( Arc String )] . t srcs k ) { T sa → { ( vec_push [( Arc String )] srcs ( arc_clone [String] sa ) ) } F _ → {} }
        }
        = k + k 1
    }
    ? < idx 0 {
        ( vec_push [String] names ( string_from name ) )
        ( vec_push [( Arc String )] srcs ( arc_new [String] ( string_from tsrc ) ) )
    } {}
    ( locked_restore [( Arc TplSetImpl )] . t__h l ( arc_new [TplSetImpl] @ TplSetImpl { names srcs } ) )
}

@ tset_has TplSet t s name → b {
    : ( Arc TplSetImpl ) snap ( __tset_snapshot t )
    ^ >= ( __tset_find ( arc_get [TplSetImpl] snap ) name ) 0
}

// Let go of `t` now rather than at the end of its owner's scope.
@ tset_free sink TplSet t → v {}

// ── Renderer state ───────────────────────────────────────────────────
//
// One TplRImpl lives per render, a local of the entry point that the
// mutually recursive block renderer changes in place (`inout`): `pos`,
// the scope stack and the output. The text being rendered is not in it —
// each function is handed it as a byte view (`sv`), with the set the
// render reads (`t`), so an include renders another source without
// pointing the state at memory it does not own.
//
// Value slots A and B hold the result of expression evaluation
// (kind: 0 null/missing, 1 bool, 2 number, 3 string, 4 array, 5 object).
// The Json node for kinds 4/5 rides in a 0/1-element Vec so the struct
// needs no bare Json field; all nodes are borrows into `ctxv[0]`, a copy of
// the caller's context that the render owns.

: TplRImpl {
    i pos
    b has_set  // F: rendered without a set (include fails)
    i depth  // include nesting guard
    i tag_a  // {% elif %} expression span, handed to the if-handler
    i tag_b
    i e_end  // one-past-end of the last parsed primary expression
    b failed
    i err_pos
    String err
    String out
    String key  // scratch: NUL-terminated path segment / include name
    ( Vec Json ) ctxv  // [0] = root context (the render's own copy)
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

@ __tpl_new b has_set Json jctx → TplRImpl {
    : ( Vec Json ) ctxv ( vec_new [Json] )
    ( vec_push [Json] ctxv ( mem_dup jctx ) )
    ^ @ TplRImpl {
        0 has_set 0 0 0 0 F 0 ( string_new ) ( string_with_cap 256 ) ( string_with_cap 32 )
        ctxv ( vec_new [String] ) ( vec_new [Json] ) ( vec_new [i] ) ( vec_new [i] )
        0 F 0.0 F ( string_with_cap 32 ) ( vec_new [Json] )
        0 F 0.0 ( string_with_cap 32 ) ( vec_new [Json] )
    }
}

// Record the first failure; later ones are ignored (the first is the cause).
@ __tpl_fail inout TplRImpl r TplSetImpl t ( Slice u ) sv i fpos s msg → v {
    ? . r failed {} {
        = . r failed T
        = . r err_pos fpos
        ( string_push_str . r err msg )
    }
}

@ __tpl_errmsg inout TplRImpl r TplSetImpl t ( Slice u ) sv → String {
    : ~ i p . r err_pos
    ? > p ( slice_len [u] sv ) { = p ( slice_len [u] sv ) } {}
    : ~ i line 1
    : ~ i col 1
    : ~ i k 0
    ~ < k p {
        ? == ( slice_byte sv k ) 10 { = line + line 1 = col 1 } { = col + col 1 }
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

@ __tpl_at ( Slice u ) sv i k → i {
    ? | < k 0 >= k ( slice_len [u] sv ) { ^ - 0 1 } {}
    ^ ( slice_byte sv k )
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

@ __tpl_ws inout TplRImpl r TplSetImpl t ( Slice u ) sv i k i bnd → i {
    : ~ i j k
    ~ & < j bnd ( __tpl_is_ws ( __tpl_at sv j ) ) { = j + j 1 }
    ^ j
}

// First index >= from where src[j] == c1 and src[j+1] == c2; -1 if none.
@ __tpl_find2 inout TplRImpl r TplSetImpl t ( Slice u ) sv i from i c1 i c2 → i {
    : ~ i j from
    : ~ i found - 0 1
    ~ & < j - ( slice_len [u] sv ) 1 < found 0 {
        ? & == ( __tpl_at sv j ) c1 == ( __tpl_at sv + j 1 ) c2 { = found j } { = j + j 1 }
    }
    ^ found
}

// Does span [a,b) equal the literal `lit`?
@ __tpl_kw_is inout TplRImpl r TplSetImpl t ( Slice u ) sv i a i bnd s lit → b {
    : i n ( nurl_str_len lit )
    ? | | != - bnd a n < a 0 > bnd ( slice_len [u] sv ) { ^ F } {}
    ^ ( slice_bytes_eq ( slice_window [u] sv a n ) ( slice_of_str lit ) )
}

// Does span [a,b) begin with the literal `lit`?
@ __tpl_span_starts inout TplRImpl r TplSetImpl t ( Slice u ) sv i a i bnd s lit → b {
    : i n ( nurl_str_len lit )
    ? < - bnd a n { ^ F } {}
    ^ ( __tpl_kw_is r t sv a + a n lit )
}

// Does span [a,a+n) equal the String `nm`?
@ __tpl_seg_eq inout TplRImpl r TplSetImpl t ( Slice u ) sv i a i n String nm → b {
    ? | | != ( string_len nm ) n < a 0 > + a n ( slice_len [u] sv ) { ^ F } {}
    ^ ( slice_bytes_eq ( slice_window [u] sv a n ) ( string_bytes nm ) )
}

// scratch key := src[a, a+n)
@ __tpl_key_set String key ( Slice u ) sv i a i n → v {
    ( string_clear key )
    : ~ i k 0
    ~ < k n {
        ( string_push_char key ( __tpl_at sv + a k ) )
        = k + k 1
    }
}

// Parse span [a,b) as a non-negative decimal integer; -1 when not one.
@ __tpl_span_int inout TplRImpl r TplSetImpl t ( Slice u ) sv i a i bnd → i {
    ? >= a bnd { ^ - 0 1 } {}
    : ~ i k a
    : ~ i acc 0
    : ~ b ok T
    ~ & ok < k bnd {
        : i c ( __tpl_at sv k )
        ? & >= c 48 <= c 57 { = acc + * acc 10 - c 48 = k + k 1 } { = ok F }
    }
    ? ok { ^ acc } { ^ - 0 1 }
}

// HTML-escape a NUL-terminated string into `out`.
@ __tpl_push_escaped String outbuf s raw → v {
    : ( Slice u ) bv ( slice_of_str raw )
    : i n ( slice_len [u] bv )
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte bv k )
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

@ __tpl_resolve inout TplRImpl r TplSetImpl t ( Slice u ) sv i pa i pb → ?Json {
    : ~ i sp pa
    : ~ Json cur ( json_null )
    : ~ b have F
    : ~ b dead F
    : ~ b first T
    ~ & == dead F < sp pb {
        : ~ i se sp
        ~ & < se pb != ( __tpl_at sv se ) 46 { = se + se 1 }
        : i slen - se sp
        ? == slen 0 { = dead T } {
            ? first {
                = first F
                : i ns ( vec_len [String] . r sc_names )
                : ~ i si - ns 1
                ~ & == have F >= si 0 {
                    ?? ( vec_get [String] . r sc_names si ) {
                        T nm → {
                            ? ( __tpl_seg_eq r t sv sp slen nm ) {
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
                                ( __tpl_key_set . r key sv sp slen )
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
                    ( __tpl_key_set . r key sv sp slen )
                    ?? ( json_obj_get cur ( string_data . r key ) ) {
                        T child → { = cur child }
                        F _ → { = dead T }
                    }
                } {
                    ? ( json_is_arr cur ) {
                        : i idx ( __tpl_span_int r t sv sp se )
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

@ __tpl_slot_reset inout TplRImpl r TplSetImpl t ( Slice u ) sv → v {
    = . r va_kind 0
    = . r va_bool F
    = . r va_num 0.0
    = . r va_raw F
    ( string_clear . r va_str )
    ( vec_clear [Json] . r va_node )
}

@ __tpl_slot_a_to_b inout TplRImpl r TplSetImpl t ( Slice u ) sv → v {
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

@ __tpl_slot_from_node inout TplRImpl r TplSetImpl t ( Slice u ) sv Json node → v {
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
@ __tpl_eval_primary inout TplRImpl r TplSetImpl t ( Slice u ) sv i a i bnd → v {
    ( __tpl_slot_reset r t sv )
    : i k ( __tpl_ws r t sv a bnd )
    ? >= k bnd { ( __tpl_fail r t sv a `empty expression` ) } {
        : i c ( __tpl_at sv k )
        ? | == c 39 == c 34 {
            // string literal
            : ~ i e - 0 1
            : ~ i j + k 1
            ~ & < j bnd < e 0 {
                ? == ( __tpl_at sv j ) c { = e j } { = j + j 1 }
            }
            ? < e 0 { ( __tpl_fail r t sv k `unterminated string literal` ) } {
                = . r va_kind 3
                : ~ i q + k 1
                ~ < q e {
                    ( string_push_char . r va_str ( __tpl_at sv q ) )
                    = q + q 1
                }
                = . r e_end + e 1
            }
        } {
            ? | == c 45 & >= c 48 <= c 57 {
                // number literal
                : ~ i te k
                ~ & < te bnd ( __tpl_is_numb ( __tpl_at sv te ) ) { = te + te 1 }
                = . r va_kind 2
                : ~ i q2 k
                ~ < q2 te {
                    ( string_push_char . r va_str ( __tpl_at sv q2 ) )
                    = q2 + q2 1
                }
                ?? ( string_to_float . r va_str ) {
                    T x → { = . r va_num x }
                    F _ → { ( __tpl_fail r t sv k `malformed number` ) }
                }
                = . r e_end te
            } {
                ? ( __tpl_is_identb c ) {
                    : ~ i te2 k
                    ~ & < te2 bnd ( __tpl_is_pathb ( __tpl_at sv te2 ) ) { = te2 + te2 1 }
                    = . r e_end te2
                    ? ( __tpl_kw_is r t sv k te2 `true` ) { = . r va_kind 1 = . r va_bool T } {
                        ? ( __tpl_kw_is r t sv k te2 `false` ) { = . r va_kind 1 = . r va_bool F } {
                            ? & > ( vec_len [i] . r lp_idx ) 0 ( __tpl_span_starts r t sv k te2 `loop.` ) {
                                : i nf ( vec_len [i] . r lp_idx )
                                : ~ i li 0
                                : ~ i ln 0
                                ?? ( vec_get [i] . r lp_idx - nf 1 ) { T x2 → { = li x2 } F _ → {} }
                                ?? ( vec_get [i] . r lp_len - nf 1 ) { T x3 → { = ln x3 } F _ → {} }
                                ? ( __tpl_kw_is r t sv k te2 `loop.index` ) {
                                    = . r va_kind 2
                                    = . r va_num # f li
                                    ( string_push_int . r va_str li )
                                } {
                                    ? ( __tpl_kw_is r t sv k te2 `loop.first` ) {
                                        = . r va_kind 1
                                        = . r va_bool == li 0
                                    } {
                                        ? ( __tpl_kw_is r t sv k te2 `loop.last` ) {
                                            = . r va_kind 1
                                            = . r va_bool == li - ln 1
                                        } {
                                            ? ( __tpl_kw_is r t sv k te2 `loop.length` ) {
                                                = . r va_kind 2
                                                = . r va_num # f ln
                                                ( string_push_int . r va_str ln )
                                            } {
                                                ( __tpl_fail r t sv k `unknown loop attribute (index/first/last/length)` )
                                            } } } }
                            } {
                                ?? ( __tpl_resolve r t sv k te2 ) {
                                    T node → { ( __tpl_slot_from_node r t sv node ) }
                                    F _ → {}
                                }
                            } } }
                } {
                    ( __tpl_fail r t sv k `bad expression` )
                } } }
    }
}

@ __tpl_truthy_a inout TplRImpl r TplSetImpl t ( Slice u ) sv → b {
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

@ __tpl_eq_ab inout TplRImpl r TplSetImpl t ( Slice u ) sv → b {
    ? != . r va_kind . r vb_kind { ^ F } {}
    : i kd . r va_kind
    ? == kd 0 { ^ T } {}
    ? == kd 1 { ^ == . r va_bool . r vb_bool } {}
    ? == kd 2 { ^ == . r va_num . r vb_num } {}
    ? == kd 3 { ^ ( string_eq . r va_str . r vb_str ) } {}
    ^ F
}

// Full condition: [not] primary [(==|!=) primary]
@ __tpl_truth inout TplRImpl r TplSetImpl t ( Slice u ) sv i a i bnd → b {
    : i k ( __tpl_ws r t sv a bnd )
    : ~ i tn k
    ~ & < tn bnd ( __tpl_is_pathb ( __tpl_at sv tn ) ) { = tn + tn 1 }
    ? ( __tpl_kw_is r t sv k tn `not` ) {
        : b inner ( __tpl_truth r t sv tn bnd )
        ^ == inner F
    } {}
    ( __tpl_eval_primary r t sv k bnd )
    ? . r failed { ^ F } {}
    : i k2 ( __tpl_ws r t sv . r e_end bnd )
    ? >= k2 bnd { ^ ( __tpl_truthy_a r t sv ) } {}
    : i o1 ( __tpl_at sv k2 )
    : i o2 ( __tpl_at sv + k2 1 )
    : ~ b want T
    ? & == o1 61 == o2 61 {} {
        ? & == o1 33 == o2 61 { = want F } {
            ( __tpl_fail r t sv k2 `unsupported operator (only == and !=)` )
        }
    }
    ? . r failed { ^ F } {}
    ( __tpl_slot_a_to_b r t sv )
    ( __tpl_eval_primary r t sv + k2 2 bnd )
    ? . r failed { ^ F } {}
    : b eq ( __tpl_eq_ab r t sv )
    ? want { ^ eq } { ^ == eq F }
}

// ── Output tag: {{ expr | filters }} ─────────────────────────────────

@ __tpl_apply_filter inout TplRImpl r TplSetImpl t ( Slice u ) sv i fa i fe → v {
    ? ( __tpl_kw_is r t sv fa fe `raw` ) { = . r va_raw T } {
        ? ( __tpl_kw_is r t sv fa fe `upper` ) {
            ? | == . r va_kind 3 == . r va_kind 2 {
                : String u ( string_to_upper . r va_str )
                ( string_free . r va_str )
                = . r va_str u
            } {}
        } {
            ? ( __tpl_kw_is r t sv fa fe `lower` ) {
                ? | == . r va_kind 3 == . r va_kind 2 {
                    : String l ( string_to_lower . r va_str )
                    ( string_free . r va_str )
                    = . r va_str l
                } {}
            } {
                ? ( __tpl_kw_is r t sv fa fe `length` ) {
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
                    ? ( __tpl_kw_is r t sv fa fe `json` ) {
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
                        ( __tpl_fail r t sv fa `unknown filter (raw/upper/lower/length/json)` )
                    } } } } }
}

@ __tpl_emit_a inout TplRImpl r TplSetImpl t ( Slice u ) sv → v {
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

@ __tpl_out_tag inout TplRImpl r TplSetImpl t ( Slice u ) sv i a i bnd → v {
    ( __tpl_eval_primary r t sv a bnd )
    ? . r failed {} {
        : ~ i k . r e_end
        : ~ b more T
        ~ & more == . r failed F {
            = k ( __tpl_ws r t sv k bnd )
            ? & < k bnd == ( __tpl_at sv k ) 124 {
                : i fa ( __tpl_ws r t sv + k 1 bnd )
                : ~ i fe fa
                ~ & < fe bnd ( __tpl_is_identb ( __tpl_at sv fe ) ) { = fe + fe 1 }
                ? == fe fa { ( __tpl_fail r t sv k `empty filter` ) } {
                    ( __tpl_apply_filter r t sv fa fe )
                    = k fe
                }
            } {
                ? < k bnd { ( __tpl_fail r t sv k `trailing characters in expression` ) } {}
                = more F
            }
        }
        ? . r failed {} { ( __tpl_emit_a r t sv ) }
    }
}

// ── Control tags ─────────────────────────────────────────────────────

// {% if e %} … {% elif e %} … {% else %} … {% end %}
// Skipping is rendering with emit=F, so nesting stays balanced.
@ __tpl_do_if inout TplRImpl r TplSetImpl t ( Slice u ) sv i ea i eb b emit → v {
    : ~ b cond F
    ? emit { = cond ( __tpl_truth r t sv ea eb ) } {}
    : ~ b handled cond
    : ~ i term ( __tpl_run r t sv & emit cond )
    ~ & == term 3 == . r failed F {
        : i xa . r tag_a
        : i xb . r tag_b
        : ~ b c2 F
        ? & emit == handled F { = c2 ( __tpl_truth r t sv xa xb ) } {}
        ? c2 { = handled T } {}
        = term ( __tpl_run r t sv & emit c2 )
    }
    ? & == term 2 == . r failed F {
        = term ( __tpl_run r t sv & emit == handled F )
    } {}
    ? & != term 1 == . r failed F {
        ( __tpl_fail r t sv . r pos `'{% if %}' without matching '{% end %}'` )
    } {}
}

// {% for NAME in PATH %} … {% end %}
// The body span is re-scanned once per item; the loop variable and a
// loop frame (index/len) are pushed for the duration.
@ __tpl_do_for inout TplRImpl r TplSetImpl t ( Slice u ) sv i ea i eb b emit → v {
    ? == emit F {
        : i tt ( __tpl_run r t sv F )
        ? & != tt 1 == . r failed F {
            ( __tpl_fail r t sv . r pos `'{% for %}' without matching '{% end %}'` )
        } {}
    } {
        : i va ( __tpl_ws r t sv ea eb )
        : ~ i ve va
        ~ & < ve eb ( __tpl_is_identb ( __tpl_at sv ve ) ) { = ve + ve 1 }
        : i k1 ( __tpl_ws r t sv ve eb )
        : ~ i ke k1
        ~ & < ke eb ( __tpl_is_pathb ( __tpl_at sv ke ) ) { = ke + ke 1 }
        : ~ b ok T
        ? == ve va { = ok F } {}
        ? ( __tpl_kw_is r t sv k1 ke `in` ) {} { = ok F }
        ? == ok F {
            ( __tpl_fail r t sv ea `malformed '{% for %}': expected 'for NAME in PATH'` )
        } {
            : i pa ( __tpl_ws r t sv ke eb )
            : ~ i pb eb
            ~ & > pb pa ( __tpl_is_ws ( __tpl_at sv - pb 1 ) ) { = pb - pb 1 }
            : ~ Json seq ( json_null )
            ?? ( __tpl_resolve r t sv pa pb ) { T node → { = seq node } F _ → {} }
            : ~ i n 0
            ? ( json_is_arr seq ) { = n ( json_arr_len seq ) } {
                ? ( json_is_null seq ) {} {
                    ( __tpl_fail r t sv pa `'{% for %}' over a non-array value` )
                }
            }
            ? . r failed {} {
                ? == n 0 {
                    : i t2 ( __tpl_run r t sv F )
                    ? & != t2 1 == . r failed F {
                        ( __tpl_fail r t sv . r pos `'{% for %}' without matching '{% end %}'` )
                    } {}
                } {
                    : i body . r pos
                    ( __tpl_key_set . r key sv va - ve va )
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
                        : i t3 ( __tpl_run r t sv T )
                        ? & != t3 1 == . r failed F {
                            ( __tpl_fail r t sv . r pos `'{% for %}' without matching '{% end %}'` )
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
@ __tpl_do_include inout TplRImpl r TplSetImpl t ( Slice u ) sv i a i bnd → v {
    : i k ( __tpl_ws r t sv a bnd )
    : i qc ( __tpl_at sv k )
    ? | == qc 39 == qc 34 {
        : ~ i e - 0 1
        : ~ i j + k 1
        ~ & < j bnd < e 0 {
            ? == ( __tpl_at sv j ) qc { = e j } { = j + j 1 }
        }
        ? < e 0 { ( __tpl_fail r t sv k `unterminated template name` ) } {
            ? ! . r has_set {
                ( __tpl_fail r t sv k `'{% include %}' needs a template set (use tset_render / tpl_render_with)` )
            } {
                ? >= . r depth 16 {
                    ( __tpl_fail r t sv k `include depth limit exceeded (cycle?)` )
                } {
                    ( __tpl_key_set . r key sv + k 1 - e + k 1 )
                    : i idx ( __tset_find t ( string_data . r key ) )
                    ? < idx 0 { ( __tpl_fail r t sv k `include: template not found` ) } {
                        ?? ( vec_get [( Arc String )] . t srcs idx ) {
                            T sa → {
                                : String isrc ( arc_get [String] sa )
                                : ( Slice u ) isv ( slice_of_str ( string_data isrc ) )
                                : i opos . r pos
                                = . r pos 0
                                = . r depth + . r depth 1
                                : i t2 ( __tpl_run r t isv T )
                                ? & != t2 0 == . r failed F {
                                    ( __tpl_fail r t isv . r pos `unbalanced block tag in included template` )
                                } {}
                                = . r pos opos
                                = . r depth - . r depth 1
                            }
                            F _ → {}
                        }
                    }
                }
            }
        }
    } {
        ( __tpl_fail r t sv k `'{% include %}' expects a quoted template name` )
    }
}

// ── Block renderer ───────────────────────────────────────────────────
//
// Renders (emit=T) or skips (emit=F) from `pos` until EOF or a block
// terminator. Returns 0 = EOF, 1 = {% end %}, 2 = {% else %},
// 3 = {% elif %} (expression span left in tag_a/tag_b).

@ __tpl_run inout TplRImpl r TplSetImpl t ( Slice u ) sv b emit → i {
    : ~ i term - 0 1
    ~ & == term - 0 1 == . r failed F {
        : i p0 . r pos
        ? >= p0 ( slice_len [u] sv ) { = term 0 } {
            : i c ( __tpl_at sv p0 )
            : i c1 ( __tpl_at sv + p0 1 )
            ? & == c 123 == c1 123 {
                // {{ expr }}
                : i close ( __tpl_find2 r t sv + p0 2 125 125 )
                ? < close 0 { ( __tpl_fail r t sv p0 `unclosed '{{'` ) } {
                    ? emit { ( __tpl_out_tag r t sv + p0 2 close ) } {}
                    = . r pos + close 2
                }
            } {
                ? & == c 123 == c1 35 {
                    // {# comment #}
                    : i close ( __tpl_find2 r t sv + p0 2 35 125 )
                    ? < close 0 { ( __tpl_fail r t sv p0 `unclosed '{#'` ) } {
                        = . r pos + close 2
                    }
                } {
                    ? & == c 123 == c1 37 {
                        // {% tag %}
                        : i close ( __tpl_find2 r t sv + p0 2 37 125 )
                        ? < close 0 { ( __tpl_fail r t sv p0 `unclosed '{%'` ) } {
                            : i ta ( __tpl_ws r t sv + p0 2 close )
                            : ~ i te ta
                            ~ & < te close ( __tpl_is_identb ( __tpl_at sv te ) ) { = te + te 1 }
                            = . r pos + close 2
                            ? ( __tpl_kw_is r t sv ta te `if` ) { ( __tpl_do_if r t sv te close emit ) } {
                                ? ( __tpl_kw_is r t sv ta te `for` ) { ( __tpl_do_for r t sv te close emit ) } {
                                    ? ( __tpl_kw_is r t sv ta te `include` ) {
                                        ? emit { ( __tpl_do_include r t sv te close ) } {}
                                    } {
                                        ? | | ( __tpl_kw_is r t sv ta te `end` ) ( __tpl_kw_is r t sv ta te `endif` ) ( __tpl_kw_is r t sv ta te `endfor` ) {
                                            = term 1
                                        } {
                                            ? ( __tpl_kw_is r t sv ta te `else` ) { = term 2 } {
                                                ? ( __tpl_kw_is r t sv ta te `elif` ) {
                                                    = . r tag_a te
                                                    = . r tag_b close
                                                    = term 3
                                                } {
                                                    ( __tpl_fail r t sv ta `unknown tag (if/elif/else/for/include/end)` )
                                                } } } } } }
                        }
                    } {
                        // plain text: emit until the next tag opener or EOF
                        : ~ i k p0
                        : ~ b scan T
                        ~ & scan < k ( slice_len [u] sv ) {
                            : i tc ( __tpl_at sv k )
                            ? == tc 123 {
                                : i tn ( __tpl_at sv + k 1 )
                                ? | | == tn 123 == tn 37 == tn 35 { = scan F } { = k + k 1 }
                            } { = k + k 1 }
                        }
                        ? emit {
                            : ~ i q p0
                            ~ < q k {
                                ( string_push_char . r out ( __tpl_at sv q ) )
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

@ __tpl_render TplSetImpl t b has_set s tsrc Json jctx → !String String {
    : ~ TplRImpl r ( __tpl_new has_set jctx )
    : ( Slice u ) sv ( slice_of_str tsrc )
    : i term ( __tpl_run r t sv T )
    ? & != term 0 == . r failed F {
        ( __tpl_fail r t sv . r pos `'{% end %}' or '{% else %}' without an open block` )
    } {}
    ? . r failed { ^ @ !String String { F ( __tpl_errmsg r t sv ) } } {}
    // The output leaves the state for the caller, an empty one left in
    // its place.
    ^ @ !String String { T ( mem_replace [String] . r out ( string_new ) ) }
}

// Render template source against a Json context. The error payload is
// an owned String ("template error at line L, col C: …").
@ tpl_render s tsrc Json jctx → !String String {
    : TplSetImpl none ( __tset_empty )
    ^ ( __tpl_render none F tsrc jctx )
}

// Same, with a TplSet so `{% include 'name' %}` resolves.
@ tpl_render_with TplSet t s tsrc Json jctx → !String String {
    : ( Arc TplSetImpl ) snap ( __tset_snapshot t )
    ^ ( __tpl_render ( arc_get [TplSetImpl] snap ) T tsrc jctx )
}

// Render a named member of the set.
@ tset_render TplSet t__h s name Json jctx → !String String {
    : ( Arc TplSetImpl ) snap ( __tset_snapshot t__h )
    : TplSetImpl t ( arc_get [TplSetImpl] snap )
    : i idx ( __tset_find t name )
    ? < idx 0 {
        : String m ( string_from `template not found: ` )
        ( string_push_str m name )
        ^ @ !String String { F m }
    } {}
    ?? ( vec_get [( Arc String )] . t srcs idx ) {
        T sa → {
            : String src ( arc_get [String] sa )
            ^ ( __tpl_render t T ( string_data src ) jctx )
        }
        F _ → { ^ @ !String String { F ( string_from `template not found` ) } }
    }
}
