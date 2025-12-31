# ConfigServer Security & Firewall (CSF)

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](#license)
[![Version](https://img.shields.io/github/v/tag/Black-HOST/csf?logo=GitHub&label=Version&color=ba5225)](https://github.com/Black-HOST/csf/releases)
[![Downloads](https://img.shields.io/github/downloads/Black-HOST/csf/total?logo=github&logoColor=FFFFFF&label=Downloads&color=376892)](https://github.com/Black-HOST/csf/releases)
[![Size](https://img.shields.io/github/repo-size/Black-HOST/csf?logo=github&label=Size&color=59702a)](https://github.com/Black-HOST/csf)
[![Last Commit](https://img.shields.io/github/last-commit/Black-HOST/csf?logo=github&logoColor=FFFFFF&label=Last%20Commit&color=313131)](https://github.com/Black-HOST/csf/activity)
[![Contributors](https://img.shields.io/github/contributors/Black-HOST/csf)](https://github.com/Black-HOST/csf/graphs/contributors)

> [!NOTE]
> **This is a community-maintained fork of CSF.**
> Following the shutdown of the original project and their release of the code under the GPLv3 license in August 2025, this repository serves as a continued development and maintenance effort to keep CSF secure and compatible with modern systems.

CSF is a Stateful Packet Inspection (SPI) firewall, Login/Intrusion Detection and Security application for Linux servers, used by Linix system administrators to secure their infrastructure and simplify server management.

## Features

- **Stateful Packet Inspection (SPI)**: Advanced firewall configuration.
- **Login Failure Daemon (LFD)**: Detects and blocks brute-force attacks.
- **Extensive Control Panel Support**: Integrated UI for cPanel, DirectAdmin, Webmin, and more.
- **Security Checks**: Automated server security audits.
- **Email Alerts**: Notifications for blocked IPs, login failures, and system issues.

## Installation

You can install CSF quickly using one of the following one-liners:

```bash
# Using wget
bash <(wget -qO - https://csf.black.host)
```

or

```bash
# Using wget
bash <(curl -sL https://csf.black.host)
```

This executes the remote [installer](installer.sh), which automates the following steps:

- Installs all necessary CSF dependencies.
- Deploys the latest stable version of CSF.
- Runs `csftests` to validate the installation and ensure everything is configured correctly.

## Migration

To migrate from v14 or the original v15.00 (from Way to the Web Limited) to this fork, you need to update your download server configuration.

Execute the following command on your server:

```bash
echo "download.black.host" > /etc/csf/downloadservers
```

After updating the download server, you can either:
1.  **Upgrade immediately**: Run `csf -u`
2.  **Wait for auto-update**: The cron script will perform the upgrade automatically.

## Contributors

Any contributions are welcome. Before submitting your contribution, please review the following resources:

- [PR Template](.github/PULL_REQUEST_TEMPLATE.md)
- [Contributor Policy](CONTRIBUTING.md)

<br />

![Alt](https://repobeats.axiom.co/api/embed/78e8bdd3b2b1c8d0f0b51c8850f0f4d3d8c1342e.svg "Repobeats analytics image")

## License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)**.
See the [LICENSE](LICENSE) file for details.

The original code was released by Way to the Web Limited [https://github.com/waytotheweb/scripts](https://web.archive.org/web/20250831101013/https://github.com/waytotheweb/scripts) but was subsequently removed from GitHub. Consequently, GitHub now incorrectly identifies a repository by mappy9211 as the primary source. 

This fork continues the legacy of Way to the Web Limited and Jonathan Michaelson, with the goal of ensuring this project remains free forever.
