#
# docker build -t samngms/yubikey-ca .

# we can't ues 18.04, it ships libykcs11.so.1.3.4 which won't work in here
FROM ubuntu:19.04

ENV YUBI_PIN undefined

RUN apt-get update && apt-get install -y \
  usbutils \
  libccid \
  opensc \
  libpcsclite1 \
  openssl \
  libp11-3 \
  libengine-pkcs11-openssl \
  ykcs11 \
  yubico-piv-tool

RUN mkdir /data

WORKDIR /data

ENV PKCS11_MODULE_PATH=/usr/lib/x86_64-linux-gnu/libykcs11.so

ENTRYPOINT service pcscd restart && bash

