### Fixed

- **A value a `dyn` method hands back out of an argument is that argument's** (Agora #800). Take `: String r ( name_of d 0 a )`, where every impl of `name_of` may hand back `. a name`, then `( string_push_str r … )`. Its caller's view of `. app name` outlived the growth (heap-use-after-free). The static call was refused already. The virtual callee's lend summaries are now known when the function's conditional summary edges are settled, so the growth is a change of the caller's argument there too.
