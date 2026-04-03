# Thunder Modpack

[![Pack Checks](https://github.com/rooneyj9005/Thunder/actions/workflows/ci.yml/badge.svg?branch=development&event=push)](https://github.com/rooneyj9005/Thunder/actions/workflows/ci.yml)
[![Prerelease Build](https://github.com/rooneyj9005/Thunder/actions/workflows/prerelease.yml/badge.svg?event=push)](https://github.com/rooneyj9005/Thunder/actions/workflows/prerelease.yml)
[![Deploy Pack Metadata](https://github.com/rooneyj9005/Thunder/actions/workflows/publish-pack-pages.yml/badge.svg?event=release)](https://github.com/rooneyj9005/Thunder/actions/workflows/publish-pack-pages.yml)

Thunder is a Minecraft Forge modpack focused on technical stability, performance, and practical server tooling.

This repository is mainly for contributors working on the pack itself: metadata, configs, scripts, release assets, and workflow changes. If you are looking to play Thunder or host it for your group, the public site is the better starting point:

- Players and server owners will usually want [thunder.john.rooney.scot](https://thunder.john.rooney.scot/)
- The separate docs repository lives at [`Thunder-docs`](https://github.com/rooneyj9005/Thunder-docs)

## Contributing to the Pack

Contributors will usually want a local clone of the pack repository and a working `packwiz` installation from the upstream project.

```bash
git clone https://github.com/rooneyj9005/Thunder.git
cd Thunder
```

Once `packwiz` is on your `PATH`, these are the commands you are most likely to reach for:

```bash
packwiz modrinth add "mod name"
packwiz refresh
packwiz modrinth export
```

If `shellcheck` is not already available, `lint-shell.sh` will fetch a local copy of the latest release into `_ci/tools` and use that instead.

A few expectations tend to matter more than anything else:

- Please treat every repository content change as versioned work. `pack.toml` should move with the change.
- Patch bumps suit docs, scripts, workflows, configs, and other minor repository changes.
- Minor bumps suit adding or removing mods.
- Major bumps are best kept for thoroughly tested, production-ready milestone releases.
- If the pack name or version changes, `config/bcc-common.toml` should usually move with it.
- Create and its ecosystem are intentionally handled with care. If you are considering an update there, `mods/create.pw.toml` is the right place to start reading.

## Repository Notes for Contributors

This repository is the source of truth for:

- `pack.toml` and `index.toml`
- mod metadata under `mods/`
- bundled configs and defaults
- server scripts for Linux and Windows
- release assets such as `pterodactyl.json`
- the release workflow itself

The player-facing website is maintained separately. That split is deliberate: this repository keeps the pack sane, while the docs site explains how to use it.

## Server Script Notes

The day-to-day setup guide for players and server owners belongs on the public site. The notes here are aimed at contributors changing the scripts.

The scripts are designed around the same general ideas on both platforms:

- the install step fetches Forge and packwiz bootstrap tooling
- the startup step can sync the pack before launch
- the current server runtime accepts Java 17 or Java 21 on both Linux and Windows, with local Temurin 21 bootstrapped if the host has neither
- only exact indexed paths are pack-managed
- `pterodactyl.json` remains the public panel import asset
- the published pack metadata is expected to come from `https://packwiz.thunder.john.rooney.scot/pack.toml`

If you are touching pack sync behaviour, it is worth checking both the scripts and the docs site so they keep telling the same story.

Testing them in a separate empty directory is usually the safest approach, rather than pointing them at the repository working tree itself.

## Release Checklist

The checklist below is intended as the go/no-go release checklist for the pack repository.

<ul>
  <li><label><input type="checkbox" /> I have checked that temporary release-test files such as stray <code>.mrpack</code> exports are not in source control.</label></li>
  <li><label><input type="checkbox" /> I have checked that <code>pack.toml</code> reflects the intended release version and state.</label></li>
  <li><label><input type="checkbox" /> I have checked that <code>config/bcc-common.toml</code> reflects the intended pack name and displayed version.</label></li>
  <li><label><input type="checkbox" /> I have checked that <code>index.toml</code> matches the current pack-managed contents.</label></li>
  <li><label><input type="checkbox" /> I have checked that <code>packwiz refresh</code> completed successfully.</label></li>
  <li><label><input type="checkbox" /> I have checked that <code>packwiz modrinth export</code> completed successfully.</label></li>
  <li><label><input type="checkbox" /> I have checked that the release install/update path can pull the published pack metadata successfully.</label></li>
  <li><label><input type="checkbox" /> I have checked that <code>startup.sh</code> and <code>update.sh</code> still use LF line endings.</label></li>
  <li><label><input type="checkbox" /> I have checked that a fresh client import launches cleanly and reaches the main menu.</label></li>
  <li><label><input type="checkbox" /> I have checked that a fresh client import can join a Thunder server.</label></li>
  <li><label><input type="checkbox" /> I have checked that server install and startup behave correctly on Linux.</label></li>
  <li><label><input type="checkbox" /> I have checked that server install and startup behave correctly on Windows.</label></li>
  <li><label><input type="checkbox" /> I have checked that <code>startup.sh</code>, <code>startup.ps1</code>, <code>update.sh</code>, and <code>update.ps1</code> are included in the export.</label></li>
  <li><label><input type="checkbox" /> I have checked that <code>.packwizignore</code> excludes repository-only files without excluding files the pack genuinely needs to ship.</label></li>
  <li><label><input type="checkbox" /> I have checked that <code>pterodactyl.json</code> is present as a public release asset.</label></li>
  <li><label><input type="checkbox" /> I have checked that generated helper binaries remain CI artifacts and are not being published as release assets.</label></li>
  <li><label><input type="checkbox" /> I have checked that the docs site and the pack repository still agree on install, update, server, and release behaviour.</label></li>
  <li><label><input type="checkbox" /> I have checked that the docs site and the scripts still point at the correct packwiz host.</label></li>
  <li><label><input type="checkbox" /> I have checked that any user-facing behaviour change has been reflected in the docs repository or consciously reviewed there.</label></li>
  <li><label><input type="checkbox" /> I have checked that the live docs site, or a local preview of it, still makes sense for this release, including download links, server guidance, and version-status checks.</label></li>
  <li><label><input type="checkbox" /> I have checked that the chosen version bump matches the kind of change in this release.</label></li>
  <li><label><input type="checkbox" /> I have checked that, if this is a major release, it is genuinely production-ready rather than a hopeful milestone.</label></li>
</ul>

## Pack Contents

- **Tech:** Create, Mekanism, Applied Energistics 2, Refined Storage, Thermal Expansion, Modular Routers, CC: Tweaked, Mystical Agriculture
- **Magic:** Ars Nouveau, Blood Magic, Hexerei, Apotheosis
- **Building:** Macaw's suite, Chipped, Rechiseled, Immersive Paintings
- **World Gen:** Biomes o' Plenty, Alex's Mobs, Oh The Trees You'll Grow
- **Food:** Farmer's Delight, Create Confectionery, Better Farming Plus
- **Performance and Polish:** Memory Leak Fix, Krypton, Canary, Ferrite Core, Dynamic Torches
- **Utility and Server:** SecurityCraft, GriefLogger, LuckPerms, FTB Essentials, Xaero's Maps, Jade, Waystones, Simple Voice Chat, Lootr, Sophisticated Backpacks, WorldEdit

Anyone who wants the fuller player-facing tour is likely better served by the live [features page](https://thunder.john.rooney.scot/features/).

## Documentation Site

The player-facing site lives in the separate [`Thunder-docs`](https://github.com/rooneyj9005/Thunder-docs) repository.

This repository remains the source of truth for pack metadata, scripts, release assets, and packwiz content. The docs site reads stable release metadata from GitHub and pack metadata from the packwiz host.

## CI/CD

- `ci.yml` runs Bash and PowerShell lint on both Windows and Linux, then on Linux checks pack metadata consistency, exports `Thunder.mrpack`, and smoke-tests the runtime update path against a locally served pack metadata build.
- `prerelease.yml` runs for any tag push, rebuilds and validates the pack, uploads helper binaries as workflow artifacts, and creates the GitHub prerelease with the public release assets including `pterodactyl.json`. Version-shaped tags are still checked against `pack.toml`; ad-hoc tags are useful for smoke-testing the release pipeline.
- `publish-pack-pages.yml` runs only when a prerelease is promoted to a stable release, deploys the tagged pack metadata to GitHub Pages, smoke-tests the stable install path, and rolls Pages back while demoting the release if that smoke test fails.
- Public release assets are limited to the files intended for players and server admins. Generated helper binaries are not distributed through Releases.
- The Pterodactyl egg reinstall path uses the currently imported egg definition, then fetches `install.sh` from the latest stable release. Runtime uses the startup and update scripts bundled with the pack, and optional RCON or Simple Voice Chat ports still need matching panel allocations and firewall rules to be reachable.
- The documentation site is deployed separately from the `Thunder-docs` repository.

## Licence and Ethos

This project is as open as the licence allows. Fork it, adjust it, or build on it as you see fit. If you make Thunder better for players, a pull request would be welcome, but it is never an obligation.

The repository contents are available under the MIT licence in [`LICENSE`](./LICENSE). Individual mods included through packwiz remain under their own licences.

The general house rules are still simple:

- no gambling or real-money mechanics
- no chat spam or nag messages
