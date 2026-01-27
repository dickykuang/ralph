#!/bin/bash

# Ralph Uninstaller
# Removes Ralph slash commands from ~/.claude/commands/

TARGET_DIR="$HOME/.claude/commands"

COMMANDS=("ralph.md" "ralph-start.md" "ralph-reset.md")

echo "Ralph Uninstaller"
echo "================="
echo ""

# Check if target directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "No commands directory found at $TARGET_DIR"
    echo "Nothing to uninstall."
    exit 0
fi

# Check which files exist
files_to_remove=()
for cmd in "${COMMANDS[@]}"; do
    if [ -f "$TARGET_DIR/$cmd" ]; then
        files_to_remove+=("$cmd")
    fi
done

if [ ${#files_to_remove[@]} -eq 0 ]; then
    echo "No Ralph command files found in $TARGET_DIR"
    echo "Nothing to uninstall."
    exit 0
fi

# Show what will be removed
echo "The following files will be removed from $TARGET_DIR:"
for f in "${files_to_remove[@]}"; do
    echo "  - $f"
done
echo ""

# Confirm before deletion
read -p "Proceed with uninstall? (y/N): " response < /dev/tty || response=""
case "$response" in
    [yY][eE][sS]|[yY])
        ;;
    *)
        echo "Uninstall cancelled."
        exit 0
        ;;
esac

# Remove files
removed=0
failed=0

for cmd in "${files_to_remove[@]}"; do
    target="$TARGET_DIR/$cmd"
    if rm "$target" 2>/dev/null; then
        echo "Removed: $cmd"
        removed=$((removed + 1))
    else
        echo "Failed to remove: $cmd"
        failed=$((failed + 1))
    fi
done

echo ""
echo "================="
echo "Uninstall complete!"
echo "  Removed: $removed"
if [ $failed -gt 0 ]; then
    echo "  Failed: $failed"
fi
echo ""
echo "Ralph commands have been removed."
