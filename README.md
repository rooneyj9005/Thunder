# Thunder Modpack
[![Release Build](https://github.com/rooneyj9005/Thunder/actions/workflows/onRelease.yml/badge.svg)](https://github.com/rooneyj9005/Thunder/actions/workflows/onRelease.yml)
Thunder is a Minecraft Forge modpack built for playing with friends. It combines technology, magic, and building mods into a cohesive experience that is optimised for server performance.

You can automate your base with **Create**, craft spells with **Ars Nouveau**, set up digital storage with **AE2**, and build with **Macaw's furniture** and **Chipped** blocks. There are 122 mods, all tested for stability.

> **Looking to play?** Visit **[thunder.john.rooney.scot](https://thunder.john.rooney.scot)** for download links, installation instructions, and server setup guides. This README is for developers and contributors.

## Licence and Ethos

This project is as open as any licence can allow. Do whatever you want with it: fork it, modify it, or redistribute your own flavour of it. If you genuinely improve the player experience, a pull request is appreciated, but never required.

**The "No-Nonsense" Rules:**

- **No gambling or real-money mechanics:** This pack is for fun, not monetisation.
- **No chat spam or nag messages:** Update notifications or server advertisements are disabled. Staff-only notifications are fine; players deserve a clean, immersive experience.

## Important: Version Pinning

**Do not update Create casually.** The pack is pinned to a specific Create line and addon compatibility depends on it.

- Check the currently pinned versions in `mods/create.pw.toml` and `mods/create-slice-and-dice.pw.toml` before changing anything.
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

For specific versions (required for Create addons):

```bash
packwiz modrinth add --project-id "PROJECT_ID" --version-id "VERSION_ID"
```

### Applying Changes

Every time you add, remove, or update a mod, run:

```bash
packwiz refresh
packwiz modrinth export
```

The `refresh` command updates hashes in the index, while `export` generates the `.mrpack` file for the Releases tab.

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

By default the scripts run in **server mode** (bare metal). They assume `curl`, `jq`, and `java` are already installed, and install to the current directory:

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

Both scripts accept a `-Dir` parameter to specify the install directory. All Thunder defaults (current modloader, current game version, and packwiz URL) are built in, so no extra arguments are needed for a standard setup.

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

The published site is deployed via **GitHub Pages Actions** on release publish. The workflow stages `docs/*` at the site root and also publishes packwiz metadata files (`pack.toml`, `index.toml`, `mods/`, `config/`, `resourcepacks/`, `instance.cfg`) so both docs and pack metadata are available at [thunder.john.rooney.scot](https://thunder.john.rooney.scot).

To preview locally, open `docs/index.html` in a browser. All links are relative.

## CI/CD

- **Release workflow** (`.github/workflows/onRelease.yml`): When a GitHub release is published, the workflow compiles `packwiz.exe` from the latest packwiz release tag, exports the pack as `Thunder.mrpack`, normalises `.sh` line endings to LF, and uploads `Thunder.mrpack`, `packwiz.exe`, and the install/startup scripts.
- **GitHub Pages**: On release publish, deploys the site via Actions from the release tag snapshot.
- **Server scripts** (`install.sh`, `startup.sh`, `pterodactyl.json`): The Pterodactyl egg installs Forge and fetches `startup.sh` from the same GitHub ref as `install.sh` - either `main` or the latest release tag, controlled by the `Installation Script Source` panel variable.

## Release Checklist

Use `docs/RELEASE_CHECKLIST.md` as the mandatory go/no-go checklist before publishing a release.

## What's Actually in the Pack

- **Tech:** Create (plus addons), Mekanism, Applied Energistics 2, Refined Storage, Thermal Expansion, Modular Routers, CC: Tweaked, Mystical Agriculture.
- **Magic:** Ars Nouveau, Blood Magic, Hexerei, Apotheosis.
- **Building:** Macaw's suite (Doors, Windows, Bridges, Roofs, Fences, Stairs, Trapdoors), Chipped, Rechiseled, Immersive Paintings.
- **World Gen:** Biomes o' Plenty, Alex's Mobs, Oh The Trees You'll Grow.
- **Food:** Farmer's Delight, Create Confectionery, Better Farming Plus.
- **Performance & Polish:** Memory Leak Fix, Krypton, Canary, Ferrite Core, Dynamic Torches.
- **Utility & Server:** SecurityCraft, GriefLogger, LuckPerms, FTB Essentials, Xaero's Maps, Jade, Waystones, Simple Voice Chat, Lootr, Sophisticated Backpacks, WorldEdit.

For the full player-facing guide, visit [thunder.john.rooney.scot](https://thunder.john.rooney.scot).
