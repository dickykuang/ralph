#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM="${1:-claude}"

CLAUDE_DIR="$SCRIPT_DIR/claude"
CODEX_DIR="$SCRIPT_DIR/codex"
CLAUDE_COMMANDS=("ralph.md" "ralph-start.md" "ralph-reset.md" "ralph-retro.md")
CODEX_SKILLS=("ralph" "ralph-start" "ralph-reset" "ralph-retro")

print_usage() {
    echo "Usage: $0 [claude|codex]"
    echo "  claude (default): install markdown commands to ~/.claude/commands"
    echo "  codex:            install skills to ~/.codex/skills"
}

echo "Ralph Installer"
echo "==============="
echo ""

case "$PLATFORM" in
    claude)
        TARGET_DIR="$HOME/.claude/commands"

        if [ ! -d "$CLAUDE_DIR" ]; then
            echo "Error: Claude source directory not found at $CLAUDE_DIR"
            exit 1
        fi

        missing_files=()
        for cmd in "${CLAUDE_COMMANDS[@]}"; do
            if [ ! -f "$CLAUDE_DIR/$cmd" ]; then
                missing_files+=("$cmd")
            fi
        done

        if [ "${#missing_files[@]}" -gt 0 ]; then
            echo "Error: Missing Claude command files in $CLAUDE_DIR:"
            for f in "${missing_files[@]}"; do
                echo "  - $f"
            done
            exit 1
        fi

        if [ ! -d "$TARGET_DIR" ]; then
            echo "Creating $TARGET_DIR..."
            mkdir -p "$TARGET_DIR"
        fi

        installed=0
        skipped=0

        for cmd in "${CLAUDE_COMMANDS[@]}"; do
            src="$CLAUDE_DIR/$cmd"
            dst="$TARGET_DIR/$cmd"

            if [ -f "$dst" ]; then
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
        echo "  Target: Claude"
        echo "  Installed: $installed"
        echo "  Skipped: $skipped"
        echo ""
        echo "Ralph Claude commands are now available:"
        echo "  /ralph <task> - Start research and planning"
        echo "  /ralph-start  - Execute planned tasks"
        echo "  /ralph-reset  - Clear state and start fresh"
        echo "  /ralph-retro  - Review commits and request follow-up changes"
        ;;

    codex)
        TARGET_DIR="$HOME/.codex/skills"

        if [ ! -d "$CODEX_DIR" ]; then
            echo "Error: Codex source directory not found at $CODEX_DIR"
            exit 1
        fi

        missing_skills=()
        for skill in "${CODEX_SKILLS[@]}"; do
            if [ ! -f "$CODEX_DIR/$skill/SKILL.md" ]; then
                missing_skills+=("$skill")
            fi
        done

        if [ "${#missing_skills[@]}" -gt 0 ]; then
            echo "Error: Missing Codex skills in $CODEX_DIR:"
            for s in "${missing_skills[@]}"; do
                echo "  - $s (expected $CODEX_DIR/$s/SKILL.md)"
            done
            exit 1
        fi

        if [ ! -d "$TARGET_DIR" ]; then
            echo "Creating $TARGET_DIR..."
            mkdir -p "$TARGET_DIR"
        fi

        installed=0
        skipped=0

        for skill in "${CODEX_SKILLS[@]}"; do
            src="$CODEX_DIR/$skill"
            dst="$TARGET_DIR/$skill"

            if [ -d "$dst" ]; then
                echo ""
                echo "Skill already exists: $dst"
                read -p "Overwrite? (y/N): " response < /dev/tty || response=""
                case "$response" in
                    [yY][eE][sS]|[yY])
                        rm -rf "$dst"
                        cp -R "$src" "$dst"
                        echo "  Overwritten: $skill"
                        installed=$((installed + 1))
                        ;;
                    *)
                        echo "  Skipped: $skill"
                        skipped=$((skipped + 1))
                        ;;
                esac
            else
                cp -R "$src" "$dst"
                echo "Installed: $skill"
                installed=$((installed + 1))
            fi
        done

        echo ""
        echo "==============="
        echo "Installation complete!"
        echo "  Target: Codex"
        echo "  Installed: $installed"
        echo "  Skipped: $skipped"
        echo ""
        echo "Ralph Codex skills are now available:"
        echo "  ralph"
        echo "  ralph-start"
        echo "  ralph-reset"
        echo "  ralph-retro"
        echo ""
        echo "Restart Codex to pick up newly installed skills."
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
