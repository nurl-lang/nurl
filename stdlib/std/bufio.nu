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
//   * BufReader owns its buffer + file handle and is a library handle
//     (docs/MEMORY.md §7.6): every copy is the same reader, and the last
//     owner releases the buffer and closes the file it opened.
//     `bufreader_close` does that now (optional).
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
//   ( bufreader_read_line_raw br dst )  → b         the same, but VERBATIM:
//                                                     the line's own
//                                                     terminator is kept
//                                                     ('\n', '\r\n', or
//                                                     none at a final
//                                                     unterminated line),
//                                                     so writing every
//                                                     `dst` back out
//                                                     reproduces the input
//                                                     byte for byte. What a
//                                                     filter that must not
//                                                     rewrite line endings
//                                                     needs.
//   ( bufreader_eof br )               → b          T once fully drained
//   ( bufreader_close br )             → v          release now (optional)
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

$ `stdlib/core/marker.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/core/posix.nu`  // errno_kind
$ `stdlib/std/fs.nu`  // nurl_file_open / nurl_file_close
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

// ── libc bridges (pure-NURL FFI) ────────────────────────────────────
// fread is declared globally in nurlc's preamble (Phase 7, 2026-05-23);
// the local declaration has different pointer types so we keep this
// one for the *u pointer shape — actually wait, nope, fread is
// globally declared as (i8*, i64, i64, i8*) → i64; the per-file
// declaration with *u clashes with that. Drop the local one and
// adjust the call site to use the global shape.
& `c` @ memchr in *u hay i needle i n → s

& `c` @ memmove *u dst in *u src i n → *u

& `c` @ fdopen i fd s mode → *v

// Default read buffer: 64 KiB. Grows (×2) only for a line longer than
// the current buffer; never shrinks.
: i BUFIO_CAP 65536

// BufReader is a one-word handle on its state in an Arc, so it
// round-trips through `! T E`; every copy is the same reader, and the last
// owner releases the buffer and closes a file the reader opened
// (BufReaderImpl's drop).
//
//   h       — file handle (FILE* as i64; 0 ⇒ no stream / degrade to EOF)
//   buf     — the read buffer; its length is the capacity in use
//   start   — index of first unconsumed byte
//   end     — index past last valid byte
//   eof     — 1 once the underlying stream is exhausted
//   owns    — 1 if the reader closes the handle (it opened it)
//   scratch — start offset of the line last returned
// Sealed (`raw`): `h` is the FILE* its drop closes.
raw : BufReaderImpl { i h ( Vec u ) buf i start i end i eof i owns i scratch }

