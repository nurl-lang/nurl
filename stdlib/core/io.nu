// stdlib/core/io.nu — Tier 0 stdin/stdout completion
//
// Thin wrappers that lift the runtime read_line / flush / eof primitives
// into NURL's owned-String model and boolean convention.
//
//   ( read_line )         → String  owned line from stdin (trailing '\n' stripped)
//                                   On EOF with no data: empty String, ( stdin_eof ) turns T.
//   ( read_all_stdin )    → String  slurp stdin to EOF; empty String when no data.
//   ( stdin_eof )         → b       T iff a previous read_line hit EOF with no data
//   ( flush )             → v       fflush(stdout)
//   ( eflush )            → v       fflush(stderr)

$ `stdlib/core/string.nu`

@ read_line → String {
  : s raw ( nurl_read_line )
  : String out ( string_from raw )
  ^ out
}

// Read everything from stdin until EOF and return it as a single owned
// String. CLI tools that consume stdin (e.g. `cat`, `wc`, JSON formatters)
// use this when line-at-a-time iteration isn't required. Returns an empty
// String on allocation failure too — the runtime falls back to NULL which
// `string_from` turns into "" rather than crashing.
@ read_all_stdin → String {
  : s raw ( nurl_read_all_stdin )
  : i p # i raw
  ? == p 0 {
    ^ ( string_new )
  } {}
  : String out ( string_from raw )
  ( nurl_free raw )
  ^ out
}

@ stdin_eof → b {
  ^ != 0 ( nurl_stdin_eof )
}

@ flush → v {
  ( nurl_flush_stdout )
}

@ eflush → v {
  ( nurl_flush_stderr )
}
