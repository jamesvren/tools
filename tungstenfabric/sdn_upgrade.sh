#!/bin/bash

while getopts ":h:r:v:d" opt; do
    case $opt in
      h) nodes=$OPTARG
         ;;
      r) newRegistry=$OPTARG
         ;;
      v) newVersion=$OPTARG
         ;;
      d) deleteImage=1
         ;;
      \?) echo "Invalid option: $opt"; exit 1;;
    esac
done
shift $((OPTIND-1))

if [[ -z $newVersion ]]; then
  echo "Usage: $0 [-h node1,node2,...] [-r <reigstry>] -v <tag> [-d]"
  echo "  -h: host name, default current node if not set"
  echo "  -d: delete image"
  exit 1
fi

if [[ -z $nodes ]]; then
  nodes=$(hostname)
fi

OLD_IFS="$IFS"
IFS="," nodeArray=(${nodes})
IFS="$OLD_IFS"

for node in ${nodeArray[*]}
do
  echo -e "\nInfo: Login to $node ... do"
  ssh $node << REMOTESSH
image=\$(docker ps --format={{.Image}} | grep contrail | sed -n '1p')
OLD_IFS="\$IFS"
IFS=":" imageArray=(\${image})
IFS="/" regArray=(\${imageArray[0]})
IFS="\$OLD_IFS"

oldVersion=\${imageArray[1]}
oldRegistry=\${regArray[0]}
len=\${#regArray[@]}
for ((i=1;i<len-1;i++))
{
  oldRegistry="\${oldRegistry}/\${regArray[i]}"
}

if [[ "x${newRegistry}" == "x" ]]; then
  newRegistry=\${oldRegistry}
else
  newRegistry=${newRegistry}
fi

echo "Replace \${oldRegistry}:\${oldVersion} with \${newRegistry}:${newVersion} ..."
find /etc/contrail/ -name docker-compose.yaml | xargs -i sed -i -e "s%\${oldRegistry}%\${newRegistry}%g" -e "s%\${oldVersion}%${newVersion}%g" {}

echo "Deleting container ..."
if [[ "x${deleteImage}" == "x" ]]; then
  find /etc/contrail/ -name docker-compose.yaml | xargs -i docker-compose -f {} down
else
  find /etc/contrail/ -name docker-compose.yaml | xargs -i docker-compose -f {} down --rmi
fi
ifdown vhost0
rm -f /etc/sysconfig/network-scripts/*vhost*
rm -f /etc/sysconfig/network-scripts/*vrouter*

echo "Starting new SDN container ..."
find /etc/contrail/ -name docker-compose.yaml | xargs -i docker-compose -f {} up -d
exit
REMOTESSH
done

for node in ${nodeArray[*]}
do
  echo "========Upgrade Done. Check Services Status for $node========"
  ssh $node "contrail-status"
done
