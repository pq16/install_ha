#!/bin/bash

set -e

############################################################################################################
# Variables

SCRIPT="jethome-homeassistant-installer"

LANG=C
LC_ALL=en_US.UTF-8
LANGUAGE=C
DEBIAN_FRONTEND=noninteractive
APT_LISTCHANGES_FRONTEND=none
TIMEOUT=1200
REINSTALL="${REINSTALL:=0}"
if [ "${JETHOME}" == "yes" ]; then
  pkg_suffix="-jethome"
else
  pkg_suffix=""
fi

MACHINE="qemuarm-64"

export LANG LC_ALL LANGUAGE DEBIAN_FRONTEND APT_LISTCHANGES_FRONTEND MACHINE

SUPPORTED_OS=(
              "bookworm"
              )

############################################################################################################
# Functions

function print_info() {
    echo -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"
}

function print_request() {
    echo -n -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"
}

function print_error() {
    echo -e "\e[1;31m[${SCRIPT}] ERROR:\e[0m $1"
}

############################################################################################################
# Main

echo "####################################################################"
echo " JetHome JetHub Home Assistant Installer"
echo ""
echo " Official site: https://jethome.ru"
echo " Documentation: https://docs.jethome.ru"
echo " Telegram community: https://t.me/jethomeru"
echo "####################################################################"


# Check if script run as root
if [ "$EUID" -ne 0 ]
  then print_error "Please run as root!"
  exit
fi

CURRENT_OS=$(lsb_release -d | sed -E 's/Description:\s+//')

#
# Check if distro is supported
#
SUPPORTED=0
for distro in "${SUPPORTED_OS[@]}"
do
  # shellcheck disable=SC2076
  if [[ "${CURRENT_OS}" =~ "${distro}" ]]; then
      SUPPORTED=1
  fi
done

if [[ "${SUPPORTED}" == "0" ]]; then
    print_error "This script is not supported on this OS: '$CURRENT_OS'"
    # print supported distros
    print_error "Supported OS:"
    for distro in "${SUPPORTED_OS[@]}"
    do
        print_error "    $distro"
    done
    print_error "Please installs supported distro from http://fw.jethome.ru and try again"
    exit 1
else
    print_info "Current distro: '$CURRENT_OS' - supported"
fi


#
# Check for HA installed
#
if [[ -f /usr/sbin/hassio-supervisor ]]; then
    print_request "Home Assistant already installed. Reinstall Y/N? "

    # Read the answer from the keyboard
    if [[ "$REINSTALL" == "0" ]] ; then
      read -r answer </dev/tty
    fi

    # Check if the answer is one of the specified options
    if [[ "$answer" != "Y" && "$answer" != "y" && "$answer" != "Д" && "$answer" != "д" && "$REINSTALL" == "0" ]]; then
        print_error "Operation cancelled. Use \`export REINSTALL=1;\` to force reinstall"
        exit 1
    fi

    print_info "Remove old Home Assistant..."

    systemctl stop haos-agent > /dev/null 2>&1
    systemctl stop hassio-apparmor > /dev/null 2>&1
    systemctl stop hassio-supervisor > /dev/null 2>&1
    apt-get purge -y homeassistant-supervised\* > /dev/null 2>&1 || true
    dpkg -r homeassistant-supervised > /dev/null 2>&1 || true
    dpkg -r homeassistant-supervised-jethome > /dev/null 2>&1 || true
    dpkg -r os-agent > /dev/null 2>&1
    docker ps --format json|jq -r .Names | grep -E 'addon_|hassio_' | xargs -n 1 docker stop || true
    sleep 1
    if [ -n "$(docker ps --format json|jq -r .Names | grep -E 'addon_|hassio_')" ]; then
        print_info "Wait for stop containers"
        docker ps --format json|jq -r .Names | grep -E 'addon_|hassio_' | xargs -n 1 docker stop  || true
        sleep 5
    fi
    sleep 5
    docker system prune -a -f > /dev/null 2>&1
    docker system prune -a -f > /dev/null 2>&1
    #touch /root/.ha_prepared

    print_info "Remove old Home Assistant done"
    REINSTALL=1

fi


