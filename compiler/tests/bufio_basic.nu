// Test: stdlib/std/bufio.nu — buffered streaming line reader.
//
// Writes a fixture with mixed terminators (\r\n, \n), an empty line and
// a trailing line with no newline, then reads it back two ways:
//   1. bufreader_read_line     — fresh owned String per line
//   2. bufreader_read_line_into — one reused String, zero-alloc loop
// Confirms terminator stripping, the empty line, the unterminated last
// line, EOF, and that a missing file is rejected with an IoErr.

$ `stdlib/std/bufio.nu`
$ `stdlib/std/fs.nu`

@ main → i {
    : s path `bufio_fixture.txt`
    ( write_file path `alpha\r\nbeta\ngamma\n\nomega` )

    // ── Pass 1: owned-String lines ─────────────────────────────────
    ( nurl_print `owned:\n` )
    ?? ( bufreader_open path ) {
        T br → {
            : ~ b go T
            ~ go {
                ?? ( bufreader_read_line br ) {
                    T line → {
                        ( nurl_print `  [` )
                        ( nurl_print ( string_data line ) )
                        ( nurl_print `] len=` )
                        ( nurl_print ( nurl_str_int ( string_len line ) ) )
                        ( nurl_print `\n` )
                        ( string_free line )
                    }
                    F → { = go F }
                }
            }
            ( bufreader_close br )
        }
        F e → { ( nurl_print `open failed\n` ) }
    }

    // ── Pass 2: reused buffer (zero-alloc steady state) ────────────
    ( nurl_print `reused:\n` )
    ?? ( bufreader_open path ) {
        T br2 → {
            : String buf ( string_new )
            : ~ i count 0
            : ~ b more T
            ~ more {
                ? ( bufreader_read_line_into br2 buf ) {
                    ( nurl_print `  ` )
                    ( nurl_print ( string_data buf ) )
                    ( nurl_print `\n` )
                    = count + count 1
                } { = more F }
            }
            ( nurl_print `count=` )
            ( nurl_print ( nurl_str_int count ) )
            ( nurl_print ` eof=` )
            ( nurl_print ? ( bufreader_eof br2 ) `T` `F` )
            ( nurl_print `\n` )
            ( string_free buf )
            ( bufreader_close br2 )
        }
        F e → { ( nurl_print `open2 failed\n` ) }
    }

    // ── Missing file → IoErr ───────────────────────────────────────
    ?? ( bufreader_open `bufio_no_such_file.txt` ) {
        T br3 → { ( bufreader_close br3 ) ( nurl_print `unexpected open\n` ) }
        F e → { ( nurl_print `missing file rejected\n` ) }
    }

    ( file_delete path )
    ( nurl_print `done\n` )
    ^ 0
}
