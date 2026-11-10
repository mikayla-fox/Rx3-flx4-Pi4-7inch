#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'HELP'
Usage: ./provision.sh [--report | --packages | --apply-packages | --help]

  --report          Show system and boot diagnostics (default).
  --packages        Preview removal of installed optional desktop apps.
  --apply-packages  Show the plan and ask before removing those apps.
  --help            Show this help.
HELP
}

show() {
    local label="$1"
    shift
    printf '\n%s\n' "$label"
    "$@" || printf 'Unavailable\n'
}

report() {
    show 'Operating system' cat /etc/os-release
    show 'Architecture' uname -m
    show 'Root filesystem' df -h /
    show 'Memory' free -h
    show 'Boot time' systemd-analyze time
    show 'Slowest boot units (top 15)' bash -o pipefail -c 'systemd-analyze blame --no-pager | sed -n "1,15p"'
    show 'Boot critical chain' systemd-analyze critical-chain --no-pager
    show 'SSH and RX3 status' systemctl is-active ssh.service rx3.service
    show 'Pi throttle status' vcgencmd get_throttled
    show 'ALSA playback devices' aplay -l
}

desktop_packages() {
    local action="$1"
    local package status plan operation planned_package
    local installed=()
    local candidates=(
        # Browsers, remote desktop, and Raspberry Pi desktop utilities
        chromium chromium-browser chromium-common chromium-l10n chromium-sandbox
        realvnc-vnc-server rpi-connect
        agnostics rpi-imager piclone rp-bookshelf rp-prefapps rpi-userguide
        # Editors and learning tools
        geany geany-common thonny scratch scratch2 scratch3 sonic-pi
        # Office applications, bundled support files, and document viewers
        libreoffice-base libreoffice-base-core libreoffice-base-drivers
        libreoffice-calc libreoffice-common libreoffice-core libreoffice-draw
        libreoffice-gtk3 libreoffice-help-common libreoffice-help-en-us
        libreoffice-impress libreoffice-java-common libreoffice-math
        libreoffice-style-colibre libreoffice-writer evince evince-common
        # Printing tools and drivers
        cups cups-browsed cups-client cups-common cups-core-drivers
        cups-daemon cups-filters cups-filters-core-drivers cups-ipp-utils
        cups-ppdc cups-server-common printer-driver-gutenprint rpinters
        system-config-printer system-config-printer-common system-config-printer-udev
    )

    for package in "${candidates[@]}"; do
        status="$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null)" || continue
        if [[ "$status" == installed ]]; then
            installed+=("$package")
        fi
    done
    if (( ${#installed[@]} == 0 )); then
        printf 'No optional desktop apps from the cleanup list are installed.\n'
        return
    fi

    plan="$(LC_ALL=C apt-get --simulate --no-auto-remove purge "${installed[@]}")"
    printf '%s\n' "$plan"
    [[ "$action" == --apply-packages ]] || return 0

    # A dependency change outside the explicit list requires a separate decision.
    while read -r operation planned_package _; do
        case "$operation" in
            Inst|Conf)
                printf 'Refusing cleanup that installs or configures %s.\n' "$planned_package" >&2
                return 1
                ;;
            Remv|Purg)
                if [[ " ${installed[*]} " != *" ${planned_package%%:*} "* ]]; then
                    printf 'Refusing cleanup that also removes %s.\n' "$planned_package" >&2
                    return 1
                fi
                ;;
        esac
    done <<< "$plan"

    if [[ ! -t 0 || ! -t 1 ]]; then
        printf 'Package removal requires an interactive terminal.\n' >&2
        return 1
    fi
    # Let APT display the transaction again and request confirmation.
    sudo apt-get --no-auto-remove -o APT::Get::Assume-Yes=false purge "${installed[@]}"
}

if (( $# > 1 )); then
    usage >&2
    exit 2
fi

case "${1:---report}" in
    --report) report ;;
    --packages|--apply-packages) desktop_packages "$1" ;;
    --help|-h) usage ;;
    *)
        usage >&2
        exit 2
        ;;
esac
