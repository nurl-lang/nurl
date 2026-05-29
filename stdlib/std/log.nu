// stdlib/std/log.nu — leveled structured logging on top of fmt
//
// All output goes to stderr (matches eprintln) so logs don't interleave
// with stdout. The current threshold lives in this module's mutable
// `__g_log_level` global. Messages whose level is below the threshold
// are silently dropped.
//
// Levels (low → high):
//   0  Debug   — verbose tracing, typically off in production
//   1  Info    — normal operational events  (default threshold)
//   2  Warn    — recoverable problems
//   3  Error   — failures the caller should notice
//   4  Off     — silence everything
//
// Tag prefix is fixed (`[DEBUG] `, `[INFO]  `, `[WARN]  `, `[ERROR] `)
// so columns line up in terminals. No timestamp by default — that
// would couple every log line to wall-clock time and make tests
// non-deterministic. Add `now_ms` from `stdlib/std/time.nu` in the
// fmt template if you want one (`( log_infof1 \`t={} done\`
// ( nurl_str_int ( now_ms ) ) )`).
//
// Output modes:
//   text (default) — `[INFO]  msg key1=val1 key2=val2`
//   json           — `{"level":"info","msg":"msg","key1":"val1",...}`
//
// JSON mode applies uniformly to every log_* call. Toggle via
// `log_set_json T` / `log_set_json F`; query via `log_get_json`. JSON
// values are RFC 8259-compliant (named escapes for `"` `\` `\n` `\r`
// `\t`; remaining control bytes 0x00..0x1F → `\u00XX`).
//
// Public API:
//
//   ( log_set_level lvl )       → v
//   ( log_get_level )           → i
//   ( log_level_debug )         → i   constants for log_set_level
//   ( log_level_info )          → i
//   ( log_level_warn )          → i
//   ( log_level_error )         → i
//   ( log_level_off )           → i
//
//   ( log_set_json on )         → v   text (F, default) | JSON (T) output
//   ( log_get_json )            → b
//
//   ( log_debug msg )           → v   raw message at each level
//   ( log_info  msg )           → v
//   ( log_warn  msg )           → v
//   ( log_error msg )           → v
//
//   ( log_debugf1 tmpl a )      → v   fmt1-based variants — same `{}`
//   ( log_debugf2 tmpl a b )    → v   substitution rules as
//   ( log_debugf3 tmpl a b c )  → v   stdlib/std/fmt.nu.
//   ( log_infof1 / 2 / 3 ... )
//   ( log_warnf1 / 2 / 3 ... )
//   ( log_errorf1 / 2 / 3 ... )
//
//   ( log_debug_kv1 msg k1 v1 )                       → v   key/value variants
//   ( log_debug_kv2 msg k1 v1 k2 v2 )                 → v   (1..3 pairs, raw
//   ( log_debug_kv3 msg k1 v1 k2 v2 k3 v3 )           → v   `s` keys + values)
//   ( log_info_kv1  / 2 / 3 ... )
//   ( log_warn_kv1  / 2 / 3 ... )
//   ( log_error_kv1 / 2 / 3 ... )
//
// All `log_*f*` accept raw `s` arguments — string literals work
// directly, owned `String` use `( string_data str )`, integers use
// `( nurl_str_int n )`, floats `( nurl_str_float x )`.
//
// Note: `log_*f*` always allocates a small Vec[s] for argument
// marshalling. Below-threshold calls still pay this cost; the
// emit itself is cheap (a few stderr writes). If you have a
// hot path that logs a million Debug-suppressed lines, gate the
// call yourself with `( log_get_level )`.
//
// Example:
//   ( log_set_level ( log_level_warn ) )
//   ( log_info  `app started` )                 // suppressed (1 < 2)
//   ( log_warnf2 `disk {} at {}%` `/var` `93` ) // shown

$ `stdlib/std/fmt.nu`

// ── Level constants (functions because module-level `: i FOO` only
//    accepts literal RHS; using functions also avoids prelude clashes) ─

@ log_level_debug → i { ^ 0 }

@ log_level_info → i { ^ 1 }

@ log_level_warn → i { ^ 2 }

@ log_level_error → i { ^ 3 }

@ log_level_off → i { ^ 4 }

