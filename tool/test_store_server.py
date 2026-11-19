#!/usr/bin/env python3
"""Local HTTP catalog + `.siggpkg` fixtures for exercising the IFSCstation store.

The launcher's store is a plain HTTP client: it GETs a repository index JSON
(HTTP 200, UTF-8) and then GETs the `.siggpkg` payloads advertised by each
package's `url`. This script serves both, plus deliberately broken fixtures so
the store's error paths can be tested without a real repository.

Run it, then add `http://127.0.0.1:8080/repo.json` as a source in the store's
"Gerenciar fontes" page (or write it into `repos.json` by hand). See
`docs/test-store-server.md` for the full manual checklist.

No third-party dependencies: everything is Python's standard library.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import random
import shutil
import struct
import sys
import time
import zipfile
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

DEFAULT_GAME_DIR = "~/Downloads/Celeste64-v1.1.1-Linux-x64"
DEFAULT_CACHE_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or "/tmp", "sigg-test-server"
)

# Celeste64 is served in two versions so the store's update path can be tested
# on the SAME repository URL: 1.1.1 is the base payload, 1.1.2 adds
# UPDATE_TEST.txt so the update is easy to verify on disk. The catalog version
# is switched at runtime with /admin/celeste/<version>.
CELESTE_VERSIONS = ("1.1.1", "1.1.2")
CELESTE_LATEST = CELESTE_VERSIONS[-1]
CELESTE_UPDATE_MARKER = "UPDATE_TEST.txt"

# ---------------------------------------------------------------------------
# Tiny PNG generator (no Pillow): vertical gradient + simple triangle/rect art.
# The installer only checks file extensions, but valid art makes the installed
# entry render on Home/Library instead of showing an image error.
# ---------------------------------------------------------------------------


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    body = tag + data
    return (
        struct.pack(">I", len(data))
        + body
        + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    )


def make_png(
    width: int,
    height: int,
    top: tuple[int, int, int],
    bottom: tuple[int, int, int],
    triangles: tuple[tuple[int, int, int, int, tuple[int, int, int]], ...] = (),
    rects: tuple[tuple[int, int, int, int, tuple[int, int, int]], ...] = (),
) -> bytes:
    """Build a truecolour PNG. `triangles` are (cx, base_y, half_w, height, rgb)."""
    rows: list[bytes] = []
    for y in range(height):
        t = y / max(1, height - 1)
        color = bytes(
            round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)
        )
        row = bytearray(b"\x00")  # PNG filter type 0 (None)
        row.extend(color * width)

        for x0, y0, x1, y1, rgb in rects:
            if y0 <= y < y1:
                left = max(0, x0)
                right = min(width, x1)
                if left < right:
                    row[1 + left * 3 : 1 + right * 3] = bytes(rgb) * (right - left)

        for cx, base_y, half_w, tri_h, rgb in triangles:
            if base_y - tri_h <= y < base_y:
                frac = (base_y - y) / tri_h
                w = int(half_w * (1.0 - frac)) + 1
                left = max(0, cx - w)
                right = min(width, cx + w)
                if left < right:
                    row[1 + left * 3 : 1 + right * 3] = bytes(rgb) * (right - left)

        rows.append(bytes(row))

    return (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + _png_chunk(b"IDAT", zlib.compress(b"".join(rows), 6))
        + _png_chunk(b"IEND", b"")
    )


def art(color: tuple[int, int, int]) -> dict[str, bytes]:
    """Hero/cover/icon set for a synthetic package, tinted with `color`."""
    dark = tuple(max(0, c - 90) for c in color)
    light = tuple(min(255, c + 90) for c in color)
    return {
        "hero": make_png(
            1900,
            620,
            light,
            dark,
            triangles=((500, 620, 420, 300, dark), (1250, 620, 520, 380, dark)),
        ),
        "cover": make_png(
            600,
            900,
            light,
            dark,
            triangles=((300, 900, 300, 380, dark),),
        ),
        "icon": make_png(
            512,
            512,
            light,
            dark,
            triangles=((256, 512, 230, 260, dark),),
        ),
    }


def celeste_art() -> dict[str, bytes]:
    sky = (126, 178, 221)
    snow = (244, 249, 255)
    mountain = (43, 74, 110)
    rock = (30, 52, 78)
    sun = (255, 226, 140)
    return {
        "hero": make_png(
            1900,
            620,
            sky,
            snow,
            triangles=(
                (420, 620, 430, 360, mountain),
                (1100, 620, 520, 430, rock),
                (1620, 620, 380, 300, mountain),
            ),
            rects=((1560, 90, 1690, 220, sun),),
        ),
        "cover": make_png(
            600,
            900,
            sky,
            snow,
            triangles=((300, 900, 320, 470, mountain), (110, 900, 200, 300, rock)),
            rects=((430, 90, 520, 180, sun),),
        ),
        "icon": make_png(
            512,
            512,
            sky,
            snow,
            triangles=((256, 512, 240, 300, mountain),),
            rects=((360, 60, 440, 140, sun),),
        ),
    }


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

CELESTE_ACHIEVEMENTS = """name = "Celeste 64"

