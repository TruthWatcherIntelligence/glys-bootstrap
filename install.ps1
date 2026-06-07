<#
.SYNOPSIS
    Glys Bootstrap Installer for Windows.
.DESCRIPTION
    Installs Python 3.12, Claude Code, Git, and (optionally) Google Chrome.
    All installs are idempotent; re-running is safe.
.PARAMETER SkipChrome
    Skip the Chrome install step.
.PARAMETER NonInteractive
    Suppress all prompts; use defaults (proceed with all installs).
.NOTES
    Exit codes:
        0 - All required tools present or installed
        1 - User declined
        2 - Critical failure (Python or Claude Code absent after install)
        3 - Partial failure (Git and/or Chrome absent after install)
#>
[CmdletBinding()]
param(
    [switch]$SkipChrome,
    [switch]$NonInteractive
)

if ($PSVersionTable.PSVersion -lt [Version]'5.1') {
    Write-Host "PowerShell 5.1 or higher is required. Found $($PSVersionTable.PSVersion)." -ForegroundColor Red
    Write-Host "Upgrade PowerShell from https://aka.ms/PowerShell-Release" -ForegroundColor Yellow
    exit 1
}

$BOOTSTRAP_VERSION = "0.1.4"

# Force TLS 1.2 for all HTTPS calls. PowerShell 5.1 defaults to TLS 1.0/1.1 which
# GitHub API and many CDNs now reject. The buyer-facing one-liner sets this in
# the parent IEX scope; we set it again inside the script body so the policy
# holds regardless of how the script was invoked (direct file execution, .bat
# shim, in-script re-entry).
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

function Write-Banner {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host "[>>] $Text" -ForegroundColor White
}

function Write-Pass {
    param([string]$Text)
    Write-Host "[OK] $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "[!!] $Text" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Text)
    Write-Host "[FAIL] $Text" -ForegroundColor Red
}

function Prompt-YN {
    param(
        [string]$Question,
        [bool]$DefaultYes = $true
    )
    if ($NonInteractive) { return $DefaultYes }
    $hint = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    $response = Read-Host "$Question $hint"
    if ([string]::IsNullOrWhiteSpace($response)) { return $DefaultYes }
    return $response -match "^[Yy]"
}

function Refresh-EnvPath {
    # Re-read the machine and user PATH from the registry. Reassigning $env:Path
    # is what makes newly installed binaries discoverable in this session; the
    # registry values are updated by the .exe installers but $env:Path is only
    # a snapshot taken when PowerShell launched, so it needs an explicit refresh.
    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $combined    = "$machinePath;$userPath;$env:Path"

    # Dedupe so repeated in-session re-runs don't grow $env:Path unboundedly
    # toward the 32767-character Windows limit.
    $seen = @{}
    $deduped = @(
        foreach ($entry in ($combined -split ';')) {
            if ([string]::IsNullOrWhiteSpace($entry)) { continue }
            $key = $entry.TrimEnd('\').ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $entry
            }
        }
    )
    $env:Path = ($deduped -join ';')

    # Probe a few names so PowerShell's command discovery walks the new PATH
    # and primes the per-session resolution; harmless if any are absent.
    Get-Command python, py, git, claude, npm, node -All -ErrorAction SilentlyContinue | Out-Null
}

