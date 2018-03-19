---
title: TLS with LetsEncrypt and acmetool on Void Linux
kind: article
created_at: 2018-03-19
excerpt: Easily handling LetsEncrypt certificates using acmetool.
---

Continuing on the [Void Linux](http://voidlinux.eu) theme, I recently wanted to replace a certificate from a commercial CA that fronts my personal IRC bouncer ([znc](https://wiki.znc.in/ZNC)) with one from LetsEncrypt[^fn-1].

I wanted to keep the list of dependencies contained to packages that were available in Void, so I settled on [`acmetool`](https://github.com/hlandau/acme). Install the necessary packages[^fn-2] and configure acmetool (I chose the "proxy" validation option, which is explained below):

```bash
xbps-install acmetool snooze
acmetool quickstart
```

For the proxy validation method, you will need to configure your web server listening on port 80 to proxy requests to a local server on port 402 to serve the challenge file to LetsEncrypt. Using [Caddy](https://caddyserver.com/) as my web server, it was as easy as appending the following line to my `Caddyfile`:

```bash
proxy /.well-known/acme-challenge/ localhost:402
```

Equivalent configurations for nginx and Apache are outlined in the [acmetool user's guide](https://hlandau.github.io/acme/userguide#web-server-configuration-challenges). Now you can request a certificate:

```bash
acmetool want yourdomain.com www.yourdomain.com
```

If all goes well, you should now have certificates available at `/var/lib/acme/live/yourdomain.com` ready for use. These paths will remain "stable" through renewals, so you can reference them in configuration files or symlink them to other locations as required.

Due to the certificates having a short lifetime, you will need to configure an automated way to renew them. As I am using [`snooze`](https://github.com/chneukirchen/snooze) for this purpose, I created the following runit service:

```bash
mkdir -p /etc/sv/acmetool /etc/sv/acmetool/supervise
cat >/etc/sv/acmetool/run <<EOF
#!/bin/sh
exec 2>&1
exec snooze -D/7 acmetool --batch
EOF
chmod +x /etc/sv/acmetool
ln -s /etc/sv/acmetool /var/service/acmetool
```

With this configuration, `snooze` will call `acmetool` every 7 days to renew any soon-to-expire certificates. By design, `snooze` will terminate once `acmetool` has finished doing it's job. With runit supervising the process, it will ensure that `snooze` is restarted each time it ends, ready to take care of all your certificate renewal needs.

As an aside, acmetool also has experimental support for [rootless operation](https://hlandau.github.io/acme/userguide#annex-root-configured-non-root-operation) which I have yet to investigate. This would change the setup outlined in this post slightly[^fn-3], but is probably a good idea.

## Tying it all together with hooks

acmetool has [support for hooks](https://hlandau.github.io/acme/userguide#hooks). By default, at the time of writing the package includes a hook called `haproxy`[^fn-4]. We can use this hook to generate a certificate + private key bundle in the [format required by znc](https://wiki.znc.in/Signed_SSL_certificate). On Void Linux, you can achieve this with the following:

```bash
cat >/etc/default/acme-reload <<EOF
HAPROXY_DAEMONS="${HAPROXY_DAEMONS} znc"
EOF
```

This will only work if your binary is called `znc`. You can alternatively set the environment variable `HAPROXY_ALWAYS_GENERATE` to make acmetool create this new certificate regardless of which daemons you have installed. If you're curious how the sausage is made, read the content of the hook script at `/usr/libexec/acme/hooks/haproxy`. There you will also learn how to have [Diffie-Hellman parameters](https://en.wikipedia.org/wiki/Diffie%E2%80%93Hellman_key_exchange) appended to the bundle.

acmetool will now ensure a certificate is created at `/var/lib/acme/live/yourdomain.com/haproxy` upon each renewal, which you can either copy to another location as a following step (hint: perhaps as an acmetool hook), or symlink it (as I did, because sometimes I'm lazy).

[^fn-1]: In case you haven't heard of [LetsEncrypt](https://letsencrypt.org/) yet, I suggest you read up about the project and then consider [donating](https://letsencrypt.org/donate/) or [getting involved](https://letsencrypt.org/getinvolved/) with the project!
[^fn-2]: [`snooze`](https://github.com/chneukirchen/snooze) is optional if you don't have a working cron setup (like me at the time) and aren't tied to the idea of crontab files. It works wonderfully with runit.
[^fn-3]: At least the web server configuration, as a non-root user could not bind to port 402.
[^fn-4]: The documentation and inline comments mention that this is a legacy name and it may be renamed at some point. Here be dragons, etc.
