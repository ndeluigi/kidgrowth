<p align="center">
  <img src="assets/logo.svg" alt="kidgrowth logo" width="140" height="140">
</p>

<h1 align="center">kidgrowth</h1>

<p align="center">
  A multilingual R Shiny app to track your children's growth against the WHO standards.
</p>

<p align="center">
  <img alt="R" src="https://img.shields.io/badge/R-Shiny-2c7fb8?logo=r">
  <img alt="Docker" src="https://img.shields.io/badge/Docker-ready-41b6a6?logo=docker&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-green">
  <img alt="Languages" src="https://img.shields.io/badge/i18n-6%20languages-blueviolet">
</p>

---

A **multilingual R Shiny** app (WHO growth charts) to track your children's height, weight and BMI
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
shiny::runApp(".", port = 3838)
```

Then open http://127.0.0.1:3838

## Deploy on Synology (Container Manager)

There are two options. Option **A** is the simplest.

### A) docker-compose project (recommended)

1. Copy the whole project folder to the NAS (e.g. via File Station to
   `/docker/kidgrowth`).
2. Open **Container Manager** → **Project** → **Create**.
3. Set:
   - **Project name**: `kidgrowth`
   - **Path**: the uploaded folder (`/docker/kidgrowth`)
   - **Source**: *Use the existing docker-compose.yml*
4. Start it. On the first run the NAS **builds the image** (downloads the R
   packages: this can take several minutes).
5. Open **http://NAS-IP:3838**

The database lives in `/docker/kidgrowth/data` and is preserved across restarts and
updates.

### B) Manual build via SSH

```bash
cd /volume1/docker/kidgrowth
sudo docker build -t kidgrowth:latest .
sudo docker run -d --name kidgrowth \
  -p 3838:3838 \
  -v /volume1/docker/kidgrowth/data:/app/data \
  --restart unless-stopped \
  kidgrowth:latest
```

## Deploy with Portainer (Stacks)

Because the image is **built from source**, deploy the stack from a Git
repository so Portainer can build it for you.

1. In Portainer go to **Stacks → Add stack** and name it `kidgrowth`.
2. **Build method**: choose **Repository**.
3. Fill in:
   - **Repository URL**: `https://github.com/ndeluigi/kidgrowth`
   - **Repository reference**: `refs/heads/main`
   - **Compose path**: `docker-compose.yml`
4. Click **Deploy the stack**. Portainer clones the repo, builds the image and
   starts the container (the first build downloads R packages and takes a few
   minutes).
5. Open **http://HOST-IP:3838**

> **Persistent data**: the compose file mounts `./data`, which Portainer resolves
> inside the cloned stack directory. To make the database easier to find/back up,
> you can replace the volume line in `docker-compose.yml` with an absolute host
> path, e.g. `- /opt/kidgrowth/data:/app/data`, or a named volume.

If you prefer the **Web editor** method (pasting the compose file), you must use a
**pre-built image** instead of `build: .` — push the image to a registry and
reference it with `image: <registry>/kidgrowth:latest`.

## Notes

- **Port**: defaults to `3838`. To change it, edit `ports` in
  `docker-compose.yml` (e.g. `"8080:3838"`).
- **Backup**: save the `data/growth.sqlite` file.
- **HTTPS / external access**: use the DSM *Reverse Proxy*
  (Control Panel → Login Portal → Advanced → Reverse Proxy) to expose the app
  on a subdomain with a certificate.
- **Disclaimer**: this is a family monitoring tool, **not** a medical device.
  For clinical assessments, consult your pediatrician.