function Get-PythonVersion {
    <#
    Returns a version object if a real Python >= 3.10 is found on PATH,
    or $null if absent or only a Microsoft Store stub is present.
    Sets the caller-scope variable $script:msPythonWarning = $true when a stub
    is detected so the install step can print the right message.
    #>
    foreach ($cmd in @("python", "py")) {
        $exePath = $null
        try {
            $exePath = (Get-Command $cmd -ErrorAction SilentlyContinue).Source
        } catch { continue }
        if (-not $exePath) { continue }

        # Detect Microsoft Store redirect stub: some Store-installed Python binaries
        # redirect silently. Run with a 2-second timeout to verify.
        $isStub = $false
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $tmpErr = [System.IO.Path]::GetTempFileName()
        try {
            $proc = Start-Process -FilePath $exePath `
                -ArgumentList "--version" `
                -NoNewWindow -PassThru `
                -RedirectStandardOutput $tmpOut `
                -RedirectStandardError  $tmpErr
            if (-not $proc.WaitForExit(2000)) {
                $proc.Kill()
                $isStub = $true
            } elseif ($proc.ExitCode -ne 0) {
                $isStub = $true
            }
        } catch {
            $isStub = $true
        } finally {
            Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
        }

        if ($isStub) {
            $script:msPythonWarning = $true
            continue
        }

        # Real binary; check version.
        try {
            $versionLine = & $cmd --version 2>&1
            if ($versionLine -match "Python (\d+)\.(\d+)") {
                $major = [int]$Matches[1]
                $minor = [int]$Matches[2]
                if ($major -gt 3 -or ($major -eq 3 -and $minor -ge 10)) {
                    return [PSCustomObject]@{
                        Major   = $major
                        Minor   = $minor
                        Command = $cmd
                        Version = "$major.$minor"
                    }
                }
                Write-Warn "Found Python $major.$minor via '$cmd'; need 3.10+. Will install 3.12."
            }
        } catch {
            continue
        }
    }

    # Fallback: direct Test-Path check on the canonical install locations our
    # bootstrap places Python at. We only check amd64 paths because the script
    # installs python-3.12.10-amd64.exe; an x86 Python at the (x86) path would
    # be a pre-existing third-party install we did not place and should not
    # claim as our verify target.
    $canonicalPaths = @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:ProgramFiles\Python312\python.exe"
    )
    foreach ($p in $canonicalPaths) {
        if (Test-Path $p) {
            try {
                $versionLine = & $p --version 2>&1
                if ($versionLine -match "Python (\d+)\.(\d+)") {
                    $major = [int]$Matches[1]
                    $minor = [int]$Matches[2]
                    if ($major -gt 3 -or ($major -eq 3 -and $minor -ge 10)) {
                        return [PSCustomObject]@{
                            Major   = $major
                            Minor   = $minor
                            Command = $p
                            Version = "$major.$minor"
                        }
                    }
                }
            } catch { continue }
        }
    }
    return $null
}

function Test-ChromeInstalled {
    $paths = @(
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }
    return $false
}

function Test-ClaudeInstalled {
    if (Test-Path "$env:USERPROFILE\.local\bin\claude.exe") { return $true }
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    return ($null -ne $cmd)
}

