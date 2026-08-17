# Plan: Improve `choose-tree` (`prefix + w`) readability

## Task Description
`prefix + w` opens tmux's native `choose-tree -Zw` window/session chooser. Today the selected row uses `mode-style` inherited from the Oh My Tmux theme's bright-yellow accent color (`tmux_conf_theme_colour_5="#ffff00"`), which is jarring and makes the tree hard to scan. This task makes the chooser easier to read: a calm dark-blue/white selection bar, and (where tmux's format engine allows it) colored active/activity/bell/zoom indicators and window names — while fully preserving `choose-tree`'s existing behavior (expand/collapse, search, shortcuts, Enter-to-select) and without touching the upstream `.tmux.conf`.

## Objective
When complete:
1. `prefix + w` still opens the normal native `choose-tree -Zw` chooser with all default interaction (expand/collapse, search, tag, sort, Enter) intact.
2. The selected row renders dark-blue background / white foreground / bold, instead of bright yellow.
3. Window rows show colorized state where tmux's `-F` format actually supports it: active (`*`) green+bold, activity (`#`) yellow+bold, bell (`!`) red+bold, zoomed (`Z`) cyan, window name in light gray, with unstylable tree decoration (branch connectors, shortcut key brackets, and the session/window's own fixed name-label prefix) left as tmux renders them natively.
4. The change is applied both in the repo (`bossjones/.tmux`) and in the currently active `~/.tmux.conf.local`, and the running tmux server picks it up via a live reload with no errors and no killed sessions/windows.
5. `tmux_conf_theme_colour_5` (used elsewhere for messages/bell/command-prompt) is left untouched — the chooser fix is scoped to the mode-specific variables only.

## Problem Statement
- `mode-style` is currently `fg=#080808,bg=#ffff00,bold` (`tmux_conf_theme_mode_fg`/`_bg` derived from `tmux_conf_theme_colour_1`/`_colour_5` at `.tmux.conf.local:165-167`). This one option governs **both** copy-mode selection and `choose-tree`/`choose-buffer`/tree-mode selection in this tmux version, since `mode-style` is the only selection-style knob that exists (see Investigation Findings — tree-specific style options do not exist in this tmux).
- `tmux_conf_theme_colour_5` is shared: it also drives `tmux_conf_theme_message_bg`, `tmux_conf_theme_message_command_fg`, and `tmux_conf_theme_window_status_bell_fg` (`.tmux.conf.local:156,160,226`). Changing `colour_5` itself would silently change the bell/message color too, which is out of scope and explicitly disallowed by the user.
- `prefix + w` has no explicit `bind-key` in either `.tmux.conf` or `.tmux.conf.local` today — it is tmux's own compiled-in stock binding (`choose-tree -Zw`), left alone because `tmux_conf_preserve_stock_bindings=false` (`.tmux.conf.local:17`) means Oh My Tmux does not touch `w`/`s` at all. To add a custom `-F` format we must add an **explicit** `bind-key -T prefix w choose-tree ...` in `.tmux.conf.local` that mirrors the existing flags (`-Zw`) plus a new `-F`.

## Solution Approach
Two independent, additive changes in `.tmux.conf.local`, both fully within the existing Oh My Tmux customization model described in `CLAUDE.md`:

1. **Selection color** — override `tmux_conf_theme_mode_fg` / `_mode_bg` / `_mode_attr` directly (not via `colour_5`) to a dark blue / white / bold triple. Since this tmux has no `tree-mode-selection-style` (confirmed unsupported — see below), this is the only mechanism available, and it's exactly the mechanism the repo's `CLAUDE.md` already documents for chooser/copy-mode styling.
2. **Content coloring** — add an explicit `bind-key -T prefix w choose-tree -Zw -F '...'` in `.tmux.conf.local` with a custom format built from the *actual* default format (extracted from the installed tmux binary, see Investigation Findings) plus `#[fg=...]`/`#[bold]` wrapping around the flag characters and window name. This preserves every existing flag/behavior of the stock binding and only adds `-F`.

