#!/bin/sh

# This buildfile assumes sequential build

# Exit on fail
set -e
echo "Building very simple bash script..."
# Use jq to extract each flag from JSON (assumes JSON field 'flags' is an array)
# Safe index when no batching
# Builder always provides the BUILD_MANIFEST

# Check if BUILD_MANIFEST is set
if [ -z "$BUILD_MANIFEST" ]; then
    echo "Error: BUILD_MANIFEST environment variable is not set"
    exit 1
fi

# Extract values from BUILD_MANIFEST
FLAG=$(jq -r '.outputs[0].stage_flags[0].user_derived.suffix' "$BUILD_MANIFEST")
OUTPUT_DIR=$(jq -r '.outputs[0].task_instance_dir' "$BUILD_MANIFEST")

# echo "OUTPUT_DIR=$OUTPUT_DIR" > "debug_$(date +%s)_$RANDOM.txt"

# Create the script
echo "Creating script in $OUTPUT_DIR/secret.sh"
cat << EOF > "$OUTPUT_DIR/secret.sh"
#!/bin/bash

# The flag is now hardcoded in the script
FLAG="$FLAG"

echo "The flag is: \\flag{$FLAG}"
EOF

chmod +x "$OUTPUT_DIR/secret.sh"

echo "Task script created successfully."
echo "Creating readme in $OUTPUT_DIR/readme.txt"

cat << EOF > "$OUTPUT_DIR/readme.txt"
You are given a bash script that prints the flag.
Your task is to find the flag in the script.
EOF
