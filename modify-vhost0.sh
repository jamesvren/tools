op=$1

if [[ "x$op" == "x" || "$op" == "-h" ]]; then
    echo -e "Usage: modify vhost0 ip or nic, also support remove a vrouter\n\t $0 nic ens3f0\n\t $0 ip 192.168.10.10 192.168.10.1\n\t $0 remove"
    exit 0
fi

env_file=$(find /etc -name common_vrouter.env)
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
    old_nic=$(grep PHYSICAL_INTERFACE $env_file | awk -F '=' '{print $2}')
    echo "==> Step 2: Replace $old_nic with $nic"
    sed -i "s/PHYSICAL_INTERFACE=.*/PHYSICAL_INTERFACE=$nic/g" $env_file
    ifdown $old_nic
    # comment IP address in old nic
    sed -i "s/IPADDR=/#IPADDR=/g" /etc/sysconfig/network-scripts/ifcfg-$old_nic
    sed -i "s/PREFIX=/#PREFIX=/g" /etc/sysconfig/network-scripts/ifcfg-$old_nic

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
if [ "$op" == "ip" ]; then
    IP=$2
    if [ "x$IP" == "x" ]; then
        echo "error: IP address not set"
        exit 1
    fi
    gateway=$3
    if [ "x$gateway" == "x" ]; then
        echo "error: gateway address not set"
        exit 1
    fi
    old_ip=$(ip -4 -br a s vhost0 | awk '{print $3}' | awk -F '/' '{print $1}')
    nic=$(grep PHYSICAL_INTERFACE $env_file | awk -F '=' '{print $2}')

    echo "==> Step 1: unregist vrouter agent"
    remove_vrouter
    docker-compose -f $compose_file down

    echo ""
    echo "==> Step 2: modify environment variable"
    sed -i "s/VROUTER_GATEWAY=.*/VROUTER_GATEWAY=$gateway/g" $env_file

    echo ""
    echo "==> Step 3: replace $old_ip with $IP for physical nic"
    ifdown $nic
    sed -i "s/$old_ip/$IP/g" /etc/sysconfig/network-scripts/ifcfg-$nic
    ifup $nic

    echo ""
    echo "==> Step 4: run with new IP"
    docker-compose -f $compose_file up -d
    exit 0
fi
