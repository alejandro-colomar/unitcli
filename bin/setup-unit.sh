#!/bin/sh

#####################################################################
#
# Copyright (C) NGINX, Inc.
#
# Author:  NGINX Unit Team, F5 Inc.
# Version: 0.0.1
# Date:    2022-05-05
#
# This script will configure the repositories for NGINX Unit on Ubuntu,
# Debian, RedHat, CentOS, Oracle Linux, Amazon Linux, Fedora.
# It must be run as root.
#
# Note: curl and awk are required by this script, so the script checks to make
# sure they are installed.
#
#####################################################################

repo_setup()
{
    export LC_ALL=C

    checkOSPrereqs ()
    {

        if ! command -v curl > /dev/null 2>&1
        then
            echo "Error: curl not found in PATH.  It must be installed to run this script."
            exit 1
        fi

        if ! command -v awk > /dev/null 2>&1
        then
            echo "Error: awk not found in PATH.  It must be installed to run this script."
            exit 1
        fi

        return 0
    }

    #####################################################################
    # Function getOS
    #
    # Getting the OS is not the same on all distributions.  First, we use
    # uname to find out if we are running on Linux or FreeBSD. For all the
    # supported versions of Debian and Ubuntu, we expect to find the
    # /etc/os-release file which has multiple lines with name-value pairs
    # from which we can get the OS name and version. For RedHat and its
    # variants, the os-release file may or may not exist, depending on the
    # version.  If it doesn't, then we look for the release package and
    # get the OS and version from the package name. For FreeBSD, we use the
    # "uname -rs" command.
    #
    # A string is written to stdout with three values separated by ":":
    #    OS
    #    OS Name
    #    OS Version
    #
    # If none of these files was found, an empty string is written.
    #
    # Return: 0 for success, 1 for error
    #####################################################################
    getOS ()
    {
        os=""
        osName=""
        osVersion=""

        LC_ALL=C

        os=$(uname | tr '[:upper:]' '[:lower:]')

        if [ "$os" != "linux" ] && [ "$os" != "freebsd" ]; then
            echoErr "Error: Operating system is not Linux or FreeBSD, can't proceed"
            echo "On macOS, try 'brew install nginx/unit/unit'"
            echo
            return 1
        fi

        if [ "$os" = "linux" ]; then
            if [ -f "$osRelease" ]; then
                # The value for the ID and VERSION_ID may or may not be in quotes
                osName=$( grep "^ID=" "$osRelease" | sed s/\"//g | awk -F= '{ print $2 }')
                osVersion=$(grep "^VERSION_ID=" "$osRelease" | sed s/\"//g | awk -F= '{ print $2 }')
            else
                # rhel or centos 6.*
                if rpm -q redhat-release-server >/dev/null 2>&1; then
                    osName=rhel
                    osVersion=$(rpm -q redhat-release-server |sed 's/.*-//' | awk -F. '{print $1"."$2;}')
                elif rpm -q centos-release >/dev/null 2>&1; then
                    osName=centos
                    osVersion=$(rpm -q centos-release | sed 's/centos-release-//' | sed 's/\..*//' | awk -F- '{print $1"."$2;}')
                else
                    echoErr "Error: Unable to determine the operating system and version, or the OS is not supported"
                    echo
                    return 1
                fi
            fi
        else
            osName=$os
            osVersion=$(uname -rs | awk -F '[ -]' '{print $2}')
            if [ -z "$osVersion" ]; then
                echoErr "Unable to get the FreeBSD version"
                echo
                return 1
            fi
        fi

        # Force osName to lowercase
        osName=$(echo "$osName" | tr '[:upper:]' '[:lower:]')
        echoDebug "getOS: os=$os osName=$osName osVersion=$osVersion"
        echo "$os:$osName:$osVersion"

        return 0
    }


    installDebian ()
    {
        echoDebug "Install on Debian"

        curl --output /usr/share/keyrings/nginx-keyring.gpg https://unit.nginx.org/keys/nginx-keyring.gpg

        apt install -y apt-transport-https lsb-release ca-certificates

        printf "deb [signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://packages.nginx.org/unit/debian/ %s unit\n" "$(lsb_release -cs)" | tee /etc/apt/sources.list.d/unit.list
        printf "deb-src [signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://packages.nginx.org/unit/debian/ %s unit\n" "$(lsb_release -cs)" | tee -a /etc/apt/sources.list.d/unit.list

        apt update

        return 0
    }

    installUbuntu ()
    {
        echoDebug "Install on Ubuntu"

        curl --output /usr/share/keyrings/nginx-keyring.gpg https://unit.nginx.org/keys/nginx-keyring.gpg

        apt install -y apt-transport-https lsb-release ca-certificates

        printf "deb [signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://packages.nginx.org/unit/ubuntu/ %s unit\n" "$(lsb_release -cs)" | tee /etc/apt/sources.list.d/unit.list
        printf "deb-src [signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://packages.nginx.org/unit/ubuntu/ %s unit\n" "$(lsb_release -cs)" | tee -a /etc/apt/sources.list.d/unit.list

        apt update

        return 0
    }

    installRedHat ()
    {

        echoDebug "Install on RedHat/CentOS/Oracle"

        case "$osVersion" in
            6|6.*|7|7.*|8|8.*)
                cat << __EOF__ > /etc/yum.repos.d/unit.repo
[unit]
name=unit repo
baseurl=https://packages.nginx.org/unit/rhel/\$releasever/\$basearch/
gpgcheck=0
enabled=1
__EOF__
                ;;
            *)
                echo "Unsupported $osName version: $osVersion"
                exit 1
                ;;
        esac

        yum makecache

        return 0
    }

    installAmazon ()
    {

        echoDebug "Install on Amazon"

        case "$osVersion" in
            2)
                cat << __EOF__ > /etc/yum.repos.d/unit.repo
[unit]
name=unit repo
baseurl=https://packages.nginx.org/unit/amzn2/\$releasever/\$basearch/
gpgcheck=0
enabled=1
__EOF__
             ;;
            *)
                cat << __EOF__ > /etc/yum.repos.d/unit.repo
