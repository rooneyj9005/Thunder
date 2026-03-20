
# Thunder Modpack
[![Release Build](https://github.com/rooneyj9005/Thunder/actions/workflows/onRelease.yml/badge.svg)](https://github.com/rooneyj9005/Thunder/actions/workflows/onRelease.yml)

Thunder is a Minecraft Forge modpack for friends and communities. It blends technology, magic, and building mods into a stable, performance-optimised experience.

**Quick Links:**
- [Player Site & Docs](https://thunder.john.rooney.scot)
- [Latest Download](https://github.com/rooneyj9005/Thunder/releases/latest)
- [FAQ](https://thunder.john.rooney.scot/faq.html)
- [Server Setup Guide](https://thunder.john.rooney.scot/server.html)

---

## Table of Contents
1. [For Players](#for-players)
2. [For Server Admins](#for-server-admins)
3. [For Developers & Contributors](#for-developers--contributors)
4. [Release Process](#release-process)
5. [Pack Contents](#pack-contents)
6. [Licence and Ethos](#licence-and-ethos)

---

## For Players

- **How to Play:**
	- Download the latest `.mrpack` from [the site](https://thunder.john.rooney.scot) or [GitHub Releases](https://github.com/rooneyj9005/Thunder/releases/latest).
	- Import into Prism Launcher or any Modrinth-compatible launcher.
	- See [install guide](https://thunder.john.rooney.scot/install.html) for step-by-step help.
- **What’s in the pack?**
	- Tech, magic, building, worldgen, performance, and utility mods. [Full list](https://thunder.john.rooney.scot/features.html).
- **Need help?**
	- [FAQ](https://thunder.john.rooney.scot/faq.html) | [Report bugs](https://github.com/rooneyj9005/Thunder/issues)

---

## For Server Admins

- **Setup:**
	- Use the provided `install.sh`/`startup.sh` (Linux) or `install.ps1`/`startup.ps1` (Windows) scripts.
	- See [server setup guide](https://thunder.john.rooney.scot/server.html) for details.
- **Auto-Update & Managed Files:**
	- Thunder’s server scripts keep mods/configs up to date using packwiz. Only files listed in `pack.toml` and `index.toml` are managed—no personal or player data is touched.
	- To skip auto-update for a run: `PACKWIZ_SKIP_UPDATE=true bash startup.sh` (Linux) or `./startup.ps1 -SkipPackUpdate` (PowerShell).
- **Pterodactyl:**
	- Import `pterodactyl.json` as an egg. It handles everything automatically.

---

## For Developers & Contributors

- **Getting Started:**
	- Clone the repo:
		```bash
		git clone https://github.com/rooneyj9005/Thunder.git
		cd Thunder
		```
	- Install [packwiz](https://packwiz.infra.link/) (or use the Windows binary from Releases).
- **Adding/Updating Mods:**
	- Use `packwiz modrinth add "mod name"` or specify version/project IDs as needed.
	- After any change, run:
		```bash
		packwiz refresh
		packwiz modrinth export
		```
- **Version Pinning:**
	- Do not update Create or its addons casually. Check `mods/create.pw.toml` for the pinned version.
- **Contributing:**
	- Fork, branch, make changes, test with Prism Launcher, bump `pack.toml` version, and open a PR.
- **Testing:**
	- See [Testing and QA](https://thunder.john.rooney.scot/faq.html#testing) in the docs.
- **More details:**
	- See `CONTRIBUTING.md` for CI, release, and workflow details.

---


## Release Process

- Only release when the pack is tested and stable.
- Checklist (see `CONTRIBUTING.md` for full details):
	- [ ] **Line endings:** The CI workflow normalises `.sh` line endings to LF _before_ running `packwiz refresh` and `packwiz modrinth export`. This ensures the hashes in `index.toml` remain valid and prevents invalidation due to line ending changes.
	- [ ] `packwiz refresh` and `packwiz modrinth export` succeed
	- [ ] Fresh client import launches cleanly
	- [ ] Server install/startup works on Linux and Windows
	- [ ] No known critical issues
	- [ ] `.packwizignore` excludes repo-only files
	- [ ] Startup/update scripts included in export
	- [ ] `.gitattributes` protects packwiz hashes
	- [ ] Shell scripts are LF and pass syntax checks
	- [ ] Docs and site match current behaviour
	- [ ] Release is signed and notes are accurate

---

## Pack Contents

- **Tech:** Create (plus addons), Mekanism, AE2, Refined Storage, Thermal Expansion, Modular Routers, CC: Tweaked, Mystical Agriculture
- **Magic:** Ars Nouveau, Blood Magic, Hexerei, Apotheosis
- **Building:** Macaw's suite, Chipped, Rechiseled, Immersive Paintings
- **World Gen:** Biomes o' Plenty, Alex's Mobs, Oh The Trees You'll Grow
- **Food:** Farmer's Delight, Create Confectionery, Better Farming Plus
- **Performance & Polish:** Memory Leak Fix, Krypton, Canary, Ferrite Core, Dynamic Torches
- **Utility & Server:** SecurityCraft, GriefLogger, LuckPerms, FTB Essentials, Xaero's Maps, Jade, Waystones, Simple Voice Chat, Lootr, Sophisticated Backpacks, WorldEdit

See [features](https://thunder.john.rooney.scot/features.html) for the full list.

---

## Licence and Ethos

This project is as open as any licence can allow. Do whatever you want with it: fork it, modify it, or redistribute your own flavour. If you genuinely improve the player experience, a pull request is appreciated, but never required.

**The "No-Nonsense" Rules:**
- No gambling or real-money mechanics
- No chat spam or nag messages

---

## Licence and Ethos

This project is as open as any licence can allow. Do whatever you want with it: fork it, modify it, or redistribute your own flavour of it. If you genuinely improve the player experience, a pull request is appreciated, but never required.

**The "No-Nonsense" Rules:**

- **No gambling or real-money mechanics:** This pack is for fun, not monetisation.
- **No chat spam or nag messages:** Update notifications or server advertisements are disabled. Staff-only notifications are fine; players deserve a clean, immersive experience.


## Important: Version Pinning

**Do not update Create casually.** The pack is pinned to a specific Create line and addon compatibility depends on it.

- Check the currently pinned versions in `mods/create.pw.toml` before changing anything.
- When adding new Create addons, confirm compatibility with the versions currently pinned in this repository.

## Getting Started (Developers)

```bash
git clone https://github.com/rooneyj9005/Thunder.git
cd Thunder
```

You will need [packwiz](https://packwiz.infra.link/) installed and available on your PATH. On Windows you can also use the release-hosted binary at [packwiz.exe](https://github.com/rooneyj9005/Thunder/releases/latest/download/packwiz.exe).

### Adding a Mod

Most mods can be added with a single command:

```bash
packwiz modrinth add "mod name"
```

For specific versions:

```bash
packwiz modrinth add --project-id "PROJECT_ID" --version-id "VERSION_ID"
```

### Applying Changes

Every time you add, remove, or update a mod or config override, run:

```bash
packwiz refresh
packwiz modrinth export
```

The `refresh` command updates hashes in the index, while the `export` generates the `.mrpack` file.

## Testing and Quality Assurance

Before releasing a new version, perform the following checks:

1. **Launch:** Import the generated `.mrpack` into a fresh Prism instance.
2. **World Gen:** Create a new world and check for biome stitching or chunk errors.
3. **Log Check:** Skim `logs/latest.log`. Ignore harmless warnings, but investigate any "Error" or "Exception" entries that occur during startup or world load.

### Troubleshooting Common Errors

- **Missing Mod Error:** Usually a dependency issue. Add the missing mod via packwiz and refresh.
- **MixinTransformerError:** Often a version conflict. If you've just added a mod, it's likely incompatible with the existing environment. Try an older version or an alternative mod.

## Contributing

1. Fork the repository and create a branch for your changes.
2. Make your changes (add/remove/update mods, edit site content, etc.).
3. Test locally with Prism Launcher - import the `.mrpack` and verify it launches cleanly.
4. Bump the `version` field in `pack.toml`.
5. Open a pull request against `main`.

## Server Scripts

The repository includes scripts for setting up a dedicated server on Linux or Windows, with or without a hosting panel.

### Linux (`install.sh` / `startup.sh`)

By default the scripts run in **server mode** (bare metal). They assume `curl`, `jq`, and Java 21 are already installed, and install to the current directory:

```bash
bash install.sh
bash startup.sh
```

To install to a specific directory:

```bash
bash install.sh --dir /opt/minecraft/thunder
bash startup.sh --dir /opt/minecraft/thunder
```

The `--container` flag is used internally by the Pterodactyl egg. It installs system dependencies via `apt-get` and defaults to `/mnt/server`. You should not need to use it manually.

### Windows (`install.ps1` / `startup.ps1`)

```powershell
.\install.ps1
.\startup.ps1
```

Both scripts accept a `-Dir` parameter to specify the install directory. All Thunder defaults (current modloader, current game version, and packwiz URL) are built in, so no extra arguments are needed for a standard setup. `install.ps1` also downloads Temurin 21 automatically if Java is not on your PATH.

### Managed Files and Auto-Update

Thunder server startup scripts are self-updating by default: each run of `startup.sh` / `startup.ps1` syncs files from `pack.toml` via packwiz.

We care about player privacy and safety first. Some users reasonably view any auto-updater as a potential backdoor. If you prefer full manual control, you can disable update sync at startup (examples below).

What the updater does:

- Downloads only pack files listed by `pack.toml` and `index.toml`.
- Does not collect player data, chat logs, credentials, or personal files.
- Can be disabled per run with explicit flags/environment variables.

- **Managed files:** Only files that have explicit entries in `index.toml` are pack-managed and may be updated or restored to pack state.
- **Directory note:** A folder name like `config/` or `mods/` does not mean every file in that folder is managed; only indexed file paths are managed.
- **Usually untouched:** Extra user-added files with unique names/paths are generally left alone.
- **Will be replaced:** Anything that collides with a pack-managed filename/path.
- **Clean install mode:** `CLEAN_INSTALL=true` (Linux) or `-CleanInstall` (PowerShell) wipes `mods` first.

If you want to preserve local custom changes and skip the updater for a run, disable sync explicitly:

Linux:

```bash
PACKWIZ_SKIP_UPDATE=true bash startup.sh
```

Windows PowerShell:

```powershell
.\startup.ps1 -SkipPackUpdate
```

Windows (environment variable alternative):

```powershell
$env:PACKWIZ_SKIP_UPDATE = "true"
.\startup.ps1
```

If you disable auto-update, update to the latest Thunder release before filing issues.

### Pterodactyl / Pelican

Import `pterodactyl.json` as an egg in your panel. It passes `--container` to the install and startup scripts automatically. See the [server setup guide](https://thunder.john.rooney.scot/server.html) for full instructions.

## Documentation Site

The player-facing documentation source lives in `docs/`:

```
docs/index.html          # Landing page with latest release download
docs/install.html        # Installation guide
docs/server.html         # Server setup guide
docs/features.html       # What's in the pack
docs/faq.html            # Frequently asked questions
docs/stylesheet.css      # Shared stylesheet
docs/functions.js        # Fetches latest release from GitHub API
```

The published site is deployed via **GitHub Pages Actions** on release publish. The workflow stages `docs/*` at the site root and also publishes packwiz metadata files (`pack.toml`, `index.toml`, `mods/`, `config/`, `defaultconfigs/`, `kubejs/`, `resourcepacks/`, `instance.cfg`) plus startup scripts so both docs and pack metadata are available at [thunder.john.rooney.scot](https://thunder.john.rooney.scot).

To preview locally, open `docs/index.html` in a browser. All links are relative.

## CI/CD

- **Release workflow** (`.github/workflows/onRelease.yml`): When a GitHub release is published, the workflow installs the latest packwiz tooling via Go, builds `packwiz.exe` for Windows, exports the pack as `Thunder.mrpack`, normalises `.sh` line endings to LF, and uploads `Thunder.mrpack`, `packwiz.exe`, plus install/startup/update scripts.
- **GitHub Pages**: On release publish, deploys the site via Actions from the release tag snapshot.
- **Server scripts** (`install.sh`, `startup.sh`, `update.sh`, `pterodactyl.json`): The Pterodactyl egg install step fetches `install.sh` from the latest release tag, and runtime uses the startup/update scripts bundled with the Thunder pack files.

## Release Checklist

Only create a release when you are certain the code at this point is working, tested, and safe for real-world use.

### 1) Build and startup gate

<ul>
	<li><input type="checkbox"> `packwiz refresh` and `packwiz modrinth export` completed successfully.</li>
	<li><input type="checkbox"> Fresh client import launches without crash-level errors.</li>
	<li><input type="checkbox"> Server install/startup flow works on Linux and PowerShell paths.</li>
	<li><input type="checkbox"> No known issue remains that breaks launch, saves, networking, or pack sync.</li>
</ul>

### 2) Pack and export boundaries

<ul>
	<li><input type="checkbox"> `.packwizignore` excludes repo-only files (`docs/`, `README`, `.github`, install helpers).</li>
	<li><input type="checkbox"> `startup.sh`, `startup.ps1`, `update.sh`, and `update.ps1` are included in export.</li>
	<li><input type="checkbox"> `.gitattributes` still protects packwiz hashes (`*.toml -text`, `config/** -text`).</li>
	<li><input type="checkbox"> Shell scripts are LF (`*.sh text eol=lf`) and pass basic syntax checks.</li>
</ul>

### 3) Docs and site consistency

<ul>
	<li><input type="checkbox"> `README.md` and `docs/*` match current install/update behaviour.</li>
	<li><input type="checkbox"> GitHub Pages staging still merges docs plus pack metadata/files.</li>
	<li><input type="checkbox"> Release download links use `https://github.com/rooneyj9005/Thunder/releases/latest/download/&lt;asset&gt;` format.</li>
</ul>

### 4) Release governance

<ul>
	<li><input type="checkbox"> Release tag or release commit is signed (GPG or SSH) and verified on GitHub.</li>
	<li><input type="checkbox"> Release notes match what actually shipped.</li>
	<li><input type="checkbox"> If any required item is unchecked, do not release.</li>
</ul>

## What's Actually in the Pack

- **Tech:** Create (plus addons), Mekanism, Applied Energistics 2, Refined Storage, Thermal Expansion, Modular Routers, CC: Tweaked, Mystical Agriculture.
- **Magic:** Ars Nouveau, Blood Magic, Hexerei, Apotheosis.
- **Building:** Macaw's suite (Doors, Windows, Bridges, Roofs, Fences, Stairs, Trapdoors), Chipped, Rechiseled, Immersive Paintings.
- **World Gen:** Biomes o' Plenty, Alex's Mobs, Oh The Trees You'll Grow.
- **Food:** Farmer's Delight, Create Confectionery, Better Farming Plus.
- **Performance & Polish:** Memory Leak Fix, Krypton, Canary, Ferrite Core, Dynamic Torches.
- **Utility & Server:** SecurityCraft, GriefLogger, LuckPerms, FTB Essentials, Xaero's Maps, Jade, Waystones, Simple Voice Chat, Lootr, Sophisticated Backpacks, WorldEdit.

For the full player-facing guide, visit [thunder.john.rooney.scot](https://thunder.john.rooney.scot).
