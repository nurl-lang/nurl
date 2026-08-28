# NURL quick reference (enough to write a correct program)

NURL is a small systems language with a **regular prefix-arity grammar**:
every operator has a fixed number of arguments and is written *before* them.
There is **no infix** and **no operator precedence** — you never need
parentheses for grouping, only for function calls.

## ⚠️ stdlib functions need a `$` import (the #1 first-try failure)

NURL has **no automatic prelude.** Any program that calls a stdlib function —
above all the string functions `nurl_str_len` and `nurl_str_get` — **must**
declare the matching import as the first line, or it will not compile:

```
$ `stdlib/core/string.nu`     // REQUIRED before any nurl_str_* call
```

`nurl_println_int`, `nurl_print`, and the arithmetic / pointer operators are
built in and need no import. `nurl_str_*` and other stdlib helpers **do** — if
you call one, the matching `$` import must be at the top of the file.

## Program shape

```
// line comment

@ main → i {
    ( nurl_println_int 42 )   // prints an i64 followed by a newline
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
variable you must declare it mutable with `: ~`. This is a common mistake:
write `: ~` for anything you will later change with `=`.

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

The rule: `print` = no newline, `println` = newline; `_int` is the integer form.

- `( nurl_print s )` / `( nurl_println s )` — print a raw string.
- `( nurl_print_int n )` / `( nurl_println_int n )` — print an i64.

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

## Strings — require the `$` import (see the top of this page)

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

## Complete worked example — note the import on line 1

This program calls `nurl_str_*`, so it opens with the `$` import. Copy this
shape whenever you touch a string:

```
$ `stdlib/core/string.nu`              // REQUIRED: this program calls nurl_str_*

@ main → i {
    : s text `count the spaces in here`
    : i n ( nurl_str_len text )
    : ~ i spaces 0
    : ~ i i 0
    ~ < i n {
        ? == ( nurl_str_get text i ) 32 { = spaces + spaces 1 } {}
        = i + i 1
    }
    ( nurl_println_int spaces )
    ^ 0
}
```

Common mistakes to avoid: **calling a stdlib function (e.g. `nurl_str_len` /
`nurl_str_get`) without its `$ \`stdlib/core/string.nu\`` import** — the single
most common first-try error; reassigning with `=` something declared with a
plain `:` or a function parameter (both immutable — declare a `: ~` local
instead); using infix (`n - 1` instead of `- n 1`); using `^ 0` in a `→ v`
function; forgetting that both `?` branches need braces.