[achievements.first-summit]
title = "Primeiro cume"
description = "Alcance o topo da montanha."
points = 20

[achievements.strawberry-hunter]
title = "Caçador de morangos"
description = "Colete 10 morangos."
points = 10
needs_events = { strawberries = 10 }
"""

DEMO_ACHIEVEMENTS = """name = "{name}"

[achievements.first-launch]
title = "Primeira sessão"
description = "Abra o jogo pela loja."
points = 5
"""

RUN_SH = """#!/bin/sh
# The installer does not preserve the executable bit, so the launcher runs this
# script with `sh` (no +x needed); it restores the bit and cds into the payload
# root, which the game needs to find its Content/ assets.
cd "$(dirname "$0")/.." || exit 1
chmod +x Celeste64 2>/dev/null || true
exec ./Celeste64 "$@"
"""


def _json_bytes(data: object) -> bytes:
    return json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")


def build_synthetic_package(
    *,
    game_id: str,
    name: str,
    version: str,
    color: tuple[int, int, int],
    executable: str = "sleep 3",
    include_manifest: bool = True,
    manifest_overrides: dict | None = None,
    payload_folder: str | None = None,
    skip: tuple[str, ...] = (),
    extra: tuple[tuple[str, bytes], ...] = (),
    symlink: bool = False,
    pad_bytes: int = 0,
) -> bytes:
    """A spec-conforming `.siggpkg`, with knobs for the invalid variants."""
    payload = payload_folder or game_id
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        if include_manifest:
            manifest = {
                "package": "sigg-game",
                "pkg_version": 1,
                "game_id": game_id,
                "name": name,
                "version": version,
                "exec": "bin/demo.sh",
            }
            if manifest_overrides:
                manifest.update(manifest_overrides)
            zf.writestr("manifest.json", _json_bytes(manifest))

        def add(rel: str, data: bytes) -> None:
            if rel in skip:
                return
            zf.writestr(f"{payload}/{rel}", data)

        add(
            "metadata/game.json",
            _json_bytes(
                {
                    "name": name,
                    "tagline": f"{name} — pacote de teste.",
                    "description": "Pacote gerado pelo servidor de testes.",
                    "genre": "Teste",
                    "executable": executable,
                }
            ),
        )
        add("metadata/achievements.toml", DEMO_ACHIEVEMENTS.format(name=name).encode())
        images = art(color)
        add("images/hero.png", images["hero"])
        add("images/cover.png", images["cover"])
        add("images/icon.png", images["icon"])
        add(
            "bin/demo.sh",
            b"#!/bin/sh\necho 'demo package'\n",
        )
        if pad_bytes:
            # Incompressible filler: keeps the /slow/ download alive long
            # enough to exercise the Cancelar button.
            add("bin/pad.bin", random.Random(1234).randbytes(pad_bytes))

        for rel, data in extra:
            zf.writestr(rel, data)

        if symlink:
            info = zipfile.ZipInfo(f"{payload}/bin/link")
            info.create_system = 3  # Unix
            info.external_attr = 0o120777 << 16  # S_IFLNK | 0777
            zf.writestr(info, "../../../etc/passwd")

    return buf.getvalue()


def build_real_package(
    game_dir: str,
    software_folder: str,
    cache_path: str,
    rebuild: bool,
    version: str,
) -> str:
    """Zip the real Celeste64 folder into a cached `.siggpkg` (payload `celeste64/`).

    [version] is baked into the manifest; [CELESTE_LATEST] also gets the
    [CELESTE_UPDATE_MARKER] file so an update is visible in the installed
    folder.
    """
    if os.path.exists(cache_path) and not rebuild:
        return cache_path

    payload = "celeste64"
    install_dir = os.path.join(software_folder, "games", payload)
    # The launcher's `executable` is a shell command. The installed folder's
    # name is fixed, so bake the absolute path (works with a custom
    # --software-folder as long as the launcher uses the same one).
    executable = f'sh "{install_dir}/bin/run.sh"'
    images = celeste_art()

    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    tmp_path = cache_path + ".tmp"
    print(
        f"[build] packaging Celeste 64 {version} {game_dir} -> {cache_path}",
        flush=True,
    )
    started = time.time()
    try:
        with zipfile.ZipFile(
            tmp_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6
        ) as zf:
            zf.writestr(
                "manifest.json",
                _json_bytes(
                    {
                        "package": "sigg-game",
                        "pkg_version": 1,
                        "game_id": payload,
                        "name": "Celeste 64",
                        "version": version,
                        "exec": "bin/run.sh",
                    }
                ),
            )
            zf.writestr(
                f"{payload}/metadata/game.json",
                _json_bytes(
                    {
                        "name": "Celeste 64",
                        "tagline": "Uma montanha, uma escalada, uma aventura em 3D.",
                        "description": (
                            "A versão 3D de Celeste: corra, escale e colete "
                            "morangos pelos caminhos da montanha."
                        ),
                        "genre": "Plataforma 3D",
                        "executable": executable,
                    }
                ),
            )
            zf.writestr(
                f"{payload}/metadata/achievements.toml",
                CELESTE_ACHIEVEMENTS.encode(),
            )
            for name, data in images.items():
                zf.writestr(f"{payload}/images/{name}.png", data)
            zf.writestr(f"{payload}/bin/run.sh", RUN_SH.encode())
            if version == CELESTE_LATEST:
                zf.writestr(
                    f"{payload}/{CELESTE_UPDATE_MARKER}",
                    (
                        "Celeste 64 update marker\n"
                        f"version: {version}\n"
                        "Only the newer package contains this file, so its\n"
                        "presence proves the update replaced the payload.\n"
                    ).encode(),
                )

            generated = {
                "metadata/game.json",
                "metadata/achievements.toml",
                "images/hero.png",
                "images/cover.png",
                "images/icon.png",
                "bin/run.sh",
                CELESTE_UPDATE_MARKER,
            }
            for root, dirs, files in os.walk(game_dir):
                dirs.sort()
                files.sort()
                for fname in files:
                    if fname.endswith(".pdb"):  # debug symbols, not needed
                        continue
                    src = os.path.join(root, fname)
                    rel = os.path.relpath(src, game_dir).replace(os.sep, "/")
                    if rel in generated:
                        continue
                    zf.write(src, f"{payload}/{rel}")
        os.replace(tmp_path, cache_path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    size = os.path.getsize(cache_path)
    print(
        f"[build] done in {time.time() - started:.1f}s "
        f"({size / (1024 * 1024):.1f} MiB)",
        flush=True,
    )
    return cache_path


# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------


def package_entry(
    *,
    pid: str,
    name: str,
    version: str,
    section: str,
    icon: str,
    color: str,
    tagline: str,
    category: str = "game",
    url: str | None = None,
    badge: str | None = None,
    featured: bool = False,
) -> dict:
    entry = {
        "id": pid,
        "name": name,
        "tagline": tagline,
        "version": version,
        "section": section,
        "category": category,
        "icon": icon,
        "color": color,
    }
    if url is not None:
        entry["url"] = url
    if badge is not None:
        entry["badge"] = badge
    if featured:
        entry["featured"] = True
    return entry


def build_catalog(state: "State", host: str, variant: str) -> dict:
    base = f"http://{host}"

    if variant == "extra":
        return {
            "name": "IFSCstation Extras",
            "author": "Equipe IFSCstation",
            "description": "Segunda fonte de teste (merge de repositórios).",
            "packages": [
                package_entry(
                    pid="extra-app",
                    name="Extra App",
                    version="1.0.0",
                    section="Apps",
                    icon="extension",
                    color="#26A69A",
                    tagline="Pacote que só existe na segunda fonte.",
                    category="app",
                    url=f"{base}/pkgs/extra-app.siggpkg",
                )
            ],
        }

    packages = []

    if state.real_package:
        packages.append(
            package_entry(
                pid="celeste64",
                name="Celeste 64",
                version=state.celeste_version,
                section="Jogos",
                icon="sports_esports",
                color="#4FC3F7",
                tagline=(
                    "A montanha em 3D: corra, escale e colete morangos. "
                    "Pacote real empacotado pelo servidor de testes."
                ),
                badge="REAL",
                featured=True,
                url=f"{base}/pkgs/celeste64.siggpkg",
            )
        )

    neon_version = "2.0.0" if variant == "v2" else "1.0.0"
    neon_payload = (
        "neon-racer-2.0.0.siggpkg"
        if variant == "v2"
        else "neon-racer.siggpkg"
    )
    packages.extend(
        [
            package_entry(
                pid="neon-racer",
                name="Neon Racer",
                version=neon_version,
                section="Jogos",
                icon="directions_car",
                color="#E91E63",
                tagline=(
                    "Corridas de rua sob as luzes da cidade. "
                    "Versão 2.0.0 no /repo-v2.json."
                ),
                url=f"{base}/pkgs/{neon_payload}",
            ),
            package_entry(
                pid="calculadora-ifsc",
                name="Calculadora IFSC",
                version="1.1.0",
                section="Apps",
                icon="code",
                color="#2196F3",
                tagline="Calculadora científica — deve instalar em apps/.",
                category="app",
                url=f"{base}/pkgs/calculadora-ifsc.siggpkg",
            ),
            package_entry(
                pid="browse-only",
                name="Pacote Só Navegável",
                version="1.0.0",
                section="Apps",
                icon="widgets",
                color="#8D6E63",
                tagline="Sem url: o CTA deve ficar desabilitado (Indisponível).",
                category="app",
            ),
            package_entry(
                pid="slow-download",
                name="Download Lento",
                version="1.0.0",
                section="Jogos",
                icon="bolt",
                color="#FFB300",
                tagline="Payload servido em pedaços: use Cancelar para abortar.",
                url=f"{base}/slow/slow-download.siggpkg",
            ),
        ]
    )

    broken = [
        (
            "broken-missing-manifest",
            "Quebrado: sem manifest.json",
            "broken-missing-manifest.siggpkg",
        ),
        (
            "broken-missing-icon",
            "Quebrado: sem images/icon.*",
            "broken-missing-icon.siggpkg",
        ),
        (
            "broken-missing-achievements",
            "Quebrado: sem achievements.toml",
            "broken-missing-achievements.siggpkg",
        ),
        (
            "broken-wrong-id",
            "Quebrado: game_id divergente",
            "broken-wrong-id.siggpkg",
        ),
        (
            "broken-traversal",
            "Quebrado: caminho ../",
            "broken-traversal.siggpkg",
        ),
        (
            "broken-symlink",
            "Quebrado: link simbólico",
            "broken-symlink.siggpkg",
        ),
        (
            "broken-corrupt",
            "Quebrado: zip corrompido",
            "broken-corrupt.siggpkg",
        ),
        (
            "broken-404",
            "Quebrado: download 404",
            "404.siggpkg",
        ),
    ]
    for pid, name, file_name in broken:
        packages.append(
            package_entry(
                pid=pid,
                name=name,
                version="0.0.0",
                section="Quebrados",
                icon="gavel",
                color="#F44336",
                tagline="Fixture de erro: instalar deve falhar com uma mensagem.",
                url=f"{base}/broken/{file_name}",
            )
        )

    return {
        "name": "IFSCstation Testes",
        "author": "Equipe IFSCstation",
        "description": "Catálogo local do servidor de testes da loja.",
        "packages": packages,
    }


# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------


class State:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.celeste_packages: dict[str, str] = {}
        self.celeste_version = CELESTE_VERSIONS[0]
        self.packages: dict[str, bytes] = {}
        self.broken: dict[str, bytes] = {}

    @property
    def real_package(self) -> str | None:
        """Cache path of the Celeste package the catalog currently serves."""
        return self.celeste_packages.get(self.celeste_version)

    def prepare(self) -> None:
        self._build_synthetic()
        self._prepare_real()

    def _build_synthetic(self) -> None:
        # Valid packages.
        self.packages["neon-racer.siggpkg"] = build_synthetic_package(
            game_id="neon-racer",
            name="Neon Racer",
            version="1.0.0",
            color=(233, 30, 99),
        )
        self.packages["neon-racer-2.0.0.siggpkg"] = build_synthetic_package(
            game_id="neon-racer",
            name="Neon Racer",
            version="2.0.0",
            color=(233, 30, 99),
        )
        self.packages["calculadora-ifsc.siggpkg"] = build_synthetic_package(
            game_id="calculadora-ifsc",
            name="Calculadora IFSC",
            version="1.1.0",
            color=(33, 150, 243),
            executable="sleep 1",
        )
        self.packages["extra-app.siggpkg"] = build_synthetic_package(
            game_id="extra-app",
            name="Extra App",
            version="1.0.0",
            color=(38, 166, 154),
            executable="sleep 1",
        )
        self.packages["slow-download.siggpkg"] = build_synthetic_package(
            game_id="slow-download",
            name="Download Lento",
            version="1.0.0",
            color=(255, 179, 0),
            executable="sleep 1",
            pad_bytes=768 * 1024,
        )

        # Invalid packages.
        self.broken["broken-missing-manifest.siggpkg"] = build_synthetic_package(
            game_id="broken-missing-manifest",
            name="Sem manifest",
            version="0.0.0",
            color=(244, 67, 54),
            include_manifest=False,
        )
        self.broken["broken-missing-icon.siggpkg"] = build_synthetic_package(
            game_id="broken-missing-icon",
            name="Sem ícone",
            version="0.0.0",
            color=(244, 67, 54),
            skip=("images/icon.png",),
        )
        self.broken["broken-missing-achievements.siggpkg"] = build_synthetic_package(
            game_id="broken-missing-achievements",
            name="Sem troféus",
            version="0.0.0",
            color=(244, 67, 54),
            skip=("metadata/achievements.toml",),
        )
        self.broken["broken-wrong-id.siggpkg"] = build_synthetic_package(
            game_id="broken-wrong-id",
            name="Id divergente",
            version="0.0.0",
            color=(244, 67, 54),
            manifest_overrides={"game_id": "other-game"},
            payload_folder="other-game",
        )
        self.broken["broken-traversal.siggpkg"] = build_synthetic_package(
            game_id="broken-traversal",
            name="Traversal",
            version="0.0.0",
            color=(244, 67, 54),
            extra=(("../evil.txt", b"evil"),),
        )
        self.broken["broken-symlink.siggpkg"] = build_synthetic_package(
            game_id="broken-symlink",
            name="Symlink",
            version="0.0.0",
            color=(244, 67, 54),
            symlink=True,
        )
        self.broken["broken-corrupt.siggpkg"] = b"this is definitely not a zip"

    def _prepare_real(self) -> None:
        if self.args.no_real_game:
            print("[info] --no-real-game: skipping the Celeste64 fixture", flush=True)
            return
        game_dir = os.path.expanduser(self.args.game_dir)
        if not os.path.isdir(game_dir):
            print(
                f"[warn] real game not found at {game_dir}; "
                "skipping the Celeste64 fixture (use --game-dir)",
                flush=True,
            )
            return
        if not os.path.isfile(os.path.join(game_dir, "Celeste64")):
            print(
                f"[warn] {game_dir}/Celeste64 is missing; skipping the fixture",
                flush=True,
            )
            return
        software_folder = os.path.expanduser(self.args.software_folder)
        # The payload bakes the install path into its `executable`, so the
        # cache key includes both folders to avoid serving a stale path.
        tag = hashlib.sha1(
            f"{game_dir}|{software_folder}".encode()
        ).hexdigest()[:8]
        for version in CELESTE_VERSIONS:
            cache_path = os.path.join(
                os.path.expanduser(self.args.cache_dir),
                f"celeste64-{version}-{tag}.siggpkg",
            )
            self.celeste_packages[version] = build_real_package(
                game_dir,
                software_folder,
                cache_path,
                self.args.rebuild,
                version,
            )
        self.celeste_version = self.args.celeste_version


def _self_check(state: State) -> int:
    failures = 0
    checked = 0
    for name, data in state.packages.items():
        checked += 1
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as zf:
                names = set(zf.namelist())
                manifest = json.loads(zf.read("manifest.json"))
                gid = manifest["game_id"]
                assert manifest["package"] == "sigg-game"
                assert manifest["pkg_version"] == 1
                for rel in (
                    "metadata/game.json",
                    "metadata/achievements.toml",
                    "images/hero.png",
                    "images/cover.png",
                    "images/icon.png",
                ):
                    assert f"{gid}/{rel}" in names, f"{name}: missing {rel}"
            print(f"[ok] {name}", flush=True)
        except Exception as exc:  # noqa: BLE001 - report every fixture
            failures += 1
            print(f"[FAIL] {name}: {exc}", flush=True)

    for version, path in state.celeste_packages.items():
        checked += 1
        label = f"celeste64-{version}.siggpkg"
        try:
            with zipfile.ZipFile(path) as zf:
                manifest = json.loads(zf.read("manifest.json"))
                names = zf.namelist()
                assert manifest["game_id"] == "celeste64"
                assert manifest["version"] == version, "manifest version mismatch"
                assert "celeste64/Celeste64" in names, "missing Celeste64 binary"
                assert any(
                    name.startswith("celeste64/Content/") for name in names
                ), "missing Content/ assets"
                for rel in (
                    "metadata/game.json",
                    "metadata/achievements.toml",
                    "images/hero.png",
                    "images/cover.png",
                    "images/icon.png",
                    "bin/run.sh",
                ):
                    assert f"celeste64/{rel}" in names, f"missing {rel}"
                has_marker = f"celeste64/{CELESTE_UPDATE_MARKER}" in names
                assert has_marker == (version == CELESTE_LATEST), (
                    f"update marker should exist only in {CELESTE_LATEST}"
                )
            print(f"[ok] {label}", flush=True)
        except Exception as exc:  # noqa: BLE001
            failures += 1
            print(f"[FAIL] {label}: {exc}", flush=True)

    print(
        f"\n{checked - failures}/{checked} fixture packages valid"
        + (f" — {failures} failure(s)" if failures else ""),
        flush=True,
    )
    return 1 if failures else 0


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "SiggTestStore/1.0"

    @property
    def state(self) -> State:
        return self.server.state  # type: ignore[attr-defined]

    # -- response helpers ---------------------------------------------------

    def _bytes(
        self,
        body: bytes,
        content_type: str,
        status: int = 200,
        extra_headers: dict[str, str] | None = None,
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for key, value in (extra_headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _json(self, data: object, status: int = 200) -> None:
        self._bytes(
            _json_bytes(data),
            "application/json; charset=utf-8",
            status=status,
        )

    def _not_found(self) -> None:
        self._bytes(b"not found\n", "text/plain; charset=utf-8", status=404)

    def _send_file(self, path: str, content_type: str) -> None:
        size = os.path.getsize(path)
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(size))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        with open(path, "rb") as handle:
            shutil.copyfileobj(handle, self.wfile, 256 * 1024)

    def _send_slow(self, data: bytes, content_type: str) -> None:
        delay = self.state.args.latency
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        chunk = 8 * 1024
        for offset in range(0, len(data), chunk):
            self.wfile.write(data[offset : offset + chunk])
            self.wfile.flush()
            time.sleep(delay)

    def _html_index(self, host: str) -> None:
        paths = [
            "/repo.json",
            "/repo-v2.json",
            "/repo-extra.json",
            "/pkgs/neon-racer.siggpkg",
            "/pkgs/calculadora-ifsc.siggpkg",
            "/slow/slow-download.siggpkg",
            "/admin/celeste",
            "/broken/repo-malformed.json",
            "/broken/repo-500",
        ]
        if self.state.real_package:
            paths.insert(3, "/pkgs/celeste64.siggpkg")
        rows = "\n".join(
            f'<li><a href="{path}">{path}</a></li>' for path in paths
        )
        body = (
            "<!doctype html><meta charset='utf-8'>"
            "<h1>IFSCstation test store</h1>"
            f"<p>Adicione <code>http://{host}/repo.json</code> como fonte na loja.</p>"
            f"<p>Atualizar o Celeste: <code>http://{host}/admin/celeste/"
            f"{CELESTE_LATEST}</code> (reabra a loja depois).</p>"
            f"<ul>{rows}</ul>"
        ).encode("utf-8")
        self._bytes(body, "text/html; charset=utf-8")

    # -- routing ------------------------------------------------------------

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        path = urlsplit(self.path).path
        address, port = self.server.server_address[:2]
        host = self.headers.get("Host") or f"{address}:{port}"
        try:
            if path == "/":
                self._html_index(host)
            elif path == "/repo.json":
                self._json(build_catalog(self.state, host, "v1"))
            elif path == "/repo-v2.json":
                self._json(build_catalog(self.state, host, "v2"))
            elif path == "/repo-extra.json":
                self._json(build_catalog(self.state, host, "extra"))
            elif path == "/admin/celeste":
                current = self.state.celeste_version
                available = ", ".join(self.state.celeste_packages) or "none"
                self._bytes(
                    f"Celeste: serving {current} (available: {available})\n".encode(),
                    "text/plain; charset=utf-8",
                )
            elif path.startswith("/admin/celeste/"):
                version = path[len("/admin/celeste/") :]
                if version not in self.state.celeste_packages:
                    available = ", ".join(self.state.celeste_packages) or "none"
                    self._bytes(
                        (
                            f"unknown Celeste version {version!r}; "
                            f"available: {available}\n"
                        ).encode(),
                        "text/plain; charset=utf-8",
                        status=404,
                    )
                else:
                    # Mutating on GET is fine for a local test fixture: it
                    # keeps the switch a single curl/browser hit.
                    self.state.celeste_version = version
                    self._bytes(
                        (
                            f"catalog now serves Celeste {version}. "
                            "Reload the store (Gerenciar fontes -> back) "
                            "to see the update.\n"
                        ).encode(),
                        "text/plain; charset=utf-8",
                    )
            elif path == "/broken/repo-malformed.json":
                self._bytes(
                    b'{"name": "quebrado", "packages": [',
                    "application/json; charset=utf-8",
                )
            elif path == "/broken/repo-500":
                self._bytes(
                    b"erro interno do servidor de teste\n",
                    "text/plain; charset=utf-8",
                    status=500,
                )
            elif path.startswith("/pkgs/"):
                name = path[len("/pkgs/") :]
                if name == "celeste64.siggpkg" and self.state.real_package:
                    self._send_file(self.state.real_package, "application/zip")
                elif name in self.state.packages:
                    self._bytes(self.state.packages[name], "application/zip")
                else:
                    self._not_found()
            elif path.startswith("/broken/"):
                name = path[len("/broken/") :]
                if name in self.state.broken:
                    self._bytes(self.state.broken[name], "application/zip")
                else:
                    self._not_found()
            elif path.startswith("/slow/"):
                name = path[len("/slow/") :]
                if name in self.state.packages:
                    self._send_slow(self.state.packages[name], "application/zip")
                else:
                    self._not_found()
            else:
                self._not_found()
        except (BrokenPipeError, ConnectionResetError):
            # The store cancels downloads by closing the connection.
            pass

    def log_message(self, fmt: str, *args: object) -> None:
        sys.stderr.write(
            f"[{time.strftime('%H:%M:%S')}] {self.address_string()} "
            f"{fmt % args}\n"
        )


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], state: State) -> None:
        super().__init__(address, Handler)
        self.state = state


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Local HTTP catalog + .siggpkg fixtures for the store."
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument(
        "--game-dir",
        default=DEFAULT_GAME_DIR,
        help="real game folder to package (default: %(default)s)",
    )
    parser.add_argument(
        "--software-folder",
        default="~/software",
        help="registry root the launcher will install into (default: %(default)s)",
    )
    parser.add_argument(
        "--cache-dir",
        default=DEFAULT_CACHE_DIR,
        help="where the real .siggpkg is cached (default: %(default)s)",
    )
    parser.add_argument(
        "--rebuild",
        action="store_true",
        help="rebuild the cached real .siggpkg",
    )
    parser.add_argument(
        "--no-real-game",
        action="store_true",
        help="skip the Celeste64 fixture (synthetic packages only)",
    )
    parser.add_argument(
        "--celeste-version",
        choices=CELESTE_VERSIONS,
        default=CELESTE_VERSIONS[0],
        help="Celeste version the catalog serves at startup (default: %(default)s)",
    )
    parser.add_argument(
        "--latency",
        type=float,
        default=0.15,
        help="seconds between chunks on /slow/ endpoints (default: %(default)s)",
    )
    parser.add_argument(
        "--self-check",
        action="store_true",
        help="validate the generated fixtures and exit",
    )
    args = parser.parse_args(argv)

    state = State(args)
    state.prepare()

    if args.self_check:
        return _self_check(state)

    server = Server((args.host, args.port), state)
    print(
        f"\nIFSCstation test store on http://{args.host}:{args.port}\n"
        f"  catalog: http://{args.host}:{args.port}/repo.json\n"
        f"  update:  http://{args.host}:{args.port}/repo-v2.json\n"
        f"  extra:   http://{args.host}:{args.port}/repo-extra.json",
        flush=True,
    )
    if state.celeste_packages:
        other = (
            CELESTE_VERSIONS[0]
            if state.celeste_version == CELESTE_LATEST
            else CELESTE_LATEST
        )
        print(
            f"  Celeste: serving {state.celeste_version} — switch with "
            f"http://{args.host}:{args.port}/admin/celeste/{other}",
            flush=True,
        )
    print("Press Ctrl+C to stop.\n", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopping", flush=True)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
