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
# Build lua
cd src
make clean
make all MYCFLAGS="-O2 -fPIC -g" MYLIBS="-ldl" CC="$AFLPP/afl-cc"
cd ..
popd || exit 1

# Move to target directory
TARGET="lua"
TARGET_DIR="$BENCH_DIR/$TARGET"
# Refresh
if [ -d "$TARGET_DIR" ]; then
  rm -rf "$TARGET_DIR"
fi
mkdir -p "$TARGET_DIR"
mv "$SUBJECT_DIR/src/lua" "$TARGET_DIR"

# Create and prepare seeds directories
SEEDS_BASE_DIR="$TARGET_DIR/seeds"
RAW_SEEDS_DIR="$SEEDS_BASE_DIR/raw"
CMIN_SEEDS_DIR="$SEEDS_BASE_DIR/cmin"
TMIN_SEEDS_DIR="$SEEDS_BASE_DIR/tmin"

mkdir -p "$RAW_SEEDS_DIR"
mkdir -p "$CMIN_SEEDS_DIR"
mkdir -p "$TMIN_SEEDS_DIR"

# Download test files from GitHub if they don't exist
if [ ! -d "$TARGET_DIR/lua-tests" ]; then
  echo "Downloading Lua test files from GitHub..."
  git clone https://github.com/lua/lua.git "$TARGET_DIR/lua-tests" || {
    echo "Error: Failed to clone Lua test repository"
    exit 1
  }
fi

# Copy test files to raw seeds directory
if [ -d "$TARGET_DIR/lua-tests/testes" ]; then
  cp "$TARGET_DIR/lua-tests/testes"/*.lua "$RAW_SEEDS_DIR/" 2>/dev/null
  # Clean up
  rm -rf "$TARGET_DIR/lua-tests"
else
  echo "Error: Test files not found in the cloned repository"
  exit 1
fi

# Check if we have any seeds
if [ ! "$(ls -A "$RAW_SEEDS_DIR")" ]; then
  echo "Error: No seed files found. Please provide at least one Lua file as seed."
  exit 1
fi

# Check if ENABLE_AFL_TMIN is set and equals "1"
ENABLE_AFL_TMIN=${ENABLE_AFL_TMIN:-0}

# Run afl-cmin to minimize the test corpus
"$AFLPP/afl-cmin" -i "$RAW_SEEDS_DIR" -o "$CMIN_SEEDS_DIR" -- "$TARGET_DIR/lua" @@

if [ "$ENABLE_AFL_TMIN" = "1" ]; then
  echo "Running afl-tmin for further minimization..."
  # Further minimize each seed with afl-tmin
  for seed in "$CMIN_SEEDS_DIR"/*; do
    if [ -f "$seed" ]; then
      seed_name=$(basename "$seed")
      "$AFLPP/afl-tmin" -i "$seed" -o "$TMIN_SEEDS_DIR/$seed_name" -- "$TARGET_DIR/lua" @@
    fi
  done
else
  echo "Skipping afl-tmin minimization (set ENABLE_AFL_TMIN=1 to enable)"
  # Copy cmin results to tmin directory when not using afl-tmin
  cp "$CMIN_SEEDS_DIR"/* "$TMIN_SEEDS_DIR/"
fi
