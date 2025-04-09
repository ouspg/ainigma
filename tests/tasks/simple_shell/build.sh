#!/bin/sh

# Exit on fail
set -euo pipefail
echo "Building very simple bash script..."
# Use jq to extract each flag from JSON (assumes JSON field 'flags' is an array)
# Safe index when no batching
# Builder always provides the BUILD_MANIFEST
FLAG=$(jq -r '.flags[0].stage_flags[0].user_derived.suffix' "$BUILD_MANIFEST")
OUTPUT_DIR="$(jq -r '.out_dir' "$BUILD_MANIFEST")"

echo $OUTPUT_DIR > nice.txt

# Create the script
# OUTPUT_DIR is provided by the builder and we must use it
echo "${OUTPUT_DIR:-.}"
cat << EOF > $OUTPUT_DIR/secret.sh
#!/bin/bash

# The flag is now hardcoded in the script
FLAG="$FLAG"

echo "The flag is: \flag{$FLAG}"
EOF

# Make the inner script executable
chmod +x $OUTPUT_DIR/secret.sh

echo "Task script created successfully."

# Create also readme.txt for the challenge instruction
cat << EOF > $OUTPUT_DIR/readme.txt
You are given a bash script that prints the flag.
Your task is to find the flag in the script.
EOF
