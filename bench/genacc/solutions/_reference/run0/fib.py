#!/usr/bin/env python3
# fib — recursive Fibonacci(35). Output: 9227465.
def fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)


print(fib(35))
