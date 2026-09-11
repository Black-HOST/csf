# Security Policy

## Supported Versions

We currently provide security fixes for:

| Version | Supported |
| --- | --- |
| Latest release | ✅ |
| `main` branch | ✅ |
| Older releases | ⚠️ Best effort |

## CVE-2026-67402: Messenger v3 HTTPS

The Messenger v3 Apache HTTPS template shipped in v15.03 maps `/usr/bin`
as CGI programs. When Messenger v3 HTTPS is active, this can allow an
unauthenticated blocked client to execute commands as the Apache user. See
[the cPanel advisory](https://support.cpanel.net/hc/en-us/articles/43171958716439-Security-CSF-Security-Release-September-3rd-2026).

The fix removes that mapping from the shipped template. The shared Messenger
generator also omits literal `ScriptAlias` mappings to `/usr/bin` when reading
installed Apache templates, including older/customized templates retained by
every panel installer. Other directives, PHP handlers and native LiteSpeed
templates are unchanged. Installed templates are not overwritten; this is an
upgrade compatibility filter applied to generated configuration.

**Installing files alone does not repair an already running Apache virtual
host.** After installing the fix, restart CSF and LFD (`csf -ra`) so that active
Messenger v3 configuration is regenerated. The existing `MESSENGERV3TEST`
configuration test must be configured and pass before Apache is restarted;
check the Messenger startup logs and confirm that the loaded Messenger virtual
hosts no longer contain the system-binary CGI mapping. The automatic `csf -u`
path already restarts CSF/LFD; a manual `sh install.sh` does not.

If Messenger has already been disabled, inspect and remove any stale generated
Messenger include through the normal web-server configuration/test/reload
process: disabled flags alone do not prove that an old Apache include is gone.
Until a patched release can be installed, cPanel recommends disabling
`MESSENGERV3` and restarting CSF/LFD, then verifying the effective web-server
configuration. This patch does not backport the rest of cPanel 16.31's hardening.

## Reporting a Vulnerability

Please **do not** report security vulnerabilities through public GitHub issues.

Preferred method:

1. Use GitHub's **private vulnerability reporting** (Security Advisory) for this repository.
2. Include:
   - affected version(s)
   - impact and attack scenario
   - clear reproduction steps
   - suggested fix (if available)

If you cannot use private reporting, send us an email on: `csf@black.host`

## Response Process

Our target process is:

- Acknowledge report within **72 hours**
- Confirm severity and impact
- Prepare and test a fix
- Coordinate responsible disclosure timing with reporter

## Scope

This policy applies to:

- Source code in this repository
- Installation/update scripts shipped from this repository
- Official release artifacts produced from this repository

## Safe Harbor

We appreciate responsible disclosure. If you act in good faith, avoid data destruction, and do not violate user privacy, we will treat your report as authorized security research.
