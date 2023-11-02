[![Build Windows](https://github.com/Silverlan/pr_davinci/actions/workflows/build-windows-ci.yml/badge.svg)](https://github.com/Silverlan/pr_davinci/actions/workflows/build-windows-ci.yml) [![Build Linux](https://github.com/Silverlan/pr_davinci/actions/workflows/build-linux-ci.yml/badge.svg)](https://github.com/Silverlan/pr_davinci/actions/workflows/build-linux-ci.yml)

# DaVinci Resolve Bridge
This is a binary module for the [Pragma Game Engine](https://github.com/Silverlan/pragma). For more information on binary modules, check out [this wiki article](https://wiki.pragma-engine.com/books/pragma-engine/page/binary-modules).

## Installation
To install this module, download one of the prebuilt binaries on the right and extract the archive over your Pragma installation.

The module can then be loaded in Pragma by running the following console command:
```
lua_run_cl print(engine.load_library("modules/pr_davinci/pr_davinci"))
```

(You can use `lua_run` instead of `lua_run_cl` to load the module serverside instead of clientside.)

## Developing

Please see the [wiki](https://wiki.pragma-engine.com/books/pragma-engine/page/binary-modules#bkmrk-building-modules) for instructions on how to develop and build the module.
