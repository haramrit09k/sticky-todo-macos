# Session Todo

## TL;DR — try it

On a Mac running macOS 13 or newer (Apple Silicon or Intel):

```bash
git clone https://github.com/haramrit09k/sticky-todo-macos.git && cd sticky-todo-macos && ./install.sh
```

That builds the app locally, puts it in `/Applications`, and opens it. Press `⌘⇧Space` anytime to hide or bring it back.

I made this because I kept opening a task, getting distracted by something else, and then forgetting what I had originally sat down to do.

Session Todo is a small floating todo list for macOS. It is not meant to replace Things, Reminders, Linear, or whatever you use for planning. It is just for the current work session—the handful of things you are actually trying to get done right now.

The first unfinished task stays visually obvious. Everything else can be tucked away until you need it.

## Why this exists

Most todo apps are good at storing work. I wanted something better at reminding me what I was doing five minutes ago.

The problem usually looks like this:

1. Start working on something.
2. Open a browser to look up one small detail.
3. End up six tabs deep in a completely different problem.
4. Eventually wonder what I was supposed to be doing.

This app leaves the answer one shortcut away.

## What it does

- Keeps one **NOW** task front and center.
- Hides the rest of the backlog unless you ask to see it.
- Opens or hides with `⌘⇧Space` from anywhere on the Mac.
- Lives in the menu bar when the window is hidden.
- Lets you edit a task directly by clicking its text.
- Lets you drag tasks to reorder them (expand the backlog first).
- Gives you a few seconds to undo an accidental edit, delete, reorder, or completion.
- Can send an occasional silent nudge asking if you are still on the current task.
- Stores everything locally. No account and no sync.

There are intentionally no projects, labels, due dates, streaks, productivity scores, or dashboards.

## Install

For now, Session Todo is built from source. You need macOS 13 or newer and Xcode Command Line Tools.

If you do not have the command-line tools yet:

```bash
xcode-select --install
```

Then clone and install the app:

```bash
git clone https://github.com/haramrit09k/sticky-todo-macos.git
cd sticky-todo-macos
chmod +x build.sh install.sh
./install.sh
```

That builds the app, copies it to `/Applications/Session Todo.app`, and opens it.

If you would rather not install it yet:

```bash
./build.sh
open "outputs/Session Todo.app"
```

The build script compiles for the Mac it runs on, so it works on both Apple Silicon and Intel Macs. I have not packaged or notarized a downloadable universal release yet.

## How to use it

Type a concrete next step and press Return. Smaller tasks work better than vague ones—“write the intro paragraph” is more useful than “finish website.”

- Click the checkbox to complete a task.
- Click the task text or pencil to edit it. Return saves; Escape cancels.
- Expand **Show later** to see the backlog.
- Drag a task card to reorder it, or use the small up arrow.
- Press `⌘⇧Space` to hide or bring back the window.
- The `×` hides the window. It does not quit the app.
- Use `⌘Q` or the menu-bar menu when you actually want to quit.

## Nudges

The optional nudge feature sends a silent notification at a random point between 20 and 35 minutes, as long as you have an unfinished task.

It asks whether you are still working on the current task. **Yep** dismisses it. **Got distracted** brings the window back.

I made the timing slightly random because a perfectly predictable reminder is very easy to dismiss without thinking. That said, notifications can also become noise, so nudges can be turned off from the checkmark icon in the menu bar.

## Launch at login

There is a **Launch at login** toggle in the menu-bar menu. Install the app in `/Applications` before enabling it; macOS may reject login-item registration for a build running from another folder.

## Privacy

Tasks are saved with macOS `UserDefaults` on your own computer. The app does not make network requests and does not include analytics or telemetry.

Notifications are scheduled locally by macOS.

## Building / hacking on it

This is a deliberately small native Swift/AppKit app. There are no third-party dependencies.

```bash
./build.sh
```

The main code is in `Sources/SessionTodo/main.swift`. The build script compiles it with `swiftc`, creates the `.app` bundle in `outputs/`, and applies an ad-hoc signature.

The app uses:

- AppKit for the UI and floating window
- Carbon for the global shortcut
- UserNotifications for the focus check-ins
- ServiceManagement for launch at login

The code is still fairly compact and a little scrappy in places. Issues and small improvements are welcome.

## License

MIT. See [LICENSE](LICENSE).
