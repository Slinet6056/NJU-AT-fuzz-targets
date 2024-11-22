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
TARGET="cxxfilt"
TARGET_DIR="$BENCH_DIR/$TARGET"
# Refresh
if [ -d "$TARGET_DIR" ]; then
  rm -rf "$TARGET_DIR"
fi
mkdir -p "$TARGET_DIR"
mv "$SUBJECT_DIR/binutils/cxxfilt" "$TARGET_DIR" || mv "$SUBJECT_DIR/binutils/.libs/cxxfilt" "$TARGET_DIR"

# Create and prepare seeds directories
SEEDS_BASE_DIR="$TARGET_DIR/seeds"
RAW_SEEDS_DIR="$SEEDS_BASE_DIR/raw"
CMIN_SEEDS_DIR="$SEEDS_BASE_DIR/cmin"
TMIN_SEEDS_DIR="$SEEDS_BASE_DIR/tmin"

mkdir -p "$RAW_SEEDS_DIR"
mkdir -p "$CMIN_SEEDS_DIR"
mkdir -p "$TMIN_SEEDS_DIR"

# Generate initial seeds
echo "_Z1fv" >"$RAW_SEEDS_DIR/seed1"
echo "_ZN3std6vectorI4ItemSaIS0_EE9push_backERKS0_" >"$RAW_SEEDS_DIR/seed2"
echo "_ZNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEED1Ev" >"$RAW_SEEDS_DIR/seed3"
echo "_ZNSt6thread11_State_implINS_8_InvokerISt5tupleIJZZN8TestCase7runImplIJZN13SeqCstAcqRel23runEvEUlvE_ZNS5_3runEvEUlvE0_EEE10TestResultDpT_ENKUlT_E_clIS7_EEDaS9_EUlvE_EEEEEE6_M_runEv" >"$RAW_SEEDS_DIR/seed4"

# Check if AFL_USE_TMIN is set and equals "1"
AFL_USE_TMIN=${AFL_USE_TMIN:-0}

# Run afl-cmin to minimize the test corpus
"$AFLPP/afl-cmin" -i "$RAW_SEEDS_DIR" -o "$CMIN_SEEDS_DIR" -- "$TARGET_DIR/cxxfilt"

if [ "$AFL_USE_TMIN" = "1" ]; then
  echo "Running afl-tmin for further minimization..."
  # Further minimize each seed with afl-tmin
  for seed in "$CMIN_SEEDS_DIR"/*; do
    if [ -f "$seed" ]; then
      seed_name=$(basename "$seed")
      "$AFLPP/afl-tmin" -i "$seed" -o "$TMIN_SEEDS_DIR/$seed_name" -- "$TARGET_DIR/cxxfilt"
    fi
  done
else
  echo "Skipping afl-tmin minimization (set AFL_USE_TMIN=1 to enable)"
  # Copy cmin results to tmin directory when not using afl-tmin
  cp "$CMIN_SEEDS_DIR"/* "$TMIN_SEEDS_DIR/"
fi
