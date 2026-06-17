// should_fail_unterminated_enum.nu — an unterminated enum body must error,
// not hang. The enum-variant loop used to spin on a no-op advance at EOF.
: | Event { Click i
