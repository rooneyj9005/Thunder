# Thunder Modpack

Thunder is a Minecraft 1.20.1 modpack built for playing with friends. It combines technology, magic, and building mods into a cohesive experience that is optimised for server performance.

You can automate your base with **Create**, craft spells with **Ars Nouveau**, set up digital storage with **AE2**, and build with **Macaw's furniture** and **Chipped** blocks. There are 122 mods, all tested for stability.

> **Looking to play?** Visit **[thunder.john.rooney.scot](https://thunder.john.rooney.scot)** for download links, installation instructions, and server setup guides. This README is for developers and contributors.

## License and Ethos

This project is as open as any license can allow. Do whatever you want with it: fork it, modify it, or redistribute your own flavour of it. If you genuinely improve the player experience, a pull request is appreciated, but never required.

**The "No-Nonsense" Rules:**

- **No gambling or real-money mechanics:** This pack is for fun, not monetisation.
- **No chat spam or nag messages:** Update notifications or server advertisements are disabled. Staff-only notifications are fine; players deserve a clean, immersive experience.

## Important: Version Pinning

**Do not update Create.** The pack is built on **Create 6.0.6**, and many included addons only work with this version. Updating to 6.0.7 or later will almost certainly cause crashes.

- When adding new Create addons, check they support version 6.0.6.
- **Create Slice & Dice** is pinned at version **3.4.0** for the same reason.

## Getting Started (Developers)

```bash
git clone https://github.com/rooneyj9005/Thunder.git
cd Thunder
```

You will need [packwiz](https://packwiz.infra.link/) installed and available on your PATH. On Windows you can also keep a local copy at `bin/packwiz.exe` and run it from there.

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
4. Bump the `version` field in `pack.toml` (PRs that don't bump the version will fail CI).
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

Both scripts accept a `-Dir` parameter to specify the install directory. All Thunder defaults (Forge 47.4.13, Minecraft 1.20.1, packwiz URL) are built in, so no extra arguments are needed for a standard setup.

### Pterodactyl / Pelican

Import `pterodactyl.json` as an egg in your panel. It passes `--container` to the install and startup scripts automatically. See the [server setup guide](https://thunder.john.rooney.scot/server.html) for full instructions.

## Documentation Site

The player-facing documentation site lives in the repository root alongside the packwiz files:

```
index.html          # Landing page with latest release download
install.html        # Installation guide
server.html         # Server setup guide
features.html       # What's in the pack
faq.html            # Frequently asked questions
stylesheet.css      # Shared stylesheet
scripts.js          # Fetches latest release from GitHub API
```

The site is deployed via **GitHub Pages** from the root of the `main` branch to [thunder.john.rooney.scot](https://thunder.john.rooney.scot). Changes pushed to `main` are deployed automatically.

To preview locally, open `index.html` in a browser. All links are relative.

## CI/CD

- **Release workflow** (`.github/workflows/buildReleaseArtifacts.yml`): When a GitHub release is published, the workflow installs packwiz, runs `packwiz modrinth export`, and uploads the resulting `.mrpack` to the release.
- **GitHub Pages**: Serves the documentation site from the repository root on `main`.
- **Server scripts** (`install.sh`, `startup.sh`, `pterodactyl.json`): The Pterodactyl egg installs Forge and fetches `startup.sh` from the same GitHub ref as `install.sh` - either `main` or the latest release tag, controlled by the `Installation Script Source` panel variable.

## Release Checklist

Use `RELEASE_CHECKLIST.md` as the mandatory go/no-go checklist before publishing a release.

## What's Actually in the Pack

- **Tech:** Create (plus addons), Mekanism, Applied Energistics 2, Refined Storage, Thermal Expansion, Modular Routers, CC: Tweaked, Mystical Agriculture.
- **Magic:** Ars Nouveau, Blood Magic, Hexerei, Apotheosis.
- **Building:** Macaw's suite (Doors, Windows, Bridges, Roofs, Fences, Stairs, Trapdoors), Chipped, Rechiseled, Immersive Paintings.
- **World Gen:** Biomes o' Plenty, Alex's Mobs, Oh The Trees You'll Grow.
- **Food:** Farmer's Delight, Create Confectionery, Better Farming Plus.
- **Performance & Polish:** Memory Leak Fix, Krypton, Canary, Ferrite Core, Dynamic Torches.
- **Utility & Server:** SecurityCraft, GriefLogger, LuckPerms, FTB Essentials, Xaero's Maps, Jade, Waystones, Simple Voice Chat, Lootr, Sophisticated Backpacks, WorldEdit.

For the full player-facing guide, visit [thunder.john.rooney.scot](https://thunder.john.rooney.scot).
