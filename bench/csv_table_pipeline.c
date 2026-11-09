// benchmark-contract: csv-table-pipeline;rows=100000;cols=id,name,city,qty,price,note;eol=CRLF;lcg=mmix(seed=1);draw=state>>33;name=names[r&15],form=(r>>4)&7(0:"O""<n>",1:"<n>, Jr.",else:<n>);city=cities[(r>>7)&7];qty=(r>>10)%1000;price=((r>>20)%100000)/100.2dp;note=(r>>27)&3(0:empty,1:fragile,2:"line one\nline two",3:"says ""hi""");passes=4;agg=per-city sum(qty*cents),count;fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// csv_table_pipeline — build a 100k-row RFC 4180 document, then four
// times: copy it, parse the copy into a table, and aggregate five columns
// through per-cell views (see csv_table_pipeline.nu for the workload).
// C has no CSV reader in its standard library, so the table is the
// stdlib's CSVTable written out by hand: one content buffer, an
// (offset, length) pair per cell (a negative offset into a separate
// buffer for the unescaped bytes of a cell with `""` escapes), a
// row-start / row-length index, the header row kept apart, and a view
// accessor that bounds-checks (row, column). Same quote, separator and
// end-of-row rules as stdlib/ext/csv.nu's __csv_parse_content. An
// unquoted cell is scanned byte by byte (the stdlib uses an SSE2 scan).
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
#define BENCH_SCALE 1ULL

static void *xrealloc(void *p, size_t n) {
  void *q = realloc(p, n);
  if (!q) abort();
  return q;
}

// ── a growable byte buffer ───────────────────────────────────────
typedef struct { unsigned char *p; size_t len, cap; } Buf;

static void buf_reserve(Buf *b, size_t need) {
  if (need <= b->cap) return;
  size_t c = b->cap ? b->cap * 2 : 16;
  while (c < need) c *= 2;
  b->p = xrealloc(b->p, c);
  b->cap = c;
}
static void buf_byte(Buf *b, int c) {
  buf_reserve(b, b->len + 1);
  b->p[b->len++] = (unsigned char)c;
}
static void buf_str(Buf *b, const char *s) {
  size_t n = strlen(s);
  buf_reserve(b, b->len + n);
  memcpy(b->p + b->len, s, n);
  b->len += n;
}
static void buf_dec(Buf *b, uint64_t v) {
  if (v >= 10) buf_dec(b, v / 10);
  buf_byte(b, (int)('0' + v % 10));
}

// ── a growable i64 vector ────────────────────────────────────────
typedef struct { int64_t *p; size_t len, cap; } I64s;

static void i64s_reserve(I64s *v, size_t need) {
  if (need <= v->cap) return;
  size_t c = v->cap ? v->cap * 2 : 16;
  while (c < need) c *= 2;
  v->p = xrealloc(v->p, c * sizeof(int64_t));
  v->cap = c;
}

// ── the table ────────────────────────────────────────────────────
typedef struct {
  unsigned char *content;
  size_t clen;
  char **headers;
  size_t n_headers;
  I64s cells;       // [off0, len0, off1, len1, ...]
  I64s row_starts;  // cell index of row r
  I64s row_lens;    // cell count of row r
  Buf esc;          // unescaped bytes of quoted cells with "" escapes
} Table;

typedef struct { const unsigned char *p; size_t len; } View;

