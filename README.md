# Thunder Modpack

Thunder is a Minecraft 1.20.1 modpack built for playing with friends. It combines technology, magic, and building mods into a cohesive experience that is optimised for server performance.

You can automate your base with **Create**, craft spells with **Ars Nouveau**, set up digital storage with **AE2**, and build with **Macaw's furniture** and **Chipped** blocks. There are 112 mods, all tested for stability.

## Quick Start

### For Players

If you just want to play, do not download the code from this repository. Visit the **[website](https://thunder.john.rooney.scot)** or:

1. Go to the **[Releases](../../releases)** tab.
2. Download the latest `Thunder-[v].mrpack` file.
3. Import this file into **Prism Launcher** (or any Modrinth-compatible launcher).

For full installation instructions, see the [installation guide](https://thunder.john.rooney.scot/install.html).

### For Server Owners

This pack uses **packwiz** to keep server files synchronised.

1. Download the [packwiz-installer-bootstrap](https://github.com/packwiz/packwiz-installer-bootstrap/releases).
2. Run the following command in your server directory:
   ```bash
   java -jar packwiz-installer-bootstrap.jar -g -s server https://thunder.john.rooney.scot/pack.toml
   ```
3. The installer will automatically download the correct mod versions and configurations, excluding client-side-only mods.

For full server setup instructions, see the [server guide](https://thunder.john.rooney.scot/server.html).

## License and Ethos

This project is as open as any license can allow. Do whatever you want with it: fork it, modify it, or redistribute your own flavour of it. If you genuinely improve the player experience, a pull request is appreciated, but never required.

**The "No-Nonsense" Rules:**
* **No gambling or real-money mechanics:** This pack is for fun, not monetisation.
* **No chat spam or nag messages:** Update notifications or server advertisements are disabled. Staff-only notifications are fine; players deserve a clean, immersive experience.

## Important: Version Pinning

**Do not update Create.** or do I'm not your mother, but the pack is built on **Create 6.0.6**. Many included addons were designed specifically for this version; updating to 6.0.7 or 6.0.8 will most likely cause crashes.
* When adding new Create addons, ensure they support version 6.0.6.
* **Create Slice & Dice** is pinned at version **3.4.0** for the same reason.

## Development Workflow

To contribute to or modify the pack, you will need **packwiz**, **Git**, and ideally **Prism Launcher** for local testing.

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
* **Missing Mod Error:** Usually a dependency issue. Add the missing mod via packwiz and refresh.
* **MixinTransformerError:** Often a version conflict. If you've just added a mod, it's likely incompatible with the existing environment. Try an older version or an alternative mod.

## Documentation Site

The player-facing documentation site lives in the repository root alongside the packwiz files:

```
index.html          # Landing page with latest release download
install.html        # Installation guide
server.html         # Server setup guide
features.html       # What's in the pack
faq.html            # Frequently asked questions
css/style.css       # Shared stylesheet
js/release.js       # Fetches latest release from GitHub API
```

The site is deployed via **GitHub Pages** from the root of the `main` branch to [thunder.john.rooney.scot](https://thunder.john.rooney.scot). Changes pushed to `main` are deployed automatically.

To preview locally, open `index.html` in a browser. All links are relative.

## CI/CD

* **Release workflow** (`.github/workflows/buildReleaseArtifacts.yml`): When a GitHub release is published, the workflow installs packwiz, runs `packwiz modrinth export`, and uploads the resulting `.mrpack` to the release.
* **GitHub Pages**: Serves the documentation site from the repository root on `main`.

## What's Actually in the Pack

* **Tech:** Create (plus addons), Mekanism, Applied Energistics 2, Refined Storage, Thermal Expansion, Modular Routers, CC: Tweaked, Mystical Agriculture.
* **Magic:** Ars Nouveau, Blood Magic, Hexerei, Apotheosis.
* **Building:** Macaw's suite (Doors, Windows, Bridges, Roofs, Fences, Stairs, Trapdoors), Chipped, Rechiseled, Immersive Paintings.
* **World Gen:** Biomes o' Plenty, Better Nether, Alex's Mobs, Oh The Trees You'll Grow.
* **Food:** Farmer's Delight, Create Confectionery, Better Farming Plus.
* **Performance:** Dynamic Torches, Memory Leak Fix, Krypton, Canary, Ferrite Core.
* **Utility:** SecurityCraft, LuckPerms, FTB Essentials, Xaero's Maps, Jade, Waystones, Simple Voice Chat, Lootr, Sophisticated Backpacks, WorldEdit.
