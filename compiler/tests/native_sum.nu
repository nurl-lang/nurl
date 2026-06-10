// Ensimmäinen natiivisti käännetty NURL-ohjelma.
// Laskee summan 1..10 = 55 ja palauttaa sen exit-koodina.
//
// Käännös:
//   python nurlc.py --llvm tests/native_sum.nu > /tmp/sum.ll
//   clang /tmp/sum.ll -o /tmp/sum
//   /tmp/sum ; echo $?   # → 55

@ sumto i n → i {
    : ~ i acc 0
    : ~ i k 1
    ~ <= k n {
        = acc + acc k
        = k + k 1
    }
    ^ acc
}

@ fib i n → i {
    ? <= n 1
    n
    + ( fib - n 1 ) ( fib - n 2 )
}

@ main → i {
    // sumto(10) = 55, fib(10) = 55 — molemmat antavat 55
    ^ ( sumto 10 )
}
