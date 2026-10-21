// diag_supertrait_missing_import.nu — a missing supertrait impl, reported
// where the impl is: file, line AND column of its `%`, the echoed line
// and a caret, like every other diagnostic.
//
// The obligation is checked once every impl in the program is registered,
// after the impl's file was lexed, so the report used to be
// `file:2: error: …` — no column, no echo, no caret. The impl lives in an
// imported module here, below other declarations: the location names the
// module and its line, not the importer, and the echo is the module's
// line — re-read from the source the compilation used.
$ `compiler/tests/diag_supertrait_missing_import_mod.nu`

% Eq [T] { @ eq T a T b → b }

% Ord [T] : Eq { @ cmp T a T b → i }

@ main → i { ^ 0 }
