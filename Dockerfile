# Use an Ubuntu base image
FROM ubuntu:22.04

# docker build -t openssl3-pkcs11 .
# docker run -it --device /dev/bus/usb -v /dev/bus/usb:/dev/bus/usb -v /run/pcscd/pcscd.comm:/run/pcscd/pcscd.comm  --privileged openssl3-pkcs11
# To sign w/ PKCS#11 Token:
# OPENSSL_CONF=./openssl-pkcs11.cnf openssl pkeyutl   -sign   -in data.txt   -out data.sig   -inkey "pkcs11:model=PKCS%2315%20emulated;manufacturer=piv_II;serial=00870010164edbb5;token=JET%20Technology%20Labs%20Inc.;id=%01;object=PIV%20AUTH%20key;type=private"   -provider pkcs11
# Gen PKCS#7 signature 
# openssl cms -sign   -engine pkcs11   -keyform engine   -inkey "pkcs11:model=PKCS%2315%20emulated;manufacturer=piv_II;serial=00870010164edbb5;token=JET%20Technology%20Labs%20Inc.;id=%01;object=PIV%20AUTH%20key;type=private"   -signer cert.pem   -in message.txt -out message.p7s   -outform DER -nodetach


# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive


# Install required packages
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    wget \
    perl \
    cmake \ 
    sbsigntool \
    opensc pcscd yubico-piv-tool gnutls-bin \
    pkg-config meson libp11-kit-dev p11-kit \
    tar gzip unzip zlib1g-dev \
    ca-certificates \
    sudo

RUN mkdir -p /workspace/

# setup OpenSSL v3.3 - pkcs11 provider requires newer version than is installed by default
RUN git clone --branch openssl-3.3.3 https://github.com/openssl/openssl.git
RUN cd openssl && \
    ./config --prefix=/usr/local/openssl --openssldir=/usr/local/openssl shared zlib && \
    make -j && \
    make install && \
    echo '/usr/local/openssl/lib64' > /etc/ld.so.conf.d/openssl.conf && \
    ldconfig && \
    /usr/local/openssl/bin/openssl version

# update PKG_CONFIG_PATH for the new openssl version
ENV PKG_CONFIG_PATH=/usr/local/openssl/lib64/pkgconfig
ENV LD_LIBRARY_PATH=/usr/local/openssl/lib64
RUN pkg-config --modversion libcrypto


# setup OpenSSL PKCS#11 Provider
RUN git clone https://github.com/latchset/pkcs11-provider.git
RUN cd pkcs11-provider && mkdir build  && \
    meson setup build && \
    meson compile -C build && \
    meson install -C build

# Install osslsigncode from source
WORKDIR /opt
RUN git clone https://github.com/mtrojnar/osslsigncode.git
WORKDIR /opt/osslsigncode
COPY ./patches/0001-osslsigncode.patch /opt/osslsigncode/
RUN ls -al && patch -p1 < 0001-osslsigncode.patch
RUN  mkdir build && cd build && cmake -S .. && cmake --build . && cmake --install .

# Install SafeNet libetoken
WORKDIR /opt
RUN wget https://www.digicert.com/StaticFiles/Linux_SAC_10.9_GA.zip --no-check-certificate
RUN unzip Linux_SAC_10.9_GA.zip
RUN ls -al && cd "SAC_10.9 GA" && ls -al && cd "SAC Package" && unzip *.zip && \
    cd "SAC Linux 10.9" && cd Installation/withoutUI/Ubuntu-2204/ && dpkg -i *.deb

# copy pkcs11 config
COPY ./openssl_opensc.cnf /workspace/
COPY ./openssl_safenet.cnf /workspace/

WORKDIR /workspace/

# Set entrypoint - run passed in command or bash
ENTRYPOINT ["/bin/bash", "-c", "if [ $# -gt 0 ]; then exec \"$@\"; else /bin/bash;  fi", "--"]
