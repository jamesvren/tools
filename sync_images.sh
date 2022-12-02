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
reg=$2
tag=$3

if [[ "$oper" != "pull" && "$oper" != "sync" && "$oper" != "push" || "x$reg" == "x" || "x$tag" == "x" ]]; then
    echo "Usage: $0 <pull|sync|push> <registry> <tag>"
    echo "          sync = pull and push to 10.130.176.111:6666"
    exit 0
fi

if [[ "$oper" == "sync" ]]; then
    src_reg=$reg
    dst_reg=10.130.176.111:6666
elif [[ "$oper" == "push" ]]; then
    src_reg=192.168.192.1:6666
    dst_reg=$reg
fi

for((i=0; i<${#images[@]}; i++))
do
    echo "*** 1. pull image: ${images[i]}"
    docker pull ${src_reg}/${images[i]}:${tag}
    if [[ "$oper" != "pull" ]]; then
        echo "*** 2. tag image: ${images[i]}"
        docker tag  ${src_reg}/${images[i]}:${tag} ${dst_reg}/${images[i]}:${tag}
        echo "*** 3. push image: ${images[i]}"
        docker push ${dst_reg}/${images[i]}:${tag}
    fi
done

exit 0

if [[ "$oper" == "pull" ]]; then
    exit 0
fi

for((i=0; i<${#images[@]}; i++))
do
    echo "*** 0. delete image: ${images[i]}"
    docker rmi ${reg}/${images[i]}:${tag}
    docker rmi 10.130.176.111:6666/${images[i]}:${tag}
done
