#!/bin/bash
# Script to check the Maccy scroll debug log

LOG_FILE="/tmp/maccy_scroll_debug.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "❌ Log file not found at $LOG_FILE"
    echo "Make sure Maccy is running first!"
    exit 1
fi

echo "📝 Maccy Scroll Debug Log"
echo "========================="
echo ""
cat "$LOG_FILE"
echo ""
echo "========================="
echo "📍 Log location: $LOG_FILE"
echo "💡 Tip: Run 'tail -f $LOG_FILE' to watch in real-time"
