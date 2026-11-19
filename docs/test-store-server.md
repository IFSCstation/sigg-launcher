# Test store server

`tool/test_store_server.py` is a dependency-free (Python 3 stdlib) HTTP server
that serves a store catalog and `.siggpkg` payloads, so the store's full flow —
load catalog → install → update → no-op → downgrade refusal → uninstall, plus
every error path — can be exercised without a real repository.

It packages a real game folder (Celeste64 by default) into two valid `.siggpkg`
versions — 1.1.1 and 1.1.2, the latter adding `UPDATE_TEST.txt` — so updates
can be tested on the **same source URL**, and generates synthetic packages for
the edge cases.

## Run

```bash
# Terminal 1 — the server (packages Celeste64 on first start, then caches it)
# --software-folder must match the launcher's SOFTWARE_FOLDER below.
python3 tool/test_store_server.py --port 8080 \
  --software-folder /tmp/sigg-test/software

# Terminal 2 — the launcher, sandboxed so the real ~/software is untouched
flutter run -d linux \
  --dart-define=SOFTWARE_FOLDER=/tmp/sigg-test/software \
  --dart-define=REPOS_FILE=/tmp/sigg-test/repos.json
```

Then in the app: **Loja → Gerenciar fontes → Adicionar repositório** and enter
`http://127.0.0.1:8080/repo.json`.

> The launcher's `SOFTWARE_FOLDER` and the server's `--software-folder` must
> match: the Celeste64 `game.json` bakes the absolute install path into its
> `executable` command. For the sandbox above, start the server with
> `--software-folder /tmp/sigg-test/software`.

If you run the built bundle instead of `flutter run`, the `--dart-define`
values are compiled in; use `HOME`/`XDG_CONFIG_HOME` to relocate instead:

```bash
HOME=/tmp/sigg-test XDG_CONFIG_HOME=/tmp/sigg-test/config \
  ./build/linux/x64/debug/bundle/sigg_launcher
```

## Options

| Option | Default | Meaning |
|---|---|---|
| `--host` | `127.0.0.1` | Bind address (`0.0.0.0` to test from the Pi over LAN) |
| `--port` | `8080` | Port |
| `--game-dir` | `~/Downloads/Celeste64-v1.1.1-Linux-x64` | Real game folder to package |
| `--software-folder` | `~/software` | Registry root the launcher installs into |
| `--cache-dir` | `$XDG_CACHE_HOME/sigg-test-server` (or `/tmp/...`) | Cached real `.siggpkg` |
| `--rebuild` | off | Rebuild the cached real `.siggpkg` files |
| `--no-real-game` | off | Skip Celeste64 (synthetic fixtures only) |
| `--celeste-version` | `1.1.1` | Celeste version the catalog serves at startup (`1.1.1` or `1.1.2`) |
| `--latency` | `0.15` | Seconds between chunks on `/slow/` endpoints |
| `--self-check` | off | Validate every generated fixture and exit |

## Routes

| Route | Purpose |
|---|---|
| `/` | HTML index with links |
| `/repo.json` | Main catalog (Celeste at the current version, `neon-racer` v1.0.0) |
| `/repo-v2.json` | Same catalog with `neon-racer` v2.0.0 (second-source update test) |
| `/repo-extra.json` | Second valid source (merge test) |
| `/admin/celeste` | Current Celeste version + available ones |
| `/admin/celeste/<version>` | Switch the catalog to that Celeste version (same source, no restart) |
| `/broken/repo-malformed.json` | Malformed index (source error) |
| `/broken/repo-500` | HTTP 500 (source error) |
| `/pkgs/<id>.siggpkg` | Valid payloads (Celeste serves the current version) |
| `/broken/<case>.siggpkg` | Invalid payloads |
| `/slow/<id>.siggpkg` | Valid payload streamed slowly (cancel test) |

## Fixtures

Catalog packages:

