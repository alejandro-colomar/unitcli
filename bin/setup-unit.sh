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

program_name="$0";

print_help()
{
    echo 'SYNOPSIS';
    echo "      $program_name [-h] SUBCOMMAND [ARGS]";
    echo;
    echo 'DESCRIPTION';
    echo '      This program intends to make it easier for first-time users';
    echo '      to install and configure an NGINX Unit server.';
    echo;
    echo '      Run the -h option of subcommands to read their help.';
    echo;
    echo 'SUBCOMMANDS';
    echo '      repo-config';
    echo '              Configure the package manager repository to later';
    echo '              install NGINX Unit';
    echo;
    echo '      welcome Configure a running instance of NGINX Unit with a';
    echo '              basic configuration.';
    echo;
    echo 'OPTIONS';
    echo '      -h, --help';
    echo '              Print this help and exit.';
    echo;
}

repo_config()
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


unitd_config()
{
    dry_run='no';

    print_help_unitd_config()
    {
        echo 'SYNOPSIS';
        echo "      $program_name welcome [-hn]";
        echo;
        echo 'DESCRIPTION';
        echo '      This command intends to make it easier for first-time';
        echo '      users to configure a running NGINX Unit server.';
        echo;
        echo 'OPTIONS';
        echo '      -h, --help';
        echo '              Print this help and exit.';
        echo;
        echo '      -n, --dry-run';
        echo '              Dry run.  Print the commands that would be run,'
        echo '              instead of actually running them.  They are';
        echo '              preceeded by a line explaining what they do.';
        echo '              This option is recommended for learning.';
    }

    dry_run_echo()
    {
        test "$dry_run" = "yes" \
        && echo "$@";
    }

    dry_run_eval()
    {
        if test "$dry_run" = "yes"; then
            echo "    $@";
        else
            eval "$@";
        fi;
    }

    err_no_pid()
    {
        >&2 echo 'Unit is not running.';
        exit 1;
    }

    err_pids()
    {
        >&2 echo 'There should be only one instance of Unit running.';
        exit 1;
    }

    err_conf()
    {
        >&2 echo 'Unit is already configured.'
        exit 1;
    }

    err_curl()
    {
        >&2 echo "Can't connect to control socket.";
        exit 1;
    }

    while echo $1 | grep '^-' >/dev/null; do
        case $1 in
        -h | --help)
            print_help_unitd_config;
            exit 0;
            ;;
        -n | --dry-run)
            dry_run='yes';
            ;;
        *)
            >&2 print_help_unitd_config;
            exit 1;
            ;;
        esac;
        shift;
    done;

    www="/srv/www/unit/index.html";
    test -e "$www" \
    && www="$(mktemp)";

    # Check there's exactly one instance.
    ps ax \
    | grep 'unit: main' \
    | grep -v grep \
    | wc -l \
    | if read -r nprocs; then
        test 0 -eq "$nprocs" \
        && err_no_pid;

        test 1 -eq "$nprocs" \
        || err_pids;
    fi;

    ps ax \
    | grep 'unit: main' \
    | grep -v grep \
    | sed 's/.*\[\(.*\)].*/\1/' \
    | if read -r cmd; then
        # Check unitd is not configured already.
        if echo "$cmd" | grep '\--state' >/dev/null; then
            echo "$cmd" \
            | sed 's/ --/\n--/g' \
            | grep '\--state' \
            | cut -d' ' -f2;
        else
            $cmd --help \
            | sed -n '/\--state/,+1p' \
            | grep 'default:' \
            | sed 's/ *default: "\(.*\)"/\1/';
        fi \
        | sed 's,$,/conf.json,' \
        | xargs test -e \
        && err_conf;

        if echo "$cmd" | grep '\--control' >/dev/null; then
            echo "$cmd" \
            | sed 's/ --/\n--/g' \
            | grep '\--control' \
            | cut -d' ' -f2;
        else
            $cmd --help \
            | sed -n '/\--control/,+1p' \
            | grep 'default:' \
            | sed 's/ *default: "\(.*\)"/\1/';
        fi;
    fi \
    | if read -r control; then
        if echo "$control" | grep '^unix:' >/dev/null; then
            unix_socket="$(echo "$control" | sed 's/unix:/ --unix-socket /')";
            host='localhost';
        else
            unix_socket='';
            host="$control";
        fi;

        # Check we can connect to the control socket.
        curl $unix_socket "http://$host/config/" >/dev/null 2>&1 \
        || err_curl;

        (
            nc -l localhost 0 &

            lsof -i \
            | grep $! \
            | awk '{print $9}' \
            | cut -d':' -f2;

            kill $!;
        ) \
        | if read -r port; then
            dry_run_echo 'Create a file to serve:';
            dry_run_eval "mkdir -p $(dirname $www);";
            dry_run_eval "echo 'Welcome to NGINX Unit!' >'$www';";
            dry_run_echo;
            dry_run_echo 'Give it appropriate permissions:';
            dry_run_eval "chmod 644 '$www';";
            dry_run_echo;

            dry_run_echo 'Configure unitd:'
            dry_run_eval "cat <<EOF \\
    | sed 's/8080/$port/' \\
    | curl -X PUT -d@- $unix_socket 'http://$host/config/';
    {
        \"listeners\": {
            \"*:8080\": {
                \"pass\": \"routes\"
            }
        },
        \"routes\": [{
            \"action\": {
                \"share\": \"$www\"
            }
        }]
    }
EOF";
            dry_run_echo;

            echo
            echo "You may want to try the following commands now:"
            echo
            echo "Read the current unitd configuration:"
            echo "  sudo curl $unix_socket http://$host/config/"
            echo
            echo "Browse the welcome page:"
            echo "  curl http://localhost:$port";
        fi;
    fi;
}

while echo $1 | grep '^-' >/dev/null; do
    case $1 in
    -h | --help)
        print_help;
        exit 0;
        ;;
    *)
        >&2 print_help;
        exit 1;
        ;;
    esac;
    shift;
done;

case $1 in
welcome)
    shift;
    unitd_config $@;
    ;;
repo-config)
    shift;
    repo_config $@;
    ;;
esac;
