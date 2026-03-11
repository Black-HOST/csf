#!/bin/sh

DRY_RUN=${DRY_RUN:-0}
PANEL_HINT=""
WARNINGS=0

usage() {
    echo "Usage: $0 [--dry-run] [cpanel|cwp|cyberpanel|directadmin|generic|interworx|vesta]" >&2
}

is_valid_panel() {
    case "$1" in
        cpanel|cwp|cyberpanel|directadmin|generic|interworx|vesta)
            return 0
            ;;
    esac

    return 1
}

for arg in "$@"
do
    case "$arg" in
        --dry-run)
            DRY_RUN=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if is_valid_panel "$arg"; then
                if [ -n "$PANEL_HINT" ] && [ "$PANEL_HINT" != "$arg" ]; then
                    usage
                    exit 1
                fi
                PANEL_HINT="$arg"
            else
                usage
                exit 1
            fi
            ;;
    esac
done

case "$DRY_RUN" in
    1|true|TRUE|yes|YES|on|ON)
        DRY_RUN=1
        ;;
    *)
        DRY_RUN=0
        ;;
esac

print_cmd() {
    printf '%s' "$1"
    shift

    for arg in "$@"
    do
        printf ' %s' "$arg"
    done

    printf '\n'
}

warn_cmd_failed() {
    WARNINGS=$((WARNINGS + 1))
    printf 'WARNING: command failed: ' >&2
    print_cmd "$@" >&2
}

warn_in_dir_failed() {
    WARNINGS=$((WARNINGS + 1))
    printf 'WARNING: command failed in %s: ' "$1" >&2
    shift
    print_cmd "$@" >&2
}

phase() {
    printf '==> %s\n' "$1"
}

run_cmd() {
    if [ "$DRY_RUN" = "1" ]; then
        printf '[DRY-RUN] '
        print_cmd "$@"
    elif "$@"; then
        return 0
    else
        warn_cmd_failed "$@"
        return 1
    fi
}

run_cmd_quiet() {
    if [ "$DRY_RUN" = "1" ]; then
        printf '[DRY-RUN] '
        print_cmd "$@"
    elif "$@" >/dev/null 2>&1; then
        return 0
    else
        warn_cmd_failed "$@"
        return 1
    fi
}

run_cmd_in_dir() {
    DIR="$1"
    shift

    if [ "$DRY_RUN" = "1" ]; then
        printf '[DRY-RUN] (cd %s && ' "$DIR"
        print_cmd "$@"
    else
        if (
            cd "$DIR" || exit 1
            "$@"
        ); then
            return 0
        else
            warn_in_dir_failed "$DIR" "$@"
            return 1
        fi
    fi
}

echo "Uninstalling csf and lfd..."
echo

panel_detect() {
    if is_valid_panel "$PANEL_HINT"; then
        echo "$PANEL_HINT"
    elif [ -e "/usr/local/cpanel/version" ]; then
        echo "cpanel"
    elif [ -e "/usr/local/directadmin/directadmin" ]; then
        echo "directadmin"
    elif [ -e "/usr/local/interworx" ]; then
        echo "interworx"
    elif [ -e "/usr/local/cwpsrv" ]; then
        echo "cwp"
    elif [ -e "/usr/local/vesta" ]; then
        echo "vesta"
    elif [ -e "/usr/local/CyberCP" ]; then
        echo "cyberpanel"
    else
        echo "generic"
    fi
}

stop_csf() {
    if [ -x /usr/sbin/csf ]; then
        run_cmd /usr/sbin/csf -f
    fi
}

disable_services() {
    INIT_COMM=""

    if [ -r /proc/1/comm ]; then
        INIT_COMM=$(cat /proc/1/comm 2>/dev/null)
    fi

    if { [ "$INIT_COMM" = "systemd" ] || [ -d /run/systemd/system ]; } && command -v systemctl >/dev/null 2>&1; then
        run_cmd_quiet systemctl disable csf.service
        run_cmd_quiet systemctl disable lfd.service
        run_cmd_quiet systemctl stop lfd.service
        run_cmd_quiet systemctl stop csf.service

        run_cmd rm -fv /usr/lib/systemd/system/csf.service
        run_cmd rm -fv /usr/lib/systemd/system/lfd.service
        run_cmd rm -fv /etc/systemd/system/csf.service
        run_cmd rm -fv /etc/systemd/system/lfd.service
        run_cmd rm -fv /lib/systemd/system/csf.service
        run_cmd rm -fv /lib/systemd/system/lfd.service
        run_cmd_quiet systemctl daemon-reload
    else
        if [ -f /etc/redhat-release ]; then
            run_cmd_quiet /sbin/chkconfig csf off
            run_cmd_quiet /sbin/chkconfig lfd off
            run_cmd_quiet /sbin/chkconfig csf --del
            run_cmd_quiet /sbin/chkconfig lfd --del
        elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
            run_cmd_quiet update-rc.d -f lfd remove
            run_cmd_quiet update-rc.d -f csf remove
        elif [ -f /etc/gentoo-release ]; then
            run_cmd_quiet rc-update del lfd default
            run_cmd_quiet rc-update del csf default
        elif [ -f /etc/slackware-version ]; then
            run_cmd rm -vf /etc/rc.d/rc3.d/S80csf
            run_cmd rm -vf /etc/rc.d/rc4.d/S80csf
            run_cmd rm -vf /etc/rc.d/rc5.d/S80csf
            run_cmd rm -vf /etc/rc.d/rc3.d/S85lfd
            run_cmd rm -vf /etc/rc.d/rc4.d/S85lfd
            run_cmd rm -vf /etc/rc.d/rc5.d/S85lfd
        else
            run_cmd_quiet /sbin/chkconfig csf off
            run_cmd_quiet /sbin/chkconfig lfd off
            run_cmd_quiet /sbin/chkconfig csf --del
            run_cmd_quiet /sbin/chkconfig lfd --del
        fi

        run_cmd rm -fv /etc/init.d/csf
        run_cmd rm -fv /etc/init.d/lfd
    fi
}

