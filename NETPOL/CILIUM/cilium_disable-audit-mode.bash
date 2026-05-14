#!/bin/bash
#
CILIUMNS=kube-system
NODESLIST="k8smaster10.lab.byte13.org k8sworker11.lab.byte13.org k8sworker12.lab.byte13.org"
NODE=""
NODE=${1}

clear

if [ ${NODE}X != "X" ] ; then
    NODENAME=${NODE}
    echo "Working on node ${NODENAME}..."
    CILIUMPODNAME=$(kubectl -n ${CILIUMNS} get pods -l "k8s-app=cilium" \
	                    -o jsonpath="{.items[?(@.spec.nodeName=='${NODENAME}')].metadata.name}")
    HOSTEPID=$(kubectl -n ${CILIUMNS} exec ${CILIUMPODNAME} -- \
	       cilium-dbg endpoint list -o jsonpath='{[?(@.status.identity.id==1)].id}')
    echo "Find host endpoint ID ${HOSTEPID}..."
    kubectl -n ${CILIUMNS} exec ${CILIUMPODNAME} -- cilium-dbg status | grep 'Host firewall'
    kubectl -n ${CILIUMNS} exec ${CILIUMPODNAME} -- cilium-dbg endpoint config ${HOSTEPID} PolicyAuditMode=Disabled
    kubectl -n ${CILIUMNS} exec ${CILIUMPODNAME} -- cilium-dbg endpoint config ${HOSTEPID} | grep PolicyAuditMode
else 

    for NODENAME in ${NODESLIST}; do
        echo "Working on node ${NODENAME}..."
        CILIUMPODNAME=$(kubectl -n ${CILIUMNS} get pods -l "k8s-app=cilium" \
    	                    -o jsonpath="{.items[?(@.spec.nodeName=='${NODENAME}')].metadata.name}")
        HOSTEPID=$(kubectl -n ${CILIUMNS} exec ${CILIUMPODNAME} -- \
    	       cilium-dbg endpoint list -o jsonpath='{[?(@.status.identity.id==1)].id}')
        echo "Find host endpoint ID ${HOSTEPID}..."
        kubectl -n ${CILIUMNS} exec ${CILIUMPODNAME} -- cilium-dbg status | grep 'Host firewall'
        kubectl -n ${CILIUMNS} exec ${CILIUMPODNAME} -- cilium-dbg endpoint config ${HOSTEPID} PolicyAuditMode=Disabled
        kubectl -n ${CILIUMNS} exec ${CILIUMPODNAME} -- cilium-dbg endpoint config ${HOSTEPID} | grep PolicyAuditMode
        echo "------------"
    done
fi

#
# When PolicyAuditMode is Enabled, the following command displays accepted of rejected trafics 
#kubectl -n ${CILIUMNS} exec ${CILIUMPODNAME} --  cilium-dbg monitor -t policy-verdict --related-to ${HOSTEPID}
# To see all rejected trafics, use the following loop
if [ ${NODE}X != "X" ] ; then
    NODENAME=${NODE}
    echo "Working on node ${NODENAME}..."
    CILIUMPODNAME=$(kubectl -n ${CILIUMNS} get pods -l "k8s-app=cilium" \
	                    -o jsonpath="{.items[?(@.spec.nodeName=='${NODENAME}')].metadata.name}")
    HOSTEPID=$(kubectl -n ${CILIUMNS} exec ${CILIUMPODNAME} -- \
	       cilium-dbg endpoint list -o jsonpath='{[?(@.status.identity.id==1)].id}')
    echo "Looking for rejected trafics on host endpoint ID ${HOSTEPID}..."
    kubectl -n ${CILIUMNS} exec ${CILIUMPODNAME} -- cilium-dbg monitor -t policy-verdict \
	    --related-to ${HOSTEPID} | grep "action audit"
    exit ${?}
fi
    
for NODENAME in ${NODESLIST}; do
    echo "Working on node ${NODENAME}..."
    CILIUMPODNAME=$(kubectl -n ${CILIUMNS} get pods -l "k8s-app=cilium" \
	                    -o jsonpath="{.items[?(@.spec.nodeName=='${NODENAME}')].metadata.name}")
    HOSTEPID=$(kubectl -n ${CILIUMNS} exec ${CILIUMPODNAME} -- \
	       cilium-dbg endpoint list -o jsonpath='{[?(@.status.identity.id==1)].id}')
    echo "Looking for rejected trafics on host endpoint ID ${HOSTEPID}..."
    kubectl -n ${CILIUMNS} exec ${CILIUMPODNAME} -- cilium-dbg monitor -t policy-verdict \
	    --related-to ${HOSTEPID} | grep "action audit"
done
