### Fixed

- **A callee growing a field of its struct parameter through a local ends the caller's view of that field** (Agora #647). Given `@ ext App a → v { : String nm . a name ( string_push_str nm … ) }`, a caller's `( string_data . app name )` outlived `( ext app )` and read the moved buffer. The same happened when the caller bound the field first (`: String held . app name`), when the field was nested (`. . out inner name`), when the callee read it through an accessor (`( nameof a )`, `. ( innerof o ) name`) or a forwarder, and for a slice of, or a `~` loop over, a Vec field the callee grew. Only the direct spelling `( string_push_str . a name … )` was refused before.

  A callee that grows only what is inside an element of a container in its parameter, such as `( vec_reserve ( vec_at . p rows 0 ) 4096 )`, a local bound to such an element, or a `~` loop's element, still leaves views of the argument's own fields valid. A loop over `. w rows` calling it stays accepted. A `: ~` local holding an element counts as possibly holding a field too, since it may be given one later, or round a loop before the grow.

### Known issues

- The answer is per parameter, not per field: a helper appending to one field of its struct parameter through a local ends the caller's views of the struct's other fields, and a `~` loop over another field. This is the rule a direct `( string_push_str . p out … )` in the helper already followed (Agora #401). A closure body that grows a field or an element read out of a parameter is not seen yet (Agora #797).
