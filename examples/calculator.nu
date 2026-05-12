// calculator.nu — Simple expression evaluator with enums and pattern matching
//
// Demonstrates:
//   - Enum types with payloads (: | Name { ... })
//   - Pattern matching (?? expr { ... })
//   - Option type (?T) for error handling
//   - Recursion
//   - Heap allocation and pointers
//
// Build & run:
//   ./build/nurlc examples/calculator.nu > /tmp/calc.ll
//   clang /tmp/calc.ll stdlib/runtime.o -o /tmp/calc
//   /tmp/calc

// AST for arithmetic expressions
: | Expr {
    Num i
    Add *Expr *Expr
    Sub *Expr *Expr
    Mul *Expr *Expr
    Div *Expr *Expr
}

// Allocate an Expr on the heap
@ box Expr e → *Expr {
    : *Expr p # *Expr ( malloc Z Expr )
    = . p 0 e
    ^ p
}

// Evaluate an expression, returning None on division by zero
@ eval *Expr e → ?i {
    ?? . e 0 {
        Num n → @ ?i { T n }

        Add l r → {
            : i a1 \ ( eval l )
            : i b1 \ ( eval r )
            ^ @ ?i { T + a1 b1 }
        }

        Sub l r → {
            : i a2 \ ( eval l )
            : i b2 \ ( eval r )
            ^ @ ?i { T - a2 b2 }
        }

        Mul l r → {
            : i a3 \ ( eval l )
            : i b3 \ ( eval r )
            ^ @ ?i { T * a3 b3 }
        }

        Div l r → {
            : i dividend \ ( eval l )
            : i divisor \ ( eval r )
            ? == divisor 0
                @ ?i { F 0 }
                @ ?i { T / dividend divisor }
        }
    }
}

// Print result or error
@ print_result ?i result → v {
    ?? result {
        T val → {
            ( nurl_print `Result: ` )
            ( nurl_print ( nurl_str_int val ) )
            ( nurl_print `\n` )
        }
        F → ( nurl_print `Error: division by zero\n` )
    }
}

@ main → i {
    ( nurl_print `Calculator example\n\n` )

    // Build: (10 + 5) * 2 = 30
    : *Expr ten   ( box @ Expr { Num 10 } )
    : *Expr five  ( box @ Expr { Num 5 } )
    : *Expr two   ( box @ Expr { Num 2 } )
    : *Expr sum   ( box @ Expr { Add ten five } )
    : *Expr expr1 ( box @ Expr { Mul sum two } )

    ( nurl_print `(10 + 5) * 2 = ` )
    ( print_result ( eval expr1 ) )

    // Build: 100 / (5 - 5) = error
    : *Expr h     ( box @ Expr { Num 100 } )
    : *Expr f1    ( box @ Expr { Num 5 } )
    : *Expr f2    ( box @ Expr { Num 5 } )
    : *Expr zero  ( box @ Expr { Sub f1 f2 } )
    : *Expr expr2 ( box @ Expr { Div h zero } )

    ( nurl_print `100 / (5 - 5) = ` )
    ( print_result ( eval expr2 ) )

    // Build: (8 - 3) * (4 + 2) = 30
    : *Expr e8  ( box @ Expr { Num 8 } )
    : *Expr e3  ( box @ Expr { Num 3 } )
    : *Expr e4  ( box @ Expr { Num 4 } )
    : *Expr e2  ( box @ Expr { Num 2 } )
    : *Expr lhs ( box @ Expr { Sub e8 e3 } )
    : *Expr rhs ( box @ Expr { Add e4 e2 } )
    : *Expr expr3 ( box @ Expr { Mul lhs rhs } )

    ( nurl_print `(8 - 3) * (4 + 2) = ` )
    ( print_result ( eval expr3 ) )

    ^ 0
}
