/* Differential: nolibc's %f/%e/%g against glibc's, over random doubles
 * and every precision that matters. Any difference is a nolibc bug —
 * these conversions have one right answer. */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>
extern int nl_format_double(char *out, double v, char conv, int prec, int alt);
static uint64_t xs(uint64_t*s){uint64_t x=*s;x^=x<<13;x^=x>>7;x^=x<<17;return *s=x;}
static long long checked=0, bad=0;

static void one(double v, char conv, int prec) {
    char mine[1200], want[1200], fmt[16];
    int n = nl_format_double(mine, v, conv, prec, 0);
    mine[n] = 0;
    snprintf(fmt, sizeof fmt, "%%.%d%c", prec, conv);
    snprintf(want, sizeof want, fmt, v);
    checked++;
    if (strcmp(mine, want) != 0) {
        if (bad < 12) {
            uint64_t b; memcpy(&b, &v, 8);
            fprintf(stderr, "MISMATCH %%.%d%c of %.17g (%016llx)\n  glibc: %s\n  nolibc: %s\n",
                    prec, conv, v, (unsigned long long)b, want, mine);
        }
        bad++;
    }
}

int main(int argc, char **argv) {
    long long n = argc > 1 ? atoll(argv[1]) : 200000;
    uint64_t s = argc > 2 ? (uint64_t)atoll(argv[2]) : 99;
    const char convs[3] = {'f','e','g'};
    /* systematic first: the values a formatter gets wrong */
    double fixed[] = {0.0, -0.0, 1.0, -1.0, 0.1, 0.5, 1.5, 2.5, 3.5, 0.3,
        1e-5, 1e-4, 123456.0, 999999.5, 9999995.0, 0.000123456789,
        1e22, 1e23, 5e-324, 2.2250738585072014e-308, 1.7976931348623157e308,
        3.141592653589793, 1.0/3.0, 2.0/3.0, 1e100, 1e-100, 0.0625, 1024.0};
    for (unsigned i = 0; i < sizeof fixed / sizeof *fixed; i++)
        for (int c = 0; c < 3; c++)
            for (int p = 0; p <= 20; p++) one(fixed[i], convs[c], p);
    for (long long i = 0; i < n; i++) {
        uint64_t b = xs(&s);
        double v; memcpy(&v, &b, 8);
        if (isnan(v) || isinf(v)) continue;
        /* full-range doubles, and "data-shaped" ones */
        one(v, convs[i % 3], (int)(xs(&s) % 18));
        one(fmod(v, 1e6), convs[(i + 1) % 3], (int)(xs(&s) % 12));
    }
    printf("checked %lld, mismatches %lld\n", checked, bad);
    return bad ? 1 : 0;
}
