"""
Live integration tests for the ``jaclu/tmux-menus`` plugin (issue #8).

These run the *real* plugin init against a hermetic tmux server booted from our
config, then assert on the resulting key bindings.

Why this layer exists
  The static tests only prove the ``@plugin`` / ``@menus_trigger`` lines are in
  the file.  What we actually care about is the effective binding: ``<prefix> \\``
  opens tmux-menus and ``<prefix> Enter`` stays oh-my-tmux's ``copy-mode``
  (.tmux.conf:117) instead of being taken by the plugin's secondary default
  (docs/SecondaryDefault.md in jaclu/tmux-menus).

How the plugin is loaded
  Under TPM, ``menus.tmux`` backgrounds ``scripts/plugin_init.sh`` and exits 0,
  so the binding appears asynchronously.  Here we call ``plugin_init.sh``
  synchronously via ``run-shell`` (which blocks and hands the child ``$TMUX``
  for this test server) and pass ``TMUX_BIN`` explicitly: the plugin defaults
  to ``tmux`` on PATH, which may be an asdf/pyenv shim that breaks once HOME is
  overridden (see ``_resolve_tmux_bin`` in conftest.py).

Hermeticity
  No network.  The plugin source comes from ``$TMUX_MENUS_SRC`` (CI clones a
  pinned tag) or the developer's real ``~/.tmux/plugins/tmux-menus``; if neither
  exists the tests skip.  The checkout is *copied* (not symlinked) into each
  temp HOME because the plugin writes ``cache/`` next to itself and must not be
  shared between tmux instances (see the header comment of menus.tmux).
"""
from __future__ import annotations

import os
import re
import shutil
import time
from pathlib import Path
from typing import Generator, Optional

import libtmux
import pytest

from tests.conftest import (
    REPO_ROOT,
    TMUX_BIN,
    _make_tmux_home,
    _start_server,
    list_keys,
)

pytestmark = pytest.mark.plugin_integration


# ---------------------------------------------------------------------------
# Resolve the plugin checkout at import time, before HOME is monkeypatched.
# ---------------------------------------------------------------------------


def _resolve_menus_src() -> Optional[Path]:
    candidates = [
        os.environ.get("TMUX_MENUS_SRC", ""),
        str(Path.home() / ".tmux" / "plugins" / "tmux-menus"),
    ]
    for candidate in candidates:
        if candidate and (Path(candidate) / "scripts" / "plugin_init.sh").is_file():
            return Path(candidate)
    return None


#: tmux-menus checkout to copy into each test HOME, or None to skip.
MENUS_SRC: Optional[Path] = _resolve_menus_src()

#: How long to wait for the trigger binding to appear after init.
BIND_TIMEOUT_S = 5.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _prefix_binding(server: libtmux.Server, key_pattern: str) -> str:
    """Return the ``list-keys -T prefix`` line for *key_pattern*, or ''."""
    regex = re.compile(r"-T prefix\s+" + key_pattern + r"\s")
    for line in list_keys(server, "prefix").splitlines():
        if regex.search(line):
            return line
    return ""


#: ``list-keys`` prints the backslash key escaped, as ``\\``.
BACKSLASH = r"\\\\"


