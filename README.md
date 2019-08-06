<div align="center">
  <img width="100px" src="https://p0deje.github.io/Maccy/img/maccy/Logo.svg" alt="Logo" />
  <h1>
    <a href="https://p0deje.github.io/Maccy/">Maccy</a>
  </h1>
</div>

Maccy is a lightweight clipboard manager for macOS. It keeps the history of what you copy
and lets you easily navigate, search and use previous clipboard contents.

<!-- vim-markdown-toc Marked -->

* [Features](#features)
* [Install](#install)
* [Usage](#usage)
* [Customization](#customization)
  * [Automatically Start at Login](#automatically-start-at-login)
  * [Change Default Settings](#change-default-settings)
    * [Popup Hotkey](#popup-hotkey)
    * [History Size](#history-size)
    * [Show/Hide Icon in Status Bar](#show/hide-icon-in-status-bar)
    * [Automatically Paste by Default](#automatically-paste-by-default)
* [Update](#update)
* [Why Yet Another Clipboard Manager](#why-yet-another-clipboard-manager)
* [CI](#ci)
* [License](#license)

<!-- vim-markdown-toc -->

## Features

* Lightweight and fast
* Keyboard-first
* Secure and private
* Native UI
* Open source and free

## Install

Download the latest version from the [releases](https://github.com/p0deje/Maccy/releases/latest) page, or use [Homebrew](https://brew.sh/):

```bash
brew cask install maccy
```

## Usage

1. ⌘+⇧+C to popup Maccy or click on its icon in menu bar.
2. Type what you want to find.
3. To select the history item you want to copy, press Enter, or click the item, or use ⌘+n shortcut.
4. To select the history item and paste, press ⌥+Enter, or ⌥+click the item, or use ⌥+n shortcut.

## Customization

### Automatically Start at Login

Just add Maccy to your "Login items".

### Change Default Settings

To change default settings, use the following commands from Terminal.

#### Popup Hotkey

```bash
defaults write org.p0deje.Maccy hotKey control+option+m # default is command+shift+c
```

#### History Size

```bash
defaults write org.p0deje.Maccy historySize 100 # default is 999
```

#### Show/Hide Icon in Status Bar

```bash
defaults write org.p0deje.Maccy showInStatusBar false # default is true
```

#### Automatically Paste by Default

```bash
defaults write org.p0deje.Maccy pasteByDefault true # default is false
```

## Update

Download and reinstall the latest version from the [releases](https://github.com/p0deje/Maccy/releases/latest) page, or use [Homebrew](https://brew.sh/):

```bash
brew update
brew cask upgrade maccy
killall Maccy # closes the app if is running
open /Applications/Maccy.app # opens the new version
```

## Why Yet Another Clipboard Manager

There are dozens of similar applications out there, so why build another?
Over the past years since I moved from Linux to macOS, I struggled to find
a clipboard manager that is as free and simple as [Parcellite](http://parcellite.sourceforge.net),
but I couldn't. So I've decided to build one.

Also, I wanted to learn Swift and get acquainted with macOS application development.

## CI

[![Build Status](https://app.bitrise.io/app/716921b669780314/status.svg?token=3pMiCb5dpFzlO-7jTYtO3Q&branch=master)](https://app.bitrise.io/app/716921b669780314)

## License

[MIT](./LICENSE)
