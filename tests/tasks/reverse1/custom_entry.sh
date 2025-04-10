#!/bin/sh
# Script that uses batch build
#
#
set -e

# Use jq to extract each flag item from JSON (assumes JSON field 'flags' is an array of objects)
# Builder always provides the BUILD_MANIFEST
OUTPUT_DIR="$(jq -r '.out_dir' "$BUILD_MANIFEST")"
TASK_ID="$(jq -r '.task.id' "$BUILD_MANIFEST")"

# Extract the number of flags
FLAGS_COUNT=$(jq '.outputs | length' "$BUILD_MANIFEST")

# Iterate through the flags array by index
for i in $(seq 0 $(($FLAGS_COUNT - 1))); do
    # Extract the flag value and uuid from each object in the flags array
    flag=$(jq -r ".outputs[$i].flag" "$BUILD_MANIFEST")
    uuid=$(jq -r ".outputs[$i].uuid" "$BUILD_MANIFEST")

    # Create a directory using the extracted uuid
    OUT_DIR="${OUTPUT_DIR}/${uuid}/${TASK_ID}"
    mkdir -p "$OUT_DIR"
    SECRET_KEY="1234567890ABCDEF"

    echo "Building the C++ reversing task in directory: $OUT_DIR"
    clang++ -DMY_SECRET_KEY="\"$SECRET_KEY\"" -o "${OUT_DIR}/reversable.bin" source.cpp
    chmod +x "${OUT_DIR}/reversable.bin"
    "${OUT_DIR}/reversable.bin" "flag{${flag}}"
    # Create a readme.txt file in the output dir
    cat << EOF > "${OUT_DIR}/readme.txt"
You are given a binary file that encrypts the flag with a simple algorithm.
Your task is to reverse the algorithm in order to find a key and logic and then decrypt the flag.
The flag is located in the 'encrypted_output.txt' file.
You will know when you find the flag.
EOF

    echo "Task built successfully in $OUT_DIR!"
done
