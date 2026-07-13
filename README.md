SensorsKit
==========

[![Build Status](https://img.shields.io/github/actions/workflow/status/macmade/SensorsKit/ci-mac.yaml?label=macOS&logo=apple)](https://github.com/macmade/SensorsKit/actions/workflows/ci-mac.yaml)
[![Issues](http://img.shields.io/github/issues/macmade/SensorsKit.svg?logo=github)](https://github.com/macmade/SensorsKit/issues)
![Status](https://img.shields.io/badge/status-active-brightgreen.svg?logo=git)
![License](https://img.shields.io/badge/license-mit-brightgreen.svg?logo=open-source-initiative)  
[![Contact](https://img.shields.io/badge/follow-@macmade-blue.svg?logo=twitter&style=social)](https://twitter.com/macmade)
[![Sponsor](https://img.shields.io/badge/sponsor-macmade-pink.svg?logo=github-sponsors&style=social)](https://github.com/sponsors/macmade)

### About

SensorsKit is a macOS framework providing read access to hardware sensors via the SMC and IOHID private APIs.

### Features

  - Reads sensors from two subsystems: **IOHID** and the **System Management Controller (SMC)**.
  - Reports four kinds of readings: **temperature**, **voltage**, **current** and **ambient light**.
  - Polls every sensor once per second on a dedicated background thread.
  - Keeps a rolling history of the 50 most recent samples per sensor, with derived **min**, **max** and **last** values.
  - Publishes results through key-value-observable properties on the main queue, ready to bind to a UI.
  - Fully Objective-C interoperable.

> **Note:** SMC readings are classified by their key-name prefix (`T`, `V`, `I`), which is a best-effort heuristic — some values may be mislabeled and some sensors omitted.

License
-------

Project is released under the terms of the MIT License.

Repository Infos
----------------

    Owner:          Jean-David Gadina - XS-Labs
    Web:            www.xs-labs.com
    Blog:           www.noxeos.com
    Twitter:        @macmade
    GitHub:         github.com/macmade
    LinkedIn:       ch.linkedin.com/in/macmade/
    StackOverflow:  stackoverflow.com/users/182676/macmade