// ── Threshold state + accessors ─────────────────────────────────────
//
// Pure-NURL mutable global; default Info (1). Single-process, so no
// pthread synchronisation — the value is a single i64, atomic on
// every supported target. `set` from one thread is observable to
// `get` on another with the next memory-fenced syscall (which every
// `log_*` call performs via `nurl_eprint`).

: ~ i __g_log_level 1

@ log_set_level i lvl → v {
    = __g_log_level lvl
}

@ log_get_level → i {
    ^ __g_log_level
}

// ── Output-mode toggle (text vs JSON) ───────────────────────────────
//
// Default is text (F). Set to T to emit one-line JSON objects suitable
// for log-aggregation tools. Affects every log_* call uniformly.

: ~ b __g_log_json F

@ log_set_json b on → v {
    = __g_log_json on
}

@ log_get_json → b {
    ^ __g_log_json
}

// ── Internal emit ───────────────────────────────────────────────────

@ __log_tag i level → s {
    ? == level 0 { ^ `[DEBUG] ` } {}
    ? == level 1 { ^ `[INFO]  ` } {}
    ? == level 2 { ^ `[WARN]  ` } {}
    ? == level 3 { ^ `[ERROR] ` } {}
    ^ `[?]     `
}

// Lower-case level name for the JSON `"level":"..."` field.
@ __log_level_name i level → s {
    ? == level 0 { ^ `debug` } {}
    ? == level 1 { ^ `info` } {}
    ? == level 2 { ^ `warn` } {}
    ? == level 3 { ^ `error` } {}
    ^ `unknown`
}

// Push one hex nibble (0..15) as its ASCII char into `out`. Lowercase
// ('0'..'9' / 'a'..'f') so the output matches stdlib/ext/json.nu's
// `__js_emit_str` convention.
@ __log_json_hex String out i n → v {
    : i c ? < n 10 + n 48 + n 87
    ( string_push_char out c )
}

// JSON-encode the raw `s` value `in` (NUL-terminated) into `out`,
// including the surrounding double quotes. Five named escapes
// (\" \\ \n \r \t) cover the common cases; remaining control bytes
// (0x00..0x1F without a named escape) emit `\u00XX`. The walk uses
// a `*u` pointer to avoid the O(strlen) per-byte cost of the
// generic `nurl_str_get` helper.
@ __log_json_emit_raw String out s in → v {
    ( string_push_char out 34 )
    : i n ( nurl_str_len in )
    : *u p # *u in
    : ~ i k 0
    ~ < k n {
        : i c & # i . p k 255
        ? == c 34 { ( string_push_char out 92 ) ( string_push_char out 34 ) } {
            ? == c 92 { ( string_push_char out 92 ) ( string_push_char out 92 ) } {
                ? == c 10 { ( string_push_char out 92 ) ( string_push_char out 110 ) } {
                    ? == c 13 { ( string_push_char out 92 ) ( string_push_char out 114 ) } {
                        ? == c 9 { ( string_push_char out 92 ) ( string_push_char out 116 ) } {
                            ? < c 32 {
                                ( string_push_char out 92 )
                                ( string_push_char out 117 )
                                ( string_push_char out 48 )
                                ( string_push_char out 48 )
                                ( __log_json_hex out & >> c 4 15 )
                                ( __log_json_hex out & c 15 )
                            } {
                                ( string_push_char out c )
                            } } } } } }
        = k + k 1
    }
    ( string_push_char out 34 )
}

// vec_get [s] returns `?s`; unwrap or empty (out-of-range is a
// programmer error here, never reached on the public API path).
@ __log_vec_at ( Vec s ) v i idx → s {
    : ?s o ( vec_get [s] v idx )
    ?? o { T sv → sv F → `` }
}