function Test-GitInstalled {
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd) { return $true }
    # Fallback: filesystem check (PATH cache may not be refreshed)
    return (Test-Path "$env:ProgramFiles\Git\bin\git.exe") -or `
           (Test-Path "${env:ProgramFiles(x86)}\Git\bin\git.exe")
}

function Test-WingetAvailable {
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    return ($null -ne $cmd)
}

function Invoke-Download {
    <#
    Downloads a URL to a local temp file and returns the path.
    Uses BITS if available; falls back to WebClient.
    #>
    param([string]$Url, [string]$FileName)
    $dest = Join-Path $env:TEMP $FileName
    Write-Step "Downloading $FileName ..."
    try {
        Import-Module BitsTransfer -ErrorAction SilentlyContinue
        Start-BitsTransfer -Source $Url -Destination $dest -ErrorAction Stop
    } catch {
        (New-Object System.Net.WebClient).DownloadFile($Url, $dest)
    }
    return $dest
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$script:msPythonWarning = $false

# Step 1: Banner
Write-Banner "Glys Bootstrap v$BOOTSTRAP_VERSION"

# Step 2: Privilege detection
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warn "Running as Administrator."
    Write-Warn "winget per-user installs work best from a NON-admin PowerShell window."
    Write-Warn "Recommended: close this window, open a new (non-admin) PowerShell, and re-run."
    Write-Warn "Continuing anyway in 5 seconds (press Ctrl+C to abort)..."
    Start-Sleep -Seconds 5
    Write-Host ""
}

# Step 3: Detect Python
Write-Step "Checking Python..."
$pythonInfo = Get-PythonVersion
$hasPython  = ($null -ne $pythonInfo)
if ($hasPython) {
    Write-Pass "Python $($pythonInfo.Version) found."
} elseif ($script:msPythonWarning) {
    Write-Warn "Microsoft Store Python stub detected (no real Python runtime)."
} else {
    Write-Warn "Python not found."
}

# Step 4: Detect Claude Code
Write-Step "Checking Claude Code..."
$hasClaude = Test-ClaudeInstalled
if ($hasClaude) { Write-Pass "Claude Code found." } else { Write-Warn "Claude Code not found." }

# Step 5: Detect Git
Write-Step "Checking Git..."
$hasGit = Test-GitInstalled
if ($hasGit) { Write-Pass "Git found." } else { Write-Warn "Git not found." }

# Step 6: Detect Chrome
Write-Step "Checking Chrome..."
$hasChrome = Test-ChromeInstalled
if ($hasChrome)     { Write-Pass "Google Chrome found." }
elseif ($SkipChrome){ Write-Warn "Chrome check skipped (-SkipChrome)." }
else                { Write-Warn "Google Chrome not found." }

Write-Host ""

# Step 7: Idempotency check
$chromeRequired = -not $SkipChrome
$allPresent = $hasPython -and $hasClaude -and $hasGit -and (-not $chromeRequired -or $hasChrome)

if ($allPresent) {
    Write-Pass "All prerequisites are already installed."
    Write-Host ""
    Write-Host "Next: open a new terminal window and run:" -ForegroundColor Cyan
    Write-Host "    claude" -ForegroundColor White
    Write-Host ""
    Write-Host "Then inside Claude Code:" -ForegroundColor Cyan
    Write-Host "    /plugin marketplace add TruthWatcherIntelligence/glys" -ForegroundColor White
    Write-Host ""
    exit 0
}

# Step 8: Confirmation prompt
Write-Host "The following will happen:" -ForegroundColor Cyan
if ($hasPython)  { Write-Host "  [x] Python 3.12      already installed (Python $($pythonInfo.Version))" -ForegroundColor Green }
else             { Write-Host "  [ ] Python 3.12      will be installed" }
if ($hasClaude)  { Write-Host "  [x] Claude Code      already installed" -ForegroundColor Green }
else             { Write-Host "  [ ] Claude Code      will be installed" }
if ($hasGit)     { Write-Host "  [x] Git              already installed" -ForegroundColor Green }
else             { Write-Host "  [ ] Git              will be installed" }
if ($SkipChrome) { Write-Host "  [-] Chrome           skipped (-SkipChrome)" -ForegroundColor Gray }
elseif ($hasChrome) { Write-Host "  [x] Chrome           already installed" -ForegroundColor Green }
else             { Write-Host "  [ ] Chrome           will be installed (optional)" }
Write-Host ""
Write-Host "Disk: ~500 MB. Time: 3-10 minutes."
Write-Host ""

if (-not (Prompt-YN "Proceed with install?" $true)) {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# Step 9: winget availability
$hasWinget = Test-WingetAvailable
if (-not $hasWinget) {
    Write-Step "winget not found. Installing App Installer (winget) for cleaner Git and Chrome installs..."
    Write-Warn "This downloads ~80 MB. Falls back to direct downloads if install fails."

    try {
        # PID-suffixed temp dir so concurrent runs and stale-files-from-crashed-prior-runs
        # both work cleanly. Force-clean to remove any prior partial state.
        $wingetTmp = "$env:TEMP\glys-winget-bootstrap-$PID"
        if (Test-Path $wingetTmp) {
            Remove-Item -Recurse -Force $wingetTmp -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Force -Path $wingetTmp | Out-Null

        Write-Step "Downloading VCLibs dependency..."
        Invoke-WebRequest "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" `
            -OutFile "$wingetTmp\VCLibs.appx" -UseBasicParsing

        Write-Step "Downloading UI XAML dependency..."
        Invoke-WebRequest "https://github.com/microsoft/winget-cli/releases/download/v1.7.10661/Microsoft.UI.Xaml.2.8.x64.appx" `
            -OutFile "$wingetTmp\UIXaml.appx" -UseBasicParsing

        Write-Step "Resolving latest winget release..."
        $latestRelease = Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -UseBasicParsing
        $msixAsset = $latestRelease.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1
        if (-not $msixAsset) {
            throw "Could not find winget msixbundle in latest release"
        }
        Write-Step "Downloading winget $($latestRelease.tag_name)..."
        Invoke-WebRequest $msixAsset.browser_download_url -OutFile "$wingetTmp\winget.msixbundle" -UseBasicParsing

        Write-Step "Installing AppX packages..."
        Add-AppxPackage "$wingetTmp\VCLibs.appx" -ErrorAction Stop
        Add-AppxPackage "$wingetTmp\UIXaml.appx" -ErrorAction Stop
        Add-AppxPackage "$wingetTmp\winget.msixbundle" -ErrorAction Stop

        # Re-check after install
        Refresh-EnvPath
        $hasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
        if ($hasWinget) {
            Write-Pass "winget installed successfully."
        } else {
            Write-Warn "winget install completed but command not found on PATH."
            Write-Warn "Falling back to direct downloads."
        }
    } catch {
        # Surface targeted hint for GitHub API rate-limit (corporate NAT, rapid retries).
        $statusCode = $null
        try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($statusCode -eq 403) {
            Write-Warn "GitHub API rate limit hit (403). This usually clears in 60 minutes."
            Write-Warn "If you share an IP with many other developers (corporate NAT), this is the cause."
        }
        Write-Warn "winget auto-install failed: $_"
        Write-Warn "Falling back to direct downloads for Git and Chrome."
        $hasWinget = $false
    } finally {
        if (Test-Path $wingetTmp) {
            Remove-Item -Recurse -Force $wingetTmp -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Step 10: Install Python
# ---------------------------------------------------------------------------

$pythonInstallFailed = $false

if (-not $hasPython) {
    Write-Step "Installing Python 3.12..."

    if ($script:msPythonWarning) {
        Write-Warn "Microsoft Store Python detected. Installing python.org Python alongside."
        Write-Warn "After install, use 'py -3.12' to invoke the correct Python."
    }

    # Python is installed directly from python.org rather than via winget.
    # winget's Python.Python.3.12 package actually pulls from this same python.org URL,
    # but going direct avoids the winget abstraction (which is restricted on some
    # corporate machines) and removes any chance of buyer confusion with the
    # Microsoft Store Python package, which lacks FTS5 and breaks /user-osint.
    try {
        $pyUrl  = "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe"
        Write-Step "Downloading Python 3.12.10 directly from python.org..."
        $pyExe  = Invoke-Download -Url $pyUrl -FileName "python-3.12.10-amd64.exe"
        Write-Step "Running Python installer (quiet)..."
        $p = Start-Process -FilePath $pyExe `
            -ArgumentList "/quiet PrependPath=1 InstallAllUsers=0" `
            -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            throw "Python installer exited $($p.ExitCode)"
        }
        Remove-Item $pyExe -ErrorAction SilentlyContinue
    } catch {
        Write-Fail "Python install failed: $_"
        $pythonInstallFailed = $true
    }

    # Refresh so subsequent steps can find the new Python.
    Write-Step "Refreshing PATH..."
    Refresh-EnvPath
}

# ---------------------------------------------------------------------------
# Step 11: Install Git
# Git must be installed BEFORE Claude Code. Claude Code's installer requires
# Git for Windows (bash.exe) to be present; installing Claude first causes
# a clean-machine failure with "Claude Code on Windows requires Git for Windows."
# ---------------------------------------------------------------------------

$gitInstallFailed = $false

if (-not $hasGit) {
    Write-Step "Installing Git..."
    $installed = $false

    if ($hasWinget) {
        try {
            Write-Step "Trying winget for Git..."
            winget install Git.Git --silent --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) {
                throw "winget exited with code $LASTEXITCODE"
            }
            $installed = $true
        } catch {
            Write-Warn "winget install failed: $_"
        }
    }

    if (-not $installed) {
        try {
            $gitUrl  = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe"
            $gitExe  = Invoke-Download -Url $gitUrl -FileName "Git-2.47.1-64-bit.exe"
            Write-Step "Running Git installer (silent)..."
            $p = Start-Process -FilePath $gitExe `
                -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=`"icons,ext\reg\shellhere,assoc,assoc_sh`"" `
                -Wait -PassThru
            if ($p.ExitCode -ne 0) {
                throw "Git installer exited $($p.ExitCode)"
            }
            Remove-Item $gitExe -ErrorAction SilentlyContinue
            $installed = $true
        } catch {
            Write-Fail "Git install failed: $_"
            $gitInstallFailed = $true
        }
    }

    Write-Step "Refreshing PATH..."
    Refresh-EnvPath
}

# ---------------------------------------------------------------------------
# Step 12: PATH refresh (also covers tools installed before this run)
# ---------------------------------------------------------------------------

Write-Step "Refreshing PATH..."
Refresh-EnvPath

# ---------------------------------------------------------------------------
# Step 13: Install Claude Code
# Note: Git for Windows must be installed before this step (Claude needs bash.exe).
# ---------------------------------------------------------------------------

$claudeInstallFailed = $false

if (-not $hasClaude) {
    Write-Step "Installing Claude Code..."
    $installed = $false

    try {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
        Write-Step "Fetching Claude Code installer from claude.ai..."
        Write-Warn "This may take 30 seconds depending on your connection. Script is not frozen."
        $installerScript = Invoke-RestMethod -Uri "https://claude.ai/install.ps1" -UseBasicParsing
        if ($installerScript.Length -lt 100 -or $installerScript -notmatch '\$|function|param') {
            throw "Unexpected content from claude.ai/install.ps1 (got $($installerScript.Length) bytes; possible network error)"
        }
        Invoke-Expression $installerScript
        $installed = $true
    } catch {
        Write-Warn "Claude Code primary install failed: $_"
    }

    if (-not $installed) {
        $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
        $npmCmd  = Get-Command npm  -ErrorAction SilentlyContinue
        if ($npmCmd) {
            try {
                Write-Step "Trying npm fallback for Claude Code..."
                npm install -g "@anthropic-ai/claude-code"
                $installed = $true
            } catch {
                Write-Fail "npm fallback failed: $_"
            }
        } else {
            Write-Warn "Node.js/npm not found; cannot use npm fallback."
        }
    }

    if (-not $installed) {
        Write-Fail "Claude Code could not be installed."
        $claudeInstallFailed = $true
    }

    Write-Step "Refreshing PATH..."
    Refresh-EnvPath
}

# ---------------------------------------------------------------------------
# Step 14: Install Chrome (optional)
# ---------------------------------------------------------------------------

$chromeInstallFailed = $false
$chromeDeclined = $false

if (-not $hasChrome -and -not $SkipChrome) {
    Write-Host ""
    if (Prompt-YN "Install Google Chrome?" $true) {
        Write-Step "Installing Google Chrome..."
        $installed = $false

        if ($hasWinget) {
            try {
                Write-Step "Trying winget for Chrome..."
                winget install Google.Chrome --silent --accept-source-agreements --accept-package-agreements
                if ($LASTEXITCODE -ne 0) {
                    throw "winget exited with code $LASTEXITCODE"
                }
                $installed = $true
            } catch {
                Write-Warn "winget install failed: $_"
            }
        }

        if (-not $installed) {
            try {
                $chromeUrl = "https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi"
                $chromeMsi = Invoke-Download -Url $chromeUrl -FileName "GoogleChromeStandaloneEnterprise64.msi"
                Write-Step "Running Chrome installer (quiet)..."
                $p = Start-Process -FilePath "msiexec.exe" `
                    -ArgumentList "/i `"$chromeMsi`" /quiet /norestart" `
                    -Wait -PassThru
                if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 1638) {
                    # 1638 = another version already installed; treat as success
                    throw "Chrome MSI exited $($p.ExitCode)"
                }
                Remove-Item $chromeMsi -ErrorAction SilentlyContinue
                $installed = $true
            } catch {
                Write-Warn "Chrome install failed (non-fatal): $_"
                $chromeInstallFailed = $true
            }
        }
    } else {
        $chromeDeclined = $true
    }
}

