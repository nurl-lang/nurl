// log_structured.nu — exercises stdlib/std/log.nu's structured-logging
// additions (JSON mode toggle + log_<level>_kv1/2/3 variants).
//
// All log_* output lands on stderr; the test runner combines stdout +
// stderr into a single OUTPUT block in correct.txt, so the baseline
// captures both. Lines are interleaved deterministically because every
// log call flushes via nurl_eprint and the test serialises them.
//
// Layout of the baseline (one line per check):
//   ── Text mode ────────────────
//   [INFO]  hello                              raw msg
//   [INFO]  user logged in user_id=42          one kv
//   [INFO]  request ip=1.2.3.4 path=/health    two kvs
//   [WARN]  near limit pct=92 host=db ip=10.0.0.5
//   [DEBUG] verbose trace               (suppressed — level=Info default)
//   ── JSON mode ────────────────
//   {"level":"info","msg":"hello"}
//   {"level":"info","msg":"user logged in","user_id":"42"}
//   {"level":"warn","msg":"near limit","pct":"92","host":"db"}
//   {"level":"error","msg":"with \"quote\" and \\","detail":"line\nbreak"}
//   (escape coverage check — `"`, `\`, `\n` all round-trip through
//   __log_json_emit_raw)

$ `stdlib/std/log.nu`

@ main → i {
    // ── Text mode (default) ─────────────────────────────────────────
    ( log_info `hello` )
    ( log_info_kv1 `user logged in` `user_id` `42` )
    ( log_info_kv2 `request` `ip` `1.2.3.4` `path` `/health` )
    ( log_warn_kv3 `near limit` `pct` `92` `host` `db` `ip` `10.0.0.5` )
    // Below-threshold: default level is Info (1); a Debug call is
    // silently dropped both in text and JSON mode.
    ( log_debug `verbose trace` )

    // ── JSON mode ───────────────────────────────────────────────────
    ( log_set_json T )
    ( log_info `hello` )
    ( log_info_kv1 `user logged in` `user_id` `42` )
    ( log_warn_kv2 `near limit` `pct` `92` `host` `db` )

    // Escape coverage: the msg contains a literal `"` and `\`; the kv
    // value contains a `\n`. Output MUST be RFC 8259 compliant.
    ( log_error_kv1 `with "quote" and \\` `detail` `line\nbreak` )

    ( log_set_json F )
    ^ 0
}