| Id | Kind | What it tests |
|---|---|---|
| `celeste64` | real game, featured, `REAL` badge | Full install at 1.1.1, then switch the **same** source to 1.1.2 (adds `UPDATE_TEST.txt`) to test update/downgrade |
| `neon-racer` | synthetic game | Fast install; v2.0.0 on `/repo-v2.json` for update/downgrade |
| `calculadora-ifsc` | synthetic **app** | Installs into `apps/`, not `games/` |
| `browse-only` | no `url` | Disabled CTA / "Sem fonte de download" |
| `slow-download` | valid, served slowly | Progress + Cancelar |
| `broken-*` | invalid payloads | Validation error SnackBars |

Broken payloads: missing `manifest.json`, missing `images/icon.*`, missing
`metadata/achievements.toml`, `game_id` mismatch, `../` traversal entry,
symlink entry, corrupt zip, and a 404 download URL.

`--self-check` reopens every generated zip and asserts the manifest and
required files, so a fixture typo fails fast instead of mid-test.

## Manual checklist

1. Add the source → "Jogos"/"Apps"/"Quebrados" sections + featured banner load.
2. Category chips filter Todos/Jogos/Apps.
3. Install `celeste64` (1.1.1) → determinate progress → "instalado";
   INSTALADO pill; folder at `<software>/games/celeste64/`; the game appears on
   Home/Library with its generated art; launching it hides the launcher and
   runs the game.
4. Re-install the same version → "já está atualizado"; local files untouched.
5. Update on the **same source**:

   ```bash
   curl http://127.0.0.1:8080/admin/celeste/1.1.2
   ```

   In the app open **Gerenciar fontes** and go back (the store reloads the
   source), open Celeste → the dialog shows `Versão 1.1.2` /
   `Instalado 1.1.1` → **Atualizar** → "Celeste 64 atualizado." and
   `<software>/games/celeste64/UPDATE_TEST.txt` exists with `version: 1.1.2`
   (the ledger `metadata/package.json` also says 1.1.2).
6. Switch back with `/admin/celeste/1.1.1`, reload → **Atualizar** →
   downgrade refused ("não é possível rebaixar"); the install stays 1.1.2 and
   `UPDATE_TEST.txt` survives.
7. Install `calculadora-ifsc` → lands in `<software>/apps/`.
8. Uninstall → confirm → folder removed, pill cleared, Home entry gone.
9. `browse-only` → disabled CTA / "Sem fonte de download".
10. Each `broken-*` → the matching validation SnackBar; staging stays empty.
11. `slow-download` → Cancelar stops it and sweeps staging.
12. `/broken/repo-malformed.json` and `/broken/repo-500` as sources → the
    repositories page shows the error and other sources still load.

The synthetic `neon-racer` pair (`/repo.json` 1.0.0 vs `/repo-v2.json` 2.0.0)
exercises the same update/downgrade flow through a *second* source, if you want
to test source switching too.

## Notes

- The installer does not preserve file permissions. Celeste64's payload ships
  `bin/run.sh`, run through `sh`, which restores the executable bit and `cd`s
  into the payload root before exec'ing the game.
- The real packages are cached (~30.8 MiB each, 1.1.1 and 1.1.2); the first
  start takes a few seconds, later starts are instant. Use `--rebuild` after
  changing the game folder (it rebuilds both versions).
- `UPDATE_TEST.txt` exists only in the 1.1.2 payload, so its presence proves the
  update replaced the installed folder. Same-version re-installs keep the old
  folder untouched (local files survive), and downgrades are refused.
- `slow-download` carries ~768 KiB of incompressible filler, so at the default
  `--latency 0.15` the download runs for ~15 s — long enough to click
  **Cancelar**.
- The store does not dedupe package ids across sources: adding both
  `/repo.json` and `/repo-v2.json` shows two `neon-racer` entries (1.0.0 and
  2.0.0). Remove the v1 source before adding v2 so the detail dialog has a
  single "Atualizar" target. The Celeste version switch does **not** create
  duplicates — it changes the version served by the same source URL.
- `addSource` accepts http(s) URLs (it awaits `RepositoryService.fetch`); local
  paths still use the synchronous `fetchSync` path.
