<!-- Lives at .github/security/threat_model.md in https://github.com/Black-HOST/csf. Read by Anthropic's OSS Scanner before each scan. -->
# Threat model: CSF (ConfigServer Security & Firewall), BlackHOST maintanance continuation 

## What this project does and where untrusted input enters

CSF is a Perl front-end to iptables/ip6tables/ipset (nftables via iptables-nft) plus
`lfd`, the Login Failure Daemon: a root daemon that tails service logs, detects
brute force, port scans, process and account anomalies, and blocks attackers. It runs
as root on shared-hosting servers (cPanel/WHM, DirectAdmin, CentOS Web Panel,
CyberPanel, InterWorx, VestaCP, Webmin and generic Linux). Every code path is root.
Assume the attacker is a remote client of one of the services the host runs, or a
hosting customer / reseller on the same box.

Untrusted input, in order of exposure:

1. **Log lines read by lfd** (`lfd.pl`, `lib/ConfigServer/RegexMain.pm`,
   `regex.custom.pm`, `etc/conf/csf.logfiles`, `csf.syslogs`): sshd, exim, dovecot,
   courier, pure-ftpd/proftpd, Apache and ModSecurity, cPanel/WHM, Webmin, suhosin,
   syslog. Any remote client can place attacker-chosen bytes in these logs (usernames,
   URLs, headers, SMTP envelope, PAM messages). Treat every log line as adversarial.
   Matches become IPs that are passed to iptables, to `BLOCK_REPORT` /
   `UNBLOCK_REPORT` hook scripts as arguments, to email templates in `tpl/`, and to
   `/var/lib/csf/` state files.
2. **Messenger service** (`lib/ConfigServer/Messenger.pm`, `etc/messenger/*.php`,
   `index.html`, `index.recaptcha.*`, `tpl/apache.*.txt`, `tpl/litespeed.*.txt`):
   an HTTP, HTTPS and SMTP responder shown to *blocked*, hostile clients. v1 is Perl
   daemons, v2 is PHP, v3 is an Apache or LiteSpeed virtual host generated from the
   templates, with an optional reCAPTCHA self-unblock flow. CVE-2026-67402
   (unauthenticated command execution as the web user through a `/usr/bin`
   ScriptAlias in the v15.03 Apache HTTPS template) is the reference incident; the
   regression test lives in `.github/tests/security/messenger/`.
3. **Cluster mode** (`CLUSTER_*` in `csf.conf`, handled in `lfd.pl` with
   `lib/Crypt`): lfd listens on `CLUSTER_PORT` for encrypted commands from
   `CLUSTER_SENDTO` / `CLUSTER_RECVFROM` members and executes allow/deny/config
   changes as root. Weak key handling, replay, or parsing bugs here are root-level
   lateral movement between servers.
4. **Downloaded data** (`lib/ConfigServer/URLGet.pm`, `csget.pl`, `csf -u`,
   `etc/conf/downloadservers`, `installer.sh`, `csf.blocklists`, `CC_*` GeoIP data,
   `csf.dyndns`, `lib/ConfigServer/RBLLookup.pm`, `AbuseIP.pm`, `CloudFlare.pm`):
   blocklists and country data are fetched (some over plain HTTP) and turned into
   ipset / iptables entries; the updater fetches and unpacks a tarball and runs the
   installer. Downloaded content must only ever become IP/CIDR entries or verified
   release files, never shell, Perl, or arbitrary file writes.
5. **Web UI** (`lib/ConfigServer/DisplayUI.pm`, `DisplayResellerUI.pm`, `cseUI.pm`,
   the panel glue under `panels/` and the integrated UI enabled by `UI = "1"`): the
   user is the panel administrator (root), except cPanel **resellers**, who get a
   restricted UI governed by `csf.resellers` and `RESTRICT_UI`. Every form field ends
   up as `csf` arguments, config lines, or file paths (`cseUI.pm` is a root file
   browser). Resellers must never reach root-only actions; CSRF and XSS matter because
   the victim's browser session is root.
6. **Local, semi-trusted input**: `/etc/csf/*` config and list files are root-owned
   and an attacker who can write them already owns the box, so that is out of scope.
   What is in scope is the handling of *values* that originate remotely and are stored
   there (comments on `csf -a`/`-d`/`-td` entries, dynamic DNS names, reseller names,
   log excerpts in temporary-block records) and the privilege boundary of
   `PT_DELETED_ACTION`, `BLOCK_REPORT`, `UNBLOCK_REPORT` and the `lfd` process
   tracking of user processes (`PT_*`, `lib/ConfigServer/KillSSH.pm`).

## Components that matter most / least

Most: `lfd.pl`, `csf.pl`, `lib/ConfigServer/*.pm` (RegexMain, Messenger, CheckIP,
Config, DisplayUI, DisplayResellerUI, cseUI, Sanity, GetIPs, GetEthDev, LookUpIP,
RBLLookup, RBLCheck, AbuseIP, CloudFlare, URLGet, Slurp, Sendmail, Logger, Ports,
Service, ServerCheck, ServerStats, KillSSH), `regex.custom.pm`, `etc/messenger/*`,
`tpl/apache.*.txt`, `tpl/litespeed.*.txt`, the installer and updater (`install*.sh`,
`installer.sh`, `csget.pl`, `auto*.pl`, `migratedata.sh`, `uninstall.sh`,
`os.pl`), and the per-panel defaults in `etc/conf/<panel>/csf.conf`.

