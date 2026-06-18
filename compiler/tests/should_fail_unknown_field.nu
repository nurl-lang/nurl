// should_fail_unknown_field.nu — accessing a field a struct does not have
// used to silently read field 0 (a miscompile) or emit a malformed index.
: P { i x  i y }
@ main → i { : P p @ P { 1 2 }  : i z . p nope  ^ 0 }
