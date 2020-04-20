#!/bin/bash
set -e

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
  echo "  -r: like as 10.130.176.11:6666 or 10.192.13.66/dev"
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
  ssh root@$node << REMOTESSH
image=\$(docker ps --format={{.Image}} | grep contrail | sed -n '1p')
# 10.130.176.11:6666/contrail-vrouter-agent:james
# 10.192.13.66/dev/contrail-vrouter-agent:james

OLD_IFS="\$IFS"
IFS="/" imageArray=(\${image})
len=\${#imageArray[@]}
IFS=":" tagArray=(\${imageArray[\$len-1]})
IFS="\$OLD_IFS"

oldVersion=\${tagArray[1]}
oldRegistry=\${imageArray[0]}
for ((i=1;i<len-1;i++))
{
  oldRegistry="\${oldRegistry}/\${imageArray[i]}"
}

if [[ "x${newRegistry}" == "x" ]]; then
  newRegistry=\${oldRegistry}
else
  newRegistry=${newRegistry}
fi

echo "Replace \${oldRegistry}/<containers>:\${oldVersion} with \${newRegistry}/<containers>:${newVersion} ..."
find /etc/contrail/ -name docker-compose.yaml | xargs -i sed -i -e "s%\${oldRegistry}%\${newRegistry}%g" -e "s%\${oldVersion}%${newVersion}%g" {}

echo "Deleting container ..."
if [[ "x${deleteImage}" == "x" ]]; then
  find /etc/contrail/ -name docker-compose.yaml | xargs -i docker-compose -f {} down
else
  find /etc/contrail/ -name docker-compose.yaml | xargs -i docker-compose -f {} down
  docker rmi \$(docker images -qf label=version=\${oldVersion})
  #find /etc/contrail/ -name docker-compose.yaml | xargs -i docker-compose -f {} down --rmi all
fi
#ifdown vhost0
#rm -f /etc/sysconfig/network-scripts/*vhost*
#rm -f /etc/sysconfig/network-scripts/*vrouter*

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
