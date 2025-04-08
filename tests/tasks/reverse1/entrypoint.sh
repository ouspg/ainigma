#!/bin/sh
# $OUTPUT_DIR from env. All the build artifacts should be placed here
# $FLAG_PURE_RANDOM_TASK001 from env (task number is task001 and appended to the env)
set -e

echo "Building the c++ reversing task..."

# SECRET_KEY="$(openssl rand -hex 16)"
SECRET_KEY="1234567890ABCDEF"

clang++ -DMY_SECRET_KEY="\"$SECRET_KEY\""  -o "${OUTPUT_DIR:-.}/reversable.bin" source.cpp
chmod +x "${OUTPUT_DIR:-.}/reversable.bin"

# Run the program to generate the encrypted flag

"${OUTPUT_DIR:-.}/reversable.bin" "flag{${FLAG_USER_DERIVED_TASK001:-this_is_a_fake_flag}}"

cat << EOF > "${OUTPUT_DIR:-.}/readme.txt"
You are given a binary file that encrypts the flag with a simple algorithm.
Your task is to reverse the algorithm in order to find a key and logic and then decrypt the flag.
The flag is located in the 'encrypted_output.txt' file.
You will know when you find the flag.
EOF

echo "Task built successfully!"
