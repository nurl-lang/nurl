### Fixed

- **A value block whose tail call may lend a temporary or a block local is copied once** (Agora #822). `: String g { : String s … ( pick ( string_concat … ) s ) }` leaked a String per run: the call already copied its result where it lent, and the block copied it again over that copy. The block now copies only where the call did not.
