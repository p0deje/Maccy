# Maccy.app [![Travis builds](https://travis-ci.org/p0deje/Maccy.svg?branch=master)](https://travis-ci.org/p0deje/Maccy)

![Maccy.app](https://user-images.githubusercontent.com/665846/35605511-5a443776-0673-11e8-8d30-a0293a49332b.gif)

## About

Maccy is a simple clipboard manager for macOS inspired by [Parcellite](http://parcellite.sourceforge.net).

There are dozens of similar applications out there, so why build another?

* learn Swift
* get acquainted with macOS application development

## Features

* lightweight application using standard macOS menu
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

[MIT][LICENSE]