remove_common_files() {
    run_cmd rm -fv /usr/sbin/csf
    run_cmd rm -fv /usr/sbin/lfd
    run_cmd rm -fv /etc/cron.d/csf_update
    run_cmd rm -fv /etc/cron.d/lfd-cron
    run_cmd rm -fv /etc/cron.d/csf-cron
    run_cmd rm -fv /etc/logrotate.d/lfd
    run_cmd rm -fv /usr/local/man/man1/csf.man.1
}

cleanup_cpanel() {
    if [ -x "/usr/local/cpanel/bin/unregister_appconfig" ]; then
        run_cmd_in_dir / /usr/local/cpanel/bin/unregister_appconfig csf
    fi

    run_cmd rm -fv /usr/local/cpanel/whostmgr/docroot/cgi/addon_csf.cgi
    run_cmd rm -Rfv /usr/local/cpanel/whostmgr/docroot/cgi/csf

    run_cmd rm -fv /usr/local/cpanel/whostmgr/docroot/cgi/configserver/csf.cgi
    run_cmd rm -Rfv /usr/local/cpanel/whostmgr/docroot/cgi/configserver/csf

    run_cmd rm -fv /usr/local/cpanel/Cpanel/Config/ConfigObj/Driver/ConfigServercsf.pm
    run_cmd rm -Rfv /usr/local/cpanel/Cpanel/Config/ConfigObj/Driver/ConfigServercsf

    if [ -d "/usr/local/cpanel/Cpanel/Config/ConfigObj/Driver" ]; then
        run_cmd touch /usr/local/cpanel/Cpanel/Config/ConfigObj/Driver
    fi

    run_cmd rm -fv /etc/chkserv.d/lfd
    run_cmd rm -fv /var/run/chkservd/lfd

    if [ -f /etc/chkserv.d/chkservd.conf ] && grep -q 'lfd:1' /etc/chkserv.d/chkservd.conf 2>/dev/null; then
        run_cmd sed -i 's/lfd:1//' /etc/chkserv.d/chkservd.conf
    fi

    if [ -x /scripts/restartsrv_chkservd ]; then
        run_cmd /scripts/restartsrv_chkservd
    fi
}

cleanup_cwp() {
    run_cmd rm -fv /usr/local/cwpsrv/htdocs/resources/admin/modules/csfofficial.php
    run_cmd rm -fv /usr/local/cwpsrv/htdocs/resources/admin/modules/csf.pl
    run_cmd rm -fv /usr/local/cwpsrv/htdocs/resources/admin/addons/ajax/ajax_csfframe.php
    run_cmd rm -Rfv /usr/local/cwpsrv/htdocs/admin/design/csf/
}

cleanup_cyberpanel() {
    run_cmd rm -Rfv /usr/local/CyberCP/configservercsf
    run_cmd rm -fv /home/cyberpanel/plugins/configservercsf
    run_cmd rm -Rfv /usr/local/CyberCP/public/static/configservercsf

    if [ -f /usr/local/CyberCP/CyberCP/settings.py ] && grep -q 'configservercsf' /usr/local/CyberCP/CyberCP/settings.py 2>/dev/null; then
        run_cmd sed -i '/configservercsf/d' /usr/local/CyberCP/CyberCP/settings.py
    fi

    if [ -f /usr/local/CyberCP/CyberCP/urls.py ] && grep -q 'configservercsf' /usr/local/CyberCP/CyberCP/urls.py 2>/dev/null; then
        run_cmd sed -i '/configservercsf/d' /usr/local/CyberCP/CyberCP/urls.py
    fi

    if [ ! -e /etc/cxs/cxs.pl ] && [ -f /usr/local/CyberCP/baseTemplate/templates/baseTemplate/index.html ] && grep -q 'configserver' /usr/local/CyberCP/baseTemplate/templates/baseTemplate/index.html 2>/dev/null; then
        run_cmd sed -i '/configserver/d' /usr/local/CyberCP/baseTemplate/templates/baseTemplate/index.html
    fi

    if command -v service >/dev/null 2>&1; then
        run_cmd_quiet service lscpd restart
    fi
}

