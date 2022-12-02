#!/bin/bash

while getopts :h:p:c: opt; do
    case $opt in
        h) host=$OPTARG
          ;;
        p) pswd=$OPTARG
          ;;
        c) cmd=$OPTARG
          echo $cmd
          ;;
        *) echo "-h <HOST> -p <password> -c <cmd>"
          exit
          ;;
    esac
done
shift $((OPTIND-1))

ssh_cmd="sshpass -p $pswd ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
$ssh_cmd root@$host << REMOTESSH
cat /etc/hosts | awk '{if(\$2~".mgmt") print \$2}' | xargs -t -i sshpass -p ${pswd} ssh {} "${cmd}"
REMOTESSH
