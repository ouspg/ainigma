#!/bin/sh

# Exit on fail
set -e 

echo "Building very simple bash script..."

# Create the script
cat << EOF > secret.sh
#!/bin/bash

# The flag is now hardcoded in the script
FLAG="$FLAG_PURE_RANDOM_task005"

echo "The flag is: \$FLAG"
EOF

# Make the inner script executable
chmod +x secret.sh

echo "Task script created successfully."

