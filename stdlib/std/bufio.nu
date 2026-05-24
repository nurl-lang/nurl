// stdlib/std/bufio.nu — buffered streaming reader
//
// BufReader pulls a file (or stdin) through a growable buffer one chunk
// at a time, so a multi-gigabyte input is processed without ever being
// fully resident — the opposite of `read_file` / `csv_reader_new`, which
// load the whole file first. Built for fast ETL: log / CSV / JSONL
// line scanning over inputs far larger than RAM.
//
// Speed:
//   * One `fread` per refill against a 64 KiB buffer — few syscalls.
//   * `memchr` (glibc SIMD) finds the line terminator, not a byte loop.
//   * `bufreader_read_line_into` refills the *caller's* String, so a
//     steady-state line loop allocates nothing after warm-up.
//
// Safety:
//   * BufReader owns its buffer + file handle; `bufreader_close` frees
//     both. Same opaque-handle shape as Vec / String / HashMap.
//   * Neither read entry point hands back a pointer into the internal
//     buffer — `read_line` returns a fresh owned String, `read_line_into`
//     copies into a String the caller already owns. No view is
//     invalidated by the next call, so there is no lifetime foot-gun.
//
// API:
//   ( bufreader_open path )            → ! BufReader IoErr   open a file "rb"
//   ( bufreader_stdin )                → BufReader           wrap fd 0
//   ( bufreader_read_line br )         → ? String   owned line, '\n'/'\r\n'
//                                                     stripped; None at EOF
//   ( bufreader_read_line_into br dst ) → b         refill `dst` with the
//                                                     next line (cleared
//                                                     first); F at EOF.
//                                                     Reuse one `dst`
//                                                     across the loop for
//                                                     zero-allocation ETL.
//   ( bufreader_eof br )               → b          T once fully drained
//   ( bufreader_close br )             → v          free buffer + handle
//
// Example — count lines in a huge file without loading it. Note the
// loop shape: a `~` condition must be side-effect-free, so the read
// goes in the body and a flag drives the loop (the stdlib-wide idiom).
//   ?? ( bufreader_open `events.jsonl` ) {
//     T br → {
//       : String line ( string_new )
//       : ~ i n 0
//       : ~ b more T
//       ~ more {
//         ? ( bufreader_read_line_into br line ) { = n + n 1 } { = more F }
//       }
//       ( string_free line )
//       ( bufreader_close br )
//       ( nurl_print ( nurl_str_int n ) )
//     }
//     F e → ( nurl_eprintln `open failed` )
//   }

$ `stdlib/core/string.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/core/posix.nu`  // errno_kind

// ── libc bridges (pure-NURL FFI) ────────────────────────────────────
// fread is declared globally in nurlc's preamble (Phase 7, 2026-05-23);
// the local declaration has different pointer types so we keep this
// one for the *u pointer shape — actually wait, nope, fread is
// globally declared as (i8*, i64, i64, i8*) → i64; the per-file
// declaration with *u clashes with that. Drop the local one and
// adjust the call site to use the global shape.
& `c` @ memchr  *u hay i needle i n             → s
& `c` @ memmove *u dst *u src i n               → *u
& `c` @ fdopen  i fd s mode                     → *v

// Default read buffer: 64 KiB. Grows (×2) only for a line longer than
// the current buffer; never shrinks.
: i BUFIO_CAP 65536

// BufReader is an opaque handle over a 64-byte control block, mirroring
// the Vec / String / HashMap layout so it round-trips through `! T E`.
//
// Control block (8 × i64, via nurl_peek/poke):
//   word 0: file handle (FILE* as i64; 0 ⇒ no stream / degrade to EOF)
//   word 1: buffer pointer (i64)
//   word 2: buffer capacity (bytes)
//   word 3: start — index of first unconsumed byte
//   word 4: end   — index past last valid byte
//   word 5: eof   — 1 once the underlying stream is exhausted
//   word 6: owns  — 1 if `bufreader_close` should fclose the handle
//   word 7: scratch — start offset of the line last returned
: BufReader { s ctl }

// ── Internal ────────────────────────────────────────────────────────

// errno-kind → IoErr; order matches `nurl_errno_kind` (see fs.nu).
@ __bufio_err_of_kind i k → IoErr {
    ? == k 0 { ^ @ IoErr { NotFound } } {}
    ? == k 1 { ^ @ IoErr { PermissionDenied } } {}
    ? == k 2 { ^ @ IoErr { AlreadyExists } } {}
    ? == k 3 { ^ @ IoErr { Interrupted } } {}
    ? == k 4 { ^ @ IoErr { UnexpectedEof } } {}
    ? == k 5 { ^ @ IoErr { WriteFailed } } {}
    ? == k 6 { ^ @ IoErr { ReadFailed } } {}
    ^ @ IoErr { Other }
}

