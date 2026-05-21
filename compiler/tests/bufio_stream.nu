// Test: stdlib/std/bufio.nu — streaming over an input far larger than
// the 64 KiB read buffer. Exercises the two hard paths:
//   * line splitting across chunk-refill boundaries (~1 MB / 64 KiB ≈
//     17 refills, with lines straddling the seams)
//   * buffer growth — one 200 000-byte line forces the buffer to grow
//     past its initial capacity
// A single reused String drives the whole read (zero-allocation loop).

$ `stdlib/std/bufio.nu`
$ `stdlib/std/fs.nu`

@ main → i {
    : s path `bufio_stress.txt`

    // Build ~1 MB: 50 000 variable-length lines + one oversized line.
    : String content ( string_with_cap 2000000 )
    : ~ i i 0
    ~ < i 50000 {
        ( string_push_str content `row_` )
        ( string_push_int content i )
        ( string_push_str content `_payload` )
        ( string_push_char content 10 )
        = i + i 1
    }
    : ~ i j 0
    ~ < j 200000 {
        ( string_push_char content 65 )
        = j + j 1
    }
    ( string_push_char content 10 )
    ( write_file path ( string_data content ) )
    ( string_free content )

    ?? ( bufreader_open path ) {
        T br → {
            : String line ( string_new )
            : ~ i nlines 0
            : ~ i total_bytes 0
            : ~ i maxlen 0
            : ~ b more T
            ~ more {
                ? ( bufreader_read_line_into br line ) {
                    : i ll ( string_len line )
                    = nlines + nlines 1
                    = total_bytes + total_bytes ll
                    ? > ll maxlen { = maxlen ll } {}
                } { = more F }
            }
            ( string_free line )
            ( bufreader_close br )
            ( nurl_print `lines=` )
            ( nurl_print ( nurl_str_int nlines ) )
            ( nurl_print ` maxlen=` )
            ( nurl_print ( nurl_str_int maxlen ) )
            ( nurl_print ` total_bytes=` )
            ( nurl_print ( nurl_str_int total_bytes ) )
            ( nurl_print `\n` )
        }
        F e → { ( nurl_print `open failed\n` ) }
    }

    ( file_delete path )
    ( nurl_print `done\n` )
    ^ 0
}