if [[ ! -f /root/.ha_prepared ]]; then

    #
    # Docker
    #
    if [ -x "$(command -v docker)" ]; then
        print_info "Docker already installed"
    else
        print_info "Installing docker..."
        curl -fsSL get.docker.com -o get-docker.sh && sh get-docker.sh

        if [[ -n "${SUDO_USER}" ]] ; then 
        usermod -aG docker "$SUDO_USER"
        fi
        rm -f get-docker.sh
        print_info "Installing docker done"
    fi

    #
    # Updating system
    #
    print_info "Updating system..."

    apt-get update -y
    apt-get dist-upgrade -y

    print_info "Updating system done"

    #
    # Installing dependencies
    #

    print_info "Installing dependencies..."

    apt-get install -y jq wget curl udisks2 libglib2.0-bin network-manager dbus apparmor systemd-resolved systemd-journal-remote nfs-common cifs-utils

    print_info "Installing dependencies done"

    #
    # Check 'extraargs=systemd.unified_cgroup_hierarchy=false' exists in /boot/armbianEnv.txt, add if not exists
    #
    print_info "Check CGROUP config..."
    if grep -q "extraargs=systemd.unified_cgroup_hierarchy=false" /boot/armbianEnv.txt; then
        print_info "... Already modified: /boot/armbianEnv.txt"
    else
        print_info "... Modifying /boot/armbianEnv.txt"
        echo "extraargs=systemd.unified_cgroup_hierarchy=false" >> /boot/armbianEnv.txt
    fi

    #
    # Iptables
    #
    #print_info "Installing iptables..."

    #apt install -y iptables
    #update-alternatives --set iptables /usr/sbin/iptables-legacy
    #update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

    #print_info "Installing iptables done"

    touch /root/.ha_prepared
    if [[ "${REINSTALL}" == "0" ]]; then
        touch /var/run/reboot-required
        print_info "Preparation done. Please reboot and run this script again:"
        if [ "${JETHOME}" == "yes" ]; then
            print_info "curl https://raw.githubusercontent.com/jethub-homeassistant/supervised-installer/jethome-homeassistant-supervised/jethome-homeassitant-supervised.sh | sudo JETHOME=yes bash"
        else
            print_info "curl https://raw.githubusercontent.com/jethub-homeassistant/supervised-installer/jethome-homeassistant-supervised/jethome-homeassitant-supervised.sh | sudo bash"
        fi
    else
        print_info "Reinstall pre-check done."
    fi
fi

if [[ -f /var/run/reboot-required ]]; then
    rm -f /var/run/reboot-required
    print_error "Reboot required. Please reboot and run this script again"
    exit 1
fi

#
# Install HA packages
#

#
# - Installing os-agent
#
print_info "Installing os-agent..."

apt-get install -y os-agent

systemctl enable haos-agent
systemctl start haos-agent

sleep 1

print_info "Installing os-agent done"

print_info "Fix os-release for Debian 12"

sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Debian GNU\/Linux 12 (bookworm)"/' /etc/os-release 

#
# - Installing Home Assistant Supervised
#
print_info "Installing Home Assistant Supervised (machine: ${MACHINE})..."

apt-get install -y "homeassistant-supervised${pkg_suffix}"

print_info "Home Assistant will be installed in tens of minutes"
print_info "Please wait for supervisor up (timeout 1200 sec)..."

rm -f /root/.ha_prepared

i=0

while ! docker ps |grep -q hassio_supervisor;
do
    sleep 5
    i=$((i+5))
    if (( i % 30 == 0 )); then
        echo "Waiting for Home Assistant supervisor is up $i secs....." >&2    #DEBUG
    fi
    if [ -n "${TIMEOUT}" ]; then
        if [ $i -gt "${TIMEOUT}" ]; then
            print_error "Timeout waiting for supervisor. Please check internet connection and try again"
            exit 5
        fi
    fi
done

print_info "Installing Home Assistant Supervised done. Install Home Assistant core"

i=0

while ! curl http://127.0.0.1:8123 >/dev/null 2>&1
do
    sleep 5
    i=$((i+5))
    if (( i % 30 == 0 )); then
        echo "Waiting for Home Assistant core connection $i secs....." >&2    #DEBUG
    fi
    if [ -n "${TIMEOUT}" ]; then
        if [ $i -gt "${TIMEOUT}" ]; then
            print_error "Timeout waiting for landingpage. Please check internet connection and try again"
            exit 6
        fi
    fi
done

print_info "Home Assistant landingpage is up. Install Home Assistant core"

i=0

# Loop to wait for 'homeassistant' without 'landing'
while true; do
    if docker ps | grep -q " homeassistant" && ! docker ps | grep -q "landing"; then
        break
    else
        sleep 5
        i=$((i+5))
        # Every 15 seconds, display a waiting message
        if (( i % 30 == 0 )); then
            echo "Waiting for Home Assistant core up $i secs....." >&2    #DEBUG
        fi
        if [ -n "${TIMEOUT}" ]; then
            if [ $i -gt "${TIMEOUT}" ]; then
                print_error "Timeout waiting for Home Assistant Core. Please check internet connection and try again"
                exit 6
            fi
        fi
    fi
done

print_info "Home Assistant up and running."
print_request "Try access http://"
read -r _{,} _ _ _ _ ip _ < <(ip r g 1.0.0.0) ; echo "$ip:8123"

exit 0