// The stream is the outside world's: closing a file the reader opened is
// its own drop, run by its last owner (the buffer goes with it).
% Drop BufReaderImpl {
    @ drop BufReaderImpl r → v {
        ? && != 0 . r owns != 0 . r h { ( nurl_file_close # *v . r h ) } {}
    }
}

: BufReader { ( Arc BufReaderImpl ) a }

// Its drop closes something the outside world sees (stdlib/core/marker.nu).
% Resource BufReader {}

@ BufReader_share BufReader h → BufReader { ^ @ BufReader { ( arc_clone [BufReaderImpl] . h a ) } }

@ BufReader_drop sink BufReader h → v {}

// The reader's state in place.
@ __br BufReader h → *BufReaderImpl { ^ ( arc_ptr [BufReaderImpl] . h a ) }

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
    ^ @ BufReader { ( arc_new [BufReaderImpl] @ BufReaderImpl { # i h ( vec_zeroed [u] BUFIO_CAP ) 0 0 0 owns 0 } ) }
}

// Make room and pull one more chunk from the stream into [end, cap).
// Compacts live bytes to the front first, then grows the buffer if it
// is completely full. Sets the EOF flag when the stream yields nothing.
@ __bufreader_fill * BufReaderImpl r → v {
    ? == . r h 0 { = . r eof 1 } {
        : ~ i cap ( vec_len [u] . r buf )
        : i start . r start
        : ~ i end . r end
        // Compact: shift [start, end) down to offset 0.
        ? > start 0 {
            : i live - end start
            : *u b ( vec_data [u] . r buf )
            ? > live 0 {
                : *u _m ( memmove b # *u + # i b start live )
            } {}
            = end live
            = . r start 0
            = . r end end
        } {}
        // Grow when the buffer is full and compaction freed nothing.
        ? >= end cap {
            = cap * cap 2
            : b _g ( vec_resize_zeroed [u] . r buf cap )
        } {}
        // The data pointer is read after any grow.
        : *u b ( vec_data [u] . r buf )
        : i want - cap end
        : i got ( fread # s + # i b end 1 want # s . r h )
        ? > got 0 { = . r end + end got } { = . r eof 1 }
    }
}

// Absolute buffer index of the next '\n' in [start, end), or -1.
@ __bufreader_find_nl * BufReaderImpl r → i {
    : i start . r start
    : i n - . r end start
    ? <= n 0 { ^ -1 } {}
    : *u buf ( vec_data [u] . r buf )
    : s found ( memchr # *u + # i buf start 10 n )
    ? == 0 # i found { ^ -1 } {}
    ^ - # i found # i buf
}

// Consume the next line. Returns its length excluding the terminator
// (>= 0), or -1 at end of input. On success `scratch` holds the line's
// start offset in the current buffer — valid only until the next call.
@ __bufreader_next_line * BufReaderImpl r → i {
    : ~ i result -2
    ~ == result -2 {
        : i nl ( __bufreader_find_nl r )
        ? >= nl 0 {
            : i start . r start
            : ~ i len - nl start
            : *u buf ( vec_data [u] . r buf )
            ? > len 0 {
                ? == # i . buf - nl 1 13 { = len - len 1 } {}
            } {}
            = . r scratch start
            = . r start + nl 1
            = result len
        } {
            ? == 0 . r eof {
                ( __bufreader_fill r )
            } {
                // EOF: emit the trailing unterminated line, if any.
                : i start . r start
                : i end . r end
                ? > - end start 0 {
                    : ~ i len - end start
                    : *u buf ( vec_data [u] . r buf )
                    ? == # i . buf - end 1 13 { = len - len 1 } {}
                    = . r scratch start
                    = . r start end
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
    ? == 0 # i h {
        : *BufReaderImpl r ( __br br )
        = . r eof 1
    } {}
    ^ br
}

// ── Reading ─────────────────────────────────────────────────────────

@ bufreader_read_line BufReader br → ?String {
    : *BufReaderImpl r ( __br br )
    : i len ( __bufreader_next_line r )
    ? < len 0 { ^ @ ?String { F # String 0 } } {}
    : *u buf ( vec_data [u] . r buf )
    ^ @ ?String { T ( string_from_bytes # *u + # i buf . r scratch len ) }
}

// Replace `dst`'s contents with the next line (terminator stripped) and
// return T; return F at EOF leaving `dst` cleared. Reuse a single `dst`
// across the read loop — its buffer grows once and is then never
// reallocated, so the hot loop performs no per-line allocation.
@ bufreader_read_line_into BufReader br String dst → b {
    : *BufReaderImpl r ( __br br )
    : i len ( __bufreader_next_line r )
    ( string_clear dst )
    ? < len 0 { ^ F } {}
    : *u buf ( vec_data [u] . r buf )
    ( string_push_bytes dst # *u + # i buf . r scratch len )
    ^ T
}

// Byte-exact twin of `bufreader_read_line_into`: `dst` receives the line
// AND the terminator the input actually carried — `\n`, `\r\n`, or
// nothing at all for a final unterminated line. Concatenating every
// `dst` reproduces the stream exactly, which is the difference between a
// filter (`head`, `grep`, `sed`) that preserves a CRLF file and one that
// silently rewrites it to LF and drops or adds a trailing newline.
//
// The stripped form is the right default for parsing; this one is the
// right default for copying. Same zero-allocation loop shape — reuse one
// `dst`.
@ bufreader_read_line_raw BufReader br String dst → b {
    : *BufReaderImpl r ( __br br )
    : i len ( __bufreader_next_line r )
    ( string_clear dst )
    ? < len 0 { ^ F } {}
    : *u buf ( vec_data [u] . r buf )
    : i off . r scratch
    // `start` is the next unconsumed byte, so the span [off, start) is
    // the line plus whatever terminated it.
    : i raw - . r start off
    ( string_push_bytes dst # *u + # i buf off raw )
    ^ T
}

// ── Inspect / cleanup ───────────────────────────────────────────────

@ bufreader_eof BufReader br → b {
    : *BufReaderImpl r ( __br br )
    ? == 0 . r eof { ^ F } {}
    ^ >= . r start . r end
}

// Release the buffer and close the file now (optional: the last owner
// does it). Every copy of `br` sees an exhausted reader afterwards.
@ bufreader_close BufReader br → v {
    : ( Arc BufReaderImpl ) a . br a
    ? == 0 # i . a ctl { ^ } {}
    : *BufReaderImpl r ( __br br )
    = . r buf ( vec_new [u] )
    ? && != 0 . r owns != 0 . r h { ( nurl_file_close # *v . r h ) } {}
    = . r h 0
    = . r start 0
    = . r end 0
    = . r eof 1
}