Write-Host ""

# ---------------------------------------------------------------------------
# Step 15: Verify
# ---------------------------------------------------------------------------

Write-Step "Verifying installations..."
Refresh-EnvPath

$postPython = Get-PythonVersion
$postClaude = Test-ClaudeInstalled
$postGit    = Test-GitInstalled
$postChrome = Test-ChromeInstalled

Write-Host ""
Write-Host "Results:" -ForegroundColor Cyan

if ($postPython) {
    Write-Pass "Python $($postPython.Version)"
} else {
    Write-Fail "Python - not found after install"
}

if ($postClaude) {
    Write-Pass "Claude Code"
} else {
    Write-Fail "Claude Code - not found after install"
}

if ($postGit) {
    Write-Pass "Git"
} else {
    Write-Fail "Git - not found after install"
}

if ($SkipChrome) {
    Write-Host "[-] Chrome - skipped" -ForegroundColor Gray
} elseif ($postChrome) {
    Write-Pass "Chrome"
} else {
    Write-Warn "Chrome - not found (non-fatal)"
}

Write-Host ""

# ---------------------------------------------------------------------------
# Step 16: Next-step instructions
# ---------------------------------------------------------------------------

$criticalFailed = (-not $postPython) -or (-not $postClaude)
$partialFailed  = (-not $postGit) -or ((-not $postChrome) -and (-not $chromeDeclined) -and (-not $SkipChrome))

