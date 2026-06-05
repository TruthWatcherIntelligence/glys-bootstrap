#!/usr/bin/env bash
# Glys Bootstrap Installer for macOS.
# Installs Python 3.12, Claude Code, Git, and (optionally) Google Chrome.
# All installs are idempotent; re-running is safe.
#
# Usage:
#   ./install.sh [--skip-chrome] [--non-interactive]
#
# Exit codes:
#   0 - All required tools present or installed
#   1 - User declined or root check failed
#   2 - Critical failure (Python or Claude Code absent after install)
#   3 - Partial failure (Git and/or Chrome absent after install)

set -euo pipefail

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------

SKIP_CHROME=0
NON_INTERACTIVE=0

for arg in "$@"; do
    case "$arg" in
        --skip-chrome)      SKIP_CHROME=1 ;;
        --non-interactive)  NON_INTERACTIVE=1 ;;
        *)
            echo "Unknown flag: $arg" >&2
            echo "Usage: $0 [--skip-chrome] [--non-interactive]" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Color helpers (degrade gracefully if tput is absent)
# ---------------------------------------------------------------------------

if command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
    C_CYAN="$(tput setaf 6)"
    C_GREEN="$(tput setaf 2)"
    C_YELLOW="$(tput setaf 3)"
    C_RED="$(tput setaf 1)"
    C_RESET="$(tput sgr0)"
else
    C_CYAN="" C_GREEN="" C_YELLOW="" C_RED="" C_RESET=""
fi

write_banner() {
    echo ""
    echo "${C_CYAN}============================================================${C_RESET}"
    echo "${C_CYAN}  $1${C_RESET}"
    echo "${C_CYAN}============================================================${C_RESET}"
    echo ""
}

write_step()  { echo "${C_CYAN}[>>]${C_RESET} $1"; }
write_pass()  { echo "${C_GREEN}[OK]${C_RESET} $1"; }
write_warn()  { echo "${C_YELLOW}[!!]${C_RESET} $1"; }
write_fail()  { echo "${C_RED}[FAIL]${C_RESET} $1"; }

# ---------------------------------------------------------------------------
# Prompt helper
# ---------------------------------------------------------------------------

prompt_yn() {
    local question="$1"
    local default_yes="${2:-1}"
    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        return "$default_yes"
    fi
    local hint
    hint=$([ "$default_yes" -eq 1 ] && echo "[Y/n]" || echo "[y/N]")
    read -r -p "$question $hint: " response
    response="${response:-}"
    if [ -z "$response" ]; then
        return "$default_yes"
    fi
    echo "$response" | grep -qiE "^y" && return 0 || return 1
}

# ---------------------------------------------------------------------------
# Hard stop for root (Homebrew refuses root)
# ---------------------------------------------------------------------------

if [ "$(id -u)" -eq 0 ]; then
    write_warn "Running as root. Homebrew refuses to install as root."
    write_warn "Re-run without sudo: ./install.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Banner
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"
VERSION="unknown"
if [ -f "$VERSION_FILE" ]; then
    VERSION="$(cat "$VERSION_FILE" | tr -d '[:space:]')"
fi
write_banner "Glys Bootstrap v$VERSION"

# ---------------------------------------------------------------------------
# Step 2: Detect Homebrew
# ---------------------------------------------------------------------------

BREW_CMD=""
for brew_path in "$(command -v brew 2>/dev/null || true)" "/opt/homebrew/bin/brew" "/usr/local/bin/brew"; do
    if [ -n "$brew_path" ] && [ -x "$brew_path" ]; then
        BREW_CMD="$brew_path"
        break
    fi
done

