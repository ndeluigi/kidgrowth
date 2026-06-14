# =============================================================================
# Curve di crescita OMS - Logica globale (librerie, database, riferimenti OMS)
# =============================================================================

library(shiny)
library(bslib)
library(ggplot2)
library(DBI)
library(RSQLite)
library(DT)
library(childsds)

# Traduzioni / Translations (multilingua)
source("translations.R", encoding = "UTF-8")

# -----------------------------------------------------------------------------
# Percorso del database (sovrascrivibile via variabile d'ambiente per Docker)
# -----------------------------------------------------------------------------
DATA_DIR <- Sys.getenv("GROWTH_DATA_DIR", unset = "data")
if (!dir.exists(DATA_DIR)) {
  dir.create(DATA_DIR, recursive = TRUE, showWarnings = FALSE)
}
DB_PATH <- file.path(DATA_DIR, "growth.sqlite")

# -----------------------------------------------------------------------------
# Connessione e inizializzazione database
# -----------------------------------------------------------------------------
db_connect <- function() {
  dbConnect(RSQLite::SQLite(), DB_PATH)
}

db_init <- function() {
  con <- db_connect()
  on.exit(dbDisconnect(con))

  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS children (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      name       TEXT NOT NULL,
      sex        TEXT NOT NULL CHECK (sex IN ('male','female')),
      birth_date TEXT NOT NULL
    )")

  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS measurements (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      child_id     INTEGER NOT NULL,
      meas_date    TEXT NOT NULL,
      height_cm    REAL,
      weight_kg    REAL,
      FOREIGN KEY (child_id) REFERENCES children(id) ON DELETE CASCADE
    )")

  # Inserisce due figli di esempio (un maschio, una femmina) se vuoto
  n <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM children")$n
  if (n == 0) {
    today <- Sys.Date()
    dbExecute(con,
      "INSERT INTO children (name, sex, birth_date) VALUES (?, ?, ?)",
      params = list("Child 1", "male", as.character(today - 365 * 5)))
    dbExecute(con,
      "INSERT INTO children (name, sex, birth_date) VALUES (?, ?, ?)",
      params = list("Child 2", "female", as.character(today - 365 * 3)))
  }
}

# Inizializza il database all'avvio dell'app (crea tabelle + dati di esempio)
db_init()

# -----------------------------------------------------------------------------
# Operazioni sui figli
# -----------------------------------------------------------------------------
get_children <- function() {
  con <- db_connect(); on.exit(dbDisconnect(con))
  dbGetQuery(con, "SELECT * FROM children ORDER BY name")
}

add_child <- function(name, sex, birth_date) {
  con <- db_connect(); on.exit(dbDisconnect(con))
  dbExecute(con,
    "INSERT INTO children (name, sex, birth_date) VALUES (?, ?, ?)",
    params = list(name, sex, as.character(birth_date)))
}

update_child <- function(id, name, sex, birth_date) {
  con <- db_connect(); on.exit(dbDisconnect(con))
  dbExecute(con,
    "UPDATE children SET name = ?, sex = ?, birth_date = ? WHERE id = ?",
    params = list(name, sex, as.character(birth_date), id))
}

delete_child <- function(id) {
  con <- db_connect(); on.exit(dbDisconnect(con))
  dbExecute(con, "DELETE FROM measurements WHERE child_id = ?", params = list(id))
  dbExecute(con, "DELETE FROM children WHERE id = ?", params = list(id))
}

# -----------------------------------------------------------------------------
# Operazioni sulle misurazioni
# -----------------------------------------------------------------------------
get_measurements <- function(child_id) {
  con <- db_connect(); on.exit(dbDisconnect(con))
  dbGetQuery(con,
    "SELECT * FROM measurements WHERE child_id = ? ORDER BY meas_date",
    params = list(child_id))
}

add_measurement <- function(child_id, meas_date, height_cm, weight_kg) {
  con <- db_connect(); on.exit(dbDisconnect(con))
  dbExecute(con,
    "INSERT INTO measurements (child_id, meas_date, height_cm, weight_kg)
     VALUES (?, ?, ?, ?)",
    params = list(child_id, as.character(meas_date), height_cm, weight_kg))
}

delete_measurement <- function(id) {
  con <- db_connect(); on.exit(dbDisconnect(con))
  dbExecute(con, "DELETE FROM measurements WHERE id = ?", params = list(id))
}

# -----------------------------------------------------------------------------
# Riferimenti OMS (childsds::who.ref) - copre 0-19 anni
#   - WHO Child Growth Standards 2006 (0-5 anni)
#   - WHO Growth Reference 2007 (5-19 anni)
# L'eta viene espressa in ANNI.
# -----------------------------------------------------------------------------

# Percentili visualizzati sulle curve
PERC_LIST <- c(3, 15, 50, 85, 97)