// Single internal dispatch: takes the level, the rendered message,
// and parallel key/value Vec[s]. Suppresses below-threshold calls;
// emits text or JSON form depending on `__g_log_json`.
@ __log_dispatch i level s msg ( Vec s ) keys ( Vec s ) vals → v {
    : i thr __g_log_level
    ? < level thr {} {
        ? __g_log_json {
            // JSON: `{"level":"<lvl>","msg":"<msg>",<k>:<v>...}\n`
            : String line ( string_new )
            ( string_push_str line `{"level":"` )
            ( string_push_str line ( __log_level_name level ) )
            ( string_push_str line `","msg":` )
            ( __log_json_emit_raw line msg )
            : i n ( vec_len [s] keys )
            : ~ i k 0
            ~ < k n {
                ( string_push_char line 44 )  // ','
                ( __log_json_emit_raw line ( __log_vec_at keys k ) )
                ( string_push_char line 58 )  // ':'
                ( __log_json_emit_raw line ( __log_vec_at vals k ) )
                = k + k 1
            }
            ( string_push_str line `}\n` )
            ( nurl_eprint ( string_data line ) )
            ( string_free line )
        } {
            // Text: `[INFO]  msg k1=v1 k2=v2\n` (no quoting of values;
            // use JSON mode for values that may contain whitespace or
            // ambiguous characters)
            ( nurl_eprint ( __log_tag level ) )
            ( nurl_eprint msg )
            : i n ( vec_len [s] keys )
            : ~ i k 0
            ~ < k n {
                ( nurl_eprint ` ` )
                ( nurl_eprint ( __log_vec_at keys k ) )
                ( nurl_eprint `=` )
                ( nurl_eprint ( __log_vec_at vals k ) )
                = k + k 1
            }
            ( nurl_eprint `\n` )
        }
    }
}

@ __log_emit i level s msg → v {
    : ( Vec s ) keys ( vec_new [s] )
    : ( Vec s ) vals ( vec_new [s] )
    ( __log_dispatch level msg keys vals )
    ( vec_free [s] keys )
    ( vec_free [s] vals )
}

@ __log_emitf i level s tmpl ( Vec s ) args → v {
    : i thr __g_log_level
    ? < level thr {} {
        : String r ( fmt tmpl args )
        : ( Vec s ) keys ( vec_new [s] )
        : ( Vec s ) vals ( vec_new [s] )
        ( __log_dispatch level ( string_data r ) keys vals )
        ( vec_free [s] keys )
        ( vec_free [s] vals )
        ( string_free r )
    }
}

// ── Raw-message variants ────────────────────────────────────────────

@ log_debug s msg → v { ( __log_emit 0 msg ) }

@ log_info s msg → v { ( __log_emit 1 msg ) }

@ log_warn s msg → v { ( __log_emit 2 msg ) }

@ log_error s msg → v { ( __log_emit 3 msg ) }

// ── Formatted variants (1..3 args; build a Vec[s] then dispatch) ────

@ log_debugf1 s tmpl s a → v {
    : ( Vec s ) v ( vec_with_cap [s] 1 )
    ( vec_push [s] v a )
    ( __log_emitf 0 tmpl v )
    ( vec_free [s] v )
}

@ log_debugf2 s tmpl s a s b → v {
    : ( Vec s ) v ( vec_with_cap [s] 2 )
    ( vec_push [s] v a )
    ( vec_push [s] v b )
    ( __log_emitf 0 tmpl v )
    ( vec_free [s] v )
}

@ log_debugf3 s tmpl s a s b s c → v {
    : ( Vec s ) v ( vec_with_cap [s] 3 )
    ( vec_push [s] v a )
    ( vec_push [s] v b )
    ( vec_push [s] v c )
    ( __log_emitf 0 tmpl v )
    ( vec_free [s] v )
}

@ log_infof1 s tmpl s a → v {
    : ( Vec s ) v ( vec_with_cap [s] 1 )
    ( vec_push [s] v a )
    ( __log_emitf 1 tmpl v )
    ( vec_free [s] v )
}

@ log_infof2 s tmpl s a s b → v {
    : ( Vec s ) v ( vec_with_cap [s] 2 )
    ( vec_push [s] v a )
    ( vec_push [s] v b )
    ( __log_emitf 1 tmpl v )
    ( vec_free [s] v )
}

@ log_infof3 s tmpl s a s b s c → v {
    : ( Vec s ) v ( vec_with_cap [s] 3 )
    ( vec_push [s] v a )
    ( vec_push [s] v b )
    ( vec_push [s] v c )
    ( __log_emitf 1 tmpl v )
    ( vec_free [s] v )
}

@ log_warnf1 s tmpl s a → v {
    : ( Vec s ) v ( vec_with_cap [s] 1 )
    ( vec_push [s] v a )
    ( __log_emitf 2 tmpl v )
    ( vec_free [s] v )
}

@ log_warnf2 s tmpl s a s b → v {
    : ( Vec s ) v ( vec_with_cap [s] 2 )
    ( vec_push [s] v a )
    ( vec_push [s] v b )
    ( __log_emitf 2 tmpl v )
    ( vec_free [s] v )
}

