#!/bin/bash

op=$1

if [[ "x$op" == "x" || "$op" == "-h" ]]; then
    echo "Usage: modify vhost0 ip or nic, also support remove a vrouter"
    echo -e "\t $0 nic ens3f0"
    echo -e "\t $0 ips <oldip1>:<newip1> <oldip2>:<newip2> <oldip3>:<newip3> <gateway-ip>"
    echo -e "\t    e.g. $0 ips 172.118.10.10:192.168.10.10 172.118.10.13:192.168.10.13 172.118.10.16:192.168.10.16 192.168.10.1"
    echo -e "\t [$0 ip <newip> <gateway-ip> -- Used only if controller IP not changed]"
    echo -e "\t $0 remove"
    exit 0
fi

vrouter_env_file=$(find /etc -name common_vrouter.env)
compose_file=$(find /etc -name docker-compose.yaml | grep vrouter)

# ***********************************************************************
# Following is handling nic replacement
# ***********************************************************************

if [ "$op" == "nic" ]; then
    nic=$2
    if [ "x$nic" == "x" ]; then
        echo "error: nic not set"
        exit 1
    fi
    IP=$(ip -4 -br a s vhost0 | awk '{print $3}' | awk -F '/' '{print $1}')
    if [ -z "$IP" ]; then
        IP=$(grep IP /etc/sysconfig/network-scripts/ifcfg-vhost0 | cut -d '=' -f2)
    fi

    echo "==> Step 1: stop vrouter agent and rollback vhost0 physical interface"
    docker-compose -f $compose_file down
    ifdown vhost0

    echo ""
    old_nic=$(grep PHYSICAL_INTERFACE $vrouter_env_file | awk -F '=' '{print $2}')
    echo "==> Step 2: Replace $old_nic with $nic"
    sed -i "s/PHYSICAL_INTERFACE=.*/PHYSICAL_INTERFACE=$nic/g" $vrouter_env_file
    ifdown $old_nic
    # comment IP address in old nic
    sed -i "s/^IPADDR=/#IPADDR=/g" /etc/sysconfig/network-scripts/ifcfg-$old_nic
    sed -i "s/^PREFIX=/#PREFIX=/g" /etc/sysconfig/network-scripts/ifcfg-$old_nic

    # make sure new nic have IP address assigned
    echo $nic | grep '\.'
    if [ $? == 0 ]; then
        vlan="VLAN=yes"
    fi
    if [ ! -f "/etc/sysconfig/network-scripts/ifcfg-$nic" ]; then
        echo "==> Warn: no found ifcfg-$nic file, create /etc/sysconfig/network-scripts/ifcfg-$nic"
        cat << EOF > /etc/sysconfig/network-scripts/ifcfg-$nic
DEVICE=$nic
BOOTPROTO=none
ONBOOT=yes
IPADDR=$IP
PREFIX=24
$vlan
EOF
    else
        grep $IP /etc/sysconfig/network-scripts/ifcfg-$nic
        if [ $? != 0 ]; then
            echo "IPADDR=$IP" >> /etc/sysconfig/network-scripts/ifcfg-$nic
            echo "PREFIX=24" >> /etc/sysconfig/network-scripts/ifcfg-$nic
        fi
    fi

    # Remove vhost0 config and flap new nic to refresh route
    rm -rf /etc/sysconfig/network-scripts/ifcfg-vhost0
    ifdown $nic
    ifup $nic
    if [ $? != 0 ]; then
        echo "==> Error: failed to ifup $nic. Fix it and up containers with 'docker-compose -f $compose_file up -d'"
        exit 1
    fi

    echo ""
    echo "==> Step 3: running with nic $nic"
    docker-compose -f $compose_file up -d
    exit 0
fi

# ***********************************************************************
# Following is handling agent remove or IP replace
# Agent can add itself by provision
# ***********************************************************************

# Support to remove a agent node
function remove_vrouter() {
    provison_container=$(docker ps -f name=vrouter_provisioner --format '{{.Names}}')
    agent_container=$(docker ps -f name=vrouter-agent_ --format '{{.Names}}')
    docker stop $agent_container
    ifdown vhost0
    rm -f /etc/sysconfig/network-scripts/ifcfg-vhost0

    api=$(docker exec $provison_container env | grep VIP | awk -F '=' '{print $2}')
    auth_param="--admin_password ArcherAdmin@123 --admin_tenant_name ArcherAdmin --admin_user ArcherAdmin"
    # $8 is hostname, $10 is hostip
    # specify hostname and ip can be support later on demand
    provison_cmd=$(docker logs $provison_container | grep cmdline | tail -n 1 | awk -v api=$api '{print $4,$5,"del",$7,$8,$9,$10,$13,api,$21,$22}')
    provison_cmd="$provison_cmd $auth_param"
    echo $provison_cmd

    # Remove vrouter by running provision script
    docker exec $provison_container $provison_cmd
}

if [ "$op" == "remove" ]; then
    remove_vrouter
    exit 0
fi

