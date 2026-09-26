# AmorDrop

AmorDrop is a private, native macOS file shelf based on [Dropshit](https://github.com/iamsumanp/Dropshit) by Suman Pokharel. It keeps the original SwiftUI/AppKit shelf and drag implementation, with the automatic updater removed and a local app bundle for this Mac.

## Use

- Drag files from Finder and shake the pointer to summon a shelf, then release the files over it.
- Drop more files, folders, images, PDFs, or text onto an open shelf.
- Drag one or more items from a shelf into Finder or another app's drop target.
- Press Space on a selected item for Quick Look. Shelf actions also include ZIP creation and image conversion.
- Click the menu bar icon for new shelves and settings. Press Control-Option-Space anywhere to create a shelf.
- Opening AmorDrop again from Finder summons a shelf if no window is visible.
- Shelves stay available across launches. Shelf expiry defaults to Never.

## Build and install

Requires complete Xcode 27 with the matching Swift toolchain and macOS 27 SDK. This build targets Apple Silicon only. From the project directory:

```sh
bash scripts/build-private-app.sh
```

This builds `build/AmorDrop.app`, with bundle identifier `com.amor.personal.amordrop`, menu-bar-only behavior, and an ad-hoc local signature. Signing takes place in a dedicated temporary directory to avoid Documents file-provider metadata interfering with the signature. To install it, copy the app bundle to `/Applications` and open it. No Developer ID, notarization, login account, or network connection is required for the shelf and shortcut. macOS may ask for access to files in protected locations.

## Verification on this Mac

The Release build and 44 XCTest tests passed on Xcode 27. The installed app launched successfully. Live checks verified shelf creation, file names and thumbnails for seven fixture types, Quick Look, clearing, undo, closing/reopening, and the Finder-copy → Shelf-paste → Shelf-copy → Finder-paste workflow, including file-content hashes. Automated tests cover multiple shelves, file-promise safety, ZIP archives, PNG/JPEG conversion, and the shake recognition algorithm.

On 2026-09-26, the owner confirmed that the menu bar icon, physical Control-Option-Space, shake-to-summon during a Finder file drag, real Finder → Shelf → Finder drag-and-drop, and edge docking all work normally. Release was rebuilt and all 44 XCTest tests passed again without application-source changes. This version is frozen as the personal AmorDrop V1 baseline under the annotated tag `amordrop-v1.0.0`. See [the baseline record](docs/V1-BASELINE.md) for verification scope and artifact identity. Browser upload drag-and-drop and long-duration sleep/wake behavior remain outside this acceptance round.

## Privacy and file handling

The app has no analytics, account, cloud upload, or update service. It does not make network requests. Files dragged from Finder remain at their original locations; shelf entries reference them. Explicitly choosing **Move to Trash** moves the selected file to the macOS Trash. Shelf expiry removes entries only and never deletes backing files; expiry is off by default. Pasted snippets and images use temporary backing files.

## Upstream attribution and license

The upstream README identifies Dropshit as MIT-licensed, but the checked-out upstream revision did not contain a `LICENSE` file. This copy includes the standard MIT license text and credits the upstream author as Suman Pokharel (GitHub: `iamsumanp`). The original source attribution remains here and in `LICENSE`.

## Scope

This is a local personal build. Sparkle, its appcast, and release packaging have been removed. Video conversion and OCR remain in the upstream source, though they are outside the requested core workflow.