if [ -z "$BREW_CMD" ]; then
    write_warn "Homebrew not found. Installing..."
    write_warn "Homebrew installation will prompt for your Mac login password."
    write_warn "This is normal. Type your password (characters won't appear) and press Enter."
    echo ""
    if [ "$NON_INTERACTIVE" -eq 0 ]; then
        read -r -p "Press Enter to continue..."
    fi
    echo ""
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Source shellenv for the new Homebrew install.
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        BREW_CMD="/opt/homebrew/bin/brew"
    elif [ -f "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
        BREW_CMD="/usr/local/bin/brew"
    fi
    if [ -z "$BREW_CMD" ]; then
        write_fail "Homebrew install succeeded but brew binary not found at expected paths."
        write_fail "Close this terminal, open a new one, and re-run the installer."
        exit 2
    fi
else
    # Source shellenv so Homebrew-managed paths are available in this session.
    eval "$("$BREW_CMD" shellenv)"
fi

write_pass "Homebrew: $BREW_CMD"

# ---------------------------------------------------------------------------
# Step 3: Detect Python
# ---------------------------------------------------------------------------

FOUND_PYTHON=0
PYTHON_VERSION=""

detect_python() {
    # Prefer Homebrew Python so we avoid the macOS /usr/bin/python3 Xcode stub
    # (returns Python 3.9 and prompts for Xcode CLT install).
    local brew_python
    brew_python="$("$BREW_CMD" --prefix 2>/dev/null)/bin/python3"
    for py_cmd in "$brew_python" "python3" "python"; do
        if command -v "$py_cmd" >/dev/null 2>&1 || [ -x "$py_cmd" ]; then
            local ver
            ver=$("$py_cmd" --version 2>&1 || true)
            if echo "$ver" | grep -qE "Python ([0-9]+)\.([0-9]+)"; then
                local major minor
                major=$(echo "$ver" | grep -oE "Python [0-9]+" | grep -oE "[0-9]+")
                minor=$(echo "$ver" | grep -oE "Python [0-9]+\.[0-9]+" | grep -oE "\.[0-9]+" | tr -d '.')
                if [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 10 ]; }; then
                    FOUND_PYTHON=1
                    PYTHON_VERSION="$major.$minor"
                    return
                else
                    write_warn "Found Python $major.$minor via '$py_cmd'; need 3.10+. Will install 3.12."
                fi
            fi
        fi
    done
    FOUND_PYTHON=0
}

write_step "Checking Python..."
detect_python
if [ "$FOUND_PYTHON" -eq 1 ]; then
    write_pass "Python $PYTHON_VERSION found."
else
    write_warn "Python 3.10+ not found."
fi

# ---------------------------------------------------------------------------
# Step 4: Detect Claude Code
# ---------------------------------------------------------------------------

write_step "Checking Claude Code..."
FOUND_CLAUDE=0
if [ -x "$HOME/.local/bin/claude" ]; then
    FOUND_CLAUDE=1
elif command -v claude >/dev/null 2>&1; then
    FOUND_CLAUDE=1
fi
[ "$FOUND_CLAUDE" -eq 1 ] && write_pass "Claude Code found." || write_warn "Claude Code not found."

# ---------------------------------------------------------------------------
# Step 5: Detect Git (handle macOS Xcode CLT stub)
# ---------------------------------------------------------------------------

write_step "Checking Git..."
FOUND_GIT=0
if command -v git >/dev/null 2>&1; then
    if git --version >/dev/null 2>&1; then
        FOUND_GIT=1
        write_pass "Git found: $(git --version)"
    else
        write_warn "Found git stub but invoking it triggers Xcode CLT install prompt."
    fi
else
    write_warn "Git not found."
fi

# ---------------------------------------------------------------------------
# Step 6: Detect Chrome
# ---------------------------------------------------------------------------

write_step "Checking Chrome..."
FOUND_CHROME=0
if [ -d "/Applications/Google Chrome.app" ]; then
    FOUND_CHROME=1
fi
if [ "$FOUND_CHROME" -eq 1 ]; then
    write_pass "Google Chrome found."
elif [ "$SKIP_CHROME" -eq 1 ]; then
    write_warn "Chrome check skipped (--skip-chrome)."
else
    write_warn "Google Chrome not found."
fi

echo ""

# ---------------------------------------------------------------------------
# Step 7: Idempotency check
# ---------------------------------------------------------------------------

CHROME_REQUIRED=1
[ "$SKIP_CHROME" -eq 1 ] && CHROME_REQUIRED=0

ALL_PRESENT=0
if [ "$FOUND_PYTHON" -eq 1 ] && [ "$FOUND_CLAUDE" -eq 1 ] && [ "$FOUND_GIT" -eq 1 ]; then
    if [ "$CHROME_REQUIRED" -eq 0 ] || [ "$FOUND_CHROME" -eq 1 ]; then
        ALL_PRESENT=1
    fi
fi

if [ "$ALL_PRESENT" -eq 1 ]; then
    write_pass "All prerequisites are already installed."
    echo ""
    echo "${C_CYAN}Next: open a new terminal window and run:${C_RESET}"
    echo "    claude"
    echo ""
    echo "${C_CYAN}Then inside Claude Code:${C_RESET}"
    echo "    /plugin marketplace add TruthWatcherIntelligence/glys"
    echo ""
    exit 0
