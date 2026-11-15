ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ARG BASE_IMAGE
LABEL tools.m2.base-image="${BASE_IMAGE}"

USER root
SHELL ["/bin/bash", "-p", "-euo", "pipefail", "-c"]
RUN export PATH=/usr/sbin:/usr/bin:/sbin:/bin; \
    umask 022; \
    mkdir /usr/local/share/tools-m2; \
    find /opt/epics -printf '%y %m %u %g %p %l\n' | LC_ALL=C sort > /usr/local/share/tools-m2/epics-members.before; \
    find /opt/epics -type f -exec sha256sum '{}' + > /usr/local/share/tools-m2/epics.sha256; \
    if command -v apt-get > /dev/null; then \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ripgrep; \
        dpkg-query -W ripgrep diffutils > /usr/local/share/tools-m2/packages.tsv; \
        apt-get clean; \
    elif command -v dnf > /dev/null; then \
        dnf install -y ripgrep diffutils; \
        rpm -q ripgrep diffutils > /usr/local/share/tools-m2/packages.tsv; \
        dnf clean all; \
    else \
        printf 'Unsupported package manager\n' >&2; exit 2; \
    fi; \
    find /opt/epics -printf '%y %m %u %g %p %l\n' | LC_ALL=C sort > /usr/local/share/tools-m2/epics-members.after; \
    cmp /usr/local/share/tools-m2/epics-members.before /usr/local/share/tools-m2/epics-members.after; \
    sha256sum --quiet -c /usr/local/share/tools-m2/epics.sha256; \
    printf '0\n' > /usr/local/share/tools-m2/payload-check.status

USER 1000:1000