No fzf, no `tree-mode-*` options (not supported by the installed tmux), no edits to `.tmux.conf`.

## Investigation Findings (already performed against the live machine)

- **tmux**: `tmux 3.5a`, installed via asdf (`/Users/malcolm/.asdf/installs/tmux/3.5a/bin/tmux`), shim at `/Users/malcolm/.asdf/shims/tmux`.
- **Config wiring**: `~/.tmux.conf` is a symlink → `/Users/malcolm/dev/bossjones/oh-my-tmux/.tmux.conf` (matches `CLAUDE.md`/README install instructions). `~/.tmux.conf.local` is a **plain copied file, not a symlink** — confirms the installer's copy-not-symlink behavior called out in the task background.
- **Repo state**: `bossjones/.tmux`, branch `master`, clean except untracked `.aif-skills/` (unrelated, ignore). Remote `git@github.com:bossjones/.tmux.git`.
- **Drift check**: `diff /Users/malcolm/dev/bossjones/oh-my-tmux/.tmux.conf.local ~/.tmux.conf.local` → **zero diff**. The active file is currently byte-identical to the repo's. There is no pre-existing local drift to preserve; the merge step is trivial (copy repo → home after editing repo).
- **Live tmux server**: running, with 3 sessions (`abtop-verify`, `aif-build`, `zsh` — attached, 13 windows). Reload must not disturb these.
- **Current selection style**: `tmux show -gw mode-style` → `fg=#080808,bg=#ffff00,bold` — confirms the bright-yellow complaint, sourced from `tmux_conf_theme_mode_bg=$tmux_conf_theme_colour_5` (`.tmux.conf.local:166`) where `tmux_conf_theme_colour_5="#ffff00"` (`.tmux.conf.local:93`).
- **Tree-specific style options do not exist in tmux 3.5a**: `tmux show -gw tree-mode-selection-style` / `tree-mode-border-style` / `tree-mode-preview-style` all return `invalid option`. These options are not a real part of any shipped tmux (up to at least 3.5a) — must not be added to the config, confirming the fallback path (`mode-style` only) is the only viable one.
- **`prefix + w` binding**: `tmux list-keys | grep choose-tree` → `bind-key -T prefix w choose-tree -Zw` and `bind-key -T prefix s choose-tree -Zs`, with **no existing `-F`**. Neither is defined in `.tmux.conf` or `.tmux.conf.local` (grep for `choose-tree`/`Zw`/`Zs` in both files returns nothing) — confirmed these are tmux's own compiled-in stock bindings, active because `tmux_conf_preserve_stock_bindings=false` means Oh My Tmux doesn't touch them.
- **Actual default `-F` format for `choose-tree`** (extracted via `strings` on the installed tmux binary — this is ground truth for 3.5a, not a guess):
  ```
  #{?pane_format,#{?pane_marked,#[reverse],}#{pane_current_command}#{?pane_active,*,}#{?pane_marked,M,}#{?#{&&:#{pane_title},#{!=:#{pane_title},#{host_short}}},: "#{pane_title}",},#{?window_format,#{?window_marked_flag,#[reverse],}#{window_name}#{window_flags}#{?#{&&:#{==:#{window_panes},1},#{&&:#{pane_title},#{!=:#{pane_title},#{host_short}}}},: "#{pane_title}",},#{session_windows} windows#{?session_grouped, (group #{session_group}: #{session_group_list}),}#{?session_attached, (attached),}}}
  ```
  This single format is evaluated per row for all three levels (pane/window/session), branching on the boolean format variables `pane_format` / `window_format`. **`window_name` and `window_flags` (the `*`/`#`/`!`/`Z` characters) are part of this customizable format** — they can be recolored.