fi

# ---------------------------------------------------------------------------
# Step 8: Confirmation prompt
# ---------------------------------------------------------------------------

echo "${C_CYAN}The following will happen:${C_RESET}"
if [ "$FOUND_PYTHON" -eq 1 ]; then
    echo "  [x] Python 3.12      already installed (Python $PYTHON_VERSION)"
else
    echo "  [ ] Python 3.12      will be installed"
fi
if [ "$FOUND_CLAUDE" -eq 1 ]; then
    echo "  [x] Claude Code      already installed"
else
    echo "  [ ] Claude Code      will be installed"
fi
if [ "$FOUND_GIT" -eq 1 ]; then
    echo "  [x] Git              already installed ($(git --version 2>/dev/null || echo 'found'))"
else
    echo "  [ ] Git              will be installed"
fi
if [ "$SKIP_CHROME" -eq 1 ]; then
    echo "  [-] Chrome           skipped (--skip-chrome)"
elif [ "$FOUND_CHROME" -eq 1 ]; then
    echo "  [x] Chrome           already installed"
else
    echo "  [ ] Chrome           will be installed (optional)"
fi
echo ""
echo "Disk: ~500 MB. Time: 3-10 minutes."
echo ""

if ! prompt_yn "Proceed with install?" 1; then
    echo "Cancelled."
    exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Step 9: Install Python
# ---------------------------------------------------------------------------

PYTHON_INSTALL_FAILED=0

if [ "$FOUND_PYTHON" -eq 0 ]; then
    write_step "Installing Python 3.12 via Homebrew..."
    if "$BREW_CMD" install python@3.12; then
        write_step "Refreshing PATH..."
        export PATH="$("$BREW_CMD" --prefix)/bin:$HOME/.local/bin:$PATH"
        write_pass "Python 3.12 installed."
    else
        write_fail "Python install failed."
        PYTHON_INSTALL_FAILED=1
    fi
    write_step "Refreshing PATH..."
    export PATH="$("$BREW_CMD" --prefix)/bin:$HOME/.local/bin:$PATH"
fi

# ---------------------------------------------------------------------------
# Step 10: Install Claude Code
# ---------------------------------------------------------------------------

CLAUDE_INSTALL_FAILED=0

if [ "$FOUND_CLAUDE" -eq 0 ]; then
    write_step "Installing Claude Code..."
    INSTALLED_CLAUDE=0

    TMP_INSTALLER=$(mktemp /tmp/claude_install.XXXXXX.sh)
    # shellcheck disable=SC2064
    trap "rm -f '$TMP_INSTALLER'" EXIT
    if curl -fsSL https://claude.ai/install.sh -o "$TMP_INSTALLER" && bash "$TMP_INSTALLER"; then
        write_pass "Claude Code installed"
        export PATH="$HOME/.local/bin:$PATH"
        INSTALLED_CLAUDE=1
    else
        write_warn "Anthropic installer failed; attempting npm fallback"
        rm -f "$TMP_INSTALLER"
    fi

    if [ "$INSTALLED_CLAUDE" -eq 0 ]; then
        if command -v npm >/dev/null 2>&1; then
            if npm install -g "@anthropic-ai/claude-code"; then
                INSTALLED_CLAUDE=1
            else
                write_fail "npm fallback failed."
            fi
        else
            write_warn "npm not found; cannot use npm fallback."
        fi
    fi

    if [ "$INSTALLED_CLAUDE" -eq 0 ]; then
        write_fail "Claude Code could not be installed."
        CLAUDE_INSTALL_FAILED=1
    fi

    write_step "Refreshing PATH..."
    export PATH="$HOME/.local/bin:$PATH"
fi

# ---------------------------------------------------------------------------
# Step 11: Install Git
# ---------------------------------------------------------------------------

GIT_INSTALL_FAILED=0

