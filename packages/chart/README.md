# chart

Draw charts in your terminal, straight from a stream of numbers. `chart`
is both an installable CLI and a reusable NURL library — pure NURL, no FFI,
leak-clean under AddressSanitizer/LeakSanitizer.

```
seq 1 20 | chart spark
▁▁▂▂▂▃▃▄▄▄▅▅▅▆▆▇▇▇██

printf '%s\n' 'apples 8.5' 'pears 6' 'cherries 2.1' | chart bar
apples   ██████████████████████████████▉ 8.5
pears    █████████████████████▉ 6
cherries ███████▋ 2.1
```

It lives in the NURL **registry**, not the core stdlib: charting is
opinionated (which glyphs, which scaling, which layout) in a way the
language proper should stay out of, but it is exactly the everyday utility
an ecosystem exists to provide. It parses flags with the stdlib `std/args`
and leans on the shipped stdlib for everything else.

## Install

```bash
nurlpkg install chart
```

## CLI

```
chart <spark|bar|hist|line> [options]
```

| Mode    | What it draws                                              |
|---------|-----------------------------------------------------------|
| `spark` | a one-line sparkline (`▁▂▃▄▅▆▇█`) of the numbers           |
| `bar`   | labelled horizontal bars, one input *line* per bar        |
| `hist`  | a histogram — bins the numbers and draws the counts       |
| `line`  | a line/scatter plot on a character grid (`plot` is an alias) |

Input is whitespace-separated numbers read from **stdin** (or `--file`).
Non-numeric tokens are ignored. In `bar` mode each line is one bar:
`<label…> <value>` (the last token is the value, the rest the label), or a
bare number whose label is its 1-based position.

### Options

| Flag                | Applies to     | Meaning                              |
|---------------------|----------------|--------------------------------------|
| `-w`, `--width N`   | bar/hist/line  | chart width in cells (default 40)    |
| `--height N`        | line           | plot height in rows (default 10)     |
| `-b`, `--bins N`    | hist           | number of buckets (default 10)       |
| `-f`, `--file PATH` | all            | read numbers from `PATH` not stdin   |
| `-t`, `--title T`   | all            | print `T` on a line above the chart  |
| `-h`, `--help`      |                | show help                            |

### Examples

```bash
# CPU load at a glance
uptime | grep -o '[0-9.]*' | tail -3 | chart spark

# distribution of file sizes
ls -l | awk '{print $5}' | chart hist --bins 8 -w 30

# a quick line plot from a file
chart line -f temps.txt --height 12 -t "Temperature"

# bars with multi-word labels
printf '%s\n' 'New York 19' 'Los Angeles 13' 'Chicago 27' | chart bar
```

The bars use Unicode block elements at **eighth-cell** resolution, so a
value of 3.5 cells reads as three full blocks plus a half block (`███▌`)
rather than rounding to whole characters. The line plot maps the series
onto a grid (top = max, bottom = min), resampling to the requested width
and joining consecutive samples so it reads as a connected line; it
handles negatives.

## Library

Add the dependency and import the renderer:

```toml
[dependencies]
chart = "^0.1"
```

```
$ `deps/chart/src/chart.nu`

: ( Vec f ) v ( vec_new [f] )
( vec_push [f] v 3.0 ) ( vec_push [f] v 7.0 ) ( vec_push [f] v 5.0 )
: String s ( chart_sparkline v )      // ▃█▆  (caller frees with string_free)
```

### API

Every renderer returns an **owned** `String`; free it with `string_free`.
`values` is a `( Vec f )`; `labels` is a `( Vec String )` that is *borrowed*
(never freed or retained). Widths/heights are in terminal cells.

```
( chart_sparkline values )           → String   one-line ▁▂▃▄▅▆▇█
( chart_bars labels values width )   → String   labelled horizontal bars
( chart_hist values bins width )     → String   binned histogram
( chart_plot values width height )   → String   line/scatter grid

( chart_min  values )                → f        summary statistics
( chart_max  values )                → f
( chart_sum  values )                → f
( chart_mean values )                → f
```

Bars and histograms assume non-negative values (the natural shape for a
bar chart); a negative value draws an empty bar. The plot accepts any
range. An empty series yields an empty string rather than trapping.

## Build & test locally

From the package directory, with the in-tree toolchain:

```bash
NURL_STDLIB=/path/to/nurl-lang \
  /path/to/nurl-lang/nurl.sh src/main.nu chart   # build the CLI
echo 1 2 3 4 5 | ./chart spark
```

## License

MIT OR Apache-2.0.
