# Juggle

A small macOS menu bar timer for switching between tasks. One task runs at a time, and time a task spends working in the background can be added the moment you switch back to it.

![Juggle timer in the menu bar](docs/screenshots/menu-bar-timer.png)

## Switch tasks

Click a task to start it and pause the others, or give each task a keyboard shortcut.

![Task list dropdown](docs/screenshots/task-dropdown.png)

## Add background time

Some work keeps going after you switch away: a build, a test run, an AI agent. When you switch to a task, Juggle offers a field for that time. Type `12` (minutes), `1:05`, `1h 5m` or `4m 32s`, or paste a line such as "Worked for 4m 32s", then press Return. If there's nothing to add, the field closes by itself after 10 seconds.

![Adding time after switching to a task](docs/screenshots/add-time.png)

## See where the time went

The Juggle window shows each task's time today and in total. A task's details keep tracked time apart from time you added, so any addition can be changed or removed later.

![Tasks window](docs/screenshots/tasks-window.png)

![Task details with tracked and added time](docs/screenshots/task-details.png)

## Also

- Export your daily history as CSV, including added time
- Pauses when your Mac sleeps or the screen locks
- Optionally follows Hubstaff: pauses when it stops, continues when it starts

Your data stays on your Mac.

## Install

Requires macOS 14 or later and Xcode. No Apple developer account is needed.

1. Build the app:

   ```sh
   git clone https://github.com/oyinlola007/juggle.git
   cd juggle
   xcodebuild -project Juggle.xcodeproj -scheme Juggle -configuration Release -derivedDataPath build
   ```

2. Copy it to Applications and open it:

   ```sh
   cp -R build/Build/Products/Release/Juggle.app /Applications/
   open /Applications/Juggle.app
   ```

Juggle appears in the menu bar, not the Dock, and opens at login. You can turn that off in Settings. If macOS asks, allow it in System Settings → General → Login Items.

To update, quit Juggle from Settings, run `git pull`, then repeat both steps after removing the old copy with `rm -rf /Applications/Juggle.app`. Your tasks and history are kept.

## Develop

Open `Juggle.xcodeproj` and press ⌘R. Press ⌘U to run the tests.

## License

[MIT](LICENSE)
