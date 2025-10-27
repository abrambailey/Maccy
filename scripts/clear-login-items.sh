#!/bin/bash

# Clear all Maccy login items before building
# This prevents duplicate login items when rebuilding the app

echo "Clearing Maccy login items..."

# Remove all Maccy entries from Background Task Management
sfltool dumpbtm | grep -i "maccy" | grep "Identifier:" | awk '{print $2}' | while read identifier; do
    echo "Removing login item: $identifier"
    sfltool remove-item "$identifier" 2>/dev/null || true
done

echo "Login items cleared."
