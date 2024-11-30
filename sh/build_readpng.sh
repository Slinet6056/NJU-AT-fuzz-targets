#!/bin/bash

# Parameter checking
if [ $# -lt 2 ]; then
  echo "<BUILD>: <SUBJECT_DIR> <BENCH_DIR>"
  exit 1
fi

# Get abspath to subject directory
SUBJECT_DIR="$1"
pushd "$SUBJECT_DIR" || exit 1
SUBJECT_DIR="$PWD"
popd || exit 1

# Get abspath to target directory
BENCH_DIR="$2"
pushd "$BENCH_DIR" || exit 1
BENCH_DIR="$PWD"
popd || exit 1

# Choose compilers
export CC="$AFLPP/afl-cc"
export CXX="$AFLPP/afl-c++"
# Add optimization flags
export CFLAGS="-O0"
export CXXFLAGS="-O0"

# Show configuration results
echo "==================== CONF-LOG ===================="
echo "SUBJECT_DIR=$SUBJECT_DIR"
echo "BENCH_DIR=$BENCH_DIR"
echo "CC=$CC"
echo "CXX=$CXX"
echo "CFLAGS=$CFLAGS"
echo "CXXFLAGS=$CXXFLAGS"
echo "==================== CONF-LOG ===================="

# Instrument SUBJECT programs
pushd "$SUBJECT_DIR" || exit 1
# Build libs
./configure --disable-shared
make clean
make
# Build readpng
$CC -O0 -o readpng ./contrib/libtests/readpng.c ./.libs/libpng16.a -lz -lm
popd || exit 1

# Move to target directory
TARGET="readpng"
TARGET_DIR="$BENCH_DIR/$TARGET"
# Refresh
if [ -d "$TARGET_DIR" ]; then
  rm -rf "$TARGET_DIR"
fi
mkdir -p "$TARGET_DIR"
mv "$SUBJECT_DIR/$TARGET" "$TARGET_DIR/$TARGET.orig"
cat > "$TARGET_DIR/readpng" << 'EOF'
#!/bin/bash
cat "$1" | "$(dirname "$0")/readpng.orig"
EOF
chmod +x "$TARGET_DIR/readpng"

# Create and prepare seeds directories
SEEDS_BASE_DIR="$TARGET_DIR/seeds"
RAW_SEEDS_DIR="$SEEDS_BASE_DIR/raw"
CMIN_SEEDS_DIR="$SEEDS_BASE_DIR/cmin"
TMIN_SEEDS_DIR="$SEEDS_BASE_DIR/tmin"

mkdir -p "$RAW_SEEDS_DIR"
mkdir -p "$CMIN_SEEDS_DIR"
mkdir -p "$TMIN_SEEDS_DIR"

# Copy initial seeds from AFL++ testcases
if [ -d "$AFLPP_DIR/testcases/images/png" ]; then
  cp "$AFLPP_DIR/testcases/images/png"/* "$RAW_SEEDS_DIR/"
else
  echo "Error: AFL++ testcases directory not found at $AFLPP_DIR/testcases/images/png"
  exit 1
fi

# Copy project's own test images
if [ -d "$SUBJECT_DIR/tests" ]; then
  cp "$SUBJECT_DIR/tests"/*.png "$RAW_SEEDS_DIR/" 2>/dev/null
else
  echo "Warning: Project test images not found at $SUBJECT_DIR/tests"
  exit 1
fi

# Check if we have any seeds
if [ ! "$(ls -A "$RAW_SEEDS_DIR")" ]; then
  echo "Error: No seed files found. Please provide at least one PNG file as seed."
  exit 1
fi

# Check if ENABLE_AFL_TMIN is set and equals "1"
ENABLE_AFL_TMIN=${ENABLE_AFL_TMIN:-0}

# Run afl-cmin to minimize the test corpus
"$AFLPP/afl-cmin" -i "$RAW_SEEDS_DIR" -o "$CMIN_SEEDS_DIR" -- "$TARGET_DIR/readpng.orig"

if [ "$ENABLE_AFL_TMIN" = "1" ]; then
  echo "Running afl-tmin for further minimization..."
  # Further minimize each seed with afl-tmin
  for seed in "$CMIN_SEEDS_DIR"/*; do
    if [ -f "$seed" ]; then
      seed_name=$(basename "$seed")
      "$AFLPP/afl-tmin" -i "$seed" -o "$TMIN_SEEDS_DIR/$seed_name" -- "$TARGET_DIR/readpng.orig"
    fi
  done
else
  echo "Skipping afl-tmin minimization (set ENABLE_AFL_TMIN=1 to enable)"
  # Copy cmin results to tmin directory when not using afl-tmin
  cp "$CMIN_SEEDS_DIR"/* "$TMIN_SEEDS_DIR/"
fi