Less: `panels/*` static assets and images, `profiles/`, `lib/csf.1.txt`, `csf.help`,
`apf_stub.pl`, `remove_apf_bfd.sh`, the Webmin packaging tarball.

Bundled third-party modules in `lib/` (`Crypt/*`, `HTTP/Tiny.pm`, `JSON/Tiny.pm`,
`Net/IP.pm`, `Net/CIDR/Lite.pm`, `version*`) are vendored upstream code: report
only how CSF uses them, or a bug that CSF's usage actually reaches.

Out of scope: the control panels themselves (cPanel, DirectAdmin, CWP, CyberPanel,
InterWorx, VestaCP, Webmin), Apache, LiteSpeed, PHP, the kernel netfilter stack,
Google reCAPTCHA, Cloudflare's API. Report how CSF drives them, not bugs in them.

## How to exercise it

- The build image installs CSF from the checkout with the generic profile:
  `/usr/sbin/csf`, `/usr/sbin/lfd`, modules in `/usr/local/csf/lib/ConfigServer/`,
  configuration in `/etc/csf/csf.conf` with `TESTING = "1"`. The source checkout is
  `/src`; it holds the per-panel profiles under `etc/conf/` and the installers.
- Unit tests: `prove -r .github/tests/unit` from `/src`. They load modules from the
  checkout through `.github/tests/lib/TestBootstrap.pm` and need no firewall.
  `regexmain.t` shows how to feed log lines to the matcher without running lfd;
  `messenger-apache.t` shows how to drive the Messenger v3 generator.
- Messenger security regression: `.github/tests/security/messenger/run.sh` with its
  own Apache/PHP image (`Dockerfile` in that folder); `driver.pl` invokes the real
  generator with controlled settings.
- Firewall operations (`csf -s`, `-r`, `-f`, `-l`, `csftest.pl`, starting `lfd`)
  need CAP_NET_ADMIN and netfilter modules. They work in a privileged container
  and not in a plain one. A report that needs a live firewall should say so and
  give the exact commands.
- lfd normally daemonises. For parsing bugs, prefer calling the RegexMain /
  Messenger / CheckIP functions directly, as the unit tests do, and show the input
  line or request that triggers the bug.

## How you rate severity

- **Critical**: unauthenticated remote code execution or root (Messenger, cluster
  port, update or download path leading to code execution, a log line that makes
  lfd execute attacker-controlled commands or write attacker-controlled paths as
  root); any remote attacker who can disable or bypass the firewall.
- **High**: authenticated UI to command injection or arbitrary file read/write beyond
  the intended config files (the UI user is root, so CSRF and stored or reflected XSS
  on state-changing pages count here); reseller to root or beyond `RESTRICT_UI`;
  a remote attacker who can make lfd block arbitrary IPs or ranges, for example a
  `/0` entry, denying service to legitimate users; downloaded blocklist or GeoIP
  content that becomes anything other than IP/CIDR entries; an update path that a
  network attacker can substitute (missing verification, HTTP fallback, TLS not
  checked); symlink or TOCTOU races in `/var/lib/csf`, `/etc/csf` or temp files that
  let a local user win root.
- **Medium**: ReDoS or unbounded memory in log matchers reachable from a remote
  client; information disclosure to blocked clients through Messenger; cluster
  message replay without root impact; local denial of service of lfd.
- **Low / informational**: anything that requires the attacker to already write
  root-owned `/etc/csf/*` files or run commands as root; documented weak defaults
  in `csf.conf`; `TESTING = "1"` disabling enforcement (intended); hardening ideas
  without a demonstrated path.

## Reports and patches

- One report per root cause. The panel installers (`install.*.sh`, `auto.*.pl`,
  `etc/conf/*/csf.conf`) and many regex blocks are copies of each other: report
  once and list the affected copies.
- Minimal patches in the existing style: Perl 5 with the modules `os.pl` checks plus
  LWP, no new CPAN dependencies, POSIX `sh` for scripts. Keep behaviour backward
  compatible; users upgrade in place with `csf -u` and keep their `csf.conf`.
- Reproducers: the log line, HTTP request, cluster message, config snippet or file,
  plus the exact command. State the prerequisites: which panel profile, which
  `csf.conf` setting must be on (`MESSENGER`, `MESSENGERV3`, `CLUSTER_*`, `UI`,
  `LF_*`, `CC_*`, `URLGET`), and whether a live firewall is needed.
- Say which panels are affected; defaults differ per profile in `etc/conf/<panel>/`.
- Security contact and disclosure process: `SECURITY.md` in the repository.

## Anything to leave alone

- The TLS or cipher choices inside LWP, Net::SSLeay or the vendored `Crypt` modules,
  unless CSF misuses them.
- Theoretical issues that need an attacker who already writes `/etc/csf/*` or runs
  commands as root.
- `TESTING = "1"` on a fresh install is documented and intended.
- Legacy `apf_stub.pl` and `remove_apf_bfd.sh` compatibility shims.
