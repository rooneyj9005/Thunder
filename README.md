# Thunder Modpack

[![Development Checks](https://github.com/rooneyj9005/Thunder/actions/workflows/checks.yml/badge.svg?branch=development&event=push)](https://github.com/rooneyj9005/Thunder/actions/workflows/checks.yml)
[![Release Build](https://github.com/rooneyj9005/Thunder/actions/workflows/build.yml/badge.svg?event=push)](https://github.com/rooneyj9005/Thunder/actions/workflows/build.yml)
[![Release Deploy](https://github.com/rooneyj9005/Thunder/actions/workflows/deploy.yml/badge.svg?event=release)](https://github.com/rooneyj9005/Thunder/actions/workflows/deploy.yml)

Thunder is a Minecraft Forge modpack focused on technical stability, performance, and practical server tooling.

This repository is for contributors working on the pack itself: metadata, configs, scripts, release assets, and workflow changes. To play Thunder or host it for your group, start at the public site instead:

- Players and server owners want [thunder.john.rooney.scot](https://thunder.john.rooney.scot/)
- The separate docs repository lives at [`Thunder-docs`](https://github.com/rooneyj9005/Thunder-docs)

## Contributing to the Pack

You need a local clone of the pack repository and a working `packwiz` installation from the upstream project.

```bash
git clone https://github.com/rooneyj9005/Thunder.git
cd Thunder
```

Once `packwiz` is on your `PATH`, these three do most of the work:

```bash
packwiz modrinth add "mod name"
packwiz refresh
packwiz modrinth export
```

If `shellcheck` is not already available, `checks-shell.sh` will fetch a local copy of the latest release into `tmp/tools` and use that instead.

A few rules matter more than the rest:

- Every repository content change needs a version bump in `pack.toml`.
- Use patch bumps for docs, scripts, workflows, configs, and other minor repository changes.
- Use minor bumps for adding or removing mods.
- Use major bumps only for thoroughly tested, production-ready milestone releases.
- Keep `config/bcc-common.toml` in step with the pack name and version.
- Create and the mods built on it are handled deliberately. Read `mods/create.pw.toml` before updating anything in that family.

Forge tracks the recommended channel. `pack.toml`, `pterodactyl.json`, `tools/install.sh` and `tools/install.ps1` pin the same build and move together, when the recommended build in Forge's promotions file for this Minecraft version passes the one pinned here. Latest is not the trigger, and a recommended build sitting below the pin means there is nothing to do. Bumping Forge is a patch.

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

The scripts work the same way on both platforms:

- the install step fetches Forge and packwiz bootstrap tooling
- the startup step can sync the pack before launch
- the current server runtime accepts Java 17 or Java 21 on both Linux and Windows, with local Temurin 21 bootstrapped if the host has neither
- only exact indexed paths are pack-managed
- `pterodactyl.json` remains the public panel import asset
- the published pack metadata is expected to come from `https://packwiz.thunder.john.rooney.scot/pack.toml`

If you touch pack sync behaviour, check the scripts and the docs site together. They have to tell the same story.

Test them in a separate empty directory. A server booted in the working tree writes its own files into the repository, which is what the second half of `.packwizignore` exists to contain.

## Release Checklist

Go/no-go for a pack release.

- [ ] I have checked that temporary release-test files such as stray `.mrpack` exports are not in source control.
- [ ] I have checked that `pack.toml` reflects the intended release version and state.
- [ ] I have checked that `config/bcc-common.toml` reflects the intended pack name and displayed version.
- [ ] I have checked that `index.toml` matches the current pack-managed contents.
- [ ] I have checked that `packwiz refresh` completed successfully.
- [ ] I have checked that `packwiz modrinth export` completed successfully.
- [ ] I have checked that the release install/update path can pull the published pack metadata successfully.
- [ ] I have checked that `startup.sh`, `functions.sh`, and `tools/update.sh` still use LF line endings.
- [ ] I have checked that a fresh client import launches cleanly and reaches the main menu.
- [ ] I have checked that a fresh client import can join a Thunder server.
- [ ] I have checked that server install and startup behave correctly on Linux.
- [ ] I have checked that server install and startup behave correctly on Windows.
- [ ] I have run the local tests (`sh tests/server.sh` and `sh tests/client.sh`) for changes that could affect runtime behaviour.
- [ ] I have checked that `startup.sh`, `startup.ps1`, `tools/update.sh`, and `tools/update.ps1` are included in the export.
- [ ] I have checked that `.packwizignore` excludes repository-only files without excluding files the pack genuinely needs to ship.
- [ ] I have checked that `pterodactyl.json` is present as a public release asset.
- [ ] I have checked that generated helper binaries remain CI artifacts and are not being published as release assets.
- [ ] I have checked that the docs site and the pack repository still agree on install, update, server, and release behaviour.
- [ ] I have checked that the docs site and the scripts still point at the correct packwiz host.
- [ ] I have checked that any user-facing behaviour change has been reflected in the docs repository or consciously reviewed there.
- [ ] I have checked that all `data-mod-count` fallback values in docs are in sync with the actual mod count (search `Thunder-docs/*.md` for `data-mod-count`).
- [ ] I have checked that the live docs site, or a local preview of it, still makes sense for this release, including download links, server guidance, and version-status checks.
- [ ] I have checked that the chosen version bump matches the kind of change in this release.
- [ ] I have checked that, if this is a major release, it is genuinely production-ready rather than a hopeful milestone.

## Pack Contents

- **Tech:** Create, Mekanism, Applied Energistics 2, Refined Storage, Thermal Expansion, Modular Routers, CC: Tweaked, Mystical Agriculture
- **Magic:** Ars Nouveau, Blood Magic, Hexerei, Apotheosis
- **Building:** Macaw's suite, Chipped, Rechiseled, Immersive Paintings
- **World Gen:** Biomes o' Plenty, Alex's Mobs, Oh The Trees You'll Grow
- **Food:** Farmer's Delight, Create Confectionery, Better Farming Plus
- **Performance and Polish:** Memory Leak Fix, Krypton, Canary, Ferrite Core, RyoamicLights
- **Utility and Server:** SecurityCraft, GriefLogger, LuckPerms, FTB Essentials, Xaero's Maps, Jade, Waystones, Simple Voice Chat, Lootr, Sophisticated Backpacks, WorldEdit

The live [features page](https://thunder.john.rooney.scot/features/) has the fuller player-facing tour.

## Documentation Site

The player-facing site lives in the separate [`Thunder-docs`](https://github.com/rooneyj9005/Thunder-docs) repository.

This repository remains the source of truth for pack metadata, scripts, release assets, and packwiz content. The docs site reads stable release metadata from GitHub and pack metadata from the packwiz host.

## CI/CD

- `checks.yml` runs on pushes to `development` and on pull requests, linting Bash and PowerShell on both Windows and Linux before validating pack metadata consistency and the runtime update path. It stays deliberately light; the heavier end-to-end tests live in `tests/` for contributors to run locally.
- `build.yml` runs for tag pushes, waits for `checks.yml` to succeed on the tagged `development` commit, then rebuilds and validates the pack, uploads helper binaries as workflow artifacts, and creates the GitHub prerelease with the public release assets including `pterodactyl.json`. Version-shaped tags are still checked against `pack.toml`; ad-hoc tags are useful for testing the release pipeline.
- `deploy.yml` runs only when a prerelease is promoted to a stable release, deploys the tagged pack metadata to GitHub Pages, tests the stable install path, and rolls Pages back while demoting the release if that test fails.
- Public release assets are limited to the files intended for players and server admins. Generated helper binaries are not distributed through Releases.
- The Pterodactyl egg reinstall path uses the currently imported egg definition, then fetches `install.sh` and `functions.sh` from the latest stable release. Runtime uses the startup and update scripts bundled with the pack, and optional RCON or Simple Voice Chat ports still need matching panel allocations and firewall rules to be reachable.
- The documentation site is deployed separately from the `Thunder-docs` repository.

## Local Testing

CI deliberately stays light. The end-to-end tests live in `tests/` and are meant to be run by contributors when a change could affect runtime behaviour.

They serve the working-tree pack metadata with `packwiz serve`, then run a Pterodactyl-style Forge server and a Prism-style Forge client against it, one at a time. The server test passes when the server has generated its world and finished starting; the client test passes when the client has loaded the full mod set and reached the title screen. Both check the installed jars against the sides declared in `index.toml`, and both zip their logs into `tmp/tests/`.

```bash
sh tests/server.sh
sh tests/client.sh
```

Each drives a single container, so only one game JVM is ever resident. A server and a client with this mod set do not fit in a default Docker Desktop VM together.

Both take `--pack-url`, so the same script and the same container test the working tree locally or published metadata elsewhere. See [`tests/README.md`](./tests/README.md) for what each test proves, the memory it needs, and the known limits of the headless client.

## Licence and Ethos

This project is as open as the licence allows. Fork it, adjust it, or build on it as you see fit. If you make Thunder better for players, a pull request would be welcome, but it is never an obligation.

The repository contents are available under the MIT licence in [`LICENSE`](./LICENSE). That covers the pack metadata, configs, scripts, and everything else written here. Individual mods included through packwiz remain under their own licences, and nothing here claims ownership of them or relicenses them.

The general house rules are still simple:

- no gambling or real-money mechanics
- no chat spam or nag messages