@ log_warnf3 s tmpl s a s b s c → v {
    : ( Vec s ) v ( vec_with_cap [s] 3 )
    ( vec_push [s] v a )
    ( vec_push [s] v b )
    ( vec_push [s] v c )
    ( __log_emitf 2 tmpl v )
    ( vec_free [s] v )
}

@ log_errorf1 s tmpl s a → v {
    : ( Vec s ) v ( vec_with_cap [s] 1 )
    ( vec_push [s] v a )
    ( __log_emitf 3 tmpl v )
    ( vec_free [s] v )
}

@ log_errorf2 s tmpl s a s b → v {
    : ( Vec s ) v ( vec_with_cap [s] 2 )
    ( vec_push [s] v a )
    ( vec_push [s] v b )
    ( __log_emitf 3 tmpl v )
    ( vec_free [s] v )
}

@ log_errorf3 s tmpl s a s b s c → v {
    : ( Vec s ) v ( vec_with_cap [s] 3 )
    ( vec_push [s] v a )
    ( vec_push [s] v b )
    ( vec_push [s] v c )
    ( __log_emitf 3 tmpl v )
    ( vec_free [s] v )
}

// ── Key/value variants (1..3 pairs at each level) ───────────────────
//
// Below-threshold calls still allocate the 2 small Vec[s] for argument
// marshalling — same cost profile as log_*fN. Use `( log_get_level )`
// to gate a hot-path Debug log explicitly if needed.

@ __log_kv_emit i level s msg s k1 s v1 i n2 s k2 s v2 i n3 s k3 s v3 → v {
    : ( Vec s ) keys ( vec_with_cap [s] 3 )
    : ( Vec s ) vals ( vec_with_cap [s] 3 )
    ( vec_push [s] keys k1 ) ( vec_push [s] vals v1 )
    ? != n2 0 { ( vec_push [s] keys k2 ) ( vec_push [s] vals v2 ) } {}
    ? != n3 0 { ( vec_push [s] keys k3 ) ( vec_push [s] vals v3 ) } {}
    ( __log_dispatch level msg keys vals )
    ( vec_free [s] keys )
    ( vec_free [s] vals )
}

@ log_debug_kv1 s msg s k1 s v1 → v {
    ( __log_kv_emit 0 msg k1 v1 0 `` `` 0 `` `` )
}

@ log_debug_kv2 s msg s k1 s v1 s k2 s v2 → v {
    ( __log_kv_emit 0 msg k1 v1 1 k2 v2 0 `` `` )
}

@ log_debug_kv3 s msg s k1 s v1 s k2 s v2 s k3 s v3 → v {
    ( __log_kv_emit 0 msg k1 v1 1 k2 v2 1 k3 v3 )
}

@ log_info_kv1 s msg s k1 s v1 → v {
    ( __log_kv_emit 1 msg k1 v1 0 `` `` 0 `` `` )
}

@ log_info_kv2 s msg s k1 s v1 s k2 s v2 → v {
    ( __log_kv_emit 1 msg k1 v1 1 k2 v2 0 `` `` )
}

@ log_info_kv3 s msg s k1 s v1 s k2 s v2 s k3 s v3 → v {
    ( __log_kv_emit 1 msg k1 v1 1 k2 v2 1 k3 v3 )
}

@ log_warn_kv1 s msg s k1 s v1 → v {
    ( __log_kv_emit 2 msg k1 v1 0 `` `` 0 `` `` )
}

@ log_warn_kv2 s msg s k1 s v1 s k2 s v2 → v {
    ( __log_kv_emit 2 msg k1 v1 1 k2 v2 0 `` `` )
}

@ log_warn_kv3 s msg s k1 s v1 s k2 s v2 s k3 s v3 → v {
    ( __log_kv_emit 2 msg k1 v1 1 k2 v2 1 k3 v3 )
}

@ log_error_kv1 s msg s k1 s v1 → v {
    ( __log_kv_emit 3 msg k1 v1 0 `` `` 0 `` `` )
}

@ log_error_kv2 s msg s k1 s v1 s k2 s v2 → v {
    ( __log_kv_emit 3 msg k1 v1 1 k2 v2 0 `` `` )
}

@ log_error_kv3 s msg s k1 s v1 s k2 s v2 s k3 s v3 → v {
    ( __log_kv_emit 3 msg k1 v1 1 k2 v2 1 k3 v3 )
}
