# 2. Google

COMBIND stores its encrypted pieces in Google Drive. For that, you create a **Google OAuth
client** once: it is free, and needs no review by Google, because COMBIND asks only for the
smallest access — `drive.file`, the files COMBIND itself creates, nothing else of yours.

Below, `cloud.203-0-113-10.nip.io` is the example's user host (`COMBIND_USER_HOST` in your
`deploy/site.env`): use yours.

## Create the client (about 10 minutes)

1. Open <https://console.cloud.google.com/> with any of your Google accounts and create a project,
   e.g. *COMBIND*.
2. **APIs & Services → Library**: enable the **Google Drive API**.
3. **Google Auth Platform → Get started**: app name *SYCLONE CLOUD*, your support e-mail,
   audience **External**, your contact e-mail.
4. **Clients → Create client → Web application.** Authorised redirect URI:
   `https://cloud.203-0-113-10.nip.io/v1/sources/google/callback`.
   Download the JSON file: it holds the client's secret, so keep it private.
5. **Branding**: *Application home page* `https://cloud.203-0-113-10.nip.io/` and *Privacy policy*
   `https://cloud.203-0-113-10.nip.io/privacy.html` (your server serves both). Google fills in the
   authorised domain from the redirect URI. **Do not upload a logo** — a logo makes Google require
   a review. Save.
6. **Audience → Publish app**, and confirm: the status must be **In production**. (In *Testing*,
   Google ends every connection after seven days.)

## Give it to your server

On the server, add the client's ID and secret to `/etc/combind/hub.toml`:

```sh
ssh root@203.0.113.10
nano /etc/combind/hub.toml
```

```toml
[google]
client_id = "123456789012-abc123.apps.googleusercontent.com"
client_secret = "GOCSPX-your-secret"
```

Save, then restart the service:

```sh
systemctl restart combind-hub
```

## Connect your Google accounts

Sign in at `https://cloud.203-0-113-10.nip.io` → **Google accounts → Connect account**, and sign in
to each Google account you want in the pool — yours, and your family's with their permission.

Google may show *"Google hasn't verified this app"*: choose
**Advanced → Go to SYCLONE CLOUD**. That is expected for a private app and changes nothing
about safety.

COMBIND keeps 6 GB free in every account, so Gmail and Google Photos keep working.

> If Google refuses the nip.io address, a free DuckDNS name (e.g. `alex-cloud.duckdns.org`) works
> the same way: point it at the server, put it in `deploy/site.env`, run
> `deploy/deploy.sh install` again, and change the host names in `/etc/combind/hub.toml` too.

Next: **[3. The Mac](mac.md)**.
