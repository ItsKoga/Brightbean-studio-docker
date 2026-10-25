# Brightbean Studio – Docker & Unraid

Unofficial all-in-one container for [Brightbean Studio](https://github.com/brightbeanxyz/brightbean-studio), the open-source social media management platform, packaged for plain Docker and Unraid.

```
ghcr.io/itskoga/brightbean-studio:latest
```

- **One container**: web app (gunicorn), publishing worker, migrations and an embedded PostgreSQL 16.
- **External database optional**: set `DATABASE_URL` and the embedded PostgreSQL is skipped.
- **Always current**: GitHub Actions checks upstream `main` daily and only rebuilds when there is a new commit.
- **Secrets handled**: `SECRET_KEY` and `ENCRYPTION_KEY_SALT` are generated on first start and stored in `/config/secrets.env`.

## Tags

| Tag | Meaning |
| --- | --- |
| `latest` | Newest build of upstream `main` |
| `sha-abc1234` | Built from that upstream commit (pin this for reproducible installs) |
| `YYYYMMDD` | Build date |
| `vX.Y.Z` | Added automatically if upstream ever tags a release |

Images are `linux/amd64` only.

## Unraid

**Option A – template repository:** *Docker → Template Repositories*, add

```
https://github.com/ItsKoga/Brightbean-studio-docker
```

then *Add Container* → pick **brightbean-studio**.

**Option B – manual:** copy [`unraid/brightbean-studio.xml`](unraid/brightbean-studio.xml) to `/boot/config/plugins/dockerMan/templates-user/my-brightbean-studio.xml` and pick it under *Add Container*.

Set at least `APP_URL` (for example `http://192.168.1.10:8000`, or your `https://` domain behind a reverse proxy).

## Docker / Compose

```bash
docker run -d --name brightbean-studio -p 8000:8000 \
  -e APP_URL=http://localhost:8000 \
  -v ./data/config:/config -v ./data/media:/app/media \
  ghcr.io/itskoga/brightbean-studio:latest
```

Or use [`docker-compose.yml`](docker-compose.yml).

## First steps

1. Open the web UI and sign up. With the default `SIGNUP_MODE=open` the first account can register directly. Afterwards switch to `invite` or `closed`.
2. Create a Django admin (for `/admin/` and platform credentials per organization):
   ```bash
   docker exec -it brightbean-studio /usr/local/bin/bb-run python manage.py createsuperuser
   ```
3. Configure the social platform apps (see the upstream README) through the `PLATFORM_*` variables or in `/admin/`.

## Configuration

All upstream variables from [`.env.example`](https://github.com/brightbeanxyz/brightbean-studio/blob/main/.env.example) are passed through. Container-specific ones:

| Variable | Default | Description |
| --- | --- | --- |
| `APP_URL` | `http://localhost:8000` | Public URL; its scheme controls secure cookies/HSTS |
| `ALLOWED_HOSTS` | host of `APP_URL`, `localhost`, `127.0.0.1` | Comma separated |
| `DATABASE_URL` | *(empty → embedded)* | External PostgreSQL |
| `PUID` / `PGID` | `99` / `100` | User the services run as |
| `SECURE_SSL_REDIRECT` | `false` | Redirect HTTP→HTTPS inside Django |
| `CSRF_TRUSTED_ORIGINS` | origin of `APP_URL` | Extra trusted origins |
| `GUNICORN_WORKERS` / `GUNICORN_THREADS` | `2` / `4` | Budget about 250 MB RAM per worker |
| `EMAIL_BACKEND_TYPE` | `smtp` if `EMAIL_HOST` is set, else `console` | `console` only writes mails to the log |
| `LOG_LEVEL` | `WARNING` | Root log level |

### Volumes

| Path | Content |
| --- | --- |
| `/config` | `secrets.env` + embedded database (`postgres/`). **Back it up.** Losing `ENCRYPTION_KEY_SALT` makes stored platform tokens unreadable. |
| `/app/media` | Uploaded images and videos |

### HTTPS / reverse proxy

Social platforms only allow OAuth callbacks and fetch media from a **public HTTPS** URL. Put the container behind SWAG, Nginx Proxy Manager, Traefik or a Cloudflare Tunnel, forward `X-Forwarded-Proto`, and set `APP_URL=https://studio.example.com`. Plain `http://IP:8000` is fine for trying it out on the LAN.

### Backups of the embedded database

```bash
docker exec brightbean-studio /usr/local/bin/bb-run pg_dump -d brightbean -h /run/postgresql -U postgres > brightbean.sql
```

## How the build works

[`.github/workflows/build.yml`](.github/workflows/build.yml):

1. Resolves the upstream `main` commit and compares it with the `io.brightbean.upstream.revision` label of the published `latest` image. Scheduled runs stop here when nothing changed. Pushes and manual runs always build.
2. Builds upstream's own `Dockerfile` as the base image, then this repo's [`Dockerfile`](Dockerfile) on top (PostgreSQL, supervisor, entrypoint, [settings override](rootfs/app-overlay/config/settings/container.py)).
3. Starts the image and waits for `/health/` before pushing to GHCR.

Local build: `make build && make run` (`PLATFORM=linux/amd64` to cross-build).

### One-time setup after forking

- After the first successful run, set the package to **public**: *GitHub profile → Packages → brightbean-studio → Package settings → Change visibility*.
- GitHub disables scheduled workflows after 60 days without repository activity. Re-enable it in the *Actions* tab if that happens.

## License

Brightbean Studio is licensed under AGPL-3.0, and so is this packaging. This project is not affiliated with Brightbean.
