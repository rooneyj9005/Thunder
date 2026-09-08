# Test Harness

End-to-end tests for the pack: a real server and a real client, each installed
and launched the way a real one is, against whichever pack metadata you point
them at. They exist so a runtime problem surfaces here rather than on someone's
server after a release.

One driver and one Dockerfile per side. Each driver builds an image, runs a
single container, watches it from the outside and collects its logs. Only one
game JVM is ever resident, and that falls out of the structure without a driver
having to police it.

That matters because of how the old harness failed. It started a server and a
client together, the Docker VM ran out of memory and thrashed, and the engine
stopped answering. From the outside that looks like a hung test, not a failed
one.

## Running Them

```bash
sh tests/server.sh
sh tests/client.sh
```

Both need Docker. Both default to testing your working tree.

```bash
sh tests/server.sh --clean            # start from an empty volume
sh tests/client.sh --memory 2048      # smaller heap
sh tests/server.sh --keep             # leave the container up afterwards
sh tests/server.sh --help             # every option
```

Logs land in `tmp/tests/` as `server-logs.zip` and `client-logs.zip`, plus
`crash-reports-server.zip` or `crash-reports-client.zip` when the game wrote any.
They survive the container. `tmp/` is where everything throwaway lives, and it is
gitignored and kept out of the pack.

## What Each One Proves

**server.sh** installs the pack the way the Pterodactyl egg does, using the
pack's own `install.sh` and `startup.sh` on the real yolk image, then waits for
`]: Done (` in the server log. That line means Forge loaded every server mod,
the world generated, and the server is accepting connections. It then checks the
installed jars against the server-side entries in `index.toml` and summarises the
ERROR and WARN lines the run produced.

**client.sh** syncs the client side with packwiz-installer, the same way a
launcher would, then launches Forge headless through portablemc. It is judged on
a ladder of markers, not one, because where it stops is the diagnostic:

| Rung        | Means                                                            |
| ----------- | ---------------------------------------------------------------- |
| `resources` | every client mod was constructed and the resource reload began    |
| `atlas`     | the texture atlases were stitched, so it reached the title screen |

It passes at `atlas`, then holds for 20 seconds to confirm the client is still
up, because a client short of heap dies around there. Anything less is a failure
that names the furthest rung it reached. The mod set is checked against the
client-side entries in `index.toml`.

The client stops at the title screen deliberately. Driving a headless client
into a world needs a save for it to open, and creating one without a UI costs
more than it proves. `server.sh` already covers world generation and loading, so
the client's job is the half only a client can do: every client mod constructs,
the resource reload completes, and the atlases stitch under software OpenGL.

## Where the Pack Comes From

By default both drivers serve your working tree with `packwiz serve`. It serves
only files listed in the index, so the container sees the file set the packwiz
host publishes and nothing else. It also refreshes the index as it is queried,
which keeps your working tree and `index.toml` from disagreeing part way through
a run. If a run rewrites `index.toml`, that is telling you the tree was stale.

Point `--pack-url` elsewhere to test published metadata instead, with the same
script, the same container and the same assertions:

```bash
sh tests/server.sh --pack-url https://packwiz.thunder.john.rooney.scot/pack.toml
```

`install.sh` and `functions.sh` are release assets rather than pack content,
and `.packwizignore` keeps `install.sh` out of the index deliberately, so the
packwiz host does not serve them. A local run mounts the working-tree copies into
the container. `--install-assets-url` fetches them from a GitHub release instead,
which is exactly what the egg's install script does.

## Memory

Defaults in MiB. The ceiling is the heap plus room for the JVM's own native
memory, so the kernel kills a runaway container instead of the whole Docker VM
going down with it.

| Test   | Heap | Container ceiling |
| ------ | ---- | ----------------- |
| server | 4096 | 5120              |
| client | 4096 | 6656              |

Override per run with `--memory`, or with `THUNDER_SERVER_MEMORY` and
`THUNDER_CLIENT_MEMORY`. Each driver checks its budget against the memory the
Docker engine actually reports before it starts anything, and says what to lower
if it does not fit.

The client heap is smaller than the server's on purpose. A Forge client keeps
about 1.2 GB outside the heap for mod metaspace, the code cache and software
rendering buffers, and the page cache for a gigabyte of jars and assets counts
against the ceiling too.

## Known Limits

**The client needs a real heap.** The long-standing failure at the texture atlas
was heap exhaustion, not the GL stack. A 3072 MiB heap dies there with
`java.lang.OutOfMemoryError: Java heap space`; 4096 MiB loads the full mod set
and reaches the title screen. That retires the older theory recorded here, which
read the absence of an `hs_err` file as evidence of a native GL crash. Software
OpenGL renders the pack perfectly well, and `glxinfo -B` is logged at startup if
you want to see what it is using.

4096 MiB is the test floor, not a recommendation. The pack's own docs put the
player floor at 6 GB, and the test only fits below that because it runs at
render distance 6 with mipmaps off and no sound.

**The client test needs about 6.9 GB of Docker VM.** Heap plus ceiling plus the
driver's reserve comes to more than a default Docker Desktop VM on a 16 GB
machine has spare once anything else is running. The driver checks this before
it builds anything and says what to lower, but the real fix is giving Docker
more memory in `%UserProfile%\.wslconfig`.

**portablemc cannot pass the game its own arguments.** `portablemc start` takes
a version and nothing else, and rejects anything after it, including anything
after a `--`. Its only Quick Play options are the multiplayer pair, `-s` and
`-p`. That is the practical reason the client stops at the title screen rather
than opening a world, and it is worth knowing before anyone tries
`--quickPlaySingleplayer` again.

## Why Offline Mode Is Not Needed

Neither test connects to Mojang, and neither connects to the other. The client
launches offline and never leaves the title screen, so nothing here needs the
server put into offline mode and the shipped pack keeps online mode on.

## Files

| File                | What it is                                               |
| ------------------- | -------------------------------------------------------- |
| `functions.sh`      | shared plumbing: pack host, waiting, log collection       |
| `server.sh`         | drives the server container and judges the result         |
| `server.Dockerfile` | the Pterodactyl yolk image, plus the install and boot     |
| `client.sh`         | drives the client container and walks the ladder          |
| `client.Dockerfile` | Java 21, Xvfb, software OpenGL, portablemc, and the sync  |

Run logs are local diagnostics. Do not commit them or publish them as release
assets.
