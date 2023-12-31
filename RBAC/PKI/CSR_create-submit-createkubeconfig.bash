#!/bin/bash

###################
#
# Last modification : 11.08.2023 
#
# Purpose : simple script to generate keys pair and x509 Certificate Signing Request (CSR)
#           The CSR should then be submitted to some Certification Authority for signature and obtain a x509 certificate.
#           The script proposes to submit the request directly to a Kubernetes cluster to retrieve the x509 certificate
#
# Pre-requisites : have the Kubernetes cluster root CA available in file ${CACERTFILE}
#                  If Kubernetes cluster is used as PKI, ensure ${CNKUBECONFIG} context has enough
#                  privileges to submit CSR's, approve CSR and retrieve x509 certificates
#                  Adjust x509 attributes in user variables section according to your organisation
#
###################

###################
#
# User variables section
#
CURDATETIME=`date +%Y%m%d%H%M`
PARENTDIR="/B13/B13lab/K8S/K8STRAINING/RBAC"
CREDSDIR="${PARENTDIR}/PKI/creds"
K8SMANIFESTSDIR="${PARENTDIR}/PKI/manifests"

# User and group to protect files
OWNER="tag"
GRP="b13admin"

# x509 local attributes
COUNTRY="CH"
STATE="Vaud"
LOCALITY="Lausanne"
OU="DevOps"

# API server root CA is usually in <masternode>:/etc/kubernetes/pki/ca.crt
CACERTFILE=${CREDSDIR}/K8S_CA-cert.crt
RSAKEYLENGTH=2048

# Kubernetes API server information to be used to submit, approve and retrieve cluster certificates 
K8SCLUSTERNAME="kubernetes"
K8SAPISERVERFQDN="k8smaster10.lab.byte13.org"
K8SAPISERVERIP="10.13.4.10"
K8SAPISERVERPORT="6443"
K8SAPISERVERURL="https://${K8SAPISERVERIP}:${K8SAPISERVERPORT}"

#
# End of user varaibles section. Nothing to modify on the rest of this script
###################

clear

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

function DisplayUsage () {
    echo -e "Usage : ${LGRAY}${0} -c <common name> -o <organisation> [-f <filename>] [-s] [-a] [-r] [-d}${NC}\n"
    echo -e "To simply create a CSR and Kubernetes manifest : ${LGRAY}${0} -c johndev -o project1 ${NC}"
    echo -e "To create and submit CSR to Kubernetes cluster : ${LGRAY}${0} -c johndev -o project1 -s${NC}"
    echo -e "To create, submit and approve CSR in Kubernetes cluster : ${LGRAY}${0} -c johndev -o project1 -s -a${NC}"
    echo -e "To create, submit, approve and retrieve CSR from Kubernetes cluster then create kubeconfig file : ${LGRAY}${0} -c johndev -o project1 -s -a -r${NC}\n"
    echo -e "To process a list of users retrieved from a file : ${LGRAY}${0} -f <filename>${NC}"
    echo -e "    Each line must have the following format (separator must be semicolumn) : ${LGRAY}<username>;<group>${NC}"
    echo -e "    ${LGRAY}-s -a -r${NC} arguments are implicit when ${LGRAY}-f <filename> ${NC}is specified.\n"
    echo -e "${LGRAY}-d ${NC}forces deletion of existing request with same name in the Kubernetes cluster."
    echo -e "If not specified and a request with same name already exists in the Kubernetes cluster, the user is prompted to confirm deletion."
}

if [[  $# -lt 4  &&  ${1} != "-f" ]]; then
    DisplayUsage
    exit 0
fi

# Initialize variables
#APPROVECSR="X"
#CN="X"
#K8SREQNAME="X"
#K8SCSRMANIFEST="X"
#INPUTFILE="X"
#RETRIEVECERT="X"
#SUBMITCSR="X"

while getopts "ac:df:o:rs" opt; do
    case ${opt} in
      a )
        APPROVECSR="yes"
        ;;
      c )
        CN=${OPTARG}
        ;;
      d )
        DELETECSR="yes"
        ;;
      f )
        INPUTFILE=${OPTARG}
        ;;
      o )
        ORG=${OPTARG}
        ;;
      r )
        RETRIEVECERT="yes"
        ;;
      s )
        SUBMITCSR="yes"
        ;;
      \? )
        DisplayUsage 
        exit 0
        ;;
      * )
        echo "Invalid Option: -$opt requires an argument" 1>&2
        DisplayUsage 
        exit 1
        ;;
    esac
