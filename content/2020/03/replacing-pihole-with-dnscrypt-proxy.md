---
title: Replacing Pi-hole with dnscrypt-proxy
kind: article
created_at: 2020-03-06
excerpt: From Rube Goldberg machine to... well, not.
---

Like many, I run my own instance of [Pi-hole](https://pi-hole.net/) at home to make an ever-increasing portion of the internet less annoying to use. However, I had begun to acquire a small laundry list of issues[^fn-1]:

1. The main functions of the web interface are [broken on PHP 7.4](https://github.com/pi-hole/pi-hole/issues/3039)[^fn-2]. This means I had to resort to using the `pihole` CLI tool for simple things such as enabling/disabling blocking[^fn-3], or go spelunking in a multitude of config files to change simple settings. At some point, this meant that my configuration files become so messed up between PHP failing to update them and editing them by hand that edits I made by hand had no effect until I deleted some of the files completely and let Pi-hole recreate them after a restart.
1. Pi-hole was the only reason I had PHP installed. Having to downgrade and keep PHP held at version 7.3.12 seemed counter-intuitive to the reason one uses a [rolling-release OS](https://archlinuxarm.org/) in the first place.
1. Not unsurprisingly, Pi-hole does not [officially support Arch Linux](https://docs.pi-hole.net/main/prerequesites/#supported-operating-systems). I'm not adverse to a few rough edges and the well-maintained AUR packages ([pi-hole-server](https://aur.archlinux.org/packages/pi-hole-server/), [pi-hole-ftl](https://aur.archlinux.org/packages/pi-hole-ftl/)) made it relatively easy to run, but every now and then a small change would mean having a subtly broken Pi-hole instance for some hours/days, figuring the issue out myself or doing the downgrade dance.

As I listlessly scrolled through my Twitter feed this morning, I came across this short thread:

<blockquote class="twitter-tweet" data-dnt="true" data-theme="light"><p lang="en" dir="ltr">dnsmasq is randomly segfaulting because a DNS response looks funny. This is a reminder that you should NEVER use dnsmasq.<br><br>The only reason there isn&#39;t a pile of sev:crit CVEs is that it&#39;s impossible to fuzz because the logic, state, and I/O are mixed with the parsing. <a href="https://t.co/zPNwYx2Uuk">https://t.co/zPNwYx2Uuk</a></p>&mdash; Filippo Valsorda (@FiloSottile) <a href="https://twitter.com/FiloSottile/status/1235044425509810176?ref_src=twsrc%5Etfw">March 4, 2020</a></blockquote> <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script> 

Combined with the above issues and Pi-hole being the only reason I even had PHP installed in the first place, it was more than enough incentive[^fn-4] to replace it with `dnscrypt-proxy`. Setup was easy with a combination of the ever great [Archwiki article](https://wiki.archlinux.org/index.php/Dnscrypt-proxy) plus the [project documentation on GitHub](https://github.com/DNSCrypt/dnscrypt-proxy/wiki). Within a few minutes I had a DNS server answering queries, albeit unfiltered.

## Managing blacklists

Blacklist management in Pi-hole is automatically managed by a process called [Gravity](https://docs.pi-hole.net/core/pihole-command/#gravity) which updates by default on a weekly basis.

With dnscrypt-proxy, a little more setup is required, but with systemd (or your time-based task scheduler of choice) it's just as simple to achieve the same. The project's GitHub repo includes a handy Python script: [`generate-domains-blacklist`](https://github.com/DNSCrypt/dnscrypt-proxy/tree/master/utils/generate-domains-blacklists)[^fn-5]. This is the script we will use to perform updates.

Before we begin, there are some minor caveats to note: most paths below are specific to those provided by the Arch Linux package. Some things you may need to modify include:
* creating a configuration file. The [default provided](https://raw.githubusercontent.com/DNSCrypt/dnscrypt-proxy/master/utils/generate-domains-blacklists/domains-blacklist.conf) is a great starting point.
* the `GENERATOR` variable in the wrapper script.
* the `WorkingDirectory` in the systemd unit. Ideally your configuration files for `generate-domains-blacklist` should be in this directory so they are found without needing to specify absolute paths.

We'll need three things: a small wrapper script around `generate-domains-blacklist`, a systemd service to actually run the updates and a timer to trigger it on a schedule.


```bash
cat >/usr/local/sbin/dnscrypt-proxy-blacklist-up <<EOF
#!/bin/bash
#
# Perform updates of dnscrypt-proxy blacklist files.

set -o pipefail

GENERATOR="/usr/bin/generate-domains-blacklist"
BLACKLIST_FILE="$1"

function err() {
  echo "error: $*" >&2
  exit 1
}

if [[ -z "${BLACKLIST_FILE}" ]]; then
  err "please specify a blacklist file, eg: $0 /etc/dnscrypt-proxy/blacklist.txt"
fi

if [[ ! -x "${GENERATOR}" ]]; then
  err "${GENERATOR} does not exist, or is not executable"
fi

BLACKLIST_TMP="$(mktemp)"
trap 'rm -rf "${BLACKLIST_TMP}"' EXIT

echo "updating blacklist"

if ! "${GENERATOR}" 2>/dev/null > "${BLACKLIST_TMP}"; then
  err "failed to generate blacklist"
fi

if ! mv "${BLACKLIST_TMP}" "${BLACKLIST_FILE}"; then
  err "failed to store new blacklist file"
fi

if ! chmod 0644 "${BLACKLIST_FILE}" ; then
  err "failed to set permissions on blacklist file"
fi

echo "successfully updated blacklist file"
exit 0
EOF
```

```bash
cat >/etc/systemd/system/dnscrypt-proxy-blacklist-up.service <<EOF
[Unit]
Description=dnscrypt-proxy blacklist updater

[Service]
Type=oneshot
WorkingDirectory=/usr/share/dnscrypt-proxy/utils/generate-domains-blacklists
ExecStart=/usr/local/sbin/dnscrypt-proxy-blacklist-up /etc/dnscrypt-proxy/blacklist.txt
ExecStartPost=/usr/bin/systemctl restart dnscrypt-proxy
EOF
```

Once that's all in place, run the service once to ensure it works before creating the timer:

```bash
$ sudo systemctl daemon-reload
$ sudo systemctl start dnscrypt-proxy-blacklist-up
```

If everything works as expected, create the timer and check it's enabled correctly:

```bash
cat >/etc/systemd/system/dnscrypt-proxy-blacklist-up.timer <<EOF
[Unit]
Description=Weekly dnscrypt-proxy blacklist update

[Timer]
OnCalendar=weekly
AccuracySec=3h
Persistent=true
EOF
```

```bash
$ sudo systemctl daemon-reload
$ systemctl list-timers dnscrypt-proxy-blacklist-up

NEXT                         LEFT        LAST PASSED UNIT                              ACTIVATES
Mon 2020-03-09 00:00:00 PDT  2 days left n/a  n/a    dnscrypt-proxy-blacklist-up.timer dnscrypt-proxy-blacklist-up.service
```

## Wrapping up

At this point, I now have an equivalent setup to Pi-hole with fewer moving parts. So far everything seems to be working great with mostly the default configuration plus a handful of additional filters. Setting up [forwarding](https://github.com/DNSCrypt/dnscrypt-proxy/wiki/Forwarding) for some locally-hosted zones I already had backed by CoreDNS was a breeze too. In the past I had Pi-hole forwarding all queries to CoreDNS which would then forward to a set of resolvers using DNS over TLS, but I've decided to give the native DNS over HTTPS support in dnscrypt-proxy a try instead.

Also, I can't lie that uninstalling PHP and it's band of extensions was a great feeling. 👋

*[AUR]: Arch User Repository
[^fn-1]: All more or less self-inflicted, but I digress.
[^fn-2]: Don't even get me started on how the PHP scripts are mostly lazy wrappers around `system()` calls to the CLI tool.
[^fn-3]: I had to do this a surprising amount. It seems there is not an easy way to block the ridiculous ads on my "smart" TV without having the Netflix app often fail to login when starting up.
[^fn-4]: The fact it's written in Go and is well-packaged for Arch Linux is the icing on the cake.
[^fn-5]: It just so happens to also be included in the Arch Linux package, complete with a handy symlink into `/usr/bin`. Wonderful.
