// diag_raw_file_stream.nu — file_from_raw takes any string as a C stream
// and closes it when its File goes: only unsafe code may call it.

$ `stdlib/std/fs.nu`

@ main → i {
    : File f ( file_from_raw `x` )
    ^ 0
}