# Calcola l'eta in anni (decimali) da data di nascita e data misurazione
age_in_years <- function(birth_date, meas_date) {
  as.numeric(difftime(as.Date(meas_date), as.Date(birth_date), units = "days")) / 365.25
}

# Estrae un segmento di parametri (mu, sigma, nu, tau) da un riferimento OMS
# per un dato indicatore e sesso. Le colonne possono essere di tipo "labelled":
# vengono convertite in numerico semplice.
#   - who.ref      : distribuzione BCCG (metodo LMS), 0-5 anni
#   - who2007.ref  : distribuzione BCPE, 5-19 anni (peso solo 5-10 anni)
get_segment <- function(ref, item, sex) {
  partab <- ref@refs[[item]]
  if (is.null(partab)) return(NULL)
  df <- partab@params[[sex]]
  if (is.null(df) || nrow(df) == 0) return(NULL)

  dist <- partab@dist[[sex]]
  pars <- list(
    age   = as.numeric(df$age),
    mu    = as.numeric(df$mu),
    sigma = as.numeric(df$sigma),
    nu    = as.numeric(df$nu)
  )
  if (!is.null(df$tau)) pars$tau <- as.numeric(df$tau)
  list(dist = dist, params = as.data.frame(pars))
}

# Segmenti che coprono 0-19 anni: OMS 2006 (0-5) + OMS 2007 (5-19).
# Per evitare sovrapposizioni il segmento 0-5 viene tagliato all'inizio del 2007.
get_ref_segments <- function(item, sex) {
  young <- get_segment(childsds::who.ref, item, sex)
  old   <- get_segment(childsds::who2007.ref, item, sex)
  segs <- list()
  boundary <- if (!is.null(old)) min(old$params$age) else Inf
  if (!is.null(young)) {
    young$params <- young$params[young$params$age < boundary, , drop = FALSE]
    if (nrow(young$params) > 0) segs <- c(segs, list(young))
  }
  if (!is.null(old)) segs <- c(segs, list(old))
  if (length(segs) == 0) NULL else segs
}

# Argomenti dei parametri (mu/sigma/nu/tau) per una riga o vettore
dist_args <- function(params, idx = NULL) {
  cols <- intersect(c("mu", "sigma", "nu", "tau"), names(params))
  args <- lapply(cols, function(c) if (is.null(idx)) params[[c]] else params[[c]][idx])
  stats::setNames(args, cols)
}

# Valore al percentile (probabilita' prob) per un segmento, vettorizzato sull'eta'
segment_values <- function(seg, prob) {
  qfun <- get(paste0("q", seg$dist), envir = asNamespace("gamlss.dist"))
  args <- c(list(p = prob), dist_args(seg$params))
  do.call(qfun, args)
}

# Genera la tabella dei percentili per un indicatore e un sesso.
# Restituisce un data.frame: age, percentile (fattore), value
percentile_curves <- function(item, sex) {
  segs <- get_ref_segments(item, sex)
  if (is.null(segs)) return(NULL)

  res <- do.call(rbind, lapply(segs, function(seg) {
    do.call(rbind, lapply(PERC_LIST, function(p) {
      data.frame(
        age        = seg$params$age,
        percentile = paste0("P", p),
        value      = segment_values(seg, p / 100)
      )
    }))
  }))
  res$percentile <- factor(res$percentile, levels = paste0("P", PERC_LIST))
  res[!is.na(res$value) & is.finite(res$value), ]
}

# Calcola lo z-score (SDS) e il percentile per un valore osservato.
# Sceglie il segmento OMS appropriato e interpola i parametri all'eta' esatta.
compute_sds <- function(value, age, sex, item) {
  if (is.na(value) || is.na(age) || value <= 0)
    return(c(sds = NA_real_, perc = NA_real_))
  segs <- get_ref_segments(item, sex)
  if (is.null(segs)) return(c(sds = NA_real_, perc = NA_real_))

  # Seleziona il segmento che contiene l'eta' (preferisce 2007 in caso di confine)
  seg <- NULL
  for (s in segs) {
    rng <- range(s$params$age)
    if (age >= rng[1] && age <= rng[2]) seg <- s
  }
  if (is.null(seg)) return(c(sds = NA_real_, perc = NA_real_))

  p <- seg$params
  interp <- function(col) stats::approx(p$age, p[[col]], xout = age)$y
  args <- list(q = value, mu = interp("mu"), sigma = interp("sigma"),
               nu = interp("nu"))
  if (!is.null(p$tau)) args$tau <- interp("tau")

  pfun <- get(paste0("p", seg$dist), envir = asNamespace("gamlss.dist"))
  prob <- do.call(pfun, args)
  c(sds = stats::qnorm(prob), perc = prob * 100)
}
