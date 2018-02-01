# Maccy.app [![Travis builds](https://travis-ci.org/p0deje/Maccy.svg?branch=master)](https://travis-ci.org/p0deje/Maccy)

![Maccy.app](https://user-images.githubusercontent.com/665846/35605511-5a443776-0673-11e8-8d30-a0293a49332b.gif)

## About

Maccy is a simple clipboard manager for macOS. It keeps the history of what you copy
and lets you easily navigate, search and use previous clipboard contents.

There are dozens of similar applications out there, so why build another?
Over the past years since I moved from Linux to macOS, I struggled to find
a clipboard manager that is as free and simple as [Parcellite](http://parcellite.sourceforge.net).
Also, I wanted to learn Swift and get acquainted with macOS application development.

## Features

* open source and free
* lightweight
* uses standard macOS menu
* search-as-you-type

## Usage

⌘+⇧+C.

## Customization

```bash
$ defaults write org.p0deje.Maccy historySize 100 # default is 999
```

## To Do

- [ ] allow to customize keyboard shortcut
- [x] ~~add preferences window~~ use `defaults`
- [x] ~~automatically start at login~~ just add Maccy to your "Login Items"
- [ ] add more unit tests
- [ ] add UI tests

## License

[MIT](./LICENSE)