@ __bufreader_make * v h i owns → BufReader {
    : s ctl ( nurl_zalloc 64 )
    : s buf ( nurl_alloc BUFIO_CAP )
    ( nurl_poke ctl 0 # i h )
    ( nurl_poke ctl 1 # i buf )
    ( nurl_poke ctl 2 BUFIO_CAP )
    ( nurl_poke ctl 6 owns )
    ^ @ BufReader { ctl }
}

// Make room and pull one more chunk from the stream into [end, cap).
// Compacts live bytes to the front first, then grows the buffer if it
// is completely full. Sets the EOF flag when the stream yields nothing.
@ __bufreader_fill s ctl → v {
    : i handle ( nurl_peek ctl 0 )
    ? == handle 0 { ( nurl_poke ctl 5 1 ) } {
        : ~ i cap ( nurl_peek ctl 2 )
        : i start ( nurl_peek ctl 3 )
        : ~ i end ( nurl_peek ctl 4 )
        // Carry the buffer address as an i64 and cast per use — a
        // mutable ': ~ *u' binding miscompiles across realloc (GOTCHAS
        // item 10); this function reassigns it on grow.
        : ~ i bufa ( nurl_peek ctl 1 )
        // Compact: shift [start, end) down to offset 0.
        ? > start 0 {
            : i live - end start
            ? > live 0 {
                ( memmove # *u bufa # *u + bufa start live )
            } {}
            = end live
            ( nurl_poke ctl 3 0 )
            ( nurl_poke ctl 4 end )
        } {}
        // Grow when the buffer is full and compaction freed nothing.
        ? >= end cap {
            = cap * cap 2
            = bufa # i ( nurl_realloc # s bufa cap )
            ( nurl_poke ctl 1 bufa )
            ( nurl_poke ctl 2 cap )
        } {}
        : i want - cap end
        : i got ( fread # s + bufa end 1 want # s handle )
        ? > got 0 { ( nurl_poke ctl 4 + end got ) } { ( nurl_poke ctl 5 1 ) }
    }
}

// Absolute buffer index of the next '\n' in [start, end), or -1.
@ __bufreader_find_nl s ctl → i {
    : i start ( nurl_peek ctl 3 )
    : i end ( nurl_peek ctl 4 )
    : i n - end start
    ? <= n 0 { ^ -1 } {}
    : *u buf # *u ( nurl_peek ctl 1 )
    : s found ( memchr # *u + # i buf start 10 n )
    ? == 0 # i found { ^ -1 } {}
    ^ - # i found # i buf
}

// Consume the next line. Returns its length excluding the terminator
// (>= 0), or -1 at end of input. On success word 7 holds the line's
// start offset in the current buffer — valid only until the next call.
@ __bufreader_next_line s ctl → i {
    : ~ i result -2
    ~ == result -2 {
        : i nl ( __bufreader_find_nl ctl )
        ? >= nl 0 {
            : i start ( nurl_peek ctl 3 )
            : ~ i len - nl start
            : *u buf # *u ( nurl_peek ctl 1 )
            ? > len 0 {
                ? == # i . buf - nl 1 13 { = len - len 1 } {}
            } {}
            ( nurl_poke ctl 7 start )
            ( nurl_poke ctl 3 + nl 1 )
            = result len
        } {
            ? == 0 ( nurl_peek ctl 5 ) {
                ( __bufreader_fill ctl )
            } {
                // EOF: emit the trailing unterminated line, if any.
                : i start ( nurl_peek ctl 3 )
                : i end ( nurl_peek ctl 4 )
                ? > - end start 0 {
                    : ~ i len - end start
                    : *u buf # *u ( nurl_peek ctl 1 )
                    ? == # i . buf - end 1 13 { = len - len 1 } {}
                    ( nurl_poke ctl 7 start )
                    ( nurl_poke ctl 3 end )
                    = result len
                } { = result -1 }
            }
        }
    }
    ^ result
}

// ── Constructors ────────────────────────────────────────────────────

@ bufreader_open s path → !BufReader IoErr {
    : *v h ( nurl_file_open path `rb` )
    ? == 0 # i h {
        ^ @ !BufReader IoErr { F ( __bufio_err_of_kind ( errno_kind ) ) }
    } {}
    ^ @ !BufReader IoErr { T ( __bufreader_make h 1 ) }
}

// Wrap stdin (fd 0). If fdopen somehow fails the reader degrades to an
// immediately-empty stream rather than faulting.
@ bufreader_stdin → BufReader {
    : *v h ( fdopen 0 `rb` )
    : BufReader br ( __bufreader_make h 1 )
    ? == 0 # i h { ( nurl_poke . br ctl 5 1 ) } {}
    ^ br
}

// ── Reading ─────────────────────────────────────────────────────────

@ bufreader_read_line BufReader br → ?String {
    : s ctl . br ctl
    : i len ( __bufreader_next_line ctl )
    ? < len 0 { ^ @ ?String { F # String 0 } } {}
    : *u buf # *u ( nurl_peek ctl 1 )
    : i off ( nurl_peek ctl 7 )
    ^ @ ?String { T ( string_from_bytes # *u + # i buf off len ) }
}

// Replace `dst`'s contents with the next line (terminator stripped) and
// return T; return F at EOF leaving `dst` cleared. Reuse a single `dst`
// across the read loop — its buffer grows once and is then never
// reallocated, so the hot loop performs no per-line allocation.
@ bufreader_read_line_into BufReader br String dst → b {
    : s ctl . br ctl
    : i len ( __bufreader_next_line ctl )
    ( string_clear dst )
    ? < len 0 { ^ F } {}
    : *u buf # *u ( nurl_peek ctl 1 )
    : i off ( nurl_peek ctl 7 )
    ( string_push_bytes dst # *u + # i buf off len )
    ^ T
}

// ── Inspect / cleanup ───────────────────────────────────────────────

@ bufreader_eof BufReader br → b {
    : s ctl . br ctl
    ? == 0 ( nurl_peek ctl 5 ) { ^ F } {}
    ^ >= ( nurl_peek ctl 3 ) ( nurl_peek ctl 4 )
}

@ bufreader_close BufReader br → v {
    : s ctl . br ctl
    : i buf ( nurl_peek ctl 1 )
    ? != 0 buf { ( nurl_free # s buf ) } {}
    ? != 0 ( nurl_peek ctl 6 ) {
        : i h ( nurl_peek ctl 0 )
        ? != 0 h { ( nurl_file_close # *v h ) } {}
    } {}
    ( nurl_free ctl )
}