// Takes `content` over, as csv_table_from_string does.
static void table_parse(Table *t, unsigned char *content, size_t clen) {
  memset(t, 0, sizeof *t);
  t->content = content;
  t->clen = clen;
  const unsigned char *cd = content;
  const int delim = ',', quote = '"';
  size_t row_est = clen / 100;
  if (row_est < 16) row_est = 16;
  i64s_reserve(&t->row_starts, row_est);
  i64s_reserve(&t->row_lens, row_est);
  size_t pos = 0;
  int first_row = 1;
  while (pos < clen) {
    size_t row_first = t->cells.len;
    i64s_reserve(&t->cells, row_first + 512);
    size_t p = pos, wi = row_first;
    int in_row = 1;
    while (in_row) {
      int64_t cell_off, cell_len;
      if (p < clen && cd[p] == quote) {
        p += 1;
        size_t scan_start = p, esc_start = 0;
        int had_escape = 0;
        while (p < clen) {
          int c = cd[p];
          if (c == quote) {
            if (p + 1 < clen && cd[p + 1] == quote) {
              if (!had_escape) {
                esc_start = t->esc.len;
                size_t pre = p - scan_start;
                buf_reserve(&t->esc, t->esc.len + pre + 16);
                memcpy(t->esc.p + t->esc.len, cd + scan_start, pre);
                t->esc.len += pre;
                had_escape = 1;
              }
              buf_byte(&t->esc, quote);
              p += 2;
            } else {
              break;
            }
          } else {
            if (had_escape) buf_byte(&t->esc, c);
            p += 1;
          }
        }
        if (had_escape) {
          cell_off = -(int64_t)(esc_start + 1);
          cell_len = (int64_t)(t->esc.len - esc_start);
        } else {
          cell_off = (int64_t)scan_start;
          cell_len = (int64_t)(p - scan_start);
        }
        if (p < clen && cd[p] == quote) p += 1;
      } else {
        size_t start = p;
        while (p < clen && cd[p] != delim && cd[p] != '\n' && cd[p] != '\r') p += 1;
        cell_off = (int64_t)start;
        cell_len = (int64_t)(p - start);
      }
      if (wi + 2 > t->cells.cap) abort();  // more than 256 cells in a row
      t->cells.p[wi] = cell_off;
      t->cells.p[wi + 1] = cell_len;
      wi += 2;
      int sep_found = 0;
      while (!sep_found && p < clen) {
        int c = cd[p];
        if (c == delim) {
          p += 1;
          sep_found = 1;
        } else if (c == '\n') {
          p += 1;
          in_row = 0;
          sep_found = 1;
        } else if (c == '\r') {
          p += 1;
          if (p < clen && cd[p] == '\n') p += 1;
          in_row = 0;
          sep_found = 1;
        } else {
          p += 1;
        }
      }
      if (p >= clen) in_row = 0;
    }
    size_t n_cells = (wi - row_first) / 2;
    int phantom = n_cells == 1 && t->cells.p[row_first + 1] == 0;
    if (!(phantom && p >= clen)) {
      if (first_row) {
        t->headers = xrealloc(NULL, n_cells * sizeof(char *));
        t->n_headers = n_cells;
        for (size_t k = 0; k < n_cells; ++k) {
          int64_t off = t->cells.p[row_first + 2 * k];
          size_t len = (size_t)t->cells.p[row_first + 2 * k + 1];
          const unsigned char *src = off >= 0 ? cd + off : t->esc.p + (-off - 1);
          char *h = xrealloc(NULL, len + 1);
          memcpy(h, src, len);
          h[len] = 0;
          t->headers[k] = h;
        }
        first_row = 0;
      } else {
        t->cells.len = wi;
        i64s_reserve(&t->row_starts, t->row_starts.len + 1);
        i64s_reserve(&t->row_lens, t->row_lens.len + 1);
        t->row_starts.p[t->row_starts.len++] = (int64_t)(row_first / 2);
        t->row_lens.p[t->row_lens.len++] = (int64_t)n_cells;
      }
    }
    pos = p;
  }
}

static void table_free(Table *t) {
  free(t->content);
  for (size_t k = 0; k < t->n_headers; ++k) free(t->headers[k]);
  free(t->headers);
  free(t->cells.p);
  free(t->row_starts.p);
  free(t->row_lens.p);
  free(t->esc.p);
}

static size_t table_n_rows(const Table *t) { return t->row_starts.len; }

static int64_t table_col_index(const Table *t, const char *name) {
  for (size_t k = 0; k < t->n_headers; ++k)
    if (strcmp(t->headers[k], name) == 0) return (int64_t)k;
  return -1;
}

// The view of (row, col), or the empty view when out of range.
static View table_view(const Table *t, int64_t row, int64_t col) {
  View v = { NULL, 0 };
  if (row < 0 || (size_t)row >= t->row_starts.len) return v;
  int64_t count = t->row_lens.p[row];
  if (col < 0 || col >= count) return v;
  int64_t idx = (t->row_starts.p[row] + col) * 2;
  int64_t off = t->cells.p[idx];
  v.len = (size_t)t->cells.p[idx + 1];
  v.p = off >= 0 ? t->content + off : t->esc.p + (-off - 1);
  return v;
}

// ── the workload ─────────────────────────────────────────────────
static const char *NAMES[16] = { "Aino", "Eino", "Helmi", "Väinö", "Ilona", "Toivo", "Siiri", "Onni",
                                 "Lempi", "Arvo", "Kerttu", "Urho", "Elli", "Paavo", "Saimi", "Veikko" };
// The city cells as written, and the values the parser hands back.
static const char *CITIES[8] = { "Helsinki", "Tampere", "Oulu", "Turku",
                                 "Espoo", "\"Washington, D.C.\"", "Vantaa", "\"Lahti\"" };
static const char *KEYS[8] = { "Helsinki", "Tampere", "Oulu", "Turku", "Espoo", "Washington, D.C.", "Vantaa", "Lahti" };

