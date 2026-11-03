#!/bin/sh
# Adamachines: tiny machines racing round the house, in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Checks that what the build needs is installed, and if something is
# missing, says what and how to install it on this system.
#   ./check-deps.sh          (make check, and before every make)

missing=""
missing_pkg_apt=""
missing_pkg_dnf=""
missing_pkg_pacman=""
missing_pkg_zypper=""
optional=""

need () {   # need WHAT apt dnf pacman zypper
    missing="$missing\n  - $1"
    missing_pkg_apt="$missing_pkg_apt $2"
    missing_pkg_dnf="$missing_pkg_dnf $3"
    missing_pkg_pacman="$missing_pkg_pacman $4"
    missing_pkg_zypper="$missing_pkg_zypper $5"
}

have () { command -v "$1" >/dev/null 2>&1; }

# The GtkAda package of Debian and Ubuntu has the library's version in its name
gtkada_apt="libgtkada-dev"
if have apt-cache; then
    found=$(apt-cache search --names-only '^libgtkada[0-9]*-dev$' 2>/dev/null | awk '{print $1}' | sort | tail -1)
    [ -n "$found" ] && gtkada_apt="$found"
fi

# The compiler and the builder
have gnat || have gnatmake || need "GNAT, the Ada compiler" gnat gcc-gnat gcc-ada gcc-ada
have gprbuild || need "gprbuild, the project builder" gprbuild gprbuild gprbuild gprbuild

# GtkAda: its project file somewhere gprbuild will look
gtkada=""
gnat_prefix=""
if have gnat; then
    gnat_prefix=$(dirname "$(dirname "$(command -v gnat)")")
fi
for dir in $(echo "${GPR_PROJECT_PATH}:${ADA_PROJECT_PATH}" | tr ':' ' ') \
           /usr/share/gpr /usr/lib/gnat /usr/local/share/gpr /usr/local/lib/gnat \
           "$gnat_prefix/share/gpr" "$gnat_prefix/lib/gnat"; do
    if [ -f "$dir/gtkada.gpr" ]; then gtkada="$dir/gtkada.gpr"; break; fi
done
[ -n "$gtkada" ] || need "GtkAda, the Ada binding of GTK" "$gtkada_apt" gtkada-devel "gtkada (from the AUR)" gtkada-devel

# A C library is there to link with when pkg-config knows it, or its .so lies about
has_lib () {   # has_lib PKG-CONFIG-NAME LIBRARY-FILE
    if have pkg-config && pkg-config --exists "$1" 2>/dev/null; then return 0; fi
    for dir in /usr/lib /usr/lib64 /usr/local/lib /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu \
               /usr/lib/i386-linux-gnu; do
        [ -e "$dir/$2" ] && return 0
    done
    return 1
}
has_lib gtk+-3.0 libgtk-3.so || need "GTK 3 (for building)" libgtk-3-dev gtk3-devel gtk3 gtk3-devel
has_lib libpulse-simple libpulse-simple.so || need "PulseAudio (for building)" libpulse-dev pulseaudio-libs-devel libpulse libpulse-devel

# Not needed, but the announcer is quiet without it
have espeak-ng || optional="espeak-ng"

if [ -n "$missing" ]; then
    printf "Adamachines needs some things that are not installed:%b\n\n" "$missing"
    id=""
    [ -r /etc/os-release ] && . /etc/os-release && id="$ID $ID_LIKE"
    case "$id" in
        *debian*|*ubuntu*|*mint*)
            echo "Install them with:"
            echo "    sudo apt install$missing_pkg_apt" ;;
        *fedora*|*rhel*|*centos*)
            echo "Install them with:"
            echo "    sudo dnf install$missing_pkg_dnf" ;;
        *arch*|*manjaro*)
            echo "Install them with:"
            echo "    sudo pacman -S$missing_pkg_pacman" ;;
        *suse*)
            echo "Install them with:"
            echo "    sudo zypper install$missing_pkg_zypper" ;;
        *)
            echo "On Debian, Ubuntu and Mint they are:  $missing_pkg_apt"
            echo "On Fedora:                             $missing_pkg_dnf"
            echo "Or get GNAT, gprbuild and GtkAda from Alire (https://alire.ada.dev)." ;;
    esac
    if [ -n "$optional" ]; then
        echo
        echo "And for the announcer (not needed to play): $optional"
    fi
    exit 1
fi

if [ -n "$optional" ]; then
    echo "Note: espeak-ng is not installed, so the announcer will be quiet."
    echo "      It is in the package espeak-ng on most systems."
fi
exit 0
