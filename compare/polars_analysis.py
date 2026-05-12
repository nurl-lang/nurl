import polars as pl
import time

t0 = time.time()
df = pl.read_csv("test_data.csv")
t_load = time.time()
print(f"Loaded {df.height} rows x {df.width} cols in {(t_load-t0)*1000:.0f}ms")

filtered = df.filter(
    (pl.col("val_float2") > 0) &
    (pl.col("text_words").str.contains("juliet"))
)
t_filter = time.time()
print(f"Filtered to {filtered.height} rows in {(t_filter-t_load)*1000:.0f}ms")

sorted_df = filtered.sort("val_int", descending=True)
t_sort = time.time()
print(f"Sorted (val_int desc) in {(t_sort-t_filter)*1000:.0f}ms")

top10 = sorted_df.head(10)
top10.write_csv("polars_top10.csv")
t_write = time.time()
print(f"Top-10 written to polars_top10.csv in {(t_write-t_sort)*1000:.0f}ms")

print(f"\nTotal: {(t_write-t0)*1000:.0f}ms\n")

# Plain CSV print (avoid Unicode box chars on cp1252 consoles)
import sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
print(",".join(top10.columns))
for row in top10.iter_rows():
    print(",".join(str(v) for v in row))