static void gen_csv(Buf *out, int rows) {
  buf_reserve(out, (size_t)rows * 64);
  buf_str(out, "id,name,city,qty,price,note\r\n");
  uint64_t x = 1;
  for (int row = 0; row < rows; ++row) {
    x = x * 6364136223846793005ULL + 1442695040888963407ULL;
    uint64_t r = x >> 33;
    buf_dec(out, (uint64_t)row);
    buf_byte(out, ',');
    const char *name = NAMES[r & 15];
    uint64_t form = (r >> 4) & 7;
    if (form == 0) {
      buf_str(out, "\"O\"\"");
      buf_str(out, name);
      buf_byte(out, '"');
    } else if (form == 1) {
      buf_byte(out, '"');
      buf_str(out, name);
      buf_str(out, ", Jr.\"");
    } else {
      buf_str(out, name);
    }
    buf_byte(out, ',');
    buf_str(out, CITIES[(r >> 7) & 7]);
    buf_byte(out, ',');
    buf_dec(out, (r >> 10) % 1000);
    buf_byte(out, ',');
    uint64_t cents = (r >> 20) % 100000;
    buf_dec(out, cents / 100);
    buf_byte(out, '.');
    buf_byte(out, (int)('0' + (cents / 10) % 10));
    buf_byte(out, (int)('0' + cents % 10));
    buf_byte(out, ',');
    uint64_t note = (r >> 27) & 3;
    if (note == 1) buf_str(out, "fragile");
    if (note == 2) buf_str(out, "\"line one\nline two\"");
    if (note == 3) buf_str(out, "\"says \"\"hi\"\"\"");
    buf_str(out, "\r\n");
  }
}

static uint64_t fnv(uint64_t h, uint64_t v) { return (h ^ v) * 1099511628211ULL; }

// The decimal digits of a cell, read as one number (the price's `.` is
// skipped, so `123.45` is 12345 cents).
static uint64_t digits(View b) {
  uint64_t acc = 0;
  for (size_t j = 0; j < b.len; ++j) {
    int c = b.p[j];
    if (c >= '0' && c <= '9') acc = acc * 10 + (uint64_t)(c - '0');
  }
  return acc;
}

static uint64_t count_byte(View b, int want) {
  uint64_t hits = 0;
  for (size_t j = 0; j < b.len; ++j)
    if (b.p[j] == want) hits += 1;
  return hits;
}

// The index of the key `v` equals, or the key count when none does.
static size_t city_index(const View *keys, size_t n, View v) {
  for (size_t j = 0; j < n; ++j)
    if (keys[j].len == v.len && (v.len == 0 || memcmp(keys[j].p, v.p, v.len) == 0)) return j;
  return n;
}

static int64_t col(const Table *t, const char *name) {
  int64_t c = table_col_index(t, name);
  if (c < 0) {
    fprintf(stderr, "csv_table_pipeline: missing column\n");
    exit(1);
  }
  return c;
}

int main(void) {
  const uint64_t passes = 4ULL * BENCH_SCALE;
  const int rows = 100000;
  View keys[8];
  for (int j = 0; j < 8; ++j) keys[j] = (View){ (const unsigned char *)KEYS[j], strlen(KEYS[j]) };

  Buf text = { NULL, 0, 0 };
  gen_csv(&text, rows);

  uint64_t h = 1469598103934665603ULL;
  for (uint64_t pass = 0; pass < passes; ++pass) {
    unsigned char *copy = xrealloc(NULL, text.len + 1);
    memcpy(copy, text.p, text.len);
    copy[text.len] = 0;
    Table t;
    table_parse(&t, copy, text.len);
    int64_t n = (int64_t)table_n_rows(&t);
    int64_t c_name = col(&t, "name"), c_city = col(&t, "city"), c_qty = col(&t, "qty");
    int64_t c_price = col(&t, "price"), c_note = col(&t, "note");
    uint64_t rev[9] = { 0 }, cnt[9] = { 0 };
    uint64_t quoted = 0, name_bytes = 0, note_bytes = 0, multiline = 0;
    for (int64_t row = 0; row < n; ++row) {
      size_t city = city_index(keys, 8, table_view(&t, row, c_city));
      uint64_t qty = digits(table_view(&t, row, c_qty));
      uint64_t cents = digits(table_view(&t, row, c_price));
      rev[city] += qty * cents;
      cnt[city] += 1;
      View nm = table_view(&t, row, c_name);
      quoted += count_byte(nm, '"');
      name_bytes += nm.len;
      View nt = table_view(&t, row, c_note);
      note_bytes += nt.len;
      multiline += count_byte(nt, '\n');
    }
    for (int c = 0; c < 9; ++c) {
      h = fnv(h, rev[c]);
      h = fnv(h, cnt[c]);
    }
    h = fnv(h, quoted);
    h = fnv(h, name_bytes);
    h = fnv(h, note_bytes);
    h = fnv(h, multiline);
    h = fnv(h, (uint64_t)n);
    table_free(&t);
  }
  free(text.p);
  printf("%lld\n", (long long)(h & 0x7fffffffffffffffULL));
  return 0;
}
