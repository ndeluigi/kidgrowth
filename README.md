<p align="center">
  <img src="assets/logo.svg" alt="kidgrowth logo" width="140" height="140">
</p>

<h1 align="center">kidgrowth</h1>

<p align="center">
  A multilingual app to track your children's growth against the WHO standards.
</p>

<p align="center">
  <a href="https://github.com/ndeluigi/kidgrowth/actions/workflows/docker-publish.yml"><img alt="Build" src="https://github.com/ndeluigi/kidgrowth/actions/workflows/docker-publish.yml/badge.svg"></a>
  <a href="https://github.com/ndeluigi/kidgrowth/pkgs/container/kidgrowth"><img alt="GHCR" src="https://img.shields.io/badge/ghcr.io-kidgrowth-2496ed?logo=docker&logoColor=white"></a>
  <a href="https://github.com/ndeluigi/kidgrowth/releases"><img alt="Release" src="https://img.shields.io/github/v/release/ndeluigi/kidgrowth?color=2c7fb8"></a>
  <img alt="License" src="https://img.shields.io/badge/License-MIT-green">
  <img alt="Languages" src="https://img.shields.io/badge/i18n-6%20languages-blueviolet">
</p>

---

A **multilingual app** (WHO growth charts) to track your children's height, weight and BMI
and compare them against the **WHO growth standards** (0-19 years).

**Available languages** (selectable from the top bar, switched in real time):
English (default), Italian, French, German, Spanish, Portuguese. The interface,
tables, charts, notifications and calendar are all translated.

- **0-5 years** → WHO Child Growth Standards 2006 (BCCG distribution / LMS method)
- **5-19 years** → WHO Growth Reference 2007 (BCPE distribution)
  - WHO *weight-for-age* is only defined up to **10 years**; beyond that, use BMI.
- The reference (2006 or 2007) is chosen **automatically** based on the age
  computed from each child's date of birth.

The calculations (z-scores and percentiles) use the official WHO parameters from
the R package `childsds` and have been verified to match `childsds::sds` exactly.

## Features

- Two (or more) children with name, sex and date of birth — editable in the
  **Children** tab.
- Enter height (cm) and weight (kg) with a date; BMI is computed automatically.
- Three WHO charts with percentiles **P3 / P15 / P50 / P85 / P97**:
  height-for-age, weight-for-age, BMI-for-age, with the child's data points over time.
- **History** table with z-scores and percentiles for each measurement.
- Data stored in a persistent **SQLite** database (`data/growth.sqlite`).

## Project structure

```
kidgrowth/
├── global.R            # libraries, SQLite database, WHO references
├── translations.R      # translation dictionary (6 languages)
├── ui.R                # UI shell (rendered server-side, bslib)
├── server.R            # reactive logic, multilingual UI, charts, CRUD
├── Dockerfile          # image based on rocker/r-ver
├── docker-compose.yml  # service + persistent data volume
├── assets/logo.svg     # project logo
├── LICENSE             # MIT license
└── data/               # database (created on startup, mounted as a volume)
```

## Run locally (to try it)

With R installed:

```r
# once
install.packages(c("shiny","bslib","ggplot2","DBI","RSQLite","DT","childsds"))
# start
shiny::runApp(".", port = 5454)
```

Then open http://127.0.0.1:5454

## Prebuilt image (GitHub Container Registry)

A ready-to-run image is published automatically by GitHub Actions to:

```
ghcr.io/ndeluigi/kidgrowth:latest
```

This is the recommended way to deploy on a NAS: the image is **pulled**, not
built on the device (building R packages on a low-power NAS can take 30+ minutes).

> The first time the image is published, make the GHCR package **public** so it
> can be pulled without authentication:
> GitHub → your profile → **Packages** → `kidgrowth` → **Package settings** →
> **Change visibility** → *Public*.

## Deploy with Portainer (Stacks)

Since we use a prebuilt image, the **Web editor** method is fastest (deploys in seconds).

1. On the NAS, create the data folder (e.g. via File Station): `/volume1/docker/kidgrowth/data`
2. In Portainer go to **Stacks → Add stack**, name it `kidgrowth`.
3. **Build method**: **Web editor**, then paste the contents of `docker-compose.yml`.
4. Click **Deploy the stack** (Portainer pulls `ghcr.io/ndeluigi/kidgrowth:latest`).
5. Open **http://NAS-IP:5454**

To update later: **Stacks → kidgrowth → Pull and redeploy** (or enable re-pull).

## Deploy on Synology (Container Manager)

### Quick (prebuilt image)

1. Create the folder `/volume1/docker/kidgrowth/data` (File Station).
2. **Container Manager → Project → Create**, name `kidgrowth`, and paste the
   `docker-compose.yml` (it references `ghcr.io/ndeluigi/kidgrowth:latest`).
3. Start it, then open **http://NAS-IP:5454**.

### Manual (SSH, prebuilt image)

```bash
sudo docker run -d --name kidgrowth \
  -p 5454:5454 \
  -v /volume1/docker/kidgrowth/data:/app/data \
  --restart unless-stopped \
  ghcr.io/ndeluigi/kidgrowth:latest
```

### Build it yourself (optional)

```bash
cd /volume1/docker/kidgrowth
sudo docker build -t kidgrowth:latest .
```

Then change the `image:` line in `docker-compose.yml` to `kidgrowth:latest`.

## Notes

- **Port**: defaults to `5454`. To change it, edit `ports` in
  `docker-compose.yml` (e.g. `"8080:5454"`).
- **Backup**: save the `data/growth.sqlite` file.
- **HTTPS / external access**: use the DSM *Reverse Proxy*
  (Control Panel → Login Portal → Advanced → Reverse Proxy) to expose the app
  on a subdomain with a certificate.
- **Disclaimer**: this is a family monitoring tool, **not** a medical device.
  For clinical assessments, consult your pediatrician.
