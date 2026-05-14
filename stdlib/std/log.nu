// stdlib/std/log.nu — leveled structured logging on top of fmt
//
// All output goes to stderr (matches eprintln) so logs don't interleave
// with stdout. The current threshold is held in a process-wide global
// (`nurl_log_level_get/set` in runtime §15); messages whose level is
// below the threshold are silently dropped.
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

// ── Threshold accessors ─────────────────────────────────────────────

@ log_set_level i lvl → v {
    ( nurl_log_level_set lvl )
}

@ log_get_level → i {
    ^ ( nurl_log_level_get )
}

// ── Internal emit ───────────────────────────────────────────────────

@ __log_tag i level → s {
    ? == level 0 { ^ `[DEBUG] ` } {}
    ? == level 1 { ^ `[INFO]  ` } {}
    ? == level 2 { ^ `[WARN]  ` } {}
    ? == level 3 { ^ `[ERROR] ` } {}
    ^ `[?]     `
}

@ __log_emit i level s msg → v {
    : i thr ( nurl_log_level_get )
    ? >= level thr {
        ( nurl_eprint ( __log_tag level ) )
        ( nurl_eprint msg )
        ( nurl_eprint `\n` )
    } {}
}

@ __log_emitf i level s tmpl ( Vec s ) args → v {
    : i thr ( nurl_log_level_get )
    ? >= level thr {
        : String r ( fmt tmpl args )
        ( nurl_eprint ( __log_tag level ) )
        ( nurl_eprint ( string_data r ) )
        ( nurl_eprint `\n` )
        ( string_free r )
    } {}
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
