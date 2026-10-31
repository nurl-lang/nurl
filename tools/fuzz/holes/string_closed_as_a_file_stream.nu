// string_closed_as_a_file_stream: safe code closed a string literal as a C stream: file_from_raw (stdlib/std/fs.nu) took any 's' as a FILE*, and the File it made fclose'd it when it went; file_raw handed a File's stream out the same way, as text.
// Closed: file_raw / file_from_raw are `unsafe` only; a program opens a File (file_open, file_create) and asks file_is_open.
// main's compiler: SIGSEGV in fclose.
// map: §6.4 | B | rejected | h256 | string literal taken as FILE* by file_from_raw and fclose'd
$ `stdlib/std/fs.nu`

@ main → i {
    : File f ( file_from_raw `not a FILE` )
    ( file_close f )
    ( nurl_println `survived` )
    ^ 0
}
