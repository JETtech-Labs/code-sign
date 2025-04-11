#!/bin/bash

set -e # Exit immediately if a command fails

THIS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

parse_args() {
    # Initialize variables with default values
    INPUT_FILE=""
    OUTPUT_FILE=""
    KEY_URI=""
    CERT_FILE=""
    USE_SAFENET=false

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -in)
                INPUT_FILE="$2"
                shift 2
                ;;
            -out)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -key_uri)
                KEY_URI="$2"
                shift 2
                ;;
            -cert)
                CERT_FILE="$2"
                shift 2
                ;;
            -safenet)
                USE_SAFENET=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: $0 -in <input_file> -out <output_file> -key_uri <uri> -cert <cert_file> [-safenet]"
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "$INPUT_FILE" ] || [ -z "$OUTPUT_FILE" ] || [ -z "$KEY_URI" ] || [ -z "$CERT_FILE" ]; then
        echo "Error: Missing required arguments"
        echo "Usage: $0 -in <input_file> -out <output_file> -key_uri <uri> -cert <cert_file> [-safenet]"
        exit 1
    fi

    # Print parsed arguments for verification
    echo "Input file: $INPUT_FILE"
    echo "Output file: $OUTPUT_FILE"
    echo "Key URI: $KEY_URI"
    echo "Certificate file: $CERT_FILE"
    echo "Using SafeNet driver: $USE_SAFENET"
}

parse_args "$@"

DOCKER_IMAGE_NAME="openssl3-pkcs11"

# docker build -t openssl3-pkcs11 .
# docker run -it --device /dev/bus/usb -v /dev/bus/usb:/dev/bus/usb -v /run/pcscd/pcscd.comm:/run/pcscd/pcscd.comm  --privileged openssl3-pkcs11
echo "Building docker image $DOCKER_IMAGE_NAME"
docker build -t $DOCKER_IMAGE_NAME ${THIS_DIR}

if [ "$USE_SAFENET" == "true" ]; then
    echo "Signing with SafeNet USB token PKCS#11 driver"
    PKCS11_MODULE="/usr/lib/libeToken.so"
    PROVIDER="pkcs11"
    OPENSSL_CNF="/workspace/openssl_safenet.cnf"

else
    echo "Signing with Yubikey compatible OpenSC PKCS#11 driver"
    PKCS11_MODULE="/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so"
    PROVIDER="/usr/local/openssl/lib64/ossl-modules/pkcs11.so"
    OPENSSL_CNF="/workspace/openssl_opensc.cnf"
fi

# Example to use PKCS#11 w/ openssl to sign:
#  OPENSSL_CONF=/workspace/openssl_safenet.cnf openssl pkeyutl   -sign   -in /tmp/infile   -out /tmp/openssl_out  -inkey "$KEY_URI" -provider pkcs11

cmd="OPENSSL_CONF=$OPENSSL_CNF osslsigncode sign \
    -provider $PROVIDER \
    -pkcs11module $PKCS11_MODULE \
    -certs /tmp/cert.pem  \
    -key \"$KEY_URI\" \
    -in /tmp/infile -out /tmp/ossl_out \
    -h sha256"

tmp_file=$(mktemp)

echo "using tmp_file $tmp_file"
echo "running command in Docker: $cmd"

# Map in Yubikey or SafeNet device (USB device and PCSCD socket)
# Map in certificate, input file, output file and run command
docker run -it \
    --user $(id -u):$(id -g) \
    --device /dev/bus/usb \
    -v /dev/bus/usb:/dev/bus/usb \
    -v /run/pcscd/pcscd.comm:/run/pcscd/pcscd.comm \
    -v $INPUT_FILE:/tmp/infile \
    -v $tmp_file:/tmp/outfile \
    -v $CERT_FILE:/tmp/cert.pem \
    $DOCKER_IMAGE_NAME \
    /bin/bash -c "openssl x509 -in /tmp/cert.pem -text && ls -al /tmp/infile && $cmd && cp /tmp/ossl_out /tmp/outfile"

if [ ! -f $tmp_file ]; then
    echo "Failed signing $INPUT_FILE!"
    exit -1
fi

# finish by copying the temporary file to the output file
cp -f $tmp_file $OUTPUT_FILE
echo "Successfully signed $INPUT_FILE to $OUTPUT_FILE"
echo "To Validate signed file:"
echo "sbverify --cert $CERT_FILE $OUTPUT_FILE"