cleanup_directadmin_pre() {
    if [ -f /usr/local/directadmin/data/admin/services.status ] && grep -q 'lfd=ON' /usr/local/directadmin/data/admin/services.status 2>/dev/null; then
        run_cmd sed -i 's/lfd=ON/lfd=OFF/' /usr/local/directadmin/data/admin/services.status
    fi
}

cleanup_directadmin() {
    run_cmd rm -Rfv /usr/local/directadmin/plugins/csf
}

cleanup_interworx() {
    if [ -x /usr/local/interworx/bin/nodeworx.pex ]; then
        run_cmd /usr/local/interworx/bin/nodeworx.pex -u --controller Plugins --action edit --plugin_name configservercsf --status 0 -n
    fi

    run_cmd rm -Rfv /usr/local/interworx/plugins/configservercsf /usr/local/interworx/html/configserver/csf

    if command -v chattr >/dev/null 2>&1; then
        run_cmd_quiet chattr -ia /etc/apf/apf
    fi

    if [ -e /etc/apf/apf.old ]; then
        # Back up the current APF script if it differs from the saved copy,
        # so that any post-install modifications are not silently lost.
        if [ -f /etc/apf/apf ] && ! cmp -s /etc/apf/apf /etc/apf/apf.old; then
            run_cmd cp -avf /etc/apf/apf /etc/apf/apf.pre-restore
        fi
        run_cmd cp -avf /etc/apf/apf.old /etc/apf/apf
        run_cmd chmod 750 /etc/apf/apf
    fi
}

cleanup_vesta() {
    run_cmd rm -fv /usr/local/vesta/bin/csf.pl

    if [ -f /usr/local/vesta/web/templates/admin/panel.html ] && grep -q 'CSF' /usr/local/vesta/web/templates/admin/panel.html 2>/dev/null; then
        run_cmd sed -i '/CSF/d' /usr/local/vesta/web/templates/admin/panel.html
    fi
}

purge_csf_data() {
    case "$1" in
        cpanel|cyberpanel|directadmin|generic|interworx)
            run_cmd rm -Rfv /etc/csf /usr/local/csf /var/lib/csf
            ;;
        vesta)
            # Preserve original Vesta behavior: remove Vesta UI state and the
            # specific ConfigServer module file, but do not wipe all of
            # /usr/local/csf or /var/lib/csf.
            run_cmd rm -Rfv /etc/csf /usr/local/vesta/web/list/csf/
            run_cmd rm -fv /usr/local/csf/lib/ConfigServer/csf.pm
            ;;
        cwp)
            # Preserve original CWP behavior: panel integration is removed, but
            # the shared CSF data directories are intentionally left in place.
            ;;
        *)
            run_cmd rm -Rfv /etc/csf /usr/local/csf /var/lib/csf
            ;;
    esac
}

cleanup_panel_pre() {
    case "$1" in
        directadmin)
            cleanup_directadmin_pre
            ;;
    esac
}

cleanup_panel() {
    case "$1" in
        cpanel)
            cleanup_cpanel
            ;;
        cwp)
            cleanup_cwp
            ;;
        cyberpanel)
            cleanup_cyberpanel
            ;;
        directadmin)
            cleanup_directadmin
            ;;
        interworx)
            cleanup_interworx
            ;;
        vesta)
            cleanup_vesta
            ;;
        generic)
            ;;
        *)
            echo "Unknown panel hint '$1', using generic cleanup only"
            ;;
    esac
}

PANEL=$(panel_detect)

echo "Detected environment: $PANEL"
if [ "$DRY_RUN" = "1" ]; then
    echo "Dry-run mode enabled: no changes will be made"
fi
echo

phase "Preparing panel-specific state"
cleanup_panel_pre "$PANEL"

echo
phase "Stopping CSF firewall rules"
stop_csf

echo
phase "Disabling services"
disable_services

echo
phase "Removing common files"
remove_common_files

echo
phase "Running panel-specific cleanup ($PANEL)"
cleanup_panel "$PANEL"

echo
phase "Purging CSF data"
purge_csf_data "$PANEL"

echo
if [ "$WARNINGS" -gt 0 ]; then
    echo "...Done with $WARNINGS warning(s)"
else
    echo "...Done cleanly"
fi