if [ "$FOUND_GIT" -eq 0 ]; then
    write_step "Installing Git..."
    if [ -n "$BREW_CMD" ]; then
        if "$BREW_CMD" install git; then
            write_step "Refreshing PATH..."
            export PATH="$("$BREW_CMD" --prefix)/bin:$HOME/.local/bin:$PATH"
            write_pass "Git installed."
        else
            write_fail "Homebrew git install failed."
            GIT_INSTALL_FAILED=1
        fi
    else
        write_warn "Homebrew not available; falling back to Xcode Command Line Tools."
        write_warn "A dialog box will appear asking you to install Command Line Developer Tools."
        write_warn "Click Install in the dialog. After the install completes, re-run this script."
        xcode-select --install 2>/dev/null || true
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Step 12: Install Chrome (optional)
# ---------------------------------------------------------------------------

CHROME_INSTALL_FAILED=0

if [ "$FOUND_CHROME" -eq 0 ] && [ "$SKIP_CHROME" -eq 0 ]; then
    echo ""
    if prompt_yn "Install Google Chrome?" 1; then
        write_step "Installing Google Chrome via Homebrew cask..."
        if "$BREW_CMD" install --cask google-chrome; then
            write_pass "Google Chrome installed."
        else
            write_warn "Chrome install failed (non-fatal)."
            CHROME_INSTALL_FAILED=1
        fi
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Step 13: Verify
# ---------------------------------------------------------------------------

write_step "Verifying installations..."
export PATH="$("$BREW_CMD" --prefix)/bin:$HOME/.local/bin:$PATH"

detect_python
POST_PYTHON=$FOUND_PYTHON

POST_CLAUDE=0
if [ -x "$HOME/.local/bin/claude" ]; then
    POST_CLAUDE=1
elif command -v claude >/dev/null 2>&1; then
    POST_CLAUDE=1
fi

POST_GIT=0
if command -v git >/dev/null 2>&1; then
    if git --version >/dev/null 2>&1; then
        POST_GIT=1
    fi
fi

POST_CHROME=0
[ -d "/Applications/Google Chrome.app" ] && POST_CHROME=1

echo ""
echo "${C_CYAN}Results:${C_RESET}"

if [ "$POST_PYTHON" -eq 1 ]; then
    write_pass "Python $PYTHON_VERSION"
else
    write_fail "Python - not found after install"
fi

if [ "$POST_CLAUDE" -eq 1 ]; then
    write_pass "Claude Code"
else
    write_fail "Claude Code - not found after install"
fi

if [ "$POST_GIT" -eq 1 ]; then
    write_pass "Git"
else
    write_fail "Git - not found after install"
fi

if [ "$SKIP_CHROME" -eq 1 ]; then
    echo "[-] Chrome - skipped"
elif [ "$POST_CHROME" -eq 1 ]; then
    write_pass "Chrome"
else
    write_warn "Chrome - not found (non-fatal)"
fi

echo ""

# ---------------------------------------------------------------------------
# PATH persistence note
# ---------------------------------------------------------------------------

echo "${C_YELLOW}NOTE: PATH changes apply only to this terminal session.${C_RESET}"
echo "To make them permanent, add these lines to ~/.zshrc (or ~/.bash_profile):"
echo ""
echo "    eval \"\$($BREW_CMD shellenv)\""
echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""

# ---------------------------------------------------------------------------
# Step 14: Next-step instructions
# ---------------------------------------------------------------------------

CRITICAL_FAILED=0
PARTIAL_FAILED=0

if [ "$POST_PYTHON" -eq 0 ] || [ "$POST_CLAUDE" -eq 0 ]; then
    CRITICAL_FAILED=1
fi
if [ "$POST_GIT" -eq 0 ]; then
    PARTIAL_FAILED=1
fi
if [ "$SKIP_CHROME" -eq 0 ] && [ "$POST_CHROME" -eq 0 ]; then
    PARTIAL_FAILED=1
fi

if [ "$CRITICAL_FAILED" -eq 1 ]; then
    write_fail "Critical tools missing. Check the errors above and re-run."
    echo ""
    echo "If the install keeps failing, see the manual install guide:"
    echo "    https://github.com/TruthWatcherIntelligence/glys-bootstrap#if-you-cant-run-the-bootstrap"
    echo ""
    exit 2
fi

echo "${C_GREEN}Setup complete.${C_RESET}"
echo ""
echo "${C_CYAN}Next: open a new terminal window and run:${C_RESET}"
echo "    claude"
echo ""
echo "${C_CYAN}Inside Claude Code:${C_RESET}"
echo "    /plugin marketplace add TruthWatcherIntelligence/glys"
echo ""

[ "$PARTIAL_FAILED" -eq 1 ] && exit 3 || exit 0
