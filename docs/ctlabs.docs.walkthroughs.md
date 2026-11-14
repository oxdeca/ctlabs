# Walkthroughs & Markdown Documentation Guide

The **Walkthroughs** view in CTLABS (`/demo`) provides an interactive documentation, playback, and authoring environment for lab scenarios. It allows instructors and operators to combine recorded terminal sessions, screen recordings, and rich Markdown notes into ordered, shareable step-by-step guides.

---

## 1. Walkthrough Sets & Folder Storage Layout

- **Dedicated Set Folders**: Each walkthrough set lives in its own directory on the server under `/srv/ctlabs-server/recordings/<walkthrough_slug>/`.
- **Set Directory Structure**:
  ```
  /srv/ctlabs-server/recordings/<walkthrough_slug>/
  ├── _walkthrough.json       # Scoped manifest (name, step sequence, unintegrated items)
  ├── <recording_id>.cast     # Terminal sessions
  ├── <video_id>.webm         # Video recordings
  ├── <video_id>.json         # Video metadata sidecar
  ├── <note_id>.md            # Markdown notes
  └── images/                 # Scoped images and screenshot attachments for this set
  ```
- **Self-Contained & Resilient**:
  - No monolithic global index file. If sets are moved, backed up, or copied individually, each set retains its own manifest (`_walkthrough.json`) and media.
  - Exporting, importing, or deleting walkthrough sets operates directly on the set directory boundaries.
  - Automatic migration cleanly transitions legacy flat storage into dedicated folders without downtime or data loss.
- **Walkthrough Set Actions**:
  - Switch sets using the **Walkthrough Set** dropdown in the left sidebar.
  - Create new sets with the **+ New Set** button.
  - Delete walkthrough sets with the red trash button (with an optional checkbox to also purge media files from disk).
- **Step Ordering & Navigation**:
  - Drag and drop steps in the sidebar to reorder them; ordering is saved automatically to the set's `_walkthrough.json`.
  - Navigate sequentially using the **Previous Step** / **Next Step** buttons or keyboard shortcuts (`Alt+Left` / `Alt+Right`, `PageUp` / `PageDown`).
  - Terminal sessions and videos automatically begin playback when advancing through steps.

---

## 2. Step Types

| Step Type | Extension | Player / Viewer | Capabilities |
|-----------|-----------|-----------------|--------------|
| **Terminal Cast** | `.cast` | Asciinema Player | Full ANSI terminal playback, speed adjustment, pause/resume, copy terminal text. |
| **Screen / Video** | `.webm`, `.mp4` | HTML5 Video Player | Fullscreen video, time scrubber, audio playback. |
| **Markdown Note** | `.md` | CodeMirror + Marked | Markdown editor, live preview, syntax highlighting, image management, emoji, and Vi mode. |

---

## 3. Markdown Note Editor & Previewer

Markdown notes support multi-view editing, rich GFM formatting, code block highlighting, and built-in image management.

### View Modes
- **Preview**: Renders the formatted Markdown document with rendered code blocks, images, tables, alerts, and emojis.
- **Edit**: Full-pane CodeMirror 5 editor with Markdown/GFM syntax highlighting and line numbers.
- **Split**: Side-by-side editing and real-time live preview.

### Editor Settings Menu (<i class="fas fa-cog"></i>)
Click the **Gear icon** on the right side of the step toolbar to configure editor preferences. Settings are persisted in browser `localStorage`:
- **Wrap code blocks**: Toggles line wrapping inside rendered `<pre><code>` blocks in the preview pane.
- **Vi / Vim keybindings**: Enables full modal editing for Vim users.

---

## 4. Vi / Vim Modal Editing Mode

When enabled in the Editor Settings menu:

- **Modal Editing**:
  - <span style="color: #38bdf8; font-weight: bold;">-- NORMAL --</span>: Default navigation (`h`, `j`, `k`, `l`, `w`, `b`, `0`, `$`, `gg`, `G`, `x`, `dd`, `yy`, `p`).
  - <span style="color: #22c55e; font-weight: bold;">-- INSERT --</span>: Standard text editing (`i`, `a`, `o`, `A`, `I`). Press `Esc` to return to Normal mode.
  - <span style="color: #f59e0b; font-weight: bold;">-- VISUAL --</span>: Text selection (`v` for character, `V` for line, `Ctrl+V` for block).
  - <span style="color: #ef4444; font-weight: bold;">-- REPLACE --</span>: Overwrite text (`R`).
- **Status Bar Indicator**:
  A compact status bar appears at the bottom of the editor displaying the current mode and active key sequences.
- **Ex Commands & Search**:
  - Type `:w` followed by `Enter` in Normal mode to save the note.
  - Type `:wq` followed by `Enter` to save the note.
  - Type `/pattern` followed by `Enter` to search forward.
  - Type `?pattern` followed by `Enter` to search backward.
  - Press `n` to jump to the next search match, or `N` to jump to the previous match.
  - Use `*` or `#` to instantly search for the word under the cursor forward or backward.
  - Full substitute support: `:%s/old/new/g` or `:s/old/new/g`.

---

## 5. Markdown Emojis & Emoji Picker

The editor supports GitHub-style emoji shortcodes both when authoring and when previewing:

- **Supported Syntax**:
  - Shortcodes like `:rocket:`, `:warning:`, `:white_check_mark:`, `:bulb:`, `:fire:`, `:tada:`, `:lock:`, `:whale:`, etc.
  - Shortcodes inside code blocks (```` ```...``` ````), inline code (`` `...` ``), and URLs are protected and preserved verbatim.