if ($criticalFailed) {
    Write-Fail "Critical tools missing. Check the errors above and re-run."
    Write-Host ""
    Write-Host "If the install keeps failing, see the manual install guide at:" -ForegroundColor Yellow
    Write-Host "    https://github.com/TruthWatcherIntelligence/glys-bootstrap#if-you-cant-run-the-bootstrap" -ForegroundColor Yellow
    Write-Host ""
    exit 2
}

Write-Host "Setup complete." -ForegroundColor Green
Write-Host ""
Write-Host "NOTE: Close this terminal and open a new one so PATH changes take effect." -ForegroundColor Yellow
Write-Host ""
Write-Host "Next: open Claude Code" -ForegroundColor Cyan
Write-Host "    claude" -ForegroundColor White
Write-Host ""
Write-Host "Inside Claude Code:" -ForegroundColor Cyan
Write-Host "    /plugin marketplace add TruthWatcherIntelligence/glys" -ForegroundColor White
Write-Host ""

if (-not $NonInteractive) {
    if (Prompt-YN "Launch Claude Code now?" $false) {
        try {
            Start-Process claude
        } catch {
            Write-Warn "Could not launch claude automatically. Run 'claude' in a new terminal."
        }
    }
}

if ($partialFailed) { exit 3 }
exit 0
