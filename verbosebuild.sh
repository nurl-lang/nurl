#!/usr/bin/env bash
set -euo pipefail

echo "Compiling runtime..."

# libcurl detection (mirrors build.sh). When pkg-config knows about
# libcurl, build the runtime with -DNURL_HAVE_LIBCURL and link with
# its libs at every clang invocation below. Without it, http_get /
# http_post symbols still resolve but every call returns
# HttpErr::HttpOther (transport unavailable).
CURL_CFLAGS=""
CURL_LIBS=""
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libcurl 2>/dev/null; then
    CURL_CFLAGS="-DNURL_HAVE_LIBCURL $(pkg-config --cflags libcurl)"
    CURL_LIBS="$(pkg-config --libs libcurl)"
    echo 1 > stdlib/runtime.curl
    echo "  libcurl detected — HTTP transport enabled"
else
    rm -f stdlib/runtime.curl
    echo "  libcurl not found — HTTP transport stubbed"
fi

clang $CURL_CFLAGS -c stdlib/runtime.c -o stdlib/runtime.o

echo "============================================"
echo " NURL Compiler Test Build"
echo "============================================"

# --- Create build directory ---
echo ""
echo "[0/9] Creating build directory..."
mkdir -p build
echo "      OK: build/ directory ready"

# --- Locate clang ---
CLANG="clang"
if ! command -v clang &>/dev/null; then
    if [ -x "/usr/lib/llvm/bin/clang" ]; then
        CLANG="/usr/lib/llvm/bin/clang"
    elif [ -x "/usr/local/bin/clang" ]; then
        CLANG="/usr/local/bin/clang"
    else
        echo "ERROR: clang not found!"
        exit 1
    fi
fi

# --- Clean old artifacts ---
echo ""
echo "[1/9] Cleaning old build artifacts..."
rm -f build/nurlc_py.ll build/nurlc_py build/nurlc_self.ll build/nurlc_self build/nurlc_self2.ll build/nurlc_self2 build/nurlc

# --- Step 1: Python compiler -> LLVM IR ---
echo ""
echo "[2/9] Compiling nurlc.nu with Python compiler..."
if ! python compiler/nurlc.py --llvm compiler/nurlc.nu > build/nurlc_py.ll; then
    echo "ERROR: Python compilation failed!"
    exit 1
fi
echo "      OK: build/nurlc_py.ll generated"

# --- Step 2: LLVM IR -> nurlc_py ---
echo ""
echo "[3/9] Building nurlc_py with clang..."
if ! "$CLANG" -O2 build/nurlc_py.ll stdlib/runtime.o -lm $CURL_LIBS -o build/nurlc_py; then
    echo "ERROR: clang build failed for nurlc_py!"
    exit 1
fi
echo "      OK: build/nurlc_py built"

# --- Step 3: Self-compiled compiler -> LLVM IR (round 1) ---
echo ""
echo "[4/9] Compiling nurlc.nu with nurlc_py (round 1)..."
if ! ./build/nurlc_py compiler/nurlc.nu > build/nurlc_self.ll; then
    echo "ERROR: Self-compilation round 1 failed!"
    exit 1
fi
echo "      OK: build/nurlc_self.ll generated"

# --- Step 4: LLVM IR -> nurlc_self ---
echo ""
echo "[5/9] Building nurlc_self with clang..."
if ! "$CLANG" -O2 build/nurlc_self.ll stdlib/runtime.o -lm $CURL_LIBS -o build/nurlc_self; then
    echo "ERROR: clang build failed for nurlc_self!"
    exit 1
fi
echo "      OK: build/nurlc_self built"

# --- Step 5: Compare round 1 (Python vs NURL) ---
echo ""
echo "[6/9] Comparing LLVM IR: Python compiler vs nurlc_py..."
if cmp -s build/nurlc_py.ll build/nurlc_self.ll; then
    echo "      MATCH: Python and NURL compilers produce identical LLVM IR"
else
    echo "      DIFFER: Python and NURL compilers produce different LLVM IR"
    echo "      Run 'diff build/nurlc_py.ll build/nurlc_self.ll' to see differences"
fi

# --- Step 6: Self-compiled compiler -> LLVM IR (round 2) ---
echo ""
echo "[7/9] Compiling nurlc.nu with nurlc_self (round 2)..."
if ! ./build/nurlc_self compiler/nurlc.nu > build/nurlc_self2.ll; then
    echo "ERROR: Self-compilation round 2 failed!"
    exit 1
fi
echo "      OK: build/nurlc_self2.ll generated"

# --- Step 7: LLVM IR -> nurlc_self2 ---
echo ""
echo "[8/9] Building nurlc_self2 with clang..."
if ! "$CLANG" -O2 build/nurlc_self2.ll stdlib/runtime.o -lm $CURL_LIBS -o build/nurlc_self2; then
    echo "ERROR: clang build failed for nurlc_self2!"
    exit 1
fi
echo "      OK: build/nurlc_self2 built"

# --- Step 8: Compare round 2 (NURL vs NURL) ---
echo ""
echo "[9/9] Comparing LLVM IR: nurlc_self vs nurlc_self2 (fixed point)..."
if cmp -s build/nurlc_self.ll build/nurlc_self2.ll; then
    echo "      FIXED POINT REACHED: nurlc_self and nurlc_self2 produce identical LLVM IR"
    echo "      Bootstrap complete — compiler is fully self-hosting!"
    cp build/nurlc_self2 build/nurlc
    # Create convenience symlink in root directory
    ln -sf build/nurlc nurlc 2>/dev/null || cp build/nurlc nurlc
else
    echo "      FIXED POINT NOT REACHED: round 1 and round 2 outputs differ"
    echo "      Run 'diff build/nurlc_self.ll build/nurlc_self2.ll' to see differences"
fi

# --- Summary ---
echo ""
echo "Build complete!"
echo ""
echo "  build/nurlc_py.ll    - LLVM IR from Python compiler"
echo "  build/nurlc_self.ll  - LLVM IR from nurlc_py  (round 1)"
echo "  build/nurlc_self2.ll - LLVM IR from nurlc_self (round 2)"
echo "  build/nurlc_py       - Built by Python compiler"
echo "  build/nurlc_self     - Built by nurlc_py  (round 1)"
echo "  build/nurlc_self2    - Built by nurlc_self (round 2)"
if [ -f build/nurlc ]; then
    echo "  build/nurlc          - Final self-hosted compiler (fixed point reached)"
    echo "  nurlc                - Convenience symlink/copy to build/nurlc"
fi

echo "============================================"