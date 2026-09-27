# Closed-Lid Mode: implementation and authorization gate

## Current state

AmorDrop now builds a dedicated root LaunchDaemon and communicates with it over a
private XPC service. It is embedded at
`Contents/MacOS/AmorDropClosedLidHelper`, with the Service Management plist at
`Contents/Library/LaunchDaemons/com.amor.personal.amordrop.closed-lid.plist`.
Building the app packages this helper but does not install it or change system
settings. Registration is a separate explicit action through `SMAppService` and
requires administrator approval. Runtime and registration state are specific to
each Mac. This source change does not modify `sudoers`, FileVault, Touch ID, or
macOS authentication settings.

The helper snapshots `SleepDisabled` before enabling the temporary
`pmset -a disablesleep 1` override. It writes a root-only recovery record to
`/var/db/com.amor.personal.amordrop.closed-lid-state.plist` before changing the
setting. It verifies the change and restoration, and keeps the state record if
restoration fails. It restores on normal stop, app/XPC disconnection, low or
unreadable battery state, and helper startup after an unexpected exit or reboot.
`KeepAlive` asks launchd to restart a crashed helper. Unregister first stops the
session and refuses to continue if restoration cannot be verified. There is no
sudoers rule or permanent sleep override.

## Approval flow

The app uses `SMAppService` for the bundled LaunchDaemon. The menu and settings
only request registration after a direct user action; registration then requires
administrator approval in System Settings. Apple documents that a LaunchDaemon
is not started until an administrator approves it. The app has an explicit
remove-helper path that restores an active session before unregistering.

## Lock-screen limitation

AmorDrop does not change macOS authentication or lock settings. Ordinary IOKit
Keep Awake assertions do not prevent forced lid-close sleep. The helper's
`disablesleep` override is a separate, system-level mechanism. The app warns the
user to lock manually with Control-Command-Q before closing the lid; automatic
lock-on-lid behavior has not been verified on this Mac, so the feature must not
be described as guaranteeing that the session locks automatically.

## Required tests before routine use

After explicit administrator approval, verify on the physical Mac:

- Registration and helper launch from the installed `/Applications/AmorDrop.app`.
- Normal start/stop restores the exact prior `SleepDisabled` value.
- App force quit, helper termination/restart, and reboot recover the saved value.
- Low battery and unreadable battery telemetry both restore normal sleep.
- Closing/opening the lid continues the intended task and preserves the locked
  session behavior expected by the user.
- Unregister restores the original value before removing the daemon.

The last closed-lid/lock checks cannot be safely simulated by unit tests. Until
they pass, use only after manually locking the session and with a power source
connected. This work has not requested administrator approval or activated the
helper.
