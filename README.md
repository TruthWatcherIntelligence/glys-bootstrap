# Glys Bootstrap

One-command installer that gets Python, Claude Code, Git, and Chrome ready
on your computer so you can install the Glys OSINT plugin.

---

## Windows

Open PowerShell and run:

```powershell
irm https://github.com/TruthWatcherIntelligence/glys-bootstrap/raw/v0.1.1/install.ps1 | iex
```

Or, if you prefer to double-click an icon:

1. Download [glys-bootstrap.bat](https://github.com/TruthWatcherIntelligence/glys-bootstrap/raw/v0.1.1/glys-bootstrap.bat)
2. Double-click the file
3. If a SmartScreen dialog appears, click **More info**, then **Run anyway**

---

## macOS

Open Terminal and run:

```bash
curl -fsSL https://github.com/TruthWatcherIntelligence/glys-bootstrap/raw/v0.1.1/install.sh | bash
```

---

## What gets installed

| Tool | Why |
|---|---|
| Python 3.12 | Required by the Glys plugin for linguistic and image analysis |
| Claude Code | The AI assistant that Glys runs inside |
| Git | Required for `/plugin marketplace add` |
| Chrome | Needed for PDF report generation (optional but recommended) |

Skip Chrome on Windows by appending `-SkipChrome` to the PowerShell command, or on macOS by replacing the curl command with:

```bash
curl -fsSL https://github.com/TruthWatcherIntelligence/glys-bootstrap/raw/v0.1.1/install.sh | bash -s -- --skip-chrome
```

---

## Disk and time

About 500 MB of disk space. Installation takes 3 to 10 minutes depending on your internet connection.

---

## After the bootstrap

Once the installer finishes, open Claude Code:

```
claude
```

Then, inside Claude Code, add the Glys plugin:

```
/plugin marketplace add TruthWatcherIntelligence/glys
```

Follow the prompts. Glys will be ready in under a minute.

---

## If SmartScreen blocks the installer

Windows marks downloaded scripts as untrusted. The PowerShell one-liner (`irm | iex`) runs the script directly in memory and does not trigger SmartScreen. The `.bat` file, because it is saved to disk, may show a SmartScreen dialog:

1. Click **More info** in the dialog
2. Click **Run anyway**

The script is open-source. You can read every line at
[install.ps1](https://github.com/TruthWatcherIntelligence/glys-bootstrap/blob/main/install.ps1)
before running it.

---

## If Gatekeeper blocks the installer on macOS

The `curl | bash` one-liner runs the script directly in memory and does not trigger Gatekeeper. If you have saved `install.sh` to disk and are trying to run it directly, macOS may show a warning that the script is from an unidentified developer:

1. Open Terminal and navigate to the folder containing `install.sh`
2. Right-click (or Control-click) the file in Finder
3. Click **Open** in the menu
4. Click **Open** again in the security dialog

Alternatively, run this in Terminal to remove the quarantine attribute:

```bash
xattr -d com.apple.quarantine install.sh
```

The script is open-source. You can read every line at
[install.sh](https://github.com/TruthWatcherIntelligence/glys-bootstrap/blob/main/install.sh)
before running it.

---

## If you cannot run the bootstrap

Some corporate environments block unsigned scripts or restrict outbound network access to `raw.githubusercontent.com`. If the bootstrap fails in your environment, follow the manual installation steps in **Appendix C** of the Glys user guide (included with your Glys license).

---

## Verify the install

Close your terminal, open a new one, and run:

```
python --version
```

You should see `Python 3.10` or higher (likely `Python 3.12.x`). A version like `Python 2.7` or `Python 3.8` means the bootstrap could not install the newer version.

```
claude --version
```

You should see any version number.

```
git --version
```

You should see `git version 2.x.x` or similar.

If any command returns "not recognized" or "command not found", re-run the bootstrap or see Appendix C of the user guide.

---

## Notes for Windows users

If you already have Python installed from the Microsoft Store, the bootstrap installs the python.org build alongside it. Use `py -3.12` to invoke the correct version when working with Glys.

After installation, PATH changes take effect in new terminal windows only. Close and reopen your terminal before running the verify commands above.

---

## Notes for macOS users

The bootstrap installs Homebrew if it is not already present. You will be prompted for your Mac login password during that step; this is normal and expected.

PATH changes made by the installer apply to the current terminal session only. To make them permanent, the installer will print the lines to add to your `~/.zshrc`.

---

## License

MIT. The bootstrap script is open-source. The Glys plugin itself is commercially licensed; see [TruthWatcherIntelligence/glys](https://github.com/TruthWatcherIntelligence/glys) for details.

---

## Questions or issues

Open an issue on this repository and we will respond within one business day.
