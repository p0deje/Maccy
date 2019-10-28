<div align="center">
  <img width="100px" src="https://p0deje.github.io/Maccy/img/maccy/Logo.svg" alt="Logo" />
  <h1>
    <a href="https://p0deje.github.io/Maccy/">Maccy</a>
  </h1>
</div>

Maccy is a lightweight clipboard manager for macOS. It keeps the history of what you copy
and lets you quickly navigate, search, and use previous clipboard contents.

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
    * [Enable/Disable Fuzzy Search](#enable/disable-fuzzy-search)
    * [Ignore Copied Items](#ignore-copied-items)
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

```sh
brew cask install maccy
```

## Usage

1. <kbd>COMMAND (⌘)</kbd> + <kbd>SHIFT (⇧)</kbd> + <kbd>C</kbd> to popup Maccy or click on its icon in the menu bar.
2. Type what you want to find.
3. To select the history item you wish to copy, press <kbd>ENTER</kbd>, or click the item, or use <kbd>COMMAND (⌘)</kbd> + `n` shortcut.
4. To choose the history item and paste, press <kbd>OPTION (⌥)</kbd> + <kbd>ENTER</kbd>, or <kbd>OPTION (⌥)</kbd> + <kbd>CLICK</kbd> the item, or use <kbd>OPTION (⌥)</kbd> + `n` shortcut.
5. To delete the history item, press <kbd>OPTION (⌥)</kbd> + <kbd>DELETE (⌫)</kbd>.
6. To see the full text of the history item, wait a couple of seconds for tooltip.

## Customization

### Automatically Start at Login

Just add Maccy to your "Login items".

### Change Default Settings

To change default settings, use the following commands in Terminal.

#### Popup Hotkey

```sh
defaults write org.p0deje.Maccy hotKey control+option+m # default is command+shift+c
```

#### History Size

```sh
defaults write org.p0deje.Maccy historySize 100 # default is 200
```

#### Show/Hide Icon in Status Bar

To hide you can simply drag the icon away from the status bar with <kbd>COMMAND (⌘)</kbd> pressed.
To recover the icon, re-open Maccy while it's already running.

You can also control visibility using configuration:

```sh
defaults write org.p0deje.Maccy showInStatusBar false # default is true
```

> Don't forget to restart Maccy after using `defaults` command!

#### Automatically Paste by Default

Select and paste in one go.

```sh
defaults write org.p0deje.Maccy pasteByDefault true # default is false
```

#### Enable/Disable Fuzzy Search

```sh
defaults write org.p0deje.Maccy fuzzySearch true # default is false
```

> Note that enabling fuzzy search will slow down when searching through the long history items list (200+).

#### Ignore Copied Items

You can tell Maccy to ignore all copied items:

```sh
defaults write org.p0deje.Maccy ignoreEvents true # default is false
```

This is useful if you have some workflow for copying sensitive data. You can set `ignoreEvents` to true, copy the data and set `ignoreEvents` back to false.

## Update

Download and reinstall the latest version from the [releases](https://github.com/p0deje/Maccy/releases/latest) page, or use [Homebrew](https://brew.sh/):

```sh
brew cask upgrade maccy
open -a Maccy
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
