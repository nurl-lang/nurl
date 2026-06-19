# NURL quick reference (enough to write a correct program)

NURL is a small systems language with a **regular prefix-arity grammar**:
every operator has a fixed number of arguments and is written *before* them.
There is **no infix** and **no operator precedence** — you never need
parentheses for grouping, only for function calls.

## Program shape

```
// line comment

@ main → i {
    ( nurl_print_int 42 )   // prints an i64 followed by a newline
    ^ 0                     // main returns i (0 = success)
}
```

- Functions: `@ name TYPE1 p1 TYPE2 p2 → RET { body }`. Parameter list is
  `type name` pairs; `→ RET` gives the return type. A no-arg function is
  `@ name → RET { ... }`.
- `^ expr` returns a value. **Void functions (`→ v`) must not use `^` at all**
  — they just fall off the end. For an "early return" in a void function,
  wrap the work in a positive `? cond { ... } {}` instead.

## Types

`i` = i64, `u` = byte/u8, `f` = f64, plus sized `i8 i16 i32 u16 u32 u64 f32`.
`b` = bool (literals `T` / `F`). `s` = raw C string. Pointers: `*i` (pointer
to i64), `*u` (pointer to byte), etc.

## Bindings and assignment

A plain `:` binding is **immutable** — you cannot reassign it. To reassign a
variable you must declare it mutable with `: ~`. This is the single most common
mistake: write `: ~` for anything you will later change with `=`.

```
: i x 10        // immutable binding:  : TYPE name value   (cannot be reassigned)
: ~ i y 0       // MUTABLE binding:    : ~ TYPE name value
= y + y 1       // reassign a mutable: = name value
```

**Function parameters are immutable too.** You cannot write `= n ...` to mutate
a parameter `n`. Copy it into a `: ~` local first and mutate that:

```
@ sum_below i n → i {
    : ~ i total 0      // mutable accumulator
    : ~ i k 0          // mutable loop counter
    ~ < k n {          // n (a parameter) is read-only; never `= n ...`
        = total + total k
        = k + k 1
    }
    ^ total
}
```

## Operators are all prefix, fixed-arity (no infix!)

```
+ a b   - a b   * a b   / a b   % a b      // arithmetic (integer / float)
< a b   > a b   <= a b  >= a b  == a b  != a b   // comparisons → bool
& a b   | a b                              // bitwise on ints, logical AND/OR on bools
^^ a b                                     // XOR     << a b   >> a b   // shifts
```

Nested expressions just chain: `i*N + j` is `+ * i N j`; `(a-b)+c` is
`+ - a b c`. `a[j] < pivot` is `< . a j pivot` (see pointers below).

## Control flow

```
? cond { then-block } { else-block }    // if/else — BOTH braces required; use {} for empty
~ cond { body }                         // while loop
```

Example loop:
```
: ~ i k 0
~ < k 100 {
    = k + k 1
}
```

## Function calls

`( fn arg1 arg2 )` — parentheses mean *call*, never grouping.
```
^ + ( fib - n 1 ) ( fib - n 2 )
```

## Printing

- `( nurl_print_int n )` — print an i64 then a newline.
- `( nurl_print s )` — print a raw string, no newline.

## Pointers / flat arrays

Allocate raw memory with the libc FFI and index it with `.`:
```
: *i a # *i ( malloc * N 8 )   // N i64 slots; # *i casts the void* to *i
= . a idx val                  // STORE: = . ptr index value
: i v . a idx                  // LOAD:  . ptr index
( free a )
```

## Casts

`# TYPE expr` converts: `# f x` (int→f64), `# i x` (→i64), `# u x` (→byte).

## Strings (need an import)

```
$ `stdlib/core/string.nu`           // imports go at the top, before use
: s text `hello world`              // string literal uses BACKTICKS
: i n ( nurl_str_len text )         // length
: i c ( nurl_str_get text i )       // byte at index i, as an i
```

## Declaring a C/libc function (FFI)

```
& `c` @ malloc i n → *u
& `c` @ free *u p → v
```

## Complete worked example

```
// recursive Fibonacci(35) -> 9227465
@ fib i n → i {
    ? < n 2 { ^ n } {}
    ^ + ( fib - n 1 ) ( fib - n 2 )
}

@ main → i {
    ( nurl_print_int ( fib 35 ) )
    ^ 0
}
```

Common mistakes to avoid: reassigning with `=` something declared with a plain
`:` or a function parameter (both immutable — declare a `: ~` local instead);
using infix (`n - 1` instead of `- n 1`); using `^ 0` in a `→ v` function;
forgetting that both `?` branches need braces; calling a stdlib function (e.g.
`nurl_str_len`) without its `$` import.