[unit]
name=unit repo
baseurl=https://packages.nginx.org/unit/amzn/\$releasever/\$basearch/
gpgcheck=0
enabled=1
__EOF__
             ;;
        esac

        yum makecache

        return 0
    }

    installFedora ()
    {

        echoDebug "Install on Fedora"

        cat << __EOF__ > /etc/yum.repos.d/unit.repo
[unit]
name=unit repo
baseurl=https://packages.nginx.org/unit/fedora/\$releasever/\$basearch/
gpgcheck=0
enabled=1
__EOF__

        dnf makecache

        return 0
    }


    am_i_root()
    {

        USERID=$(id -u)
        if [ 0 -ne "$USERID" ]; then
            echoErr "This script requires root privileges to run; now exiting."
            exit 1
        fi

        return 0
    }

    echoErr ()
    {
        echo "$*" 1>&2;
    }

    echoDebug ()
    {
        if [ "$debug" -eq 1 ]; then
            echo "$@" 1>&2;
        fi
    }

    main()
    {
        debug=0 # If set to 1, debug message will be displayed

        checkOSPrereqs

        # The name and location of the files that will be used to get Linux
        # release info
        osRelease="/etc/os-release"

        os="" # Will be "linux" or "freebsd"
        osName="" # Will be "ubuntu", "debian", "rhel",
                  # "centos", "suse", "amzn", or "freebsd"
        osVersion=""

        am_i_root

        echo "This script will setup repositories for NGINX Unit"

        # Check the OS
        osNameVersion=$(getOS)
        if [ -z "$osNameVersion" ]; then
            echoErr "Error getting the operating system information"
            exit 1
        fi

        # Break out the OS, name, and version
        os=$(echo "$osNameVersion" | awk -F: '{print $1}')
        osName=$(echo "$osNameVersion" | awk -F: '{print $2}')
        osVersion=$(echo "$osNameVersion" | awk -F: '{print $3}')

        # Call the appropriate installation function
        case "$osName" in
        debian)
            installDebian
            ;;
        ubuntu)
            installUbuntu
            ;;
        rhel)
            installRedHat
            ;;
        centos)
            installRedHat
            ;;
        ol)
            installRedHat
            ;;
        amzn)
            installAmazon
            ;;
        fedora)
            installFedora
            ;;
        *)
            echo "$osName is not supported"
            exit 1
            ;;
        esac

        echo
        echo "All done - NGINX Unit repositories for "$osName" "$osVersion" are set up"
        echo "Further steps: https://unit.nginx.org/installation/#official-packages"
    }

    main

    exit 0
}

repo_config
