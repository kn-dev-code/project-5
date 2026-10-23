# Deploying to a Google Cloud e2-micro

This runs the server on Google Cloud's free e2-micro machine, with https from
Caddy. Expect about $3.65 a month for the machine's public IPv4 address; the
machine and disk themselves are covered by the free tier if you follow the
settings below exactly. Check
[Google's free tier page](https://cloud.google.com/free/docs/free-cloud-features#compute)
first, since the limits change.

## 1. Create the project

1. Sign in at <https://console.cloud.google.com> and create a project, for
   example `football-winner`.
2. Turn on billing for it. The free tier needs a billing account even when
   nothing is charged.
3. Under **Billing → Budgets & alerts**, add a budget of about $5 with email
   alerts, so a wrong setting can't surprise you.
4. Open **Compute Engine** once so Google turns on its API.

## 2. Create the machine

These settings are what keep it free. In the console, **Compute Engine → VM
instances → Create instance**:

| Setting | Value |
| --- | --- |
| Region | `us-central1`, `us-west1` or `us-east1` (only these are free) |
| Machine type | `e2-micro` |
| Boot disk | Debian 12, **Standard persistent disk**, 30 GB. The default "Balanced" disk is *not* free. |
| Firewall | Tick **Allow HTTP traffic** and **Allow HTTPS traffic** |

Then, under **VPC network → IP addresses**, find the machine's external
address and **Promote to static**, so it doesn't change when the machine
restarts.

Or, with the [gcloud CLI](https://cloud.google.com/sdk/docs/install):

```sh
gcloud config set project football-winner
gcloud compute addresses create football-ip --region=us-central1
gcloud compute instances create football-server \
  --zone=us-central1-a --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --boot-disk-size=30GB --boot-disk-type=pd-standard \
  --address=football-ip --tags=http-server,https-server
gcloud compute firewall-rules create allow-web \
  --allow=tcp:80,tcp:443 --target-tags=http-server,https-server
gcloud compute addresses describe football-ip --region=us-central1 \
  --format='value(address)'
```

The last command prints the address you'll need next.

## 3. Point a domain at it

The app needs an https address, and https needs a domain name. If you don't
have one, get a free subdomain:

1. Sign in at <https://www.duckdns.org>.
2. Add a subdomain, e.g. `footballwinner`, and set its IP to the machine's
   static address.

You now have `footballwinner.duckdns.org`.

## 4. Install Docker and start the server

Connect to the machine with the **SSH** button in the console, or
`gcloud compute ssh football-server --zone=us-central1-a`, then:

```sh
# The machine has 1 GB of memory; swap gives the build room to compile.
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER && newgrp docker

# The code
sudo apt-get install -y git
git clone https://github.com/kn-dev-code/project-5.git
cd project-5/deploy
cp .env.example .env
nano .env          # set DOMAIN=footballwinner.duckdns.org

docker compose up -d --build
```

The first build takes several minutes on this small machine. If the repository
is private, `git clone` asks for a username and a
[personal access token](https://github.com/settings/tokens) with read access to
it, not your password.

## 5. Check it

```sh
docker compose logs -f server     # should say it's listening, no feed errors
curl https://footballwinner.duckdns.org/healthz   # prints "ok"
curl https://footballwinner.duckdns.org/v1/games  # this week's games
```

If https fails, check `docker compose logs caddy`. It's usually the domain not
pointing at the machine yet, or ports 80/443 not open.

## 6. Point the app at it

- **Locally:** `flutter run --dart-define=API_URL=https://footballwinner.duckdns.org`
- **CI builds:** in GitHub, **Settings → Secrets and variables → Actions →
  Variables**, add `API_URL` = `https://footballwinner.duckdns.org`. The next
  APK build uses it.

## Updating

```sh
cd ~/project-5 && git pull && cd deploy && docker compose up -d --build
```

Accounts and bets live in the `football-data` volume and survive updates.

## Backups

Copy the data off the machine now and then:

```sh
docker compose cp server:/data ./backup-$(date +%F)
```

## Watching costs

Outgoing traffic is free up to 1 GB a month from North America, and Caddy's
compression keeps each game list small. Keep an eye on **Billing →
Reports** for the first month.
