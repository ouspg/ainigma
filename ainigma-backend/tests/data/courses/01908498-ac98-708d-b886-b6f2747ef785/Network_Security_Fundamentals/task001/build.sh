#!/bin/sh
echo "PWD: $(pwd)"
set -e

FLAG=$(jq -r '.outputs[0].stage_flags[0].user_derived.suffix' "$BUILD_MANIFEST")
OUTPUT_DIR=$(jq -r '.outputs[0].task_instance_dir' "$BUILD_MANIFEST")

cat << EOF > "$OUTPUT_DIR/secret.sh"
#!/bin/bash
FLAG="$FLAG"
echo "Flag: \\flag{\$FLAG}"
EOF

chmod +x "$OUTPUT_DIR/secret.sh"

cat << EOF > "$OUTPUT_DIR/readme.txt"
This is a test task that includes a flag script.
EOF