done
shift $((OPTIND -1))

#
# Set variables based on user inputs
#
# In Kubernetes, Organization is interpreted as the group a user belongs, to
SUBJECT="/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORG}/OU=${OU}/CN=${CN}"
# x509 subject attribute can contain several Organizations as shown in the following example
# SUBJECT="/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORG}/O=${ORG2}/OU=${OU}/CN=${CN}"
PRIVATEKEYFILE="${CREDSDIR}/${CN}.key"
PUBLICKEYFILE="${CREDSDIR}/${CN}.pub"
CSRFILE="${CREDSDIR}/${CN}.csr"
CERTFILE="${CREDSDIR}/${CN}.cer"
K8SREQNAME="csr-${CN}"
K8SCSRMANIFEST="${K8SMANIFESTSDIR}/${CN}_CSRrequest.yaml"
CNKUBECONFIG="${CREDSDIR}/${CN}_kube.config"

#
# Create output directories if they don't exist, yet
#
if [ ! -d ${CREDSDIR} ]; then
    mkdir ${CREDSDIR}
    chown ${OWNER}:${GRP} ${CREDSDIR}
    chmod 750 ${CREDSDIR}
fi

if [ ! -d ${K8SMANIFESTSDIR} ]; then
    mkdir ${K8SMANIFESTSDIR}
    chown ${OWNER}:${GRP} ${K8SMANIFESTSDIR}
    chmod 750 ${K8SMANIFESTSDIR}
fi

#
# Definition of various functions
#
function PrepareCSR () {
### Create RSA keys and CSR
    #echo -e "${LCYAN}Entering PrepareCSR()${NC}"

    # Save existing file for same user
    if [ -f ${PRIVATEKEYFILE} ]; then
        mv ${PRIVATEKEYFILE} ${PRIVATEKEYFILE}_${CURDATETIME}
    fi

    if [ -f ${CSRFILE} ]; then
        mv ${CSRFILE} ${CSRFILE}_${CURDATETIME}
    fi

    echo -e ${YELLOW}
    echo "Preparing certificate for ${SUBJECT}"
    echo -e ${NC}

    # Generate key pair and generate Certificate Signing Request (CSR) 
    # With prompt
    #openssl req -new -newkey rsa:2048 -nodes -keyout ${PRIVATEKEYFILE} -out ${CSRFILE} -config ${OPENSSLCNF} ${RSAKEYLENGTH}
    # Without prompt
    openssl req -nodes \
	        -newkey rsa:${RSAKEYLENGTH} \
       	        -keyout ${PRIVATEKEYFILE} \
    	        -out    ${CSRFILE} \
	        -subj   ${SUBJECT} 

    # Protect generated files, aspecially the private key
    chown ${OWNER}:${GRP} ${PRIVATEKEYFILE} 
    chmod 600 ${PRIVATEKEYFILE}
    chown ${OWNER}:${GRP} ${CSRFILE} 
    chmod 640 ${CSRFILE}

    if [ "X${SUBMITCSR}" != "Xyes" ]; then
        SUBMITCSR="X"
        echo -e "${LCYAN}Would you like to submit CSR right now ? (yes / no) :${NC}"
        read SUBMITCSR
    fi
    if [ "X${SUBMITCSR}" != "Xyes" ]; then
	echo -e "${LCYAN}"
        echo -e "The Certificate Signing Request (CSR) is available in ${LGRAY}${CSRFILE}"
        echo -e "${LCYAN}You could also cut and paste the CSR from here :"
        echo -e ${LGRAY}
        cat ${CSRFILE}
        echo -e ${NC}

	CreateK8sManifest

        echo -e ${LCYAN}
        echo -e "You could now submit the CSR to a Certification Authority (CA)"
        echo -e ${NC}

	exit 0
    fi
}

function CreateK8sManifest () {
### Prepare a Kubernetes manifest to submit CSR to cluster PKI
    #echo -e "${LCYAN}Entering CreateK8sManifest()${NC}"

    if [ -f ${K8SCSRMANIFEST} ]; then
        mv ${K8SCSRMANIFEST} ${K8SCSRMANIFEST}_${CURDATETIME}
    fi

    K8SCSR=$(cat ${CSRFILE} | base64 | tr -d '\n')
    #K8SCSR=$(cat ${CSRFILE} | tr -d '\n')
    #K8SCSR=$(tail -n +2 ${CSRFILE} | head -n-1 | tr -d '\n')

    echo "apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${K8SREQNAME}
spec:
  request: ${K8SCSR}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
" >${K8SCSRMANIFEST}

    chown ${OWNER}:${GRP} ${K8SCSRMANIFEST} 
    chmod 640 ${K8SCSRMANIFEST}

    echo -e ${LCYAN}
    echo -e "The Kubernetes manifest containing ${LGRAY}${CN} ${LCYAN}CSR is available in ${LGRAY}${K8SCSRMANIFEST}"
    echo -e ${NC}
}

