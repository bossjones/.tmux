# Plan: Integrate `jaclu/tmux-menus` into the oh-my-tmux config

> **Task type:** feature · **Complexity:** medium · **Branch:** `feature-menu`
> **Tracking:** implements discovery [#8](https://github.com/bossjones/.tmux/issues/8) under epic [#10](https://github.com/bossjones/.tmux/issues/10)

## Task Description

Add the [tmux-menus](https://github.com/jaclu/tmux-menus) TPM plugin to this fork of
[gpakosz/.tmux](https://github.com/gpakosz/.tmux) so that pressing `<prefix> \` opens a
navigable popup menu of tmux actions. Each item shows the key that selects it, and a
`!` "Display commands" view lists the **real** prefix/root key bindings behind each
action, oh-my-tmux's custom ones included. This answers the epic's goal: stop memorizing
shortcuts and pick them from a menu instead.

The integration must follow this repo's rules (see [`CLAUDE.md`](../CLAUDE.md)):

- **Only `.tmux.conf.local` changes.** [`.tmux.conf`](../.tmux.conf) is upstream and read-only.
- **No manual TPM bootstrap** (`set -g @plugin 'tmux-plugins/tpm'` / `run …tpm`).
  oh-my-tmux's `_apply_plugins` ([`.tmux.conf:1662`](../.tmux.conf)) handles it.
- The executable contract in [`tests/`](../tests) must grow to cover the new deviation,
  and the change **is not done until those tests and the manual checks pass**.

## Objective

When this plan is complete:

1. `.tmux.conf.local` declares `set -g @plugin 'jaclu/tmux-menus'` with an explicit,
   deterministic trigger (`<prefix> \`).
2. On a real machine, `<prefix> I` installs the plugin and `<prefix> \` opens the tmux-menus
   main menu. `!` inside a menu shows the matching key bindings.
3. The pytest suite (`make test`) has **static** tests for the declaration and trigger option,
   plus an **opt-in live integration** test that runs the real plugin init against a hermetic
   tmux server and asserts the `\` binding exists and `Enter` is still `copy-mode`.
4. CI ([`.github/workflows/test.yml`](../.github/workflows/test.yml)) fetches a **pinned**
   tmux-menus checkout so the live integration test runs on every push.
5. `CLAUDE.md` documents the fifth plugin and the new local deviation. Issue #8 gets a go
   verdict and the epic #10 records the decision.

## Problem Statement

tmux has hundreds of actions, and this config adds more bindings on top (oh-my-tmux's
`prefix m` mouse toggle, `prefix e` edit config, TPM's `prefix I / u / M-u`, tmux-fzf's
`prefix F`, resurrect's `prefix C-s / C-r`, and others). The built-in helpers fall short here:

- `prefix ?` is bound to `list-keys -N` (tmux 3.5a), which lists **only bindings that carry a
  note**. That's a small subset.
- Stock tmux's `prefix <` / `prefix >` menus are **rebound by oh-my-tmux** to
  `swap-pane -U/-D`, so they don't open menus in this config.
- Right-click menus work (`set -g mouse on`) but only cover a handful of pane/window actions.

## Solution Approach

Adopt tmux-menus (the #8 discovery winner: most complete, actively maintained, and its
default trigger is **free** in this config) through the existing TPM flow, with minimal
configuration:

| Decision | Choice | Why |
|---|---|---|
| Trigger | `set -g @menus_trigger '\'` (explicit) | `\` is unbound here (`tmux list-keys -T prefix` has no `\`). Setting it explicitly also **disables the "secondary default" `<prefix> Enter` probe** ([SecondaryDefault.md](https://github.com/jaclu/tmux-menus/blob/v2.4.1/docs/SecondaryDefault.md)), so the result doesn't depend on plugin load order. oh-my-tmux already binds `bind Enter copy-mode` at [`.tmux.conf:117`](../.tmux.conf). Quoting `'\'` follows [QuotingPitfalls.md → Special Characters](https://github.com/jaclu/tmux-menus/blob/v2.4.1/docs/QuotingPitfalls.md#special-characters-in-tmuxconf). |
| Position | leave default (`C`/`C` on tmux ≥ 3.2) | tmux 3.5a supports centering ([README → Menu Position](https://github.com/jaclu/tmux-menus/blob/v2.4.1/README.md#menu-position)). |
| Display commands (`!`) | leave default `Yes` | This is the feature that shows real bindings, and the whole point of the epic. |
| Caching | leave default `Yes` | The cache lives in the plugin dir (`~/.tmux/plugins/tmux-menus/cache`), which TPM clones and so is writable ([Caching.md](https://github.com/jaclu/tmux-menus/blob/v2.4.1/docs/Caching.md)). |
| Config file for "Reload" item | leave default | The plugin resolves `$TMUX_CONF` first ([README → Config File Location](https://github.com/jaclu/tmux-menus/blob/v2.4.1/README.md#config-file-location)). oh-my-tmux sets `TMUX_CONF` in the global environment ([`.tmux.conf:153-161`](../.tmux.conf)), so it reloads `~/.tmux.conf` correctly. |
| Styling | none for now (defaults) | Options are documented with real screenshots in [`docs/tmux-menus/README.md`](../docs/tmux-menus/README.md), rendered by [`docs/tmux-menus/render.sh`](../docs/tmux-menus/render.sh). Adopting one is a copy-paste. Upstream reference: [Styling.md](https://github.com/jaclu/tmux-menus/blob/v2.4.1/docs/Styling.md). |

### How the plugin loads (read this before writing tests)

1. oh-my-tmux's `_apply_plugins` collects every `@plugin` line from `.tmux.conf.local` and
   runs TPM ([`.tmux.conf:1662-1760`](../.tmux.conf)). With
   `tmux_conf_update_plugins_on_launch=true` ([`.tmux.conf.local:431`](../.tmux.conf.local)),
   TPM clones missing plugins automatically.
2. TPM runs [`menus.tmux`](https://github.com/jaclu/tmux-menus/blob/v2.4.1/menus.tmux), which
   **backgrounds** `scripts/plugin_init.sh` and exits 0 immediately. The binding therefore shows
   up **asynchronously**, usually within ~0.5 s.
3. [`scripts/plugin_init.sh`](https://github.com/jaclu/tmux-menus/blob/v2.4.1/scripts/plugin_init.sh)
   validates the cache (L127-190) and then calls `bind_plugin_key "$cfg_trigger_key"` (L195).
   `bind_plugin_key` (L49-108) emits `bind-key [-N "plugin tmux-menus"] "<key>" run-shell <main menu>`.
   `check_secondary_default` (≈L10-46) only binds `Enter` when `@menus_trigger` is unset **and**
   `Enter` is free.
4. The scripts call `$TMUX_BIN` (default `tmux`, [`scripts/helpers_minimal.sh:601`](https://github.com/jaclu/tmux-menus/blob/v2.4.1/scripts/helpers_minimal.sh#L601))
   and reach the right server through the inherited `$TMUX` env var. **Consequence for tests:** run
   `plugin_init.sh` *synchronously* through `run-shell` on the test server and pass the resolved
   real tmux binary as `TMUX_BIN` (the asdf/pyenv shim problem is described in
   [`tests/conftest.py`](../tests/conftest.py) `_resolve_tmux_bin`).
5. The plugin writes `cache/` **inside its own directory**, and its README warns that tmux instances
   must not share a plugin folder ([`menus.tmux` header comment](https://github.com/jaclu/tmux-menus/blob/v2.4.1/menus.tmux)).
   Tests must **copy** the checkout into each temp HOME rather than symlink it.

## Relevant Files

Use these files to complete the task:

- [`.tmux.conf.local`](../.tmux.conf.local): **the only config file to edit.** The TPM plugin
  block is at L449-464. Add the new lines right after `set -g @plugin 'sainnhe/tmux-fzf'` (L464)
  and before the `# -- custom variables` section. Do not touch the `# EOF` (L480) / `# "$@"`
  (L517) sentinels.
- [`.tmux.conf`](../.tmux.conf): **read-only reference.** `bind Enter copy-mode` (L117), the
  config discovery (L150-165), and `_apply_plugins` (≈L1662).
- [`tests/conftest.py`](../tests/conftest.py): hermetic HOME + libtmux server fixtures
  (`_make_tmux_home`, `_start_server`, `TMUX_BIN`, `list_keys`, `global_option`). Reuse these.
  Don't write a parallel harness.
- [`tests/test_local_static.py`](../tests/test_local_static.py): the static-contract pattern
  (one test per declaration, with a message that says how to fix it). Mirror it for tmux-menus.
- [`tests/test_options_live.py`](../tests/test_options_live.py): the live-binding pattern using
  `list_keys(...)`.
- [`tests/test_discriminator.py`](../tests/test_discriminator.py) and
  [`tests/fixtures/stock.tmux.conf.local`](../tests/fixtures/stock.tmux.conf.local): the
  "prove it goes red without our change" pattern.
- [`pyproject.toml`](../pyproject.toml): pytest config. Register the new marker here.
- [`.github/workflows/test.yml`](../.github/workflows/test.yml): CI. Add a pinned checkout step.
- [`Makefile`](../Makefile): `test`, `reload`, `backup`, `docker-smoke` targets used for validation.
- [`CLAUDE.md`](../CLAUDE.md): plugin list (L34-40) and "Local Deviations" (L46-54) must be updated.
- [`specs/test-tmux.md`](test-tmux.md): the test-suite spec. Add rows to its "Deviation Contract" table.

### New Files

- `tests/test_menus_plugin.py`: opt-in live integration test for tmux-menus (details below).

### External references (pinned to tag `v2.4.1`, commit `9cd934c7b31b`)

| What | Link |
|---|---|
| Repo / README | https://github.com/jaclu/tmux-menus/tree/v2.4.1 |
| Entry script (backgrounds init) | https://github.com/jaclu/tmux-menus/blob/v2.4.1/menus.tmux |
| Init + key binding logic | https://github.com/jaclu/tmux-menus/blob/v2.4.1/scripts/plugin_init.sh |
| `TMUX_BIN`, cache paths | https://github.com/jaclu/tmux-menus/blob/v2.4.1/scripts/helpers_minimal.sh |
| Main menu definition | https://github.com/jaclu/tmux-menus/blob/v2.4.1/items/main.sh |
| Secondary default (`Enter`) | https://github.com/jaclu/tmux-menus/blob/v2.4.1/docs/SecondaryDefault.md |
| Quoting of `\` and `~` | https://github.com/jaclu/tmux-menus/blob/v2.4.1/docs/QuotingPitfalls.md |
| Caching / read-only dirs | https://github.com/jaclu/tmux-menus/blob/v2.4.1/docs/Caching.md |
| Logging, timers, cache validation | https://github.com/jaclu/tmux-menus/blob/v2.4.1/docs/Advanced.md |
| Styling options | https://github.com/jaclu/tmux-menus/blob/v2.4.1/docs/Styling.md |
| Debugging | https://github.com/jaclu/tmux-menus/blob/v2.4.1/docs/Debugging.md |
| tmux `display-menu` / `bind-key -N` | https://man.openbsd.org/tmux#display-menu · https://man.openbsd.org/tmux#bind-key |
| TPM plugin loading | https://github.com/tmux-plugins/tpm/blob/master/docs/how_to_create_plugin.md |
| libtmux API (`Server.cmd`) | https://libtmux.git-pull.com/api/servers.html |
| oh-my-tmux upstream README | https://github.com/gpakosz/.tmux/blob/master/README.md |

## Implementation Phases

### Phase 1: Foundation (tests first)
Write failing static tests and the opt-in live test skeleton, register the pytest marker, and
confirm they are **red** against the current `.tmux.conf.local`.

### Phase 2: Core Implementation
Add the two config lines to `.tmux.conf.local`, then make the static tests green. Add the CI
checkout so the live test runs green in CI and locally.

### Phase 3: Integration & Polish
Hands-on verification on the real machine (install, open the menu, `!` view, no key regressions),
docs (`CLAUDE.md`, `specs/test-tmux.md`), a commit and PR, and issue updates.

## Step by Step Tasks
IMPORTANT: Execute every step in order, top to bottom.

### 1. Baseline: confirm the current state is green and `\` is free
- `uv sync --group dev && make test`. The existing suite must pass before any change. If it
  doesn't, stop and report.
- `tmux list-keys -T prefix | grep -E '^bind-key +-T prefix +\\\\ '` should print **nothing**
  (`\` is free). `tmux list-keys -T prefix Enter` should show `copy-mode`.
- Note the current tmux version: `tmux -V` (the plan was written against **3.5a**; tmux-menus
  has a [known 3.7.x back-navigation bug](https://github.com/jaclu/tmux-menus/blob/v2.4.1/README.md#tmux-37---display-menu-bug)).

### 2. Write failing static tests (TDD red)
Append to [`tests/test_local_static.py`](../tests/test_local_static.py), following the existing
style (docstring with line reference, assertion message that says how to fix it):

```python
# ---------------------------------------------------------------------------
# tmux-menus (issue #8)
# ---------------------------------------------------------------------------


def test_plugin_tmux_menus(local_config_text: str) -> None:
    """
    ``jaclu/tmux-menus`` must be declared with ``set -g @plugin``.

    .tmux.conf.local: TPM plugin block, after sainnhe/tmux-fzf
    """
    assert "set -g @plugin 'jaclu/tmux-menus'" in local_config_text, (
        "tmux-menus @plugin declaration is missing from .tmux.conf.local.  "
        "Restore: set -g @plugin 'jaclu/tmux-menus'"
    )


def test_menus_trigger_backslash(local_config_text: str) -> None:
    """
    The trigger must be set explicitly to ``\\`` so tmux-menus does NOT probe the
    secondary default ``<prefix> Enter`` (oh-my-tmux binds Enter to copy-mode,
    .tmux.conf:117).  See docs/SecondaryDefault.md in jaclu/tmux-menus.
    """
    assert "set -g @menus_trigger '\\'" in local_config_text, (
        "Expected: set -g @menus_trigger '\\'  (single-quoted backslash, "
        "per tmux-menus docs/QuotingPitfalls.md)"
    )


def test_menus_declared_after_tmux_fzf(local_config_text: str) -> None:
    """Keep the TPM block ordered: tmux-menus is appended after tmux-fzf."""
    fzf = local_config_text.find("set -g @plugin 'sainnhe/tmux-fzf'")
    menus = local_config_text.find("set -g @plugin 'jaclu/tmux-menus'")
    assert fzf != -1 and menus != -1 and fzf < menus, (
        "jaclu/tmux-menus must be declared after sainnhe/tmux-fzf in the TPM block"
    )
```

- Also update the module docstring's "all four declarations" to "all five declarations".
- Run `uv run pytest tests/test_local_static.py -q`. The 3 new tests must **fail**, everything
  else must pass.

### 3. Register an opt-in pytest marker
In [`pyproject.toml`](../pyproject.toml) under `[tool.pytest.ini_options]`, add:

```toml
markers = [
    "plugin_integration: runs a real third-party TPM plugin checkout against a hermetic tmux server (needs TMUX_MENUS_SRC or ~/.tmux/plugins/tmux-menus)",
]
```

### 4. Write the live integration test `tests/test_menus_plugin.py` (TDD red)
Goal: prove that **the real plugin**, loaded against **our** config, binds `<prefix> \` and leaves
`<prefix> Enter` as `copy-mode`. It must stay hermetic and network-free, like the rest of the
suite: it uses a pre-fetched checkout and skips cleanly when none is available.

Design:
- **Source checkout resolution** (first hit wins):
  1. `$TMUX_MENUS_SRC` (CI sets this, see step 7)
  2. the developer's real `~/.tmux/plugins/tmux-menus`, resolved **at import time before HOME is
     monkeypatched** (same trick as `TMUX_BIN` in `conftest.py`)
  3. otherwise `pytest.skip("tmux-menus checkout not available; set TMUX_MENUS_SRC")`
- **Isolation:** `shutil.copytree(src, tmux_home_copy/".tmux/plugins/tmux-menus", ignore=shutil.ignore_patterns("cache", ".git"))`.
  Copy, don't symlink: the plugin writes `cache/` next to itself.
- Use a **function-scoped** HOME. `tmux_home` is session-scoped and shared, and we must not drop
  a plugin copy into it for every test. Build one with `conftest._make_tmux_home` (import the helper)
  under `tmp_path`, then boot via `conftest._start_server(home, monkeypatch)`.
- **Run the init synchronously**, bypassing the backgrounding in `menus.tmux`:
  ```python
  init = home / ".tmux/plugins/tmux-menus/scripts/plugin_init.sh"
  server.cmd("run-shell", f"TMUX_BIN='{TMUX_BIN}' '{init}'")
  ```
  `run-shell` without `-b` blocks until the script exits, and the child inherits `$TMUX` for
  this test server's socket.
- Then **poll** up to ~5 s (plain `time.sleep(0.1)` loop) for the binding. The init is synchronous,
  but the cache prep may still be settling on slow CI runners.

Fixtures: `menus_home` (function-scoped temp HOME with the copied checkout) and `menus_server`
(depends on `menus_home`; boots, runs init, polls, yields, kills).

Tests (all marked `@pytest.mark.plugin_integration`):

```python
def test_menus_binds_prefix_backslash(menus_server) -> None:
    keys = list_keys(menus_server, "prefix")
    line = next((l for l in keys.splitlines() if re.search(r"-T prefix\s+\\\\\s", l)), "")
    assert "run-shell" in line and "tmux-menus" in line, (
        f"<prefix> \\ is not bound to tmux-menus. prefix table:\n{keys}"
    )

def test_menus_does_not_steal_prefix_enter(menus_server) -> None:
    keys = list_keys(menus_server, "prefix")
    enter = [l for l in keys.splitlines() if re.search(r"-T prefix\s+Enter\s", l)]
    assert enter and "copy-mode" in enter[0], (
        f"<prefix> Enter must remain copy-mode (oh-my-tmux .tmux.conf:117); got {enter}"
    )

def test_menus_init_reported_no_error(menus_home) -> None:
    # plugin_init clears then may write cache/error-* on failure (plugin_init.sh ~L159)
    cache = menus_home / ".tmux/plugins/tmux-menus/cache"
    assert not list(cache.glob("error-*")), f"tmux-menus init errors: {list(cache.glob('error-*'))}"
```

- **Discriminator** (same idea as [`tests/test_discriminator.py`](../tests/test_discriminator.py)):
  one extra test runs the same init against a home built from
  [`tests/fixtures/stock.tmux.conf.local`](../tests/fixtures/stock.tmux.conf.local), which has
  **no** `@menus_trigger`, and asserts `\` is still bound (the plugin default) **and** `Enter`
  stays `copy-mode` (because oh-my-tmux binds it first). This documents that our explicit trigger
  pins behavior rather than creating it. If this turns out flaky or contradicts the plugin logic,
  drop it and record why in the PR.
- Run `TMUX_MENUS_SRC=… uv run pytest -m plugin_integration -q` with a scratch checkout
  (`git clone --depth 1 --branch v2.4.1 https://github.com/jaclu/tmux-menus <scratch>/tmux-menus`).
  Before step 5 the trigger test may **pass**, since the plugin default is also `\`. That's
  expected. The static tests in step 2 are what go red. Confirm the suite runs and isn't skipped.

### 5. Implement: edit `.tmux.conf.local`
Insert immediately after `set -g @plugin 'sainnhe/tmux-fzf'` (currently L464):

```tmux
set -g @plugin 'jaclu/tmux-menus'
## tmux-menus: <prefix> \ opens the action menu; press ! in any menu to see the
## real key bindings. Set explicitly so the secondary <prefix> Enter default is
## never probed (oh-my-tmux binds Enter to copy-mode).
## https://github.com/jaclu/tmux-menus#menu-trigger-key
set -g @menus_trigger '\'
```

- Match the surrounding comment style (`## ` for plugin-option notes, as at L460/L462).
- Do **not** add a TPM `run` line. Do **not** edit `.tmux.conf`.
- `uv run pytest -q` → all static tests green. With `TMUX_MENUS_SRC` set, the integration tests
  are green too.

### 6. Guard against regressions in existing bindings
Add one assertion to the live integration module after init: the bindings this repo cares about
still exist, i.e. `prefix r` (reload), `prefix e` (edit), `prefix m` (mouse toggle), and
`prefix F` if tmux-fzf is present in the test home (it isn't, so skip that one). Reuse the patterns
already in [`tests/test_options_live.py`](../tests/test_options_live.py) (`test_reload_binding_r`,
`test_edit_binding_e`, `test_mouse_toggle_binding_has_display`).

### 7. CI: fetch a pinned checkout and run the integration tests
In [`.github/workflows/test.yml`](../.github/workflows/test.yml), before "Run TDD contract test suite":

```yaml
      - name: Fetch tmux-menus (pinned) for plugin integration tests
        run: |
          git clone --depth 1 --branch v2.4.1 https://github.com/jaclu/tmux-menus "$RUNNER_TEMP/tmux-menus"
          echo "TMUX_MENUS_SRC=$RUNNER_TEMP/tmux-menus" >> "$GITHUB_ENV"
```

- Note that Ubuntu's apt `tmux` is 3.4 on `ubuntu-latest` (24.04). That's fine: tmux-menus
  supports ≥ 1.5 and styling from 3.4 ([compat table](https://github.com/jaclu/tmux-menus/blob/v2.4.1/README.md#dependencies--compatibility)).
- When bumping the pin later, change **only** this tag and re-run the tests.

### 8. Manual end-to-end verification on the real machine
The automated tests can't open a popup, so do this by hand (or with the `cmux`/`playwright` skills if
driving a terminal UI is available):

1. `make backup` (tars the current `~/.tmux.conf*`).
2. `cp .tmux.conf.local ~/.tmux.conf.local` (the **copy** step of `make place-configs`; don't run the
   full target, which clones/pulls a separate checkout), then `make reload`.
3. Wait for the auto-install (`tmux_conf_update_plugins_on_launch=true`) or press `<prefix> I`.
   Confirm `ls ~/.tmux/plugins/tmux-menus/menus.tmux` exists.
4. `tmux list-keys -T prefix '\'` shows `run-shell …/tmux-menus/…`.
5. Press `<prefix> \` → the main menu appears **centered**.
6. Go to Pane → press `!` → the view cycles to commands, then to key bindings. Confirm oh-my-tmux
   bindings (e.g. `-` split, `_` split) appear.
7. `<prefix> Enter` still enters copy mode. `<prefix> r` reloads. `<prefix> F` opens tmux-fzf.
8. `<prefix> ?` shows the new entry with the note `plugin tmux-menus`, if the plugin adds `-N`
   on this tmux version. Record the result; don't fail on it.
9. In a small split pane (for example 4 panes in an 80×24 window), open the menu. If you see
   `tmux-menus ERROR: Screen might be too small`, note it in the PR as a known limitation
   ([README → Screen Size Detection](https://github.com/jaclu/tmux-menus/blob/v2.4.1/README.md#screen-size-detection)).
10. Optional: `make docker-smoke`. The container's first interactive `tmux` launch clones plugins
    over the network. For a quick look, `make docker-run`, then run `tmux`, wait for plugin install,
    and press `<prefix> \`.

### 9. Documentation
- [`CLAUDE.md`](../CLAUDE.md):
  - "TPM Plugin Configuration → Currently active": add `` `jaclu/tmux-menus` — popup action menus (`<prefix> \`); `!` shows real key bindings ``.
  - "Local Deviations": change "the 4-plugin TPM block" to "the 5-plugin TPM block" and add
    `` `@menus_trigger '\'` (explicit, suppresses tmux-menus' `<prefix> Enter` secondary default) ``.
- [`specs/test-tmux.md`](test-tmux.md): in the "Deviation Contract" table, add rows for the
  `jaclu/tmux-menus` plugin and `@menus_trigger` (Static, `test_local_static.py`) and for the
  `<prefix> \` binding (Live, `test_menus_plugin.py`, opt-in). Update "4-plugin" → "5-plugin".
- `specs/modern_tmux_config.md` mentions "the 4 plugins". Leave it: it's a historical spec for
  a finished task.

### 10. Commit, PR, and issue bookkeeping
- Conventional commit on `feature-menu`, e.g.
  `feat(plugins): add jaclu/tmux-menus with explicit <prefix> \ trigger`.
  The body lists the config lines, tests, CI pin, and docs.
- Open a PR to `master` whose body includes `Closes #8` and `Part of #10`, plus the manual checklist
  results from step 8.
- After merge, comment on #10 with the decision: **tmux-menus adopted, tmux-which-key (#7) not
  adopted (overlapping menu system), tmux-fzf (#9) kept as the complementary search tool.** Close #7
  as "not planned" only if the user agrees.

### 11. Final validation
Run every command in **Validation Commands** below and paste the output summary into the PR.

## Testing Strategy

| Layer | What it proves | Where | Runs |
|---|---|---|---|
| Static (file parse) | `@plugin 'jaclu/tmux-menus'` declared, placed after tmux-fzf; `@menus_trigger '\'` set with correct quoting | `tests/test_local_static.py` | always (`make test`, CI) |
| Live integration (real plugin, hermetic server) | Real `plugin_init.sh` binds `<prefix> \` to tmux-menus; `<prefix> Enter` stays `copy-mode`; no `cache/error-*`; existing `r`/`e`/`m` bindings intact | `tests/test_menus_plugin.py` (`-m plugin_integration`) | CI (pinned v2.4.1) and locally when `TMUX_MENUS_SRC` or `~/.tmux/plugins/tmux-menus` exists; otherwise **skipped, not failed** |
| Discriminator | Explicit trigger pins behavior (stock config still gets `\`, Enter still `copy-mode`) | `tests/test_menus_plugin.py` | same as above |
| Manual E2E | Popup renders, centered; `!` view shows real bindings; no key regressions; small-pane behavior | step 8 checklist | once, before PR |

Edge cases to cover or consciously accept:
- **Async init race:** handled by calling `plugin_init.sh` synchronously plus a bounded poll.
- **asdf/pyenv shim for `tmux`** when HOME is overridden: pass `TMUX_BIN` explicitly (see `conftest.py`).
- **Shared cache between instances:** copy the checkout into each test HOME, never symlink.
- **Plugin path with spaces:** unsupported by tmux-menus ([Known Limitations](https://github.com/jaclu/tmux-menus/blob/v2.4.1/README.md#known-limitations)). pytest's `tmp_path` has no spaces on macOS or Linux, so assert that as a precondition in the fixture.
- **Checkout missing:** the test **skips** with a clear reason, and the default `make test` stays network-free.
- **`tmux_conf_uninstall_plugins_on_reload=true`:** removing the `@plugin` line and reloading uninstalls the plugin, which is the rollback path (see Notes).

## Acceptance Criteria

- [ ] `.tmux.conf.local` contains `set -g @plugin 'jaclu/tmux-menus'` directly after the tmux-fzf
      declaration, plus `set -g @menus_trigger '\'`. `.tmux.conf` is byte-identical to `master`
      (`git diff --quiet master -- .tmux.conf`).
- [ ] No `tmux-plugins/tpm` bootstrap lines were added (`test_no_tpm_bootstrap_line` green).
- [ ] `uv run pytest -q` passes. The 3 new static tests exist and were observed **failing** before step 5.
- [ ] `TMUX_MENUS_SRC=<v2.4.1 checkout> uv run pytest -m plugin_integration -q` passes with **0 skipped**.
- [ ] CI workflow clones tmux-menus at `v2.4.1` and the GitHub Actions run is green.
- [ ] Manual: `<prefix> \` opens the menu, `!` shows key bindings, and `<prefix> Enter`/`r`/`e`/`m`/`F` behave as before.
- [ ] `CLAUDE.md` and `specs/test-tmux.md` updated. The PR references `Closes #8` / `Part of #10`.

## Validation Commands

Execute these commands to validate the task is complete:

- `git diff --quiet master -- .tmux.conf && echo "upstream .tmux.conf untouched"`: the base config must be unchanged.
- `grep -nE "@plugin 'jaclu/tmux-menus'|@menus_trigger '\\\\'" .tmux.conf.local`: both lines present.
- `uv sync --group dev && make test`: full default suite green (integration tests may show as skipped locally).
- `git clone --depth 1 --branch v2.4.1 https://github.com/jaclu/tmux-menus "$TMPDIR/tmux-menus" && TMUX_MENUS_SRC="$TMPDIR/tmux-menus" uv run pytest -m plugin_integration -v`: real-plugin tests pass, **none skipped**.
- `TMUX_MENUS_SRC="$TMPDIR/tmux-menus" uv run pytest -q`: whole suite green with the integration layer active.
- `tmux -f /dev/null -L menuscheck new-session -d \; source-file ~/.tmux.conf \; kill-server`: after copying the config to `~`, it parses without errors.
- `tmux list-keys -T prefix '\' && tmux list-keys -T prefix Enter`: on the live server after `<prefix> I`, `\` → tmux-menus and `Enter` → `copy-mode`.
- `gh run list -R bossjones/.tmux --branch feature-menu --limit 1`: latest CI run is `completed success`.

## Notes

- **No new Python dependencies.** The tests use only `libtmux`, `pytest`, and the standard library,
  so no `uv add` is needed.
- **Rollback:** delete the two lines, then `make reload`. Because
  `tmux_conf_uninstall_plugins_on_reload=true` ([`.tmux.conf.local:442`](../.tmux.conf.local)),
  oh-my-tmux uninstalls the plugin on reload. Otherwise run `<prefix> M-u` (TPM clean).
- **Version drift:** TPM installs tmux-menus `main` (unpinned) on real machines, while CI pins
  `v2.4.1`. If upstream changes the trigger logic, CI stays green while local behavior shifts.
  Re-run step 8 after `<prefix> u` updates. Pinning TPM to a tag isn't supported by oh-my-tmux's
  `@plugin` syntax without a fork-branch suffix (`'jaclu/tmux-menus#v2.4.1'` is TPM branch syntax;
  consider it if drift bites).
- **Homebrew tmux upgrades:** tmux 3.7.x breaks left-arrow "back" navigation in menus (fixed in 3.8).
  Use highlight + Enter as the workaround.
- **Optional follow-ups (not in scope):** navigation styling (`@menus_nav_next/prev/home`, see
  [Styling.md → The styling I use](https://github.com/jaclu/tmux-menus/blob/v2.4.1/docs/Styling.md#the-styling-i-use)),
  `@menus_log_file` for debugging, and trimming menus via `@menus_main_menu` custom menus
  ([CustomMenus.md](https://github.com/jaclu/tmux-menus/blob/v2.4.1/docs/CustomMenus.md)).
- **Test-harness bugs found and fixed during the build (both pre-date this work):**
  1. *Env leak (destructive).* Running pytest **inside tmux** passed the parent's `TMUX*`
     variables to every test server. `TMUX_CONF_LOCAL` made test servers load the real
     `~/.tmux.conf.local` (3 discriminator tests failed locally), `TMUX_SOCKET` pointed oh-my-tmux's
     async setup at the real server, and `TMUX_PLUGIN_MANAGER_PATH` made the stock fixture, which
     declares no plugins, trigger `_apply_plugins`' uninstall branch against the **real
     `~/.tmux/plugins`**. `_start_server` now clears every `TMUX*` variable. This was verified
     with a canary plugin directory that survived a full run.
  2. *Server leak.* libtmux ≥ 0.30 removed `Server.kill_server()`. It raises `DeprecatedError`,
     which fixture teardown swallowed, so every test leaked a tmux server (~375 accumulated, which
     exhausted macOS PTYs: `fork failed: Device not configured`). Teardown now uses `Server.kill()`.
- **Discriminator uses our config minus `@menus_trigger`, not the stock fixture.** A config with
  no `@plugin` lines makes oh-my-tmux uninstall `$HOME/.tmux/plugins` asynchronously
  (`tmux_conf_uninstall_plugins_on_reload=true`), deleting the plugin copy mid-init.
- **Styling screenshots:** [`docs/tmux-menus/README.md`](../docs/tmux-menus/README.md) (rendered with
  vhs by [`render.sh`](../docs/tmux-menus/render.sh)). The `!` views need a large terminal. At
  110×32 tmux-menus reports `Screen might be too small`.
- **Not doing:** tmux-which-key (#7). It overlaps with tmux-menus, and its default `prefix Space`
  collides with `next-layout`.
