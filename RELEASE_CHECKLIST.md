# Release Checklist

Only create a release when you are certain the code at this point is working, tested, and safe for real-world use.

## 1) Release quality gate

- [ ] All planned features for this release are complete or intentionally deferred.
- [ ] Core install, update, and startup flows are tested end-to-end on the target platforms.
- [ ] No crash-level, corruption-level, security-level, or noisy failure remains.
- [ ] No known issue that breaks startup, world load, saves, networking, pack sync, or dependency resolution remains.

## 2) Bug acceptance policy

A known bug can ship only if it is silent and non-destructive:

- [ ] It does not break startup, gameplay integrity, saves, pack sync, or server/client compatibility.
- [ ] It does not spam logs, produce repeated warnings/errors, or create operational noise.
- [ ] It does not degrade security, stability, or data integrity.
- [ ] Impact is limited to a feature doing nothing or underperforming on some hardware.

If a bug does not meet every condition above, keep it on `main` and do not release yet.

## 3) Pack export boundaries (.packwizignore)

- [ ] All git-only docs/site/repo files are excluded from `.mrpack` by `.packwizignore`.
- [ ] Site files are excluded: `index.html`, `install.html`, `server.html`, `features.html`, `faq.html`, `stylesheet.css`, `scripts.js`.
- [ ] Repo/metadata files are excluded (README, LICENSE, `.github`, `.gitignore`, `.gitattributes`, etc.).
- [ ] Install/bootstrap helper scripts are excluded: `install.sh`, `install.ps1`, `pterodactyl.json`.
- [ ] `startup.sh` and `startup.ps1` remain included in packwiz export (do not ignore them).

## 4) Shell line endings and script safety

- [ ] All `.sh` files use LF line endings.
- [ ] `.gitattributes` includes `*.sh text eol=lf`.
- [ ] Startup/install scripts pass syntax checks and basic validation checks.

## 5) SRI policy for site assets

- [ ] Any local JS/CSS referenced by HTML uses `integrity` and `crossorigin="anonymous"`.
- [ ] SRI values are regenerated from live GitHub raw file bytes before release if files changed.
- [ ] Every page reference is updated when hashes rotate.

Reference command (PowerShell):

```powershell
$wc = New-Object System.Net.WebClient
$cssBytes = $wc.DownloadData('https://raw.githubusercontent.com/rooneyj9005/Thunder/main/stylesheet.css')
$jsBytes = $wc.DownloadData('https://raw.githubusercontent.com/rooneyj9005/Thunder/main/scripts.js')
$sha384 = [System.Security.Cryptography.SHA384]::Create()
"CSS=sha384-$([Convert]::ToBase64String($sha384.ComputeHash([byte[]]$cssBytes)))"
"JS=sha384-$([Convert]::ToBase64String($sha384.ComputeHash([byte[]]$jsBytes)))"
```

## 6) Lint and error checks

- [ ] Run lint/error checks for all changed files, including HTML.
- [ ] Resolve errors before release unless explicitly accepted by the bug policy above.
- [ ] Confirm there is no new warning/error noise in runtime logs.

## 7) Signed release requirement

- [ ] Release tag and/or release commit is GPG/SSH signed.
- [ ] Signing identity includes public ownership info (real name and email).
- [ ] Signing key identity is linked to a GitHub account and shows as verified.
- [ ] Unsigned releases are not permitted.

## 8) AI usage policy

AI assistance is allowed for drafting and exploration, but AI output is treated as untrusted input.

- [ ] Do not ship raw AI output without human review and hardening.
- [ ] Review AI-assisted code as if it were adversarial: verify assumptions, edge cases, and failure modes.
- [ ] Test and refactor AI-assisted code until it meets project robustness and safety standards.
- [ ] Do not include AI markers or provenance text in release artifacts.

## 9) Final release go/no-go

- [ ] `packwiz refresh` and `packwiz modrinth export` completed successfully.
- [ ] Release notes match the actual shipped state.
- [ ] All checklist items above are completed.
- [ ] If any required item is incomplete, do not release.
