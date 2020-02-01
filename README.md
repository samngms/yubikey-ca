
# Running Yubi docker

```sh
$ lsusb
Bus 004 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 003 Device 005: ID 1050:0407 Yubico.com Yubikey 4 OTP+U2F+CCID
Bus 003 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 002 Device 002: ID 0bda:0316 Realtek Semiconductor Corp. 
Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 001 Device 005: ID 138a:0097 Validity Sensors, Inc. 
Bus 001 Device 004: ID 13d3:5619 IMC Networks 
Bus 001 Device 003: ID 8087:0a2b Intel Corp. 
Bus 001 Device 002: ID 046d:c52f Logitech, Inc. Unifying Receiver
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
# in the above case, my Yubikey is in /dev/bus/usb/003/005
$ docker run -it --device=/dev/bus/usb/003/005 -v $(pwd):/data samngms/yubikey-ca
```

# Setting up Root CA

Since we need to backup our master key, we cannot create the private key inside Yubikey, we need to create the private key off-line and then import the key into Yubikey. Note we HAVE TO use RSA, otherwise, we have problem using the key performing signature via PKCS11 in later steps.

```sh
# generate private key, openssl will prompt for password to encrypt the private key
$ openssl req -x509 -newkey rsa:2048 -days 100000 -config root-ca.conf -keyout root.key -out root.crt 
# import key and certificate into yubike, in here I use slot 9c, which is Digital Signature
$ yubico-piv-tool -a import-key -s 9c -i root.key
$ yubico-piv-tool -a import-certificate -s 9c -i root.crt
$ yubico-piv-tool -a status -s 9c
# to view the content of the ca-cert
$ openssl x509 -text -in root.crt
```
​
# Setting up Intermediate CA(s)

NOTE: the root CA and the Intermedia CA are two diffrenent Yubikey (if you want to use the same, then you need to change one of the slot number)

## Generate private key and CSR

For my use case, we don't backup the Intermediate CA keys, we will use Yubikey directly. Since we can have more than one Intermediate CAs, key lost is not a fatal issue. 

Note:
1. We can only use RSA, ECC is not supported in some of the subsequent steps
2. We `MUST` use pkcs11-tool to create the key, otherwise, the key can't be use in the openssl step

```sh
# 1. you don't need the next line if you are using my docker image (already exported)
$ export PKCS11_MODULE_PATH=/usr/lib/x86_64-linux-gnu/libykcs11.so
$ pkcs11-tool --module $PKCS11_MODULE_PATH -k --key-type rsa:2048 --usage-sign --login --id 02 --login-type so --so-pin 010203040506070801020304050607080102030405060708
# need to use pkcs15 instead of 11, otherwise, it won't show the info
$ pkcs15-tool --list-keys
# slot 9c is actually id 02
$ openssl req -new -engine pkcs11 -keyform engine -key 02 -config inter-ca.conf -out inter.csr
$ openssl req -in inter.csr -noout -text
```

## Use Root CA key to sign the Intermediate CA CSR

Plugin the Root CA Yubikey to sign the Intermediate CA CSR.

```sh
$ openssl x509 -engine pkcs11 -CAkeyform engine -CAkey id_2 -sha256 -CA root.crt -CAcreateserial -req -days 3650 -extfile root-ca.conf -extensions inter_ca -in inter.csr -out inter.crt
```

Unplug the Root CA Yubikey and plugin the Intermediate CA Yubikey to import the signed certificate into the Intermedidate CA Yubikey.

```sh
$ yubico-piv-tool -a import-certificate -s 9c -i inter.crt
$ yubico-piv-tool -a status -s 9c
```


# Signing an end-user cert

Now we can use the Intermediate CA Yubikey to sign user certs. In here, we generate a test cert and have the Intermediate CA signing the CSR.

```sh
# create a key and a csr
$ openssl req -new -newkey rsa:2048 -nodes -keyout enduser.key -out enduser.csr
```

And then use the Intermediate CA Yubikey to sign the CSR.

```sh
$ openssl x509 -engine pkcs11 -CAkeyform engine -CAkey id_2 -sha256 -CA inter.crt -CAcreateserial -req -days 3560 -extfile inter-ca.conf -extensions server_cert -in enduser.csr -out enduser.crt
```

```sh
# ues the following command to validate a end user cert. And if the domain is not permitted, it will not be accepted.
$ openssl verify -CAfile root.crt -untrusted inter.crt enduser.crt
C = AU, ST = Some-State, O = Internet Widgits Pty Ltd, CN = www.google.com
error 47 at 0 depth lookup: permitted subtree violation
error enduser.crt: verification failed
```

## Reference Information

### Default PIN/PUN/Management Key

| type | value |
|------| ------|
| PIN  | 123456 |
| PUN  | 12345678 |
| management key | 010203040506070801020304050607080102030405060708 |

Reference: [https://developers.yubico.com/yubico-piv-tool/YKCS11](https://developers.yubico.com/yubico-piv-tool/YKCS11/)

### Slot to ID mapping

| ykcs11 id | PIV |
|-----------|-----|
| 1         | 9a  |
| 2         | 9c  |
| 3         | 9d  |
| 4         | 9e  |
| 5-24      | 82-95 |
| 25        | f9 |

Reference: [https://developers.yubico.com/yubico-piv-tool/YKCS11](https://developers.yubico.com/yubico-piv-tool/YKCS11/)