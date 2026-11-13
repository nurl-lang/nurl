// slice_from_a_callee_compiled_after_its_caller_runs_clean: a slice from a function defined below its caller (fresh on every path, or per call), and from a generic instance, is the caller's by the callee's module-end answer; a parameter's field handed back stays lent
// main: the caller took each for a lend and nobody released it (leak).
// map: §7.6 | A2 | runs-clean | - | agora #510: a slice from a callee compiled after its caller is owned by the callee's module-end answer, per call where it answers per call
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → [i { ^ [i | 1 2] }

@ sum [i a → i { : ~ i t 0 ~ x a { = t + t x } ^ t }

: Box { [i v }

: Holder { [i v i n }

: Outer { Box b i k }

@ main → i {
    : [i a [i | 7 8]
    : Holder h @ Holder { [i | 1 2] 3 }
    : [i b ( below )
    : [i c ( either T a )
    : [i d ( either F a )
    : [i e ( gmk [i] 5 6 )
    : [i f ( fld h )
    ( nurl_println_int + + + + + + ( sum a ) ( sum b ) ( sum c ) ( sum d ) ( sum e ) ( sum f ) ( sum . h v ) )
    ^ 0
}

@ below → [i { : [i s [i | 1 2 3] ^ s }

@ either b c [i p → [i { ? c { ^ p } {} ^ [i | 1 2 3] }

@ gmk [T] T a T b → [T { : [T s [T | a b] ^ s }

@ fld Holder p → [i { ^ . p v }
