// wordcount.nu — Count lines, words, and characters in a file
//
// Demonstrates:
//   - File I/O (nurl_read_file)
//   - String iteration with while loop
//   - Character classification (is_space, from stdlib/core/char.nu)
//   - Structs and field access
//
// Build & run:
//   ./build/nurlc examples/wordcount.nu > /tmp/wc.ll
//   clang /tmp/wc.ll stdlib/runtime.o -o /tmp/wc
//   /tmp/wc examples/wordcount.nu

// nurl_str_len comes from core/string; the measured byte view the scan
// reads (slice_of_str / slice_byte) from core/slice.
$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`

: Stats {
    i lines
    i words
    i chars
}

@ count_stats s text → Stats {
    : ( Slice u ) text_v ( slice_of_str text )
    : i len ( nurl_str_len text )
    : ~ i lines 0
    : ~ i words 0
    : ~ i chars len
    : ~ b in_word F

    : ~ i idx 0
    ~ < idx len {
        : i ch ( slice_byte text_v idx )

        // Newline
        ? == ch 10 {
            = lines + lines 1
            = in_word F
        } {
            // Space, tab, carriage return
            ? | == ch 32 | == ch 9 == ch 13 {
                = in_word F
            } {
                // Start of new word
                ? ! in_word {
                    = words + words 1
                    = in_word T
                } {}
            }
        }

        = idx + idx 1
    }

    // Count last line if no trailing newline
    ? & > len 0 != ( slice_byte text_v - len 1 ) 10 {
        = lines + lines 1
    } {}

    ^ @ Stats { lines words chars }
}

@ print_stats Stats st s filename → v {
    ( nurl_print `  ` ) ( nurl_print_int . st lines )
    ( nurl_print `  ` ) ( nurl_print_int . st words )
    ( nurl_print `  ` ) ( nurl_print_int . st chars )
    ( nurl_print `  ` ) ( nurl_print filename )
    ( nurl_print `\n` )
}

@ main → i {
    : i argc ( nurl_argv_count )

    ? < argc 2 {
        ( nurl_print `Usage: wc <file>\n` )
        ^ 1
    } {}

    : s filename ( nurl_argv_get 1 )
    : s content ( nurl_read_file filename )

    : Stats st ( count_stats content )
    ( print_stats st filename )

    ^ 0
}
