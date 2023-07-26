# References :
# https://
FROM alpine:latest

# Install usefull utilities
RUN apk add --update --no-cache --virtual .persistent-deps \
                bind-tools \
                iputils \
                nmap \
                curl \
                ethtool \
                iproute2 \
                libressl \
		tcpdump

RUN addgroup -g 4321 podgroup1 && adduser -D -h /K8SLAB -u 1234 -G podgroup1 poduser1 

# Install Peirates
RUN mkdir -p /K8SLAB && \
    cd /K8SLAB && \
    wget https://github.com/inguardians/peirates/releases/download/v1.1.12/peirates-linux-amd64.tar.xz && \
    tar xvf peirates-linux-amd64.tar.xz && \
    rm -f peirates-linux-amd64.tar.xz

# Copy some local file into the image
COPY ncwebsrv.sh /K8SLAB/ncwebsrv.sh
RUN chmod 750 /K8SLAB/ncwebsrv.sh && chown -R poduser1:podgroup1 /K8SLAB

# Command started by default when container starts
ENTRYPOINT ["/K8SLAB/ncwebsrv.sh"]
CMD ["7777"]
