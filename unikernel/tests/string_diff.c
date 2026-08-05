/* nolibc's mem and str functions against glibc's, in one process: the nolibc copies
 * are compiled with their names redefined, so both are callable and any
 * disagreement is a nolibc bug. Alignments and lengths are swept, not
 * sampled, because that is where a word-at-a-time loop goes wrong. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
typedef unsigned long nl_size_t;
void *nl_memcpy(void*,const void*,nl_size_t);
void *nl_memmove(void*,const void*,nl_size_t);
void *nl_memset(void*,int,nl_size_t);
void *nl_memchr(const void*,int,nl_size_t);
int   nl_memcmp(const void*,const void*,nl_size_t);
nl_size_t nl_strlen(const char*);
int   nl_strcmp(const char*,const char*);
char *nl_strchr(const char*,int);
char *nl_strrchr(const char*,int);
int   nl_strncmp(const char*,const char*,nl_size_t);
void *nl_memmem(const void*,nl_size_t,const void*,nl_size_t);
char *nl_strstr(const char*,const char*);
char *nl_strncpy(char*,const char*,nl_size_t);
long long nl_atoll(const char*);

static long bad = 0, checked = 0;
#define CHECK(cond, ...) do { checked++; if (!(cond)) { if (bad<10) fprintf(stderr, __VA_ARGS__); bad++; } } while (0)
static int sgn(int x){ return x<0?-1:(x>0?1:0); }

int main(void) {
    static unsigned char a[4096], b[4096], c[4096], d[4096];
    for (unsigned i = 0; i < sizeof a; i++) a[i] = (unsigned char)(i*7+3);

    for (int off1 = 0; off1 < 24; off1++)
    for (int off2 = 0; off2 < 24; off2++)
    for (int len = 0; len <= 200; len++) {
        memset(b, 0xAA, sizeof b); memset(c, 0xAA, sizeof c);
        memcpy(b+off1, a+off2, len); nl_memcpy(c+off1, a+off2, len);
        CHECK(memcmp(b,c,sizeof b)==0, "memcpy off %d/%d len %d\n", off1, off2, len);

        memset(b, 0x55, sizeof b); memset(c, 0x55, sizeof c);
        memset(b+off1, 0x3C, len); nl_memset(c+off1, 0x3C, len);
        CHECK(memcmp(b,c,sizeof b)==0, "memset off %d len %d\n", off1, len);

        /* overlapping moves, both directions */
        memcpy(b, a, sizeof b); memcpy(c, a, sizeof c);
        memmove(b+off1, b+off2, len); nl_memmove(c+off1, c+off2, len);
        CHECK(memcmp(b,c,sizeof b)==0, "memmove off %d/%d len %d\n", off1, off2, len);

        CHECK(memchr(a+off2, a[off2+len/2], len) == nl_memchr(a+off2, a[off2+len/2], len),
              "memchr off %d len %d\n", off2, len);
        memcpy(d, a, sizeof d);
        if (len) d[off2 + len - 1] ^= 0x80;
        CHECK(sgn(memcmp(a+off2, d+off2, len)) == sgn(nl_memcmp(a+off2, d+off2, len)),
              "memcmp off %d len %d\n", off2, len);
    }

    /* strings: every length and alignment, and every one-byte difference */
    for (int off = 0; off < 16; off++)
    for (int len = 0; len < 64; len++) {
        char s[128], t[128];
        for (int i = 0; i < len; i++) s[off+i] = (char)('a' + (i % 26));
        s[off+len] = 0;
        memcpy(t, s, sizeof t);
        CHECK(strlen(s+off) == nl_strlen(s+off), "strlen off %d len %d\n", off, len);
        CHECK(sgn(strcmp(s+off, t+off)) == sgn(nl_strcmp(s+off, t+off)), "strcmp equal\n");
        for (int i = 0; i < len; i++) {
            char save = t[off+i];
            t[off+i] = (char)(save + 1);
            CHECK(sgn(strcmp(s+off, t+off)) == sgn(nl_strcmp(s+off, t+off)),
                  "strcmp off %d len %d pos %d\n", off, len, i);
            t[off+i] = (char)(save - 1);
            CHECK(sgn(strcmp(s+off, t+off)) == sgn(nl_strcmp(s+off, t+off)),
                  "strcmp- off %d len %d pos %d\n", off, len, i);
            t[off+i] = save;
        }
    }
    /* the functions NURL programs reach directly: same sweep, and the
     * needle/haystack cases a hand-written search gets wrong (empty
     * needle, needle longer than hay, match at the very end). */
    {
        static const char *hays[] = {"", "a", "abc", "abcabcabd", "aaaaab",
            "the quick brown fox", "xxxxxxxxxxxxxxxxxxxxy", "\r\n\r\n"};
        static const char *nees[] = {"", "a", "b", "abc", "abd", "abcabd",
            "fox", "y", "\r\n", "zzz", "the quick brown fox "};
        for (unsigned h = 0; h < sizeof hays/sizeof *hays; h++) {
            for (unsigned n = 0; n < sizeof nees/sizeof *nees; n++) {
                CHECK(strstr(hays[h], nees[n]) == nl_strstr(hays[h], nees[n]),
                      "strstr(%s,%s)\n", hays[h], nees[n]);
                CHECK(memmem(hays[h], strlen(hays[h]), nees[n], strlen(nees[n]))
                      == nl_memmem(hays[h], strlen(hays[h]), nees[n], strlen(nees[n])),
                      "memmem(%s,%s)\n", hays[h], nees[n]);
                for (nl_size_t k = 0; k <= strlen(hays[h]) + 1; k++)
                    CHECK(sgn(strncmp(hays[h], nees[n], k)) == sgn(nl_strncmp(hays[h], nees[n], k)),
                          "strncmp(%s,%s,%lu)\n", hays[h], nees[n], (unsigned long)k);
            }
            for (int c = 0; c < 256; c++) {
                CHECK(strchr(hays[h], c) == nl_strchr(hays[h], c), "strchr %d\n", c);
                CHECK(strrchr(hays[h], c) == nl_strrchr(hays[h], c), "strrchr %d\n", c);
            }
            for (nl_size_t k = 0; k <= 24; k++) {
                char x[32], y[32];
                memset(x, 0x7E, sizeof x); memset(y, 0x7E, sizeof y);
                strncpy(x, hays[h], k); nl_strncpy(y, hays[h], k);
                CHECK(memcmp(x, y, sizeof x) == 0, "strncpy(%s,%lu)\n", hays[h], (unsigned long)k);
            }
        }
        static const char *nums[] = {"0", "1", "-1", "+42", "  12", "\t-7", "999999999999",
            "9223372036854775807", "-9223372036854775808", "12abc", "abc", "", "-", "007"};
        for (unsigned i = 0; i < sizeof nums/sizeof *nums; i++)
            CHECK(atoll(nums[i]) == nl_atoll(nums[i]), "atoll(%s): %lld vs %lld\n",
                  nums[i], atoll(nums[i]), nl_atoll(nums[i]));
    }
    printf("string differential: %ld checks, %ld mismatches\n", checked, bad);
    return bad ? 1 : 0;
}
