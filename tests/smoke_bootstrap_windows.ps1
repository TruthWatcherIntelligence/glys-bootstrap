# Verifies all four prereqs installed correctly. Run AFTER install.ps1.
[CmdletBinding()]
param()

$errors = @()

function Check-Tool {
    param([string]$Name, [string]$Cmd, [string]$Pattern)
    try {
        $out = & $Cmd --version 2>&1
        if ($out -match $Pattern) {
            Write-Host "[PASS] ${Name}: $out" -ForegroundColor Green
        } else {
            $msg = "[FAIL] ${Name}: unexpected output: $out"
            $script:errors += $msg
            Write-Host $msg -ForegroundColor Red
        }
    } catch {
        $msg = "[FAIL] ${Name}: $_"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

Check-Tool "Python"     "python" "Python 3\.(1[0-9]|[2-9][0-9])"
Check-Tool "Claude Code" "claude" "\d+\.\d+"
Check-Tool "Git"        "git"    "git version"

# Chrome: path test (no --version available without launching the browser)
$chromePaths = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
$found = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($found) {
    Write-Host "[PASS] Chrome: found at $found" -ForegroundColor Green
} else {
    Write-Host "[WARN] Chrome not found (optional)" -ForegroundColor Yellow
}

Write-Host ""
if ($errors.Count -gt 0) {
    Write-Host "$($errors.Count) check(s) failed." -ForegroundColor Red
    exit 1
} else {
    Write-Host "All checks passed." -ForegroundColor Green
    exit 0
}
