// fizzbuzz.nu — Classic FizzBuzz in NURL
//
// Demonstrates:
//   - Functions with prefix notation
//   - Conditionals (? cond then else)
//   - While loops (~ cond { body })
//   - Mutable variables (: ~ type name value)
//   - String operations
//
// Build & run:
//   ./nurl.sh examples/fizzbuzz.nu fizzbuzz && ./fizzbuzz
// Or manually (link the plain-ELF runtime, not the LTO-bitcode runtime.o):
//   ./build/nurlc examples/fizzbuzz.nu > /tmp/fizzbuzz.ll
//   clang /tmp/fizzbuzz.ll stdlib/runtime.native.o -lm -lpthread -o /tmp/fizzbuzz
//   /tmp/fizzbuzz

@ fizzbuzz i n → v {
    : ~ i i 1
    ~ <= i n {
        : b div3 == 0 % i 3
        : b div5 == 0 % i 5

        ? & div3 div5
        { ( nurl_print `FizzBuzz\n` ) }
        ? div3
        { ( nurl_print `Fizz\n` ) }
        ? div5
        { ( nurl_print `Buzz\n` ) }
        // nurl_str_cat lives in stdlib/core/string.nu — call without
        // importing it would emit `@nurl_str_cat` without a `declare`
        // and fail at link. Use the runtime's nurl_print_int instead.
        { ( nurl_print_int i ) ( nurl_print `\n` ) }

        = i + i 1
    }
}

@ main → i {
    ( fizzbuzz 30 )
    ^ 0
}
