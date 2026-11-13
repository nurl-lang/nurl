// raw_string_returned_owned_on_one_path_parameter_on_another_runs_clean: `@ pick b c s p → s { ? c { ^ p } {} : s t ( nurl_str_cat … ) ^ t }`
// Closed: a raw string returned on one path and a parameter on another is answered per call by its guard slot (already on main; agora #540's raw-string half).
// main 6e45ef9: ran clean (pinned).
// map: §7.6 | A2 | runs-clean | - | agora #540: a mixed raw-string return, bound
$ `stdlib/core/string.nu`

@ pick b c s p → s { ? c { ^ p } {} : s t ( nurl_str_cat `abc` `def and a longer tail for the heap buffer` ) ^ t }

@ main → i { : s a `lender` : s r ( pick F a ) : s q ( pick T a ) ( nurl_println r ) ( nurl_println q ) ^ 0 }