function CheckCsrStatus () {
### Check if CSR was already submited for same CN
    echo -e "${BRORANGE}Entering CheckCsrStatus()${NC}"

    ANSWER="X"
    CSREXISTS="X"
    CSRSTATUS="X"
    CSREXISTS="X"
    CSREXISTS=$(kubectl get csr ${K8SREQNAME} -o=jsonpath="{.metadata.name}")
    CSRSTATUS=$(kubectl get csr ${K8SREQNAME} -o=jsonpath="{.status.conditions[0].type}")
    if [[ ("${CSREXISTS}" == "${K8SREQNAME}") && ("${DELETECSR}" == "yes") ]]; then
        echo -e "${LCYAN}A CSR with common name ${BRORANGE}${CN} ${LCYAN}is already submitted with status ${BRORANGE}${CSRSTATUS}${LCYAN}"
        echo -e "${LCYAN}Since ${LGRAY}-d ${LCYAN}argument is set, the CSR is now deleted from Kubernetes cluster${NC}"
            kubectl delete csr ${K8SREQNAME}
    elif [ "${CSREXISTS}" == "${K8SREQNAME}" ]; then
        echo -e "${LCYAN}A CSR with common name ${BRORANGE}${CN} ${LCYAN}is already submitted with status ${BRORANGE}${CSRSTATUS}${LCYAN}; should we delete it ? (yes / no)${NC}"
            read ANSWER
        if [ "X${ANSWER}" == "Xyes" ]; then
            kubectl delete csr ${K8SREQNAME}
        else
            echo -e "${RED}Current request left as is and exiting${NC}"
            exit 0
        fi
    fi
}

function SubmitCSR () {
### Submit request for x509 certificate to Kubernetes cluster PKI
    #echo -e "${LCYAN}Entering SubmitCSR()${NC}"

    if [ -f ${K8SCSRMANIFEST} ]; then
        CheckCsrStatus
        kubectl apply -f ${K8SCSRMANIFEST} >/dev/null 2>&1
    else
	echo -e "${LGRAY}${K8SCSRMANIFEST}${LCYAN} not found; cannot submit request to Kubernetes cluster${NC}"
	exit 0
    fi

    if [ X${APPROVECSR} != "Xyes" ]; then

        echo -e "${LCYAN}An administrator with appropriate rights can now approve or deny the request using the following command :${NC}
        ${LGRAY}kubectl certificate [approve | deny] ${K8SCSRNAME} 
        ${NC}"

        APPROVECSR="X"
        echo -e "${LCYAN}Would you like to approve the request yourself right now ? (yes / no) :${NC}"
        read APPROVECSR
    fi
}

function ApproveCSR ()  {
### Approve request (requires enough privileges in Kubernetes cluster)
    #echo -e "${LCYAN}Entering ApproveCSR()${NC}"

    kubectl certificate approve ${K8SREQNAME} >/dev/null 2>&1

    if [ "X${RETRIEVECERT}" != "Xyes" ]; then
        RETRIEVECERT="X"
        echo -e "${LCYAN}Would you like to retrieve x509 certificate right now and create kubeconfig file ? (yes / no) :${NC}"
        read RETRIEVECERT
    fi
}

function RetrieveCertificate () {
### Retrieve signed x509 certificate
    #echo -e "${LCYAN}Entering RetriveCertificate()${NC}"

    if [ -f ${CERTFILE} ]; then
        mv ${CERTFILE} ${CERTFILE}_${CURDATETIME}
    fi

    echo -e "${LCYAN}Retrieving possibly approved certificate..."

    echo -e "Check CSR status...${NC}"
    CSRSTATUS=X
    CSRSTATUS=$(kubectl get csr ${K8SREQNAME} -o=jsonpath="{.status.conditions[0].type}") 
    if [ "X${CSRSTATUS}" == "XApproved" ]; then
        echo -e "\n${LCYAN}Congatulations ! Your request for a certificate has been approved :-)"
        echo -e "Retrieving signed certificate in file ${LGRAY}${CERTFILE}...${NC}"
        kubectl get csr ${K8SREQNAME} -o=jsonpath="{.status.certificate}" | base64 --decode >${CERTFILE}

        chown ${OWNER}:${GRP} ${CERTFILE} 
        chmod 640 ${CERTFILE}
    else
        echo -e "${BRORANGE}Sorry, your certificate has not been approved, yet (?)${NC}"
        exit 0
    fi    
}

