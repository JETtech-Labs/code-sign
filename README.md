# Code Signing for Secure Boot binaries
This project contains a Dockerfile and shell script to sign Secure Boot binaries using 
hardware token keys. Yubikey and SafeNet eTokens have been verified to work.

# Quick Start
Get the KEY_URI from the hardware token using:
```
# For SafeNet:
p11tool --provider  /usr/lib/libeToken.so --list-all-privkeys --login
or
# For Yubikey:
p11tool --provider  /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so --list-all-privkeys --login
```
Extract the Cert from the Token:
```
pkcs11-tool --module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so   -r -y cert -o cert.pem --id <cert_id>
```

Then sign using SafeNet eToken:
```
./code_sign.sh -in  SignableFile.bin -out signed.bin -cert cert.pem -key_uri $KEY_URI -safenet
```

or using Yubikey:
```
./code_sign.sh -in  SignableFile.bin -out signed.bin -cert cert.pem -key_uri $KEY_URI
```

To validate signature:
```
sbverify --cert cert.pem  signed.bin
```

## Secure Boot helpful hints
As of 2025 Microsoft requires using Extend Validation (EV) certs for SHIM bootloader. EV Certs must be stored on a FIPS 140-2 HSM or Token. Secure Boot does NOT support ECDSA signing by default and RSA-2048 EV certs are no longer supported (require RSA-3072+). As of April 2025 Yubikey does not (yet) have a FIPS certified token that supports storing RSA-3072+ - so it is necessary to use SafeNet eTokens which supports FIPS 140-2 storage of RSA-3072+ keys.

There was no way to sign images from an ubuntu 22.04 environment without modifying packages. In order to sign SecureBoot binaries with FIPS 140-2 tokens in a future proof was - we made this container environmnet to help. 

## Details
The shell script will build and launch the container allowing for code signing. 

The Dockerfile builds a minimal Ubuntu 22.04 image and installs necessary base packages. 

The below packages are built from source becasue they are not available pre-built for U22.04:
OpenSSL v3.3
OpenSSL PKCS#11 provider
osslsigncode - perform the actual code signing using OpenSSL + PKCS11 provider
libetoken - SafeNet PKCS11 driver (module)

Note: The ubuntu repo is used for opensc, libp11 and Yubikey pkcs11 drivers. 
