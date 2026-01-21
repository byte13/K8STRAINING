#!/bin/sh

# Get local information and set some variables
HN=`hostname`
IFNAME=`ip -o link list | grep -i link/ether | awk '{print $2}' | cut -d "@" -f 1`
HIP=`ip -4 -o addr show dev ${IFNAME} | awk '{print $4}'`
HIPNOCIDR=`ip -4 -o addr show dev ${IFNAME} | awk '{print $4}' | cut -d "/" -f 1`
IFMAC=`ip -o link list | grep -i link/ether | awk '{print $17}'` 
BGCOLORSUFFIX=`ip -o link list | grep -i link/ether | awk '{print $17}' | cut -d ":" -f 4,5,6 | awk -F ":" '{print $1 $2 $3}'` 
HTMLFILE=/K8SLAB/index.html
NCPORT=7777

# Retrieve possible argument
if [ ${1}X != X ] ; then
    NCPORT=${1}
fi

# Create a simple HTML file
if [ -f ${HTMLFILE} ] ; then
    rm ${HTMLFILE}
fi

cat <<EOF >${HTMLFILE}
HTTP/1.1 200 OK
Content-Type: text/html; charset=UTF-8
Server: netcat:-)

<!doctype html>
<html>
    <body style="background-color:#${BGCOLORSUFFIX};">
        <h1>A webpage served by netcat</h1>
        <h2>Hostname: ${HN}</h2>
        <h2>${IFNAME} IP address: ${HIP}</h2>
        <h2>${IFNAME} MAC address: ${IFMAC}</h2>
    </body>
</html>
EOF

# Run a minimal static web server
while true; do
    cat ${HTMLFILE} | nc -l -p ${NCPORT}
done