- **Session name is NOT part of `-F`** (confirmed by a second, independent string constant found in the binary: a bare `"#{session_name}: "` literal, separate from the format above). tmux's tree-drawing code prepends the session's own name (and, analogously, a window's numeric index when nested under a session) as a **fixed, non-customizable label** before appending whatever `-F` evaluates to for that row. This is a genuine tmux constraint, not a config gap — coloring the session-name label text itself via `-F` is not possible on this tmux version. (A live interactive capture to triple-confirm this visually was attempted but inconclusive because the probe pane wasn't the attached client's focused pane; the double string-constant evidence from the actual binary is treated as sufficient. If the build session wants to be extra sure, visually opening `prefix + w` after the change and eyeballing the session line is a 5-second check.)
- **Truecolor support confirmed**: `tmux info` shows `Tc: true`, `setrgbf`/`setrgbb` present, `terminal-overrides` includes `*256col*:Tc`. Hex truecolor values (e.g. `#005f87`) are safe to use directly in `mode-style`.
- **Color reuse constraint confirmed**: `tmux_conf_theme_colour_5` is referenced by `tmux_conf_theme_message_bg` (`:156`), `tmux_conf_theme_message_command_fg` (`:160`), `tmux_conf_theme_mode_bg` (`:166`), and `tmux_conf_theme_window_status_bell_fg` (`:226`). Must override `mode_bg` directly with a new literal, not touch `colour_5`.

## Relevant Files
- `/Users/malcolm/dev/bossjones/oh-my-tmux/.tmux.conf.local` — the only file to edit; contains the `tmux_conf_theme_mode_*` block (lines ~164-167) and is where the new `bind-key ... choose-tree` override belongs (append near the end, before the `# EOF` sentinel described in `CLAUDE.md`, or directly after the existing key-binding section — whichever keeps it near other `bind-key` customizations already in the file).
- `/Users/malcolm/.tmux.conf.local` — the active copy; currently identical to the repo file, gets the same edit applied (or copied wholesale from the repo version, since there is no drift to preserve).
- `/Users/malcolm/dev/bossjones/oh-my-tmux/.tmux.conf` — **do not edit** (upstream base, confirmed no `choose-tree` references exist here to conflict with).
- `/Users/malcolm/dev/bossjones/oh-my-tmux/CLAUDE.md` — optionally add one line under "Local Deviations from the Upstream Template" documenting the new `mode_*` override and the `choose-tree -F` binding, consistent with how existing deviations are listed.

## Step by Step Tasks

### 1. Change the chooser/copy-mode selection color
- In `.tmux.conf.local`, in the "window modes style" block (currently lines 164-167), replace:
  ```tmux
  tmux_conf_theme_mode_fg="$tmux_conf_theme_colour_1"
  tmux_conf_theme_mode_bg="$tmux_conf_theme_colour_5"
  tmux_conf_theme_mode_attr="bold"
  ```
  with a literal dark-blue/white/bold triple, independent of `colour_1`/`colour_5`:
  ```tmux
  tmux_conf_theme_mode_fg="#ffffff"     # white — selected-row text
  tmux_conf_theme_mode_bg="#005f87"     # dark blue — selected-row background
  tmux_conf_theme_mode_attr="bold"
  ```
- Do **not** touch `tmux_conf_theme_colour_5`, `tmux_conf_theme_message_*`, or `tmux_conf_theme_window_status_bell_fg`.

### 2. Add a custom `-F` format to the `prefix + w` binding for colorized tree content
- Add a new explicit binding in `.tmux.conf.local` (near other `bind-key` lines), overriding the stock `w` binding with the same `-Zw` flags plus a `-F` built from the real default format discovered above, wrapping the stylable pieces:
  ```tmux
  # prefix + w: choose-tree with colorized active/activity/bell/zoom indicators
  bind-key -T prefix w choose-tree -Zw -F "#{?pane_format,\
  #{?pane_marked,#[reverse],}#{pane_current_command}#{?pane_active,*,}#{?pane_marked,M,}\
  #{?#{&&:#{pane_title},#{!=:#{pane_title},#{host_short}}},: \"#{pane_title}\",},\
  #{?window_format,\
  #{?window_marked_flag,#[reverse],}\
  #[fg=colour253]#{window_name}#[default]\
  #{?window_active,#[fg=green#,bold]*#[default],}\
  #{?window_zoomed_flag,#[fg=cyan#,bold]Z#[default],}\
  #{?window_bell_flag,#[fg=red#,bold]!#[default],}\
  #{?#{&&:#{window_activity_flag},#{!window_bell_flag}},#[fg=yellow#,bold]###[default],}\
  #{?#{&&:#{==:#{window_panes},1},#{&&:#{pane_title},#{!=:#{pane_title},#{host_short}}}},: \"#{pane_title}\",},\
  #{session_windows} windows#{?session_grouped, (group #{session_group}: #{session_group_list}),}#{?session_attached, (attached),}}}"
  ```
  Notes on this format:
  - Preserves every branch of the stock default (`pane_marked`/reverse, pane title suffix, session windows/group/attached suffix) — nothing is removed, only the window-flags portion is rebuilt to add color.
  - Replaces the opaque `#{window_flags}` with explicit, individually-colored conditionals for the flags that matter (`*` active/green+bold, `Z` zoomed/cyan+bold, `!` bell/red+bold, `#` activity/yellow+bold — activity suppressed when bell is also set, matching tmux's own precedence where bell implies activity). `window_last_flag` (`-`) and `window_marked_flag` indicators are intentionally left using tmux's native rendering (not in this task's scope, and not called out in the desired UX list) — call this out explicitly to the user as a scoping choice, not an oversight.
  - `window_name` is wrapped in `colour253` (light gray) per the "ordinary window names: white/light gray" requirement.
  - Inside a `-F` string, literal commas that are format-string separators (e.g. inside `#[fg=green,bold]`) must be escaped as `#,` — already done above (`#[fg=green#,bold]`) — verify this is necessary/correct for this tmux version during implementation (`tmux source-file` will immediately error if the escaping is wrong, making this self-checking).
  - Session-name and window-index labels themselves are not recolored — this is the documented tmux constraint from Investigation Findings, not a missed requirement. State this plainly when reporting completion.
- Leave the `prefix + s` (`choose-tree -Zs`) stock binding untouched — the task and desired UX are scoped to `prefix + w`.

### 3. Sync repo → active config
- Since `diff .../.tmux.conf.local ~/.tmux.conf.local` currently shows zero drift, after editing the repo's `.tmux.conf.local`, copy it verbatim to `~/.tmux.conf.local` (`cp /Users/malcolm/dev/bossjones/oh-my-tmux/.tmux.conf.local ~/.tmux.conf.local`) rather than hand-merging — there is nothing local-only to preserve.
- Re-run the diff after copying to confirm it's back to zero.

### 4. Reload and validate without disrupting the running server
- Reload via `tmux source-file ~/.tmux.conf` (this re-sources `.tmux.conf.local` too, per Oh My Tmux's own mechanism) — do not kill the server, do not use `make reload` if it does anything more invasive than this (check the Makefile's `reload` target first; use it if equivalent, otherwise call `tmux source-file` directly).
- Confirm zero errors/output from the reload command.
- Re-run and show:
  ```bash
  tmux show -gw mode-style
  tmux show -gw tree-mode-selection-style 2>&1 || true
  tmux show -gw tree-mode-border-style 2>&1 || true
  tmux list-keys | grep -E 'choose-tree'
  ```
  Expect `mode-style` to now read `fg=#ffffff,bg=#005f87,bold` (or equivalent order), the two `tree-mode-*` lines to still say `invalid option` (expected/unsupported, not an error introduced by this change), and the `w` binding to show the new `-F`.
- Confirm existing sessions/windows (`abtop-verify`, `aif-build`, `zsh` and its 13 windows) are still present and unaffected: `tmux list-sessions`, `tmux list-windows -t zsh`.
- Actually open `prefix + w` (or `tmux choose-tree -Zw` in a throwaway pane/window, cleaned up afterward) to visually confirm: selection bar is dark blue/white/bold, window flags show the intended colors, expand/collapse/search/Enter still work normally. Clean up any throwaway pane/window created for this check.

### 5. Document and finish
- Optionally add one bullet to `CLAUDE.md`'s "Local Deviations from the Upstream Template" list noting the new `mode_*` literal override and the `choose-tree -F` binding — follow the existing terse bullet style in that section.
- Report exactly which lines changed in `.tmux.conf.local` (repo and active copy), the final `mode-style` value, the final `w` binding, and the explicit note about the session-name/window-index label limitation.
- Do not `git add`/`commit`/`push` anything.

## Acceptance Criteria
1. `prefix + w` opens the same native `choose-tree` UI with expand/collapse, search, tagging, sorting, and Enter-to-select all working as before.
2. `tmux show -gw mode-style` reports the new dark-blue/white/bold triple, not yellow.
3. `tmux list-keys | grep choose-tree` shows the `w` binding retains `-Zw` and gains the new `-F`; the `s` binding is unchanged.
4. Visually, active/activity/bell/zoomed windows are colored per the desired UX (green `*`, yellow `#`, red `!`, cyan `Z`), window names render light gray, and the selection bar is dark blue/white — with the explicit, documented exception that the session-name and window-index label prefixes themselves keep tmux's native (uncolored) rendering.
5. `tmux_conf_theme_colour_5` and everything that derives from it (messages, bell status text) are unchanged — verify with `tmux show -gw message-style` and `tmux show -gw message-command-style` before/after to confirm no diff.
6. Reload produces zero errors.
7. `tmux list-sessions` and `tmux list-windows -t zsh` show the same sessions/windows as before the change (no kills, no new persistent windows left over from testing).
8. `.tmux.conf` is untouched (`git diff -- .tmux.conf` in the repo is empty).
9. `git diff -- .tmux.conf.local` in the repo shows only the two additive changes (mode fg/bg/attr, new bind-key line) — nothing else.
10. `diff /Users/malcolm/dev/bossjones/oh-my-tmux/.tmux.conf.local ~/.tmux.conf.local` is empty after the sync step.
11. No commit, no push.

## Validation Commands
```bash
# repo is clean except the intended edit
cd /Users/malcolm/dev/bossjones/oh-my-tmux && git diff -- .tmux.conf         # expect: empty
git diff -- .tmux.conf.local                                                # expect: only the two edits

# active copy matches repo
diff -u /Users/malcolm/dev/bossjones/oh-my-tmux/.tmux.conf.local ~/.tmux.conf.local   # expect: empty

# reload cleanly
tmux source-file ~/.tmux.conf                                               # expect: no output/errors

# confirm new settings live
tmux show -gw mode-style
tmux show -gw tree-mode-selection-style 2>&1 || true    # expect: invalid option (unsupported, unchanged)
tmux show -gw tree-mode-border-style 2>&1 || true        # expect: invalid option (unsupported, unchanged)
tmux list-keys | grep -E 'choose-tree'

# confirm bell/message colors untouched
tmux show -gw message-style
tmux show -gw message-command-style

# confirm no sessions/windows lost
tmux list-sessions
tmux list-windows -t zsh
```

## Notes
- No new dependencies, no `uv add` — this is pure tmux config.
- `tree-mode-selection-style`/`tree-mode-border-style`/`tree-mode-preview-style` do not exist in any real tmux release through 3.5a (confirmed against the actual installed binary) — never add these options; they will hard-error on `source-file` (`tmux source-file` aborts and leaves the previous config partially applied on a bad option, so this must not be attempted).
- The escaped-comma syntax inside `-F` (`#[fg=green#,bold]`) is required wherever a literal `,` must not be treated as a format-conditional separator; if `tmux source-file` reports a parse error on the new `bind-key` line during implementation, that's almost certainly the first thing to check.
- If, during implementation, live visual inspection of `prefix + w` shows the session-name label unexpectedly *does* pick up color from the `-F` string (contradicting the binary-string-constant analysis above), that's fine — it just means more of the UX wishlist is achievable than documented here; treat the analysis above as a floor, not a ceiling, and take the win if the live tmux proves more permissive.
