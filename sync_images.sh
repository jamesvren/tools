images=(
sdn-vrouter-agent
sdn-nodemgr
sdn-status
sdn-tools
sdn-vrouter-kernel-build-init
sdn-controller-config-devicemgr
sdn-arstack-arnet-init
sdn-controller-config-api
sdn-vrouter-agent-helper
sdn-node-init
sdn-vrouter-kernel-init
sdn-controller-control-control
sdn-arstack-compute-init
sdn-controller-control-dns
sdn-provisioner
sdn-analytics-snmp-topology
sdn-analytics-collector
sdn-controller-webui-job
sdn-controller-webui-web
sdn-controller-config-schema
sdn-analytics-query-engine
sdn-controller-control-named
sdn-controller-config-svcmonitor
sdn-analytics-api
sdn-analytics-snmp-collector
sdn-external-cassandra
sdn-external-scylla
sdn-external-zookeeper
sdn-external-rabbitmq
sdn-external-redis
sdn-external-pacemaker
sdn-external-haproxy
sdn-arstack-keystone
sdn-vcenter-manager
sdn-vcenter-plugin
)

oper=$1

function Usage() {
    echo "Usage: $0 CMD"
    echo "    CMD can be:"
    echo "          pull <registry> <tag> |"
    echo "          push from <registry> <tag> to <registry> <tag> |"
    echo "          sync from <registry> <tag> to <registry> <tag> [clean]"
}

function pull_image() {
    for((i=0; i<${#images[@]}; i++))
    do
        echo "*** 1. pull image: ${images[i]}"
        docker pull $1/${images[i]}:$2
    done
}

function push_image() {
    for((i=0; i<${#images[@]}; i++))
    do
        echo "*** 2. tag image: ${images[i]}"
        docker tag  $1/${images[i]}:$2 $3/${images[i]}:$4
        echo "*** 3. push image: ${images[i]}"
        docker push $3/${images[i]}:$4
    done
}

function delete_image() {
    for((i=0; i<${#images[@]}; i++))
    do
        echo "*** 0. delete image: ${images[i]}"
        docker rmi $1/${images[i]}:$2
        docker rmi $3/${images[i]}:$4
    done
}

if [[ "$oper" == "pull" ]]; then
    reg=$2
    tag=$3
    if [[ -z $reg || -z $tag ]]; then
        echo "Error: Missing registry or tag"
        Usage
        exit 1
    fi
    pull_image $reg $tag
    echo "** Done **"
elif [[ "$oper" == "push" || "$oper" == "sync" ]]; then
    src_reg=$3
    src_tag=$4
    dst_reg=$6
    dst_tag=$7
    clean=$8
    if [[ -z $src_reg || -z $src_tag || -z $dst_reg || -z $dst_tag ]]; then
        echo "Error: Missing src/dst registry or tag" 
        Usage
        exit 1
    fi
    if [[ "$oper" == "sync" ]]; then
        pull_image $src_reg $src_tag
    fi
    push_image $src_reg $src_tag $dst_reg $dst_tag
    if [[ ! -z $clean ]]; then
        delete_image $src_reg $src_tag $dst_reg $dst_tag
    fi
    echo "** Done **"
else
    Usage
fi
