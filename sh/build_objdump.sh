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
export CXX="$AFLPP/afl-cc++"

# Show configuration results
echo "==================== CONF-LOG ===================="
echo "SUBJECT_DIR=$SUBJECT_DIR"
echo "BENCH_DIR=$BENCH_DIR"
echo "CC=$CC"
echo "CXX=$CXX"
echo "==================== CONF-LOG ===================="
sleep 3

# Instrument SUBJECT programs
pushd "$SUBJECT_DIR" || exit 1
# Build binutils
./configure --disable-shared
make clean
make
popd || exit 1

# Move to target directory
TARGET="objdump"
TARGET_DIR="$BENCH_DIR/$TARGET"
# Refresh
if [ -d "$TARGET_DIR" ]; then
  rm -rf "$TARGET_DIR"
fi
mkdir -p "$TARGET_DIR"
mv "$SUBJECT_DIR/binutils/objdump" "$TARGET_DIR" || mv "$SUBJECT_DIR/binutils/.libs/objdump" "$TARGET_DIR"

# Create and prepare seeds directories
SEEDS_BASE_DIR="$TARGET_DIR/seeds"
RAW_SEEDS_DIR="$SEEDS_BASE_DIR/raw"
CMIN_SEEDS_DIR="$SEEDS_BASE_DIR/cmin"
TMIN_SEEDS_DIR="$SEEDS_BASE_DIR/tmin"

mkdir -p "$RAW_SEEDS_DIR"
mkdir -p "$CMIN_SEEDS_DIR"
mkdir -p "$TMIN_SEEDS_DIR"

# Copy initial seeds from AFL++ testcases
if [ -d "$AFLPP_DIR/testcases/others/elf" ]; then
  cp "$AFLPP_DIR/testcases/others/elf"/* "$RAW_SEEDS_DIR/"
else
  echo "Error: AFL++ testcases directory not found at $AFLPP_DIR/testcases/others/elf"
  exit 1
fi

# Run afl-cmin to minimize the test corpus
"$AFLPP/afl-cmin" -i "$RAW_SEEDS_DIR" -o "$CMIN_SEEDS_DIR" -- "$TARGET_DIR/objdump" -d @@

# Further minimize each seed with afl-tmin
for seed in "$CMIN_SEEDS_DIR"/*; do
  if [ -f "$seed" ]; then
    seed_name=$(basename "$seed")
    "$AFLPP/afl-tmin" -i "$seed" -o "$TMIN_SEEDS_DIR/$seed_name" -- "$TARGET_DIR/objdump" -d @@
  fi
done
