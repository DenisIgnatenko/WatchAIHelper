# AWS Lightsail setup (manual, one time)

Target (architecture section 19): one Lightsail VM running Docker Compose (Caddy, backend, PostgreSQL),
HTTPS on the static IP via a Let's Encrypt IP-address certificate. No domain required.

## 1. Create the instance

1. Open the Lightsail console: <https://lightsail.aws.amazon.com/>.
2. **Create instance**.
3. **Region**: Frankfurt (`eu-central-1`), closest to Denmark.
4. **Platform**: Linux/Unix. **Blueprint**: *OS Only* > the newest **Ubuntu LTS** offered.
5. **SSH key pair**: *Create new* > name `aicopilot` > download the `.pem` file.
   On the Mac:
   ```sh
   mv ~/Downloads/aicopilot*.pem ~/.ssh/aicopilot-lightsail.pem
   chmod 600 ~/.ssh/aicopilot-lightsail.pem
   ```
6. **Plan**: 2 GB RAM (JVM + PostgreSQL need it; 1 GB is too tight). Check the monthly price shown in the console.
7. **Name**: `aicopilot`. **Create instance**.

## 2. Static IP

Instance > **Networking** > **Attach static IP** (create one named `aicopilot-ip`).
Never detach it: the iPhone and Watch apps store this address.
A static IP is free while it is attached to a running instance.

## 3. Firewall

Instance > **Networking** > IPv4 Firewall. Keep exactly:

| Application | Port | Why |
|---|---|---|
| SSH | 22 | Administration (optionally restrict to your IP) |
| HTTP | 80 | Let's Encrypt certificate validation; Caddy redirects to HTTPS |
| HTTPS | 443 | The API |

Do not open PostgreSQL (5432) or the backend port (8080) to the internet.

## 4. Backups

Instance > **Snapshots** > enable **Automatic snapshots** (daily).

## 5. Check access from the Mac

```sh
ssh -i ~/.ssh/aicopilot-lightsail.pem ubuntu@<STATIC_IP> 'uname -a'
```

## 6. Hand over

Send the static IP. Server software (Docker, Compose files, Caddy) is installed by a script
from `deploy/` in Phase 2. The `.pem` key and `backend/.env` never go into git.

## 7. Continuous deployment from GitHub Actions (optional)

`.github/workflows/backend.yml` deploys after green tests on `main`, but only once it is enabled.
It uses a **separate deploy key**, never the Lightsail `.pem`: the key can be revoked on the server at any time
without touching your own access.

1. Create the key on the Mac (no passphrase: it is used by a machine):
   ```sh
   ssh-keygen -t ed25519 -N "" -C github-deploy -f ~/.ssh/aicopilot-github-deploy
   ```
2. Authorise it on the server:
   ```sh
   ssh -i ~/.ssh/aicopilot-lightsail.pem ubuntu@<STATIC_IP> \
    "cat >> ~/.ssh/authorized_keys" < ~/.ssh/aicopilot-github-deploy.pub
   ```
3. GitHub repository > Settings > Secrets and variables > Actions:
   - secret `DEPLOY_SSH_KEY` = contents of `~/.ssh/aicopilot-github-deploy` (the private key);
   - variables `DEPLOY_HOST` = `<STATIC_IP>`, `DEPLOY_ENABLED` = `true`.
4. Optional: Settings > Environments > `production` > Required reviewers, to approve each deploy by hand.

Revoke: delete the `github-deploy` line from `~/.ssh/authorized_keys` on the server and the secret on GitHub.
Port 22 must stay open to the internet for this (GitHub runners have no fixed IP).
