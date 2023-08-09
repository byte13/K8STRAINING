#!/bin/bash

###################
#
# Author : Byte13.org
# Last modification : 04.04.2021 13:00 
#
# Purpose : create a certificate signing request using openssl
#           submit the request to a Kubernetes cluster
#	    retrieve the signed certificate
#	    create a kube config file for repsective user
#
# Pre-requisites :
#	openssl and kubectl installed        
#       Root CA certificate of the cluster pointed to by ${CACERTFILE}
#               Typically avaiblable from <masternode>:/etc/kubernetes/pki/ca.crt
#	Enough credentials in the cluster to submit and/or approve certificates
#
###################

###################
#
# User variables section
#
CURDATETIME=$(date +%Y%m%d%H%M)
CREDSDIR=/B13/B13lab/K8S/K8STRAINING/RBAC/CREDS
RSAKEYLENGTH=2048
#CN=b13adm1
#CN=b13dev1
CN=b13pm1
#DN="/CN=${CN}/OU=ITSEC/O=Byte13/O=b13admin/C=CH"
CERTDAYS=365
K8SREQNAME=b13-${CN}-csr
CLNAME=kubernetes
MASTERIP=10.13.4.1
MASTERHN=winux041.lab.byte13.org
#CACERTFILE=/etc/kubernetes/pki/ca.crt
CACERTFILE=${CREDSDIR}/K8S_CA-cert.crt

#
# End of user varaibles section. Nothing to modify on the rest of this script
###################

# Colors variables
NC='\033[0m' # No Color
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BRORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LGRAY='\033[0;37m'
DGRAY='\033[1;30m'
LRED='\033[1;31m'
LGREEN='\033[1;32m'
YELLOW='\033[1;33m'
LBLUE='\033[1;34m'
LPURPLE='\033[1;35m'
LCYAN='\033[1;36m'
WHITE='\033[1;37m'

# Check for output directory
if [ ! -d ${CREDSDIR} ] ; then
    mkdir ${CREDSDIR}
    chown user1:b13admin ${CREDSDIR}
    chmod 750 ${CREDSDIR}
fi

# Check if CSR for same CN exists
CSREXISTS="X"
CSRSTATUS="X"
CSREXISTS=$(kubectl get csr ${K8SREQNAME} -o=jsonpath="{.metadata.name}")
CSRSTATUS=$(kubectl get csr ${K8SREQNAME} -o=jsonpath="{.status.conditions[0].type}") 
if [ "X${CSREXISTS}" == "X${K8SREQNAME}" ]; then
    
    echo -e "${LCYAN}A CSR with common name ${CN} is already submitted with status ${BRORANGE}${CSRSTATUS}${LCYAN}; should we delete it ? (Yes / No)${NC}"
    read ANSWER    
    if [ "X${ANSWER}" == "XYes" ]; then
        kubectl delete csr ${K8SREQNAME} 
    else
	echo -e "${RED}Current request left as is and exiting${NC}"
	exit 0
    fi
fi

openssl genrsa -out ${CREDSDIR}/${CN}.key ${RSAKEYLENGTH}
openssl req -new -key ${CREDSDIR}/${CN}.key -out ${CREDSDIR}/${CN}.csr #-subj ${DN}

CSR=$(cat ${CREDSDIR}/${CN}.csr | base64 | tr -d '\n')
#CSR=$(cat ${CREDSDIR}/${CN}.csr | tr -d '\n')
#CSR=$(tail -n +2 ${CREDSDIR}/${CN}.csr | head -n-1 | tr -d '\n')

echo "apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${K8SREQNAME}
spec:
  request: ${CSR}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
" >${CREDSDIR}/${CN}_k8sCertReq.yml

if [ -f ${CREDSDIR}/${CN}_k8sCertReq.yml ]; then
    kubectl apply -f ${CREDSDIR}/${CN}_k8sCertReq.yml
fi

echo -e "${LCYAN}An administrator with appropriate rights can now approve or deny the request using the following command :${NC}
         ${CYAN}kubectl get csr
         kubectl certificate [approve | deny] <csr request name>
	 ${NC}"

ANSWER="X"
echo -e "${LCYAN}Would you like to approve it right now ? (Yes / No)${NC}"
read ANSWER
if [ X${ANSWER} == "XYes" ]; then
    kubectl certificate approve ${K8SREQNAME} >/dev/null 2>&1
else
    echo -e "${LCYAN}Please, ask a cluster administrator to approve your request."
    echo -e "Hit Enter key when done..."
    read ANSWER
fi

echo -e "Retrieving possibly approved certificate..."
echo -e "Check CSR status...${NC}"
CSRSTATUS=X
CSRSTATUS=$(kubectl get csr ${K8SREQNAME} -o=jsonpath="{.status.conditions[0].type}") 
if [ X${CSRSTATUS} == "XApproved" ]; then
    echo -e "Congatulations ! Your request for a certificate has been approved :-)"
    echo -e "Retrieving signed certificate in file ${CREDSDIR}${CN}.cer..."
    kubectl get csr ${K8SREQNAME} -o=jsonpath="{.status.certificate}" | base64 --decode >${CREDSDIR}/${CN}.cer
else
    echo -e "${BRORANGE}Sorry, your certificate has not been approved, yet (?)${NC}"
    exit 0
fi    

echo -e "Preparing kubeconfig file..."
KUBECONFIG=${CREDSDIR}/${CN}_K8S.config
#kubectl config set-cluster ${CLNAME} --server=https://${MASTERIP}:6443 \
kubectl config --kubeconfig ${KUBECONFIG} set-cluster ${CLNAME} --server=https://${MASTERIP}:6443 \
	                                                        --certificate-authority ${CACERTFILE} \
				                                --embed-certs=true

#kubectl config set-credentials ${CN} --client-key=${CREDSDIR}/${CN}.key \
kubectl config --kubeconfig ${KUBECONFIG} set-credentials ${CN} --client-key=${CREDSDIR}/${CN}.key \
	                                                        --client-certificate=${CREDSDIR}/${CN}.cer \
				                                --embed-certs=true
#kubectl config set-context ${CN} --cluster=kubernetes --user=${CN}
kubectl config --kubeconfig ${KUBECONFIG} set-context ${CN} --cluster=kubernetes --user=${CN}
kubectl config --kubeconfig ${KUBECONFIG} use-context ${CN} --cluster=kubernetes --user=${CN}

echo -e "${LCYAN}Please, provide the user with ${KUBECONFIG} and ask him to use it as kubernetes client config file.
         The following syntax could be used :${NC}
         ${CYAN}kubectl config --kubeconfig ${CN}_K8S.config <command> 
	 ${NC}"
echo -e "${LCYAN}Instead of using --kubeconfig, she may also copy ${KUBECONFIG} into ~/.kube/config && chmod 600 $~/.kube/config${NC}"

