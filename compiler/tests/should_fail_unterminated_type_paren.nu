// should_fail_unterminated_type_paren.nu — an unterminated type application
// `( Name …` (reachable in any type position) used to spin parse_type_paren
// on a no-op advance at EOF.
: S { ( Vec i
