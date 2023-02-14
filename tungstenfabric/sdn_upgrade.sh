#!/bin/bash
set -e

while getopts ":c:h:r:t:p:i:dPku" opt; do
    case $opt in
      c) container=$OPTARG
         ;;
      h) nodes=$OPTARG
         ;;
      r) newRegistry=$OPTARG
         ;;
      t) newVersion=$OPTARG
         ;;
      p) password=$OPTARG
         ;;
      i) keyfile=$OPTARG
         ;;
      d) deleteImage=1
         ;;
      P) pullImage=1
         ;;
      k) upgradeKernel=1
         ;;
      u) upgradeName=1
         ;;
      \?) echo "Invalid option: $opt"; exit 1;;
    esac
done
shift $((OPTIND-1))

if [[ -z $newVersion ]]; then
  echo "Usage: $0 [-h <node1,node2,...> ] [ -p <password> ] [ -i <private key> ] [ -d ] [-k ] [-u] [-r <reigstry>] -t <tag>"
  echo "  -h: host name, default current node if not set"
  echo "  -p: password for all hosts, prompt input if not set"
  echo "  -i: ssh private key for login"
  echo "  -r: replace registry, separate by '#' between old and new. For exampe: 10.130.176.11:6666#harbor.archeros.cn/qa"
  echo "  -d: delete image"
  echo "  -k: update kernel by ifdown vhost0"
  echo "  -u: update name to sdn during upgrade"
  echo "  -c: container to get information from"
  exit 1
fi

if [[ -z $nodes ]]; then
  nodes=$(hostname)
fi

OLD_IFS="$IFS"
IFS="," nodeArray=(${nodes})
IFS="$OLD_IFS"

ssh_cmd="ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
if [[ "x${password}" != "x" ]]; then
  ssh_cmd="sshpass -p ${password} $ssh_cmd"
fi

if [[ "x${keyfile}" != "x" ]]; then
  ssh_cmd="$ssh_cmd -i $keyfile"
fi

# display the info to let user to confirm
for node in ${nodeArray[*]}
do
  echo "### Information in node: ${node}"
  compose_file=$($ssh_cmd root@$node find /etc/ -name docker-compose.yaml | head -1)
  tag=$($ssh_cmd root@$node grep -E ' image' $compose_file | grep -oE '/.*:.*-(x86_64|aarch64)' | awk -F: '{print $2}' | head -1)
  reg=$($ssh_cmd root@$node grep -E ' image' $compose_file | awk -F\" '{print $2}' | head -1)
  echo "current tag: $tag"
  echo $reg
done
echo ""
read -p "### Your input [Replace Registry:${newRegistry}, Tag:${newVersion}], confirm(y/n)?" confirmed
if [[ $confirmed != "y" ]]; then
  exit 0
fi

# ssh to each node and upgrade the containers
for node in ${nodeArray[*]}
do
  echo -e "\n****** Login to $node ... do ******"
  $ssh_cmd root@$node << REMOTESSH
# 10.130.176.11:6666/contrail-vrouter-agent:james
# 10.192.13.66/dev/contrail-vrouter-agent:james

compose_file=\$(find /etc/ -name docker-compose.yaml | head -1)
oldVersion=\$(grep -E ' image' \$compose_file | grep -oE '/.*:.*-(x86_64|aarch64)' | awk -F: '{print \$2}' | head -1)

if [[ "x${newRegistry}" != "x" ]]; then
  #echo '{"insecure-registries": ["${newRegistry}"]}' > /etc/docker/daemon.json
  #systemctl reload docker
  echo "  Replace Registry: \${newRegistry} ..."
  find /etc -name docker-compose.yaml | xargs -i sed -i -e "s#${newRegistry}#g" {}
fi

echo "  Replace \${oldVersion} with ${newVersion} ..."
find /etc -name docker-compose.yaml | xargs -i sed -i -e "s%\${oldVersion}%${newVersion}%g" {}

if [[ "x${pullImage}" != "x" ]]; then
  find /etc -name docker-compose.yaml | xargs -i docker-compose -f {} pull
  exit
fi

if [[ "x${upgradeName}" != "x" ]]; then
  if [[ -d "/etc/contrail/analytics_database/" ]]; then
    echo "  Modify name to SDN (Analytics Database) ..."
    docker-compose -f /etc/contrail/analytics_database/docker-compose.yaml exec cassandra ./cassandra_change_cluster_name.sh sdn_analytics
  fi
  if [[ -d "/etc/contrail/config_database/" ]]; then
    echo "  Modify name to SDN (Config Database) ..."
    docker-compose -f /etc/contrail/config_database/docker-compose.yaml exec cassandra ./cassandra_change_cluster_name.sh sdn_config
  fi
fi

echo "  Deleting container ..."
if [[ "x${deleteImage}" == "x" ]]; then
  find /etc -name docker-compose.yaml | xargs -i docker-compose -f {} down
else
  find /etc -name docker-compose.yaml | xargs -i docker-compose -f {} down --rmi all
fi
if [[ "x${upgradeKernel}" != "x" ]]; then
  ifdown vhost0 || true
  rm -f /etc/sysconfig/network-scripts/*vhost*
  rm -f /etc/sysconfig/network-scripts/*vrouter*
fi

if [[ "x${upgradeName}" != "x" ]]; then
  echo "  Modify name to SDN ..."
  mv /etc/contrail /etc/sdn
  mv -f /var/lib/contrail /var/lib/sdn
  find /etc/sdn/ -name *.env | xargs -i sed -i -e "s/CONTRAIL_VERSION/SDN_VERSION/g" -e "s/CONTRAIL_REGISTRY/SDN_REGISTRY/g" {}
  find /etc/sdn/ -name docker-compose.yaml | xargs -i sed -i -e "s/CONTRAIL_STATUS_IMAGE/SDN_STATUS_IMAGE/g" -e "s/contrail/sdn" -e "s/openstack/arstack/g" {}
  if [[ -d "/etc/neutron" ]]; then
    grep -i contrail -r /etc/neutron -l | xargs  -i sed -i -e "s#opencontrail#sdn#g" -e "s#contrail#sdn#g" -e "s#Contrail#Sdn#g" {}
    mv /etc/neutron/plugins/opencontrail /etc/neutron/plugins/sdn
    mv /etc/neutron/plugins/sdn/ContrailPlugin.ini /etc/neutron/plugins/sdn/SdnPlugin.ini
    rm -rf /usr/lib/python2.7/site-packages/neutron_plugin_contrail*
  fi
fi

echo "  Starting new SDN container ..."
find /etc -name docker-compose.yaml | xargs -i docker-compose -f {} up -d
if [[ -d "/etc/neutron" ]]; then
  echo "  Restart neutron server ..."
  systemctl restart neutron-server.service
fi
exit
REMOTESSH
done

echo -e "\n"
for node in ${nodeArray[*]}
do
  echo "========Upgrade Done. Check Services Status for $node========"
  $ssh_cmd $node "sdn-status"
done
