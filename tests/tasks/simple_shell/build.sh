#!/bin/sh

# Exit on fail
set -e

echo "Building very simple bash script..."

# Create the script
# OUTPUT_DIR is provided by the builder and we must use it
echo "${OUTPUT_DIR:-.}"
cat << EOF > $OUTPUT_DIR/secret.sh
#!/bin/bash

# The flag is now hardcoded in the script
FLAG="$FLAG_PURE_RANDOM_task005"

echo "The flag is: \$FLAG"
EOF

# Make the inner script executable
chmod +x $OUTPUT_DIR/secret.sh

echo "Task script created successfully."

# Create also readme.txt for the challenge instruction
cat << EOF > $OUTPUT_DIR/readme.txt
You are given a bash script that prints the flag.
Your task is to find the flag in the script.
EOF
