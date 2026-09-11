// diag_const_missing_name.nu — ':' followed by a name and then neither a
// body nor a name/value pair. A struct declaration whose '{ … }' body is
// missing lands here, so the diagnostic offers both readings.

: Point

@ main → i {
    : Point p @ Point { 1 2 }
    ^ . p x
}
