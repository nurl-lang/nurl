// diag_foreach_not_iterable.nu — a foreach over something that is neither
// a slice nor a Vec. The element type was taken by slicing fixed offsets
// out of the `{ T*, i64 }` carrier shape; on an `i64` that yields an EMPTY
// type, and the loop emitted `alloca `, `getelementptr , `, `load , ` and
// an `extractvalue` on a non-aggregate. Invalid IR, with nothing on stderr
// at all: clang reported "expected type" at a line number in generated
// text, which is no report at all.

@ main → i {
    : ~ i k 0
    ~ e k { = k 1 }
    ^ 0
}
