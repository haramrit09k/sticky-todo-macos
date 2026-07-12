# Session Todo

A small, local-only macOS focus widget for keeping the current session's next task visible—without turning productivity into another project.

Session Todo is built for people who get pulled into rabbit holes, lose track of their original intention, or feel overwhelmed by a large task manager. It keeps one task visually dominant, hides the backlog until requested, and offers gentle focus check-ins.

## The problem it solves

Traditional todo apps are excellent for planning, but they can be too heavy for answering a simpler question:

> What was I supposed to be doing right now?

Session Todo creates a lightweight boundary between planning and doing. It helps you:

- Recover your intention after getting distracted.
- Keep one next action visible without staring at an entire project backlog.
- Capture a task quickly without organizing tags, dates, projects, or priorities.
- Notice a distraction loop through optional, low-frequency nudges.
- Return to the list from anywhere with one keyboard shortcut.

It deliberately avoids accounts, cloud sync, streaks, analytics, and complicated productivity systems.

## Features

- One visually prominent **NOW** task.
- Collapsible backlog for keeping later work out of sight.
- Global `⌘⇧Space` shortcut to show or hide the widget.
- Menu-bar access when the window is hidden.
- Inline task editing: click the task text or pencil, then press Return to save.
- Checkbox-only completion to prevent accidental task completion.
- Drag-and-drop task reordering when the backlog is expanded.
- Arrow control as an accessible reordering fallback.
- Five-second Undo after completing, deleting, editing, or reordering.
- Optional silent focus nudges at randomized 20–35 minute intervals.
- A **Got distracted** notification action that restores the widget.
- Optional launch at login.
- Local persistence through macOS `UserDefaults`.
- No network requests, accounts, telemetry, or sync.

## Requirements

- macOS 13 Ventura or later.
- Apple Silicon Mac. The included build script currently creates an `arm64` app using the active Swift toolchain.
- Xcode Command Line Tools or Xcode.

Install the command-line tools if needed:

```bash
xcode-select --install
```

## Install from source

Clone and build:

```bash
git clone https://github.com/haramrit09k/session-todo.git
cd session-todo
chmod +x build.sh install.sh
./install.sh
```

The installer builds an ad-hoc-signed app, copies it to `/Applications/Session Todo.app`, and opens it.

You can also build without installing:

```bash
./build.sh
open "outputs/Session Todo.app"
```

## Using Session Todo

1. Type a small, concrete next step and press Return.
2. Work from the task marked **NOW**.
3. Click the checkbox when it is complete.
4. Use **Show later** to reveal the backlog.
5. Drag tasks to reorder them, or use the upward arrow.
6. Click task text to edit it in place. Press Return to save or Escape to cancel.
7. Press `⌘⇧Space` from any app to hide or restore the widget.

The `×` button hides the window without quitting. Use `⌘Q` or the menu-bar menu to quit completely.

## Gentle nudges

When enabled, Session Todo sends a silent check-in at a randomized interval between 20 and 35 minutes, but only when an unfinished task exists.

The notification asks whether you are still working on the current task:

- **Yep** dismisses the check-in.
- **Got distracted** restores Session Todo and focuses the input.

Nudges can be enabled or disabled from the checkmark icon in the macOS menu bar. macOS notification permission is required.

## Launch at login

Open the checkmark menu-bar menu and enable **Launch at login**. macOS may require the app to be installed in `/Applications` before it can register as a login item.

## Privacy

Session Todo is intentionally local-only.

- Tasks are stored in macOS `UserDefaults` on your computer.
- The app does not connect to the internet.
- There is no account, sync service, analytics SDK, or telemetry.
- Notifications are created locally by macOS.

## Development

The app is a small native Swift/AppKit project with no third-party dependencies.

```bash
./build.sh
```

The script:

1. Compiles `Sources/SessionTodo/main.swift` with `swiftc`.
2. Creates a standard macOS `.app` bundle under `outputs/`.
3. Writes the bundle metadata.
4. Applies an ad-hoc code signature.

Main frameworks:

- AppKit for the interface and floating panel.
- Carbon for the global keyboard shortcut.
- UserNotifications for focus nudges.
- ServiceManagement for launch-at-login support.

## Design principles

- **One thing first:** the current task gets the strongest visual treatment.
- **Progressive disclosure:** later tasks remain hidden until requested.
- **Low shame:** nudges are neutral check-ins, not streaks or warnings.
- **Fast recovery:** one global shortcut brings the original intention back.
- **Minimal administration:** no projects, labels, due dates, or setup ceremony.

## License

MIT License. See [LICENSE](LICENSE).