# Replace IP address for vhost0
function get_controls() {
    ips="$1 $2 $3"
    PYCMD=$(cat <<EOF
ips = "$ips".split()
controls = ''
for ip in ips:
  controls += ip.split(':')[1] + ','
print(controls.strip(','))
EOF
)
    python -c "$PYCMD"
}

function get_my_newip() {
    ips="$1 $2 $3"
    PYCMD=$(cat <<EOF
ips = "$ips".split()
for ip in ips:
  node = ip.split(':')
  if node[0] == "$4":
    print(node[1])
    break
EOF
)
    python -c "$PYCMD"
}

function reg_node() {
    node=$1
    PYCMD=$(cat <<EOF
ips = "$node".split(':')
print('s/%s/%s/g' %(ips[0], ips[1]))
EOF
)
    python -c "$PYCMD"
}

if [ "$op" == "ips" ]; then
    node1=$2
    node2=$3
    node3=$4
    if [[ "x$node1" == "x" || "x$node2" == "x" || "x$node3" == "x" ]]; then
        echo "error: IP address not set"
        exit 1
    fi
    gateway=$5
    if [ "x$gateway" == "x" ]; then
        echo "error: gateway address not set"
        exit 1
    fi
    old_ip=$(ip -4 -br a s vhost0 | awk '{print $3}' | awk -F '/' '{print $1}')
    nic=$(grep PHYSICAL_INTERFACE $vrouter_env_file | awk -F '=' '{print $2}')

    controls=$(get_controls $node1 $node2 $node3)
    IP=$(get_my_newip $node1 $node2 $node3 $old_ip)
    echo "new controller is $controls, my old ip is $old_ip, my new ip is $IP and vrouter gateway $gateway"
    read -p "### Is this correct?(y/n)" confirmed
    if [[ $confirmed != "y" ]]; then
      exit 0
    fi

    echo ""
    echo "==> Step 1: modify environment variable"
    echo "    | modify /etc/hosts"
    echo "    <<<<<< old /etc/hosts"
    cat /etc/hosts | grep cluster
    for node in $node1 $node2 $node3; do
        reg=$(reg_node $node)
        sed -i.bak "$reg" /etc/hosts
    done
    echo "    >>>>>> new /etc/hosts"
    cat /etc/hosts | grep cluster
    read -p "### Is this correct?(y/n)" confirmed
    if [[ $confirmed != "y" ]]; then
      exit 0
    fi

    echo "    | modify gateway and control nodes for vrouter"
    sed -i "s/VROUTER_GATEWAY=.*/VROUTER_GATEWAY=$gateway/g" $vrouter_env_file
    sed -i "s/CONTROL_NODES=.*/CONTROL_NODES=$controls/g" $vrouter_env_file
    echo "    | modify gateway and control nodes for control"
    control_env_file=$(find /etc -name common_control.env)
    sed -i "s/VROUTER_GATEWAY=.*/VROUTER_GATEWAY=$gateway/g" $control_env_file
    sed -i "s/CONTROL_NODES=.*/CONTROL_NODES=$controls/g" $control_env_file
    web_env_file=$(find /etc -name common_web.env)
    echo "    | modify gateway and control nodes for web"
    sed -i "s/VROUTER_GATEWAY=.*/VROUTER_GATEWAY=$gateway/g" $web_env_file
    sed -i "s/CONTROL_NODES=.*/CONTROL_NODES=$controls/g" $web_env_file

    echo ""
    echo "==> Step 2: replace $old_ip with $IP"
    echo "    | for vrouter nodes"
    echo "** Please do this in SDN GUI manually. In Configure->Infrastructure->Nodes->Virtual Routers"
    echo "    | for control nodes"
    echo "** Please do this in SDN GUI manually. In Configure->Infrastructure->BGP Routers"
    read -p "### Done?(y/n)" confirmed
    if [[ $confirmed != "y" ]]; then
      exit 0
    fi

    echo ""
    echo "==> Step 3: replace $old_ip with $IP for physical nic"
    docker-compose -f $compose_file down
    ifdown vhost0
    rm -f /etc/sysconfig/network-scripts/*vhost0
    ifdown $nic
    sed -i "s/$old_ip/$IP/g" /etc/sysconfig/network-scripts/ifcfg-$nic
    ifup $nic

    echo ""
    echo "==> Step 4: rebuild vrouter with new IP"
    docker-compose -f $compose_file up -d
    echo "==> Step 5: rebuild controller with new IP"
    compose_file=$(find /etc -name docker-compose.yaml | grep control)
    docker-compose -f $compose_file down
    docker-compose -f $compose_file up -d
    compose_file=$(find /etc -name docker-compose.yaml | grep dns)
    if [ -f $compose_file ]; then
        docker-compose -f $compose_file down
        docker-compose -f $compose_file up -d
    fi
    echo "==> Step 6: rebuild web with new IP"
    compose_file=$(find /etc -name docker-compose.yaml | grep web)
    docker-compose -f $compose_file down
    docker-compose -f $compose_file up -d

    echo ""
    echo "*** Check vrouter status"
    docker ps -f name=vrouter
    echo "*** Check control status"
    docker ps -f name=control
    echo "*** Check all status"
    sdn-status

    exit 0
fi