function CreateKubeconfigFile () {
### Create a kubeconfig file with retrieved x509 certificate and respective private key
    #echo -e "${LCYAN}Entering CreateKubeconfigFile()${NC}"

    if [ -f ${CNKUBECONFIG} ]; then
        mv ${CNKUBECONFIG} ${CNKUBECONFIG}_${CURDATETIME}
    fi

    if [ ! -f ${CACERTFILE} ]; then
        echo -e "${BRORANGE}${CACERTFILE} is missing; ensure it contains respective Kubernetes cluster root CA certificate${NC}"
        exit 0
    fi

    echo -e "\n${LCYAN}Preparing kubeconfig file..."
    kubectl config --kubeconfig ${CNKUBECONFIG} set-cluster ${K8SCLUSTERNAME} --server=${K8SAPISERVERURL} \
	                                                                      --certificate-authority ${CACERTFILE} \
				                                              --embed-certs=true
    if [ -f ${CNKUBECONFIG} ]; then
        chown ${OWNER}:${GRP} ${CNKUBECONFIG}
        chmod 600 ${CNKUBECONFIG}
    else
        echo -e "${BRORANGE}${CNKUBECONFIG} file missing.${NC}"
        exit 0
    fi

    kubectl config --kubeconfig ${CNKUBECONFIG} set-credentials ${CN} --client-key=${PRIVATEKEYFILE} \
    	                                                              --client-certificate=${CERTFILE} \
				                                      --embed-certs=true
    kubectl config --kubeconfig ${CNKUBECONFIG} set-context ${CN} --cluster=${K8SCLUSTERNAME} --user=${CN}
    kubectl config --kubeconfig ${CNKUBECONFIG} use-context ${CN} --cluster=${K8SCLUSTERNAME} --user=${CN}

    echo -e "\n${LCYAN}Please, provide the user with ${LGRAY}${CNKUBECONFIG}${LCYAN}."
    echo -e "${BRORANGE}This file contains sensitive credentials; please, instruct users to carefully protect such files."
    echo -e "${LCYAN}Please, instruct him to use it as kubernetes client config file.
             The following syntax could be used :${NC}
             ${LGRAY}kubectl --kubeconfig ${CNKUBECONFIG} <command>\n"
    echo -e "${LCYAN}Instead of using ${LGRAY}--kubeconfig ${LCYAN}with each kubectl command, she may :"
    echo -e "    move this file into ${LGRAY} ~/.kube/config chmod 600 $~/.kube/config"
    echo -e "    ${LCYAN}then ${LGRAY}chmod 600 $~/.kube/config"
    echo -e "    ${LCYAN}or point the variable ${LGRAY}KUBECONFIG ${LCYAN}to this file${NC}"
}

########################################
#
# Main section
#
########################################

if [ "X${INPUTFILE}" != "X" ]; then

    if [ ! -f ${INPUTFILE} ]; then
	echo -e "${BRORANGE}${INPUTFILE} not found...${NC}"
	exit 0
    fi

    USERSLIST=$(cat ${INPUTFILE})

    for LINE in ${USERSLIST}; do
        echo -e "${LCYAN}Processing ${LGRAY}${LINE}${NC}"

	CN=$(echo ${LINE} | awk -F"\;" '{print $1}')
	ORG=$(echo ${LINE} | awk -F"\;" '{print $2}')

	if [ "${DELETECSR}" == "yes" ]; then
	    ${0} -c ${CN} -o ${ORG} -s -a -r -d
	else
	    ${0} -c ${CN} -o ${ORG} -s -a -r
	fi

    done
    exit 0
fi

PrepareCSR

if [ "X${SUBMITCSR}" == "Xyes" ]; then
    CreateK8sManifest
    SubmitCSR
fi

if [ "X${APPROVECSR}" == "Xyes" ]; then
    ApproveCSR
fi

if [ "X${RETRIEVECERT}" == "Xyes" ]; then
    RetrieveCertificate
    CreateKubeconfigFile
fi

