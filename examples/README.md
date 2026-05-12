# NURL Examples

Practical examples demonstrating NURL language features.

## Building Examples

```bash
# Build the compiler first (if not already built)
./build.sh

# Compile and run an example
./nurl.sh examples/fizzbuzz.nu

# Or compile manually
./build/nurlc examples/fizzbuzz.nu > /tmp/fizzbuzz.ll
clang /tmp/fizzbuzz.ll stdlib/runtime.o -o /tmp/fizzbuzz
/tmp/fizzbuzz
```

## Examples

### `fizzbuzz.nu`
Classic FizzBuzz — demonstrates loops, conditionals, and mutable variables.

### `wordcount.nu`
Count lines, words, and characters in a file — demonstrates file I/O, structs, and command-line arguments.

### `calculator.nu`
Expression evaluator with AST — demonstrates enums, pattern matching, Option types, recursion, and heap allocation.

## Language Features Demonstrated

| Feature | fizzbuzz | wordcount | calculator |
|---------|----------|-----------|------------|
| Functions (`@`) | ✓ | ✓ | ✓ |
| Conditionals (`?`) | ✓ | ✓ | ✓ |
| While loops (`~`) | ✓ | ✓ | |
| Mutable vars (`~ type`) | ✓ | ✓ | |
| Structs (`: Name {}`) | | ✓ | |
| Enums (`: \| Name {}`) | | | ✓ |
| Pattern match (`??`) | | | ✓ |
| Option type (`?T`) | | | ✓ |
| Try operator (`\`) | | | ✓ |
| Pointers (`*T`) | | | ✓ |
| File I/O | | ✓ | |
| CLI args | | ✓ | |
