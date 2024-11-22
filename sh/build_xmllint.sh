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
# Build libxml2
NOCONFIGURE=1 ./autogen.sh
./configure --disable-shared --without-python
make clean
make
popd || exit 1

# Move to target directory
TARGET="xmllint"
TARGET_DIR="$BENCH_DIR/$TARGET"
# Refresh
if [ -d "$TARGET_DIR" ]; then
  rm -rf "$TARGET_DIR"
fi
mkdir -p "$TARGET_DIR"
mv "$SUBJECT_DIR/xmllint" "$TARGET_DIR"

# Create and prepare seeds directories
SEEDS_BASE_DIR="$TARGET_DIR/seeds"
RAW_SEEDS_DIR="$SEEDS_BASE_DIR/raw"
CMIN_SEEDS_DIR="$SEEDS_BASE_DIR/cmin"
TMIN_SEEDS_DIR="$SEEDS_BASE_DIR/tmin"

mkdir -p "$RAW_SEEDS_DIR"
mkdir -p "$CMIN_SEEDS_DIR"
mkdir -p "$TMIN_SEEDS_DIR"

# Copy initial seeds from AFL++ testcases
if [ -d "$AFLPP_DIR/testcases/others/xml" ]; then
  cp "$AFLPP_DIR/testcases/others/xml"/* "$RAW_SEEDS_DIR/"
else
  echo "Error: AFL++ testcases directory not found at $AFLPP_DIR/testcases/others/xml"
  exit 1
fi

# Copy project's own test files
if [ -d "$SUBJECT_DIR/test" ]; then
  find "$SUBJECT_DIR/test" -type f -name "*.xml" -exec cp {} "$RAW_SEEDS_DIR/" \;
else
  echo "Warning: Project test files not found at $SUBJECT_DIR/test"
  exit 1
fi

# Check if we have any seeds
if [ ! "$(ls -A "$RAW_SEEDS_DIR")" ]; then
  echo "Error: No seed files found. Please provide at least one XML file as seed."
  exit 1
fi

# Check if AFL_USE_TMIN is set and equals "1"
AFL_USE_TMIN=${AFL_USE_TMIN:-0}

# Run afl-cmin to minimize the test corpus
"$AFLPP/afl-cmin" -i "$RAW_SEEDS_DIR" -o "$CMIN_SEEDS_DIR" -- "$TARGET_DIR/xmllint" @@

if [ "$AFL_USE_TMIN" = "1" ]; then
  echo "Running afl-tmin for further minimization..."
  # Further minimize each seed with afl-tmin
  for seed in "$CMIN_SEEDS_DIR"/*; do
    if [ -f "$seed" ]; then
      seed_name=$(basename "$seed")
      "$AFLPP/afl-tmin" -i "$seed" -o "$TMIN_SEEDS_DIR/$seed_name" -- "$TARGET_DIR/xmllint" @@
    fi
  done
else
  echo "Skipping afl-tmin minimization (set AFL_USE_TMIN=1 to enable)"
  # Copy cmin results to tmin directory when not using afl-tmin
  cp "$CMIN_SEEDS_DIR"/* "$TMIN_SEEDS_DIR/"
fi
