---
title: Managing OpenVPN certificates with cfssl
kind: article
created_at: 2018-01-08
excerpt: Adventures in switching to cfssl for a distro that uses libressl (which does not play nicely with easy-rsa).
---

I run an instance of OpenVPN for use when I'm out and about on public WiFi, eg. at cafes or airports. Until recently, it ran on a small VPS with Arch Linux x86. Given the deprecation of the x86 architecture by Arch and that I don't run anything of much value there, I decided to give [Void Linux](http://voidlinux.eu) a spin (mostly because I really like [runit](http://smarden.org/runit/), which is the init system in Void). As Void uses libressl which is [known to not play nicely with easy-rsa](https://github.com/OpenVPN/easy-rsa/issues/76), I decided to try managing the CA and client certificates with [cfssl](https://github.com/cloudflare/cfssl).

**As a leading caveat:** Proper security around key handling is an exercise left to the reader, this is merely a guide to be able to replace the basic functionality of `easy-rsa` with `cfssl`. Operations other than issuing keys are also left up to the reader.

As cfssl expects JSON files for configuration, we'll take care of that first (modify as needed, eg. common names and country/organisation values):

```bash
mkdir -p vpn/{config,certs}
cat >vpn/config/csr.json <<CSR
{
    "cn": "My VPN CA",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "DE",
            "O": "OpenVPN"
        }
    ]
}
CSR
cat >vpn/config/ca.json <<CA
{
    "signing": {
        "profiles": {
            "server": {
                "expiry": "43800h",
                "usages": [
                    "digital signature",
                    "key encipherment",
                    "server auth"
                ]
            },
            "client": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "client auth"
                ]
            }
        }
    }
}
CA
```

You'll notice we're using TLS key usage extensions as outlined in [RFC3280](https://www.ietf.org/rfc/rfc3280.txt) to take advantage of things like the OpenVPN client directive `remote-cert-tls server`.

Now we can initialise the CA and generate certificates for the server:

```bash
cfssl genkey -initca vpn/config/csr.json | \
  cfssljson -bare vpn/certs/ca

cfssl gencert -ca vpn/certs/ca.pem \
  -ca-key vpn/certs/ca-key.pem \
  -config=vpn/config/ca.json \
  -profile="server" \
  -hostname="server" \
  vpn/config/csr.json | \
    cfssljson -bare vpn/certs/server
```

Now we can generate certificates for the client. The process is identical to above for the server certificate, only substituting in "client" where appropriate to use the different signing profile. Modify the value of `CLIENT_NAME` as necessary.

```bash
export CLIENT_NAME="client1"
cfssl gencert -ca vpn/certs/ca.pem \
  -ca-key vpn/certs/ca-key.pem \
  -config=vpn/config/ca.json \
  -profile="client" \
  -hostname="${CLIENT_NAME}" \
  vpn/config/csr.json | \
    cfssljson -bare "vpn/certs/${CLIENT_NAME}"
```

You should now have the following files for copying to the server: `ca.pem`, `server.pem` and `server-key.pem`; and `ca.pem`, `client1.pem` and `client1-key.pem` for copying to the client.

Happy VPNing!
