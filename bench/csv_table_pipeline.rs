// benchmark-contract: csv-table-pipeline;rows=100000;cols=id,name,city,qty,price,note;eol=CRLF;lcg=mmix(seed=1);draw=state>>33;name=names[r&15],form=(r>>4)&7(0:"O""<n>",1:"<n>, Jr.",else:<n>);city=cities[(r>>7)&7];qty=(r>>10)%1000;price=((r>>20)%100000)/100.2dp;note=(r>>27)&3(0:empty,1:fragile,2:"line one\nline two",3:"says ""hi""");passes=4;agg=per-city sum(qty*cents),count;fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// csv_table_pipeline — build a 100k-row RFC 4180 document, then four
// times: copy it, parse the copy into a table, and aggregate five columns
// through per-cell views (see csv_table_pipeline.nu for the workload).
// Rust's standard library has no CSV reader (and this suite builds with
// bare rustc, no crates), so the table is the NURL stdlib's CSVTable in
// safe Rust: one content buffer, an (offset, length) pair per cell (a
// negative offset into a separate buffer for the unescaped bytes of a
// cell with `""` escapes), a row-start / row-length index, the header
// row kept apart, and a view accessor that bounds-checks (row, column)
// and hands back a borrowed `&[u8]`. Same quote, separator and
// end-of-row rules as stdlib/ext/csv.nu's __csv_parse_content. An
// unquoted cell is scanned byte by byte (the stdlib uses an SSE2 scan).
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.

// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

struct Table {
    content: Vec<u8>,
    headers: Vec<String>,
    cells: Vec<i64>,      // [off0, len0, off1, len1, ...]
    row_starts: Vec<i64>, // cell index of row r
    row_lens: Vec<i64>,   // cell count of row r
    esc: Vec<u8>,         // unescaped bytes of quoted cells with "" escapes
}

impl Table {
    // Takes `content` over, as csv_table_from_string does.
    fn parse(content: Vec<u8>) -> Table {
        let clen = content.len();
        let row_est = (clen / 100).max(16);
        let mut t = Table {
            content,
            headers: Vec::new(),
            cells: Vec::new(),
            row_starts: Vec::with_capacity(row_est),
            row_lens: Vec::with_capacity(row_est),
            esc: Vec::new(),
        };
        let cd = &t.content;
        let (delim, quote) = (b',', b'"');
        let mut pos = 0usize;
        let mut first_row = true;
        while pos < clen {
            let row_first = t.cells.len();
            let mut p = pos;
            let mut in_row = true;
            while in_row {
                let (cell_off, cell_len): (i64, i64);
                if p < clen && cd[p] == quote {
                    p += 1;
                    let scan_start = p;
                    let mut esc_start = 0usize;
                    let mut had_escape = false;
                    while p < clen {
                        let c = cd[p];
                        if c == quote {
                            if p + 1 < clen && cd[p + 1] == quote {
                                if !had_escape {
                                    esc_start = t.esc.len();
                                    t.esc.extend_from_slice(&cd[scan_start..p]);
                                    had_escape = true;
                                }
                                t.esc.push(quote);
                                p += 2;
                            } else {
                                break;
                            }
                        } else {
                            if had_escape {
                                t.esc.push(c);
                            }
                            p += 1;
                        }
                    }
                    if had_escape {
                        cell_off = -((esc_start + 1) as i64);
                        cell_len = (t.esc.len() - esc_start) as i64;
                    } else {
                        cell_off = scan_start as i64;
                        cell_len = (p - scan_start) as i64;
                    }
                    if p < clen && cd[p] == quote {
                        p += 1;
                    }
                } else {
                    let start = p;
                    while p < clen && cd[p] != delim && cd[p] != b'\n' && cd[p] != b'\r' {
                        p += 1;
                    }
                    cell_off = start as i64;
                    cell_len = (p - start) as i64;
                }
                t.cells.push(cell_off);
                t.cells.push(cell_len);
                let mut sep_found = false;
                while !sep_found && p < clen {
                    let c = cd[p];
                    if c == delim {
                        p += 1;
                        sep_found = true;
                    } else if c == b'\n' {
                        p += 1;
                        in_row = false;
                        sep_found = true;
                    } else if c == b'\r' {
                        p += 1;
                        if p < clen && cd[p] == b'\n' {
                            p += 1;
                        }
                        in_row = false;
                        sep_found = true;
                    } else {
                        p += 1;
                    }
                }
                if p >= clen {
                    in_row = false;
                }
            }
            let n_cells = (t.cells.len() - row_first) / 2;
            let phantom = n_cells == 1 && t.cells[row_first + 1] == 0;
            if !(phantom && p >= clen) {
                if first_row {
                    for k in 0..n_cells {
                        let off = t.cells[row_first + 2 * k];
                        let len = t.cells[row_first + 2 * k + 1] as usize;
                        let src = if off >= 0 {
                            &cd[off as usize..off as usize + len]
                        } else {
                            let e = (-off - 1) as usize;
                            &t.esc[e..e + len]
                        };
                        t.headers.push(String::from_utf8_lossy(src).into_owned());
                    }
                    t.cells.truncate(row_first);
                    first_row = false;
                } else {
                    t.row_starts.push((row_first / 2) as i64);
                    t.row_lens.push(n_cells as i64);
                }
            } else {
                t.cells.truncate(row_first);
            }
            pos = p;
        }
        t
    }

    fn n_rows(&self) -> usize {
        self.row_starts.len()
    }

    fn col_index(&self, name: &str) -> Option<usize> {
        self.headers.iter().position(|h| h == name)
    }

