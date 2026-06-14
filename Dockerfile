# =============================================================================
# kidgrowth - Docker image (R Shiny)
# Designed for deployment on Synology (Container Manager / docker-compose).
# =============================================================================
FROM rocker/r-ver:4.4.3

# Librerie di sistema necessarie a ggplot2 (rendering PNG) e ai pacchetti R
RUN apt-get update && apt-get install -y --no-install-recommends \
      libxml2-dev \
      libssl-dev \
      libcurl4-openssl-dev \
      libpng-dev \
      libjpeg-dev \
      libtiff5-dev \
      libcairo2-dev \
      libfontconfig1-dev \
      libfreetype6-dev \
    && rm -rf /var/lib/apt/lists/*

# Pacchetti R (binari Posit Package Manager configurati in rocker/r-ver)
RUN install2.r --error --skipinstalled \
      shiny \
      bslib \
      ggplot2 \
      DBI \
      RSQLite \
      DT \
      childsds

# Codice applicazione
WORKDIR /app
COPY global.R ui.R server.R translations.R /app/

# Cartella dati persistente (montata come volume)
RUN mkdir -p /app/data
ENV GROWTH_DATA_DIR=/app/data

EXPOSE 5454

CMD ["R", "-e", "shiny::runApp('/app', host = '0.0.0.0', port = 5454)"]
