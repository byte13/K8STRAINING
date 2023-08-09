#!/bin/bash

###################
#
# Last modification : 07.08.2023 
#
# Purpose : simple script to generate keys pair and x509 Certificate Signing Request (CSR)
#           The CSR should then be submitted to some Certification Authority for signature and obtain a x509 certificate.
#           The script proposes to submit the request directly to a Kubernetes cluster to retrieve the x509 certificate
#
# Pre-requisites : have the Kubernetes cluster root CA available in file ${CACERTFILE}
#                  If Kubernetes cluster is used as PKI, ensure ${KUBECONFIG} points to credentials with enough i
#                  privileges to submit CSR's and retrieve x509 certificates
#
###################

###################
#
# User variables section
#
CURDATETIME=`date +%Y%m%d%H%M`
PARENTDIR="/B13/B13lab/K8S/K8STRAINING/RBAC/PKI"
OUTPUTDIR="${PARENTDIR}/CREDS"
COUNTRY="CH"
STATE="Vaud"
LOCALITY="Lausanne"
OU="DevOps"
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

function DisplayUsage () {
    echo -e "Usage :   ${0} -c <common name> -o <organisation>"
    echo -e "Example : ${LGRAY}${0} -c johndev -o project1 ${NC}"
}

if [ $# != 4 ]; then
    DisplayUsage
    exit 0
fi

while getopts "c:o:s" opt; do
    case ${opt} in
      c )
        CN=${OPTARG}
        ;;
      o )
        ORG=${OPTARG}
        ;;
      s )
        GETCERT="yes"
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

PRIVATEKEYFILE=${OUTPUTDIR}/${CN}.key
PUBLICKEYFILE=${OUTPUTDIR}/${CN}.pub
CSRFILE=${OUTPUTDIR}/${CN}.csr
SUBJECT="/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORG}/OU=${OU}/CN=${CN}"

echo -e ${YELLOW}
echo "Preparing certificate for ${SUBJECT}"
echo -e ${NC}

# Check for output directory
if [ ! -d ${CREDSDIR} ] ; then
    mkdir ${CREDSDIR}
    chown tag:b13admin ${CREDSDIR}
    chmod 750 ${CREDSDIR}
fi

# Generate key pair and generate Certificate Signing Request (CSR) 
# With prompt
#openssl req -new -newkey rsa:2048 -nodes -keyout ${PRIVATEKEYFILE} -out ${CSRFILE} -config ${OPENSSLCNF} 
# Without prompt
openssl req -nodes -newkey rsa:2048 \
	    -keyout ${PRIVATEKEYFILE} \
	    -out    ${CSRFILE} \
	    -subj   ${SUBJECT} 

echo -e ${YELLOW}
echo "The Certificate Signing Request (CSR) is available in ${CSRFILE}"
echo "You could now submit is to a Certification Authority (CA)"
echo "You could also cut and paste the CSR from here :"
echo -e ${LGRAY}
cat ${CSRFILE}
echo -e ${NC}

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
