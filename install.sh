#!/bin/bash

# Ralph Installer
# Copies Ralph slash commands to ~/.claude/commands/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$SCRIPT_DIR/commands"
TARGET_DIR="$HOME/.claude/commands"

COMMANDS=("ralph.md" "ralph-start.md" "ralph-reset.md")

echo "Ralph Installer"
echo "==============="
echo ""

# Check if source commands directory exists
if [ ! -d "$COMMANDS_DIR" ]; then
    echo "Error: Commands directory not found at $COMMANDS_DIR"
    echo "Please ensure the commands/ directory exists with ralph.md, ralph-start.md, and ralph-reset.md"
    exit 1
fi

# Check if all command files exist
missing_files=()
for cmd in "${COMMANDS[@]}"; do
    if [ ! -f "$COMMANDS_DIR/$cmd" ]; then
        missing_files+=("$cmd")
    fi
done

if [ ${#missing_files[@]} -gt 0 ]; then
    echo "Error: Missing command files in $COMMANDS_DIR:"
    for f in "${missing_files[@]}"; do
        echo "  - $f"
    done
    exit 1
fi

# Create target directory if it doesn't exist
if [ ! -d "$TARGET_DIR" ]; then
    echo "Creating $TARGET_DIR..."
    mkdir -p "$TARGET_DIR"
fi

# Copy each command file
installed=0
skipped=0

for cmd in "${COMMANDS[@]}"; do
    src="$COMMANDS_DIR/$cmd"
    dst="$TARGET_DIR/$cmd"

    if [ -f "$dst" ]; then
        # File exists, prompt before overwriting
        echo ""
        echo "File already exists: $dst"
        read -p "Overwrite? (y/N): " response < /dev/tty || response=""
        case "$response" in
            [yY][eE][sS]|[yY])
                cp "$src" "$dst"
                echo "  Overwritten: $cmd"
                installed=$((installed + 1))
                ;;
            *)
                echo "  Skipped: $cmd"
                skipped=$((skipped + 1))
                ;;
        esac
    else
        cp "$src" "$dst"
        echo "Installed: $cmd"
        installed=$((installed + 1))
    fi
done

echo ""
echo "==============="
echo "Installation complete!"
echo "  Installed: $installed"
echo "  Skipped: $skipped"
echo ""
echo "Ralph commands are now available:"
echo "  /ralph <task> - Start research and planning"
echo "  /ralph-start  - Execute planned tasks"
echo "  /ralph-reset  - Clear state and start fresh"