- **Interactive Emoji Picker**:
  - Click the **Emoji button** (<i class="far fa-smile"></i>) on the editor toolbar or press `Ctrl+E` (`Cmd+E` on macOS).
  - Categorized tabs: Status & Alerts, Tech & DevOps, People & Reactions, Symbols & Objects.
  - Real-time search filter with quick clear.
  - Insert format toggle: Choose between inserting `:shortcode: ` or raw Unicode character (`Char`).

---

## 6. Image Resizing & Attachment Management

- **Custom Image Dimensions**:
  Images in Markdown notes can be resized using multiple intuitive syntaxes:
  - **Equal syntax**: `![Architecture](images/arch.png =400x250)` or `![Server](images/server.png =60%)`
  - **Curly attribute syntax**: `![Diagram](images/diag.png){width=500 height=300}` or `![Diagram](images/diag.png){width="80%"}`
  - **Obsidian pipe syntax**: `![Diagram|400x200](images/diag.png)`
- **Image Insertion**:
  - **Upload**: Click the picture button on the toolbar to select local image files.
  - **Copy-Paste**: Paste images directly from the OS clipboard into CodeMirror (`Ctrl+V` / `Cmd+V`).
  - **Drag & Drop**: Drag images directly onto the editor pane. Images are automatically saved to `/recordings/images/` and linked at the cursor.

---

## 7. Export & Import Workflows

### Exporting
- **Walkthrough Set Export**:
  - Click the **Export Walkthrough Set** button on the top toolbar.
  - A modal prompts for a custom zip file name (defaults to `<set_name>_walkthrough.zip`).
  - Bundles `_walkthrough.json`, terminal `.cast` recordings, `.webm`/`.mp4` videos, `.md` notes, and referenced image assets.
- **Markdown Note Export**:
  - Click the **Download** button on any Markdown note step.
  - Choose between downloading the raw `.md` file or downloading a **Markdown Bundle (.zip)** that includes all referenced images with localized paths.

### Importing
- **Drag & Drop**: Drag `.cast`, `.webm`, `.mp4`, `.md`, or `.zip` files directly onto the left sidebar to import them into the active walkthrough set.
- **Import Button**: Click the **Import** button next to the walkthrough title.
- **Duplicate Protection**: Importing files with matching names offers conflict warnings or automatic unique naming to avoid overwriting existing documentation.
- **Image Path Normalization**: Imported markdown zip files automatically resolve local relative image links to `/recordings/images/` so screenshots render immediately.

---

## 8. Git Repository Sync

Each walkthrough set can be linked to its own git repository so sets can be authored locally, versioned remotely, and shared between CTLABS installations. The git metadata is kept **outside** the set directory, so it never pollutes the set folder or the server's recording storage.

- **Open the Git Dialog**: Click the <i class="fas fa-code-branch"></i> branch icon in the Walkthroughs toolbar. The dialog shows the current link state, remote, branch, last commit, ahead/behind counts, and any uncommitted files.
- **Link an Existing Set**:
  - Open the set, enter a **Remote URL** (and optional branch), then click **Link / Save Remote**.
  - The first **Push** creates the branch on the remote (the branch is created from the set's current files).
- **Clone a Repository as a New Set**:
  - Expand **Clone a repository as a new walkthrough set** in the dialog, enter the repository URL, and optionally a branch and set name.
  - The clone is imported into `/srv/ctlabs-server/recordings/<slug>/` and opened immediately.
  - Cloning always creates a new set; existing sets are never overwritten.
- **Sync Actions**:
  - **Fetch**: Updates remote-tracking refs without touching local files.
  - **Pull**: Fast-forward only. Pull fails rather than creating merge conflicts; resolve divergent branches in the remote repository or via the CLI.
  - **Push**: Commits any local changes (using the message field) and pushes the branch upstream.
  - **Commit**: Commits local changes without pushing.
  - **Unlink**: Removes the local git link and metadata. The set files stay on disk.
- **What Is Tracked**:
  - Manifests, Markdown notes, terminal `.cast` recordings, image attachments, and other set files are tracked.
  - `.webm`/`.mp4` videos are excluded from git sync to keep repositories small. Existing tracked videos remain tracked; new videos are ignored.
- **Remote URL Support**:
  - Supported: `https://`, `http://`, `ssh://`, `git://`, and scp-like `git@host:org/repo.git`.
  - SSH uses the server's `~/.ssh` configuration and SSH agent (non-interactive; host keys are accepted on first use).
  - HTTPS credentials may be embedded in the URL (`https://token@host/org/repo.git`); credentials are redacted in status responses.
  - `file://` and absolute local paths are disabled by default and only allowed when `CTLABS_GIT_ALLOW_LOCAL_REMOTES=1`.
  - `ext::` transport helpers, option-looking URLs, whitespace, and control characters are rejected.
- **Environment Overrides**:
  - `CTLABS_RECORDINGS_ROOT` (default `/srv/ctlabs-server/recordings`) controls where sets live.
  - `CTLABS_WALKTHROUGH_GIT_DIR` (default `/srv/ctlabs-server/walkthrough-git`) controls where per-set git metadata is stored.
- **Relationship to Version History**:
  - The existing **Version History** dialog (<i class="fas fa-history"></i>) continues to track the whole recording root in a separate local repository.
  - Git sync operations also mirror their commit into that local history, so per-set changes remain visible in the server's version history.
- **Operational Notes**:
  - Git must be installed on the server; the dialog reports when it is not.
  - Pull/push commands run non-interactively with a 180-second timeout.
  - Failed clones clean up the partially created set directory and git metadata automatically.
