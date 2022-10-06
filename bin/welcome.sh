#!/bin/sh

program_name="$0";
dry_run='no';

print_help()
{
    echo 'SYNOPSIS';
    echo "      $program_name [-hn]";
    echo
    echo 'DESCRIPTION';
    echo '      This program intends to make it easier for first-time users';
    echo '      to configure an NGINX Unit server.';
    echo
    echo 'OPTIONS';
    echo '      -n      Dry run.  Print the commands that would be run,'
    echo '              instead of actually running them.  They are preceeded';
    echo '              by a line explaining what they do.  This option is';
    echo '              recommended for learning.';
    echo
    echo '      -h      Print this help and exit.';
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

while getopts "hn" opt; do
    case "$opt" in
    h)
        print_help;
        exit 0;
        ;;
    n)
        dry_run='yes';
        ;;
    esac;
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
