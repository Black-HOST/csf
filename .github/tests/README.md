# CSF test system

This directory contains the repository-owned test suite used by the `Tests` GitHub Actions workflow.

The goal is to keep the test system simple, portable, and friendly to contributors:

- use standard Perl tooling (`prove`, `Test::More`) where possible
- run tests against the current repository checkout
- keep unit tests fast and deterministic
- provide shared helpers for future growth without locking the project into a heavy framework

## How the current CI flow works

The workflow entrypoint is `.github/workflows/tests.yml`.

It groups the checks as follows:

- **unit → tests** — discovers `.t` files and runs each in its own matrix job.
- **install → smoke / upgrade / uninstall** — validates the installation lifecycle.
- **compatibility → distro checks** — calls `.github/workflows/compatibility.yml`.
- **security → security-tests** — loads `.github/security.json` and runs each suite in its own matrix job, currently `messenger`.

Like `unit → tests`, the Actions graph shows a separate `security` discovery
job feeding the `security-tests` matrix. Add future security suites to
`.github/security.json` with a unique `name`, a `dockerfile` path, and a Bash
`script` path relative to the repository root. Each suite runs in its own
disposable container with networking disabled and the checkout mounted
read-only at `/repo`. Messenger's Perl unit regressions remain in the normal
unit-test matrix.

## Directory layout

```text
.github/tests/
├── README.md            # this document
├── integration/         # disposable-environment integration tests
├── lib/                 # shared test helpers and bootstrap modules
└── unit/                # unit test files (*.t)
```

### `lib/`
Shared helpers live here.

Current helper:

- `TestBootstrap.pm` — ensures tests load modules from the repository checkout instead of any system-installed CSF copy

### `unit/`
Contains fast tests for isolated code paths.

Unit tests should prefer:

- pure function testing
- deterministic inputs and outputs
- no network access
- no dependency on `/etc/csf`, `/usr/local/csf`, or a live firewall state

Because discovery is recursive, contributors may add subdirectories under `unit/` later if grouping tests becomes useful.

## Running tests locally

From the repository root:

```bash
prove -v -r .github/tests/unit/
```

If you only want to run one file:

```bash
prove -v .github/tests/unit/checkip.t
```

## How to write a new unit test

1. Create a new `.t` file anywhere under `.github/tests/unit/`
2. Use `strict`, `warnings`, and `Test::More`
3. Add `.github/tests/lib` to `@INC`
4. Load `TestBootstrap` before loading project modules
5. Import the function(s) or module(s) you want to test
6. Keep the test self-contained and deterministic

### Example skeleton

```perl
#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();
use ConfigServer::SomeModule qw(some_function);

subtest 'some_function handles the happy path' => sub {
    is( some_function('example'), 'expected', 'returns expected value' );
};

done_testing;
```

## Test design guidelines

When adding tests, prefer the following order:

### 1. Test behavior, not implementation trivia
Good tests lock down externally useful behavior.
Avoid asserting internal details unless they are part of the contract.

### 2. Keep tests local-first
Prefer tests that run without special services, custom images, or machine-specific setup.
If a behavior needs a richer environment, it likely belongs in a future integration suite.

### 3. Use shared helpers when repetition appears
If two or three tests need the same bootstrap or fixture logic, move that logic into `.github/tests/lib/`.

### 4. Keep fixtures explicit
If a test needs sample data, store it in a clear form and make the dependency obvious inside the test.

### 5. Fail loudly and clearly
Test names should make it obvious what broke.
Future contributors should be able to understand a failure from the `prove` output alone.

## Scope boundaries

This test directory is intentionally separate from upstream historical test layouts.
We may study external approaches, but tests added here should be repository-owned and written for this project's needs.

In practice that means:

- do not copy vendor-specific test harnesses wholesale
- do not depend on control-panel-specific test utilities
- do not introduce external branding or references into the local test system

## Messenger Apache integration test

GitHub Actions runs this as **messenger** in the `security-tests` matrix,
after the **security** discovery job in `.github/workflows/tests.yml`.

Run this test only in a disposable Docker container. It writes real CSF/Apache
paths inside that container and never installs CSF or changes the host firewall:

```bash
docker build -f .github/tests/integration/Dockerfile.messenger-apache -t csf-messenger-test .
docker run --rm --network none -v "$PWD:/repo:ro" csf-messenger-test bash /repo/.github/tests/integration/messenger-apache.sh
```

The test uses a harmless CGI response as a vulnerable positive control, then
exercises the real Messenger v3 generator and Apache/PHP over TLS. It verifies
fresh and retained v15.03 templates, two TLS virtual hosts, custom settings,
unchanged installed template bytes, and repeated regeneration. It does not
exercise real firewall redirection or Google's reCAPTCHA service.

## Future growth

As coverage expands, this structure can grow without changing the basic workflow model. Likely next steps are:

- more files under `unit/`
- reusable helpers under `lib/`
- optional sibling suites later, such as `integration/` or `fixtures/`

The workflow can keep a single `Tests` entrypoint while adding more jobs only when the suite actually needs them.
