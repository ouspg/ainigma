#!/bin/sh
# Script that uses batch build
#
#
set -e

# Extract the number of flags
FLAGS_COUNT=$(jq '.outputs | length' "$BUILD_MANIFEST")

# Iterate through the flags array by index
# shellcheck disable=SC2004
for i in $(seq 0 $(($FLAGS_COUNT - 1))); do
    # Extract the flag value and uuid from each object in the flags array
    flag=$(jq -r ".outputs[$i].flag" "$BUILD_MANIFEST")
    OUTPUT_DIR=$(jq -r ".outputs[$i].task_instance_dir" "$BUILD_MANIFEST")
    export OUTPUT_DIR # Needed for clang
    # echo "OUTPUT_DIR=$OUTPUT_DIR" > "debug_$(date +%s)_$RANDOM.txt"

    # Create a directory using the extracted uuid
    SECRET_KEY="1234567890ABCDEF"

    echo "Building the C++ reversing task in directory: $OUTPUT_DIR"
    clang++ -DMY_SECRET_KEY="\"$SECRET_KEY\"" -o "${OUTPUT_DIR}/reversable.bin" source.cpp
    chmod +x "${OUTPUT_DIR}/reversable.bin"
    "${OUTPUT_DIR}/reversable.bin" "flag{${flag}}"
    # Create a readme.txt file in the output dir
    cat << EOF > "${OUTPUT_DIR}/readme.txt"
You are given a binary file that encrypts the flag with a simple algorithm.
Your task is to reverse the algorithm in order to find a key and logic and then decrypt the flag.
The flag is located in the 'encrypted_output.txt' file.
You will know when you find the flag.
EOF

    echo "Task built successfully in $OUTPUT_DIR!"
done
