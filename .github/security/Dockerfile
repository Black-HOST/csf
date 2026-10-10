# Build CSF for Anthropic's OSS Scanner (https://github.com/anthropics/oss-scanner).
#
# Lives at .github/security/Dockerfile in this repository and is referenced from
# projects/csf/project.yaml in anthropics/oss-scanner. It mirrors the "Install" job
# of .github/workflows/tests.yml: Ubuntu 24.04, the OS packages from
# .github/actions/setup-csf, then `sh install.sh` from this checkout.
#
# The scanner builds this file with network access and then runs its audit with
# no Internet, so everything the tests need is fetched here. Nothing starts the
# firewall: `docker build` has no CAP_NET_ADMIN, and csf.conf stays in TESTING mode.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# Same packages as CI, plus git/ca-certificates (scanner layer), cron/logrotate so the
# installer's /etc/cron.d and /etc/logrotate.d files land in real directories, and
# man-db/bsdextrautils so the installer can render /usr/local/csf/lib/csf.help.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git \
      wget curl tar perl libwww-perl liblwp-protocol-https-perl libgd-graph-perl \
      iptables host unzip sendmail \
      cron logrotate man-db bsdextrautils \
    && rm -rf /var/lib/apt/lists/*

# scanner contract: the checkout lives inside the image, at /src
COPY . /src
WORKDIR /src

# Install CSF from this checkout exactly as CI does. The generic installer copies the
# Perl sources to /usr/sbin/csf, /usr/sbin/lfd and /usr/local/csf/lib and the generic
# profile to /etc/csf. install.sh exits 0 even when a precondition fails, so verify
# the installed layout explicitly.
RUN sh install.sh \
    && test -x /usr/sbin/csf \
    && test -x /usr/sbin/lfd \
    && test -s /etc/csf/csf.conf \
    && test -d /usr/local/csf/lib/ConfigServer \
    && csf -v

# Fast, deterministic unit tests, as the CI "tests" matrix runs them. A failing test
# must not abort the build; the log goes to primary_contact.
RUN prove -r .github/tests/unit || echo "WARNING: prove reported failures"