    // The view of (row, col), or the empty view when out of range.
    fn view(&self, row: usize, col: usize) -> &[u8] {
        if row >= self.row_starts.len() {
            return &[];
        }
        let count = self.row_lens[row] as usize;
        if col >= count {
            return &[];
        }
        let idx = (self.row_starts[row] as usize + col) * 2;
        let off = self.cells[idx];
        let len = self.cells[idx + 1] as usize;
        if off >= 0 {
            &self.content[off as usize..off as usize + len]
        } else {
            let e = (-off - 1) as usize;
            &self.esc[e..e + len]
        }
    }
}

const NAMES: [&str; 16] = [
    "Aino", "Eino", "Helmi", "Väinö", "Ilona", "Toivo", "Siiri", "Onni", "Lempi", "Arvo", "Kerttu", "Urho", "Elli",
    "Paavo", "Saimi", "Veikko",
];
// The city cells as written, and the values the parser hands back.
const CITIES: [&str; 8] =
    ["Helsinki", "Tampere", "Oulu", "Turku", "Espoo", "\"Washington, D.C.\"", "Vantaa", "\"Lahti\""];
const KEYS: [&str; 8] = ["Helsinki", "Tampere", "Oulu", "Turku", "Espoo", "Washington, D.C.", "Vantaa", "Lahti"];

fn push_dec(out: &mut Vec<u8>, v: u64) {
    if v >= 10 {
        push_dec(out, v / 10);
    }
    out.push(b'0' + (v % 10) as u8);
}

fn gen_csv(rows: usize) -> Vec<u8> {
    let mut out: Vec<u8> = Vec::with_capacity(rows * 64);
    out.extend_from_slice(b"id,name,city,qty,price,note\r\n");
    let mut x: u64 = 1;
    for row in 0..rows {
        x = x
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        let r = x >> 33;
        push_dec(&mut out, row as u64);
        out.push(b',');
        let name = NAMES[(r & 15) as usize].as_bytes();
        let form = (r >> 4) & 7;
        if form == 0 {
            out.extend_from_slice(b"\"O\"\"");
            out.extend_from_slice(name);
            out.push(b'"');
        } else if form == 1 {
            out.push(b'"');
            out.extend_from_slice(name);
            out.extend_from_slice(b", Jr.\"");
        } else {
            out.extend_from_slice(name);
        }
        out.push(b',');
        out.extend_from_slice(CITIES[((r >> 7) & 7) as usize].as_bytes());
        out.push(b',');
        push_dec(&mut out, (r >> 10) % 1000);
        out.push(b',');
        let cents = (r >> 20) % 100000;
        push_dec(&mut out, cents / 100);
        out.push(b'.');
        out.push(b'0' + ((cents / 10) % 10) as u8);
        out.push(b'0' + (cents % 10) as u8);
        out.push(b',');
        let note = (r >> 27) & 3;
        if note == 1 {
            out.extend_from_slice(b"fragile");
        }
        if note == 2 {
            out.extend_from_slice(b"\"line one\nline two\"");
        }
        if note == 3 {
            out.extend_from_slice(b"\"says \"\"hi\"\"\"");
        }
        out.extend_from_slice(b"\r\n");
    }
    out
}

fn fnv(h: u64, v: u64) -> u64 {
    (h ^ v).wrapping_mul(1099511628211)
}

// The decimal digits of a cell, read as one number (the price's `.` is
// skipped, so `123.45` is 12345 cents).
fn digits(b: &[u8]) -> u64 {
    let mut acc: u64 = 0;
    for &c in b {
        if c.is_ascii_digit() {
            acc = acc.wrapping_mul(10).wrapping_add((c - b'0') as u64);
        }
    }
    acc
}

fn count_byte(b: &[u8], want: u8) -> u64 {
    b.iter().filter(|&&c| c == want).count() as u64
}

// The index of the key `v` equals, or the key count when none does.
fn city_index(keys: &[&[u8]], v: &[u8]) -> usize {
    keys.iter().position(|k| *k == v).unwrap_or(keys.len())
}

fn col(t: &Table, name: &str) -> usize {
    t.col_index(name).expect("csv_table_pipeline: missing column")
}

fn main() {
    let passes = 4 * BENCH_SCALE;
    let rows = 100_000usize;
    let keys: Vec<&[u8]> = KEYS.iter().map(|k| k.as_bytes()).collect();
    let text = gen_csv(rows);

    let mut h: u64 = 1469598103934665603;
    for _ in 0..passes {
        let t = Table::parse(text.clone());
        let n = t.n_rows();
        let (c_name, c_city, c_qty) = (col(&t, "name"), col(&t, "city"), col(&t, "qty"));
        let (c_price, c_note) = (col(&t, "price"), col(&t, "note"));
        let mut rev = [0u64; 9];
        let mut cnt = [0u64; 9];
        let (mut quoted, mut name_bytes, mut note_bytes, mut multiline) = (0u64, 0u64, 0u64, 0u64);
        for row in 0..n {
            let city = city_index(&keys, t.view(row, c_city));
            let qty = digits(t.view(row, c_qty));
            let cents = digits(t.view(row, c_price));
            rev[city] = rev[city].wrapping_add(qty.wrapping_mul(cents));
            cnt[city] += 1;
            let nm = t.view(row, c_name);
            quoted += count_byte(nm, b'"');
            name_bytes += nm.len() as u64;
            let nt = t.view(row, c_note);
            note_bytes += nt.len() as u64;
            multiline += count_byte(nt, b'\n');
        }
        for c in 0..9 {
            h = fnv(h, rev[c]);
            h = fnv(h, cnt[c]);
        }
        h = fnv(h, quoted);
        h = fnv(h, name_bytes);
        h = fnv(h, note_bytes);
        h = fnv(h, multiline);
        h = fnv(h, n as u64);
    }
    println!("{}", (h & 0x7fff_ffff_ffff_ffff) as i64);
}
