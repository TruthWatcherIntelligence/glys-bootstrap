#!/usr/bin/env bash
# Verifies all four prereqs installed correctly. Run AFTER install.sh.
set -euo pipefail

errors=0

check_tool() {
    local name="$1" cmd="$2" pattern="$3"
    if out=$("$cmd" --version 2>&1); then
        if echo "$out" | grep -qE "$pattern"; then
            echo "[PASS] $name: $out"
        else
            echo "[FAIL] $name: unexpected: $out"
            errors=$((errors+1))
        fi
    else
        echo "[FAIL] $name: command failed"
        errors=$((errors+1))
    fi
}

check_tool "Python"     "python3" "Python 3\.(1[0-9]|[2-9][0-9])"
check_tool "Claude Code" "claude" "[0-9]+\.[0-9]+"
check_tool "Git"        "git"    "git version"

if [ -d "/Applications/Google Chrome.app" ]; then
    echo "[PASS] Chrome: /Applications/Google Chrome.app present"
else
    echo "[WARN] Chrome not found (optional)"
fi

echo ""
if [ $errors -gt 0 ]; then
    echo "$errors check(s) failed."
    exit 1
else
    echo "All checks passed."
    exit 0
fi
