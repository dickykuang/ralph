#!/bin/bash

set -euo pipefail

PLATFORM="${1:-claude}"
CLAUDE_TARGET_DIR="$HOME/.claude/commands"
CODEX_TARGET_DIR="$HOME/.codex/skills"
CLAUDE_COMMANDS=("ralph.md" "ralph-start.md" "ralph-reset.md" "ralph-retro.md")
CODEX_SKILLS=("ralph" "ralph-start" "ralph-reset" "ralph-retro")

print_usage() {
    echo "Usage: $0 [claude|codex]"
    echo "  claude (default): remove Ralph command files from ~/.claude/commands"
    echo "  codex:            remove Ralph skill folders from ~/.codex/skills"
}

echo "Ralph Uninstaller"
echo "================="
echo ""

case "$PLATFORM" in
    claude)
        TARGET_DIR="$CLAUDE_TARGET_DIR"

        if [ ! -d "$TARGET_DIR" ]; then
            echo "No commands directory found at $TARGET_DIR"
            echo "Nothing to uninstall."
            exit 0
        fi

        files_to_remove=()
        for cmd in "${CLAUDE_COMMANDS[@]}"; do
            if [ -f "$TARGET_DIR/$cmd" ]; then
                files_to_remove+=("$cmd")
            fi
        done

        if [ "${#files_to_remove[@]}" -eq 0 ]; then
            echo "No Ralph command files found in $TARGET_DIR"
            echo "Nothing to uninstall."
            exit 0
        fi

        echo "The following files will be removed from $TARGET_DIR:"
        for f in "${files_to_remove[@]}"; do
            echo "  - $f"
        done
        echo ""

        read -p "Proceed with uninstall? (y/N): " response < /dev/tty || response=""
        case "$response" in
            [yY][eE][sS]|[yY])
                ;;
            *)
                echo "Uninstall cancelled."
                exit 0
                ;;
        esac

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
        echo "  Target: Claude"
        echo "  Removed: $removed"
        if [ "$failed" -gt 0 ]; then
            echo "  Failed: $failed"
        fi
        echo ""
        echo "Ralph Claude commands have been removed."
        ;;

    codex)
        TARGET_DIR="$CODEX_TARGET_DIR"

        if [ ! -d "$TARGET_DIR" ]; then
            echo "No skills directory found at $TARGET_DIR"
            echo "Nothing to uninstall."
            exit 0
        fi

        dirs_to_remove=()
        for skill in "${CODEX_SKILLS[@]}"; do
            if [ -d "$TARGET_DIR/$skill" ]; then
                dirs_to_remove+=("$skill")
            fi
        done

        if [ "${#dirs_to_remove[@]}" -eq 0 ]; then
            echo "No Ralph skill directories found in $TARGET_DIR"
            echo "Nothing to uninstall."
            exit 0
        fi

        echo "The following skill directories will be removed from $TARGET_DIR:"
        for d in "${dirs_to_remove[@]}"; do
            echo "  - $d/"
        done
        echo ""

        read -p "Proceed with uninstall? (y/N): " response < /dev/tty || response=""
        case "$response" in
            [yY][eE][sS]|[yY])
                ;;
            *)
                echo "Uninstall cancelled."
                exit 0
                ;;
        esac

        removed=0
        failed=0

        for skill in "${dirs_to_remove[@]}"; do
            target="$TARGET_DIR/$skill"
            if rm -rf "$target" 2>/dev/null; then
                echo "Removed: $skill/"
                removed=$((removed + 1))
            else
                echo "Failed to remove: $skill/"
                failed=$((failed + 1))
            fi
        done

        echo ""
        echo "================="
        echo "Uninstall complete!"
        echo "  Target: Codex"
        echo "  Removed: $removed"
        if [ "$failed" -gt 0 ]; then
            echo "  Failed: $failed"
        fi
        echo ""
        echo "Ralph Codex skills have been removed."
        ;;

    -h|--help|help)
        print_usage
        ;;

    *)
        echo "Error: Invalid platform '$PLATFORM'"
        echo ""
        print_usage
        exit 1
        ;;
esac