def _boot_with_menus(
    base: Path,
    local_config_src: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> tuple[libtmux.Server, Path]:
    if MENUS_SRC is None:
        pytest.skip(
            "tmux-menus checkout not available; set TMUX_MENUS_SRC "
            "(git clone --depth 1 --branch v2.4.1 https://github.com/jaclu/tmux-menus)"
        )

    # tmux-menus does not support paths containing spaces (README: Known Limitations).
    assert " " not in str(base), f"temp path must not contain spaces: {base}"

    home = _make_tmux_home(base=base, repo=REPO_ROOT, local_config_src=local_config_src)
    plugin_dir = home / ".tmux" / "plugins" / "tmux-menus"
    shutil.copytree(
        MENUS_SRC,
        plugin_dir,
        symlinks=True,  # upstream ships a dangling docs/ symlink
        ignore=shutil.ignore_patterns("cache", ".git"),
    )

    server = _start_server(home, monkeypatch)
    init = plugin_dir / "scripts" / "plugin_init.sh"
    server.cmd("run-shell", f"TMUX_BIN='{TMUX_BIN}' '{init}'")

    deadline = time.monotonic() + BIND_TIMEOUT_S
    while time.monotonic() < deadline:
        if _prefix_binding(server, BACKSLASH):
            break
        time.sleep(0.1)

    return server, home


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def menus_home_and_server(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> Generator[tuple[Path, libtmux.Server], None, None]:
    """Our ``.tmux.conf.local`` + a private tmux-menus copy, init already run."""
    server, home = _boot_with_menus(
        tmp_path / "home", REPO_ROOT / ".tmux.conf.local", monkeypatch
    )
    yield home, server
    try:
        server.kill()
    except Exception:  # noqa: BLE001
        pass


@pytest.fixture
def menus_server(menus_home_and_server: tuple[Path, libtmux.Server]) -> libtmux.Server:
    return menus_home_and_server[1]


@pytest.fixture
def menus_home(menus_home_and_server: tuple[Path, libtmux.Server]) -> Path:
    return menus_home_and_server[0]


@pytest.fixture
def no_trigger_menus_server(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> Generator[libtmux.Server, None, None]:
    """
    Our ``.tmux.conf.local`` with only the ``@menus_trigger`` line removed.

    Not the stock fixture: a config that declares *no* plugins makes
    oh-my-tmux's async _apply_plugins uninstall ``$HOME/.tmux/plugins``
    (``tmux_conf_uninstall_plugins_on_reload``), deleting the plugin copy
    mid-init.
    """
    local = tmp_path / "no_trigger.tmux.conf.local"
    text = (REPO_ROOT / ".tmux.conf.local").read_text()
    kept = [ln for ln in text.splitlines(keepends=True) if "@menus_trigger" not in ln]
    assert len(kept) < len(text.splitlines()), "@menus_trigger line not found"
    local.write_text("".join(kept))
    server, _ = _boot_with_menus(tmp_path / "no_trigger_home", local, monkeypatch)
    yield server
    try:
        server.kill()
    except Exception:  # noqa: BLE001
        pass


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_menus_binds_prefix_backslash(menus_server: libtmux.Server) -> None:
    """``<prefix> \\`` must run the tmux-menus main menu."""
    line = _prefix_binding(menus_server, BACKSLASH)
    assert "run-shell" in line and "tmux-menus" in line, (
        "<prefix> \\ is not bound to tmux-menus.  prefix table:\n"
        + list_keys(menus_server, "prefix")
    )


def test_menus_does_not_steal_prefix_enter(menus_server: libtmux.Server) -> None:
    """``<prefix> Enter`` must remain oh-my-tmux's ``copy-mode`` (.tmux.conf:117)."""
    line = _prefix_binding(menus_server, "Enter")
    assert "copy-mode" in line and "tmux-menus" not in line, (
        f"<prefix> Enter must remain copy-mode; got {line!r}"
    )


def test_menus_init_reported_no_error(menus_home: Path) -> None:
    """plugin_init.sh records failures as ``cache/error-*`` files."""
    cache = menus_home / ".tmux" / "plugins" / "tmux-menus" / "cache"
    errors = sorted(p.name for p in cache.glob("error-*"))
    assert not errors, f"tmux-menus init reported errors: {errors}"


def test_menus_keeps_existing_bindings(menus_server: libtmux.Server) -> None:
    """Loading tmux-menus must not clobber the bindings this repo relies on."""
    reload_line = _prefix_binding(menus_server, "r")
    edit_line = _prefix_binding(menus_server, "e")
    mouse_line = _prefix_binding(menus_server, "m")

    assert "source" in reload_line, f"<prefix> r (reload) changed: {reload_line!r}"
    assert "EDITOR" in edit_line or "edit" in edit_line.lower(), (
        f"<prefix> e (edit config) changed: {edit_line!r}"
    )
    assert "mouse" in mouse_line, f"<prefix> m (mouse toggle) changed: {mouse_line!r}"


def test_explicit_trigger_pins_default_behavior(
    no_trigger_menus_server: libtmux.Server,
) -> None:
    """
    Discriminator: without ``@menus_trigger`` the plugin falls back to its own
    default ``\\``, and only probes ``Enter`` as a secondary trigger when it
    is free.  oh-my-tmux binds Enter first, so Enter must still be copy-mode.
    Our explicit trigger therefore *pins* this behavior rather than creating it.
    """
    backslash = _prefix_binding(no_trigger_menus_server, BACKSLASH)
    enter = _prefix_binding(no_trigger_menus_server, "Enter")
    assert "tmux-menus" in backslash, (
        f"no @menus_trigger: expected tmux-menus default trigger on \\, got {backslash!r}"
    )
    assert "copy-mode" in enter and "tmux-menus" not in enter, (
        f"no @menus_trigger: <prefix> Enter should stay copy-mode, got {enter!r}"
    )
