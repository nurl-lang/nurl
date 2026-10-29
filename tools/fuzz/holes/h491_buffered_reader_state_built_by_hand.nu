// H491: a `BufReaderImpl` literal of the program's own — `owns` 1 and a
// handle of 4096 — passed 4096 to fclose when it was dropped.
// Closed: BufReaderImpl is sealed (`raw :`).
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/std/bufio.nu`

@ main → i {
    : BufReaderImpl r @ BufReaderImpl { 4096 ( vec_new [u] ) 0 0 0 1 0 }
    ( nurl_println_int . r eof )
    ^ 0
}
