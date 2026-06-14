# =============================================================================
# WHO Growth Charts - server logic (multilingual)
# =============================================================================

# Builds the entire translated UI for a given language.
build_app_ui <- function(lang, children, sel_child) {
  t <- function(k) tr_get(lang, k)
  date_lang <- unname(LANG_DATE[lang]); if (is.na(date_lang)) date_lang <- "en"

  child_choices <- if (nrow(children)) stats::setNames(children$id, children$name) else NULL
  sel <- if (!is.null(sel_child) && sel_child %in% children$id) sel_child
          else if (nrow(children)) children$id[1] else NULL
  sex_choices <- stats::setNames(c("male", "female"), c(t("opt_male"), t("opt_female")))

  page_navbar(
    title = t("app_title"),
    theme = bs_theme(version = 5, bootswatch = "minty", primary = "#2c7fb8"),
    fillable = FALSE,

    nav_panel(
      title = t("nav_growth"),
      layout_sidebar(
        sidebar = sidebar(
          width = 320,
          title = t("sidebar_title"),
          selectInput("child", t("lbl_child"), choices = child_choices, selected = sel),
          uiOutput("child_info"),
          hr(),
          h6(t("new_meas")),
          dateInput("meas_date", t("lbl_date"), value = Sys.Date(),
                    format = "dd/mm/yyyy", language = date_lang, weekstart = 1),
          numericInput("height_cm", t("lbl_height"), value = NA,
                       min = 30, max = 220, step = 0.1),
          numericInput("weight_kg", t("lbl_weight"), value = NA,
                       min = 1, max = 150, step = 0.1),
          actionButton("add_meas", t("btn_add_meas"),
                       class = "btn-primary", icon = icon("plus")),
          div(class = "text-muted small mt-2", t("compare_note"))
        ),
        layout_columns(
          col_widths = c(4, 4, 4),
          value_box(title = t("vb_height"), value = textOutput("vb_height"),
                    showcase = icon("ruler-vertical"), theme = "primary",
                    p(textOutput("vb_height_perc"))),
          value_box(title = t("vb_weight"), value = textOutput("vb_weight"),
                    showcase = icon("weight-scale"), theme = "info",
                    p(textOutput("vb_weight_perc"))),
          value_box(title = t("vb_bmi"), value = textOutput("vb_bmi"),
                    showcase = icon("calculator"), theme = "secondary",
                    p(textOutput("vb_bmi_perc")))
        ),
        navset_card_tab(
          title = t("curves_card"),
          nav_panel(t("tab_height"), plotOutput("plot_height", height = "460px")),
          nav_panel(t("tab_weight"), plotOutput("plot_weight", height = "460px")),
          nav_panel(t("tab_bmi"),    plotOutput("plot_bmi", height = "460px"))
        )
      )
    ),

    nav_panel(
      title = t("nav_history"),
      card(
        card_header(t("history_header")),
        DT::DTOutput("meas_table"),
        div(class = "mt-2",
            actionButton("del_meas", t("btn_del_meas"),
                         class = "btn-outline-danger btn-sm", icon = icon("trash")))
      )
    ),

    nav_panel(
      title = t("nav_children"),
      layout_columns(
        col_widths = c(5, 7),
        card(
          card_header(t("children_addedit")),
          textInput("c_name", t("lbl_name")),
          selectInput("c_sex", t("lbl_sex"), choices = sex_choices),
          dateInput("c_birth", t("lbl_birth"), value = Sys.Date() - 365 * 3,
                    format = "dd/mm/yyyy", language = date_lang, weekstart = 1,
                    startview = "decade"),
          div(
            actionButton("c_add", t("btn_add"), class = "btn-success",
                         icon = icon("user-plus")),
            actionButton("c_update", t("btn_update"), class = "btn-primary",
                         icon = icon("save")),
            actionButton("c_delete", t("btn_delete"), class = "btn-outline-danger",
                         icon = icon("user-minus"))
          ),
          div(class = "text-muted small mt-2", t("select_row_hint"))
        ),
        card(
          card_header(t("children_header")),
          DT::DTOutput("children_table")
        )
      )
    ),

    nav_spacer(),
    nav_item(selectInput("lang", NULL, choices = LANG_CHOICES,
                         selected = lang, width = "150px")),
    nav_item(tags$span(class = "navbar-text small", t("navbar_note")))
  )
}

server <- function(input, output, session) {

  # Trigger reattivi per ricaricare dati dopo modifiche
  rv <- reactiveValues(children = 0, meas = 0)

  # Lingua selezionata e helper di traduzione
  lang <- reactive({
    l <- input$lang
    if (is.null(l) || !(l %in% names(TR))) DEFAULT_LANG else l
  })
  t <- function(key) tr_get(lang(), key)

  # ---------------------------------------------------------------------------
  # Elenco figli
  # ---------------------------------------------------------------------------
  children_df <- reactive({
    rv$children
    get_children()
  })

  # ---------------------------------------------------------------------------
  # UI tradotta (ricostruita al cambio di lingua o dell'elenco figli)
  # ---------------------------------------------------------------------------
  output$app_ui <- renderUI({
    build_app_ui(lang(), children_df(), isolate(input$child))
  })

  current_child <- reactive({
    req(input$child)
    df <- children_df()
    row <- df[df$id == as.integer(input$child), , drop = FALSE]
    if (nrow(row) == 0) return(NULL)
    row[1, ]
  })

  # ---------------------------------------------------------------------------
  # Misurazioni del figlio selezionato (con et\u00e0, IMC, z-score, percentili)
  # ---------------------------------------------------------------------------
  meas_df <- reactive({
    rv$meas
    child <- current_child()
    req(child)
    m <- get_measurements(child$id)
    if (nrow(m) == 0) {
      return(data.frame())
    }
    m$age <- age_in_years(child$birth_date, m$meas_date)
    m$bmi <- ifelse(!is.na(m$height_cm) & m$height_cm > 0 & !is.na(m$weight_kg),
                    m$weight_kg / (m$height_cm / 100)^2, NA_real_)

    sex <- child$sex
    # z-score e percentili per ogni indicatore
    hp <- mapply(function(v, a) compute_sds(v, a, sex, "height"),
                 m$height_cm, m$age)
    wp <- mapply(function(v, a) compute_sds(v, a, sex, "weight"),
                 m$weight_kg, m$age)
    bp <- mapply(function(v, a) compute_sds(v, a, sex, "bmi"),
                 m$bmi, m$age)

    m$height_sds  <- hp["sds", ];  m$height_perc <- hp["perc", ]
    m$weight_sds  <- wp["sds", ];  m$weight_perc <- wp["perc", ]
    m$bmi_sds     <- bp["sds", ];  m$bmi_perc    <- bp["perc", ]
    m[order(m$meas_date), ]
  })

  last_meas <- reactive({
    m <- meas_df()
    if (nrow(m) == 0) return(NULL)
    m[nrow(m), ]
  })

  # Formattazione data in base alla lingua
  fmt_date <- function(d) {
    format(as.Date(d), if (lang() == "en") "%Y-%m-%d" else "%d/%m/%Y")
  }

  # ---------------------------------------------------------------------------
  # Info figlio nella sidebar
  # ---------------------------------------------------------------------------
  output$child_info <- renderUI({
    child <- current_child()
    if (is.null(child)) return(NULL)
    age <- age_in_years(child$birth_date, Sys.Date())
    sex_lbl <- if (child$sex == "male") t("opt_male") else t("opt_female")
    tagList(
      tags$small(
        sprintf("%s \u2022 %s %s \u2022 %.1f %s",
                sex_lbl, t("info_born"), fmt_date(child$birth_date),
                age, t("info_years"))
      )
    )
  })

  # ---------------------------------------------------------------------------
  # Value box (ultima misurazione)
  # ---------------------------------------------------------------------------
  fmt_perc <- function(p) {
    if (is.null(p) || is.na(p)) return(t("perc_na"))
    sprintf("%s %d (z = %s)", t("perc_label"), round(p),
            formatC(stats::qnorm(p / 100), format = "f", digits = 2))
  }

  output$vb_height <- renderText({
    m <- last_meas(); if (is.null(m) || is.na(m$height_cm)) return("\u2013")
    sprintf("%.1f cm", m$height_cm)
  })
  output$vb_height_perc <- renderText({
    m <- last_meas(); if (is.null(m)) return(""); fmt_perc(m$height_perc)
  })
  output$vb_weight <- renderText({
    m <- last_meas(); if (is.null(m) || is.na(m$weight_kg)) return("\u2013")
    sprintf("%.1f kg", m$weight_kg)
  })
  output$vb_weight_perc <- renderText({
    m <- last_meas(); if (is.null(m)) return(""); fmt_perc(m$weight_perc)
  })
  output$vb_bmi <- renderText({
    m <- last_meas(); if (is.null(m) || is.na(m$bmi)) return("\u2013")
    sprintf("%.1f", m$bmi)
  })
  output$vb_bmi_perc <- renderText({
    m <- last_meas(); if (is.null(m)) return(""); fmt_perc(m$bmi_perc)
  })

  # ---------------------------------------------------------------------------
  # Funzione generica per disegnare una curva di crescita
  # ---------------------------------------------------------------------------
  draw_curve <- function(item, value_col) {
    child <- current_child()
    req(child)
    curves <- percentile_curves(item, child$sex)

    m <- meas_df()
    pts <- if (nrow(m) > 0) {
      data.frame(age = m$age, value = m[[value_col]])
    } else {
      data.frame(age = numeric(0), value = numeric(0))
    }
    pts <- pts[!is.na(pts$value) & !is.na(pts$age), , drop = FALSE]

    if (is.null(curves)) {
      return(
        ggplot() +
          annotate("text", x = 0, y = 0, label = t("ref_unavailable")) +
          theme_void()
      )
    }

    # Limita l'asse x all'intervallo utile (eta del bambino + margine)
    max_age <- if (nrow(pts) > 0) max(pts$age, na.rm = TRUE) else 5
    x_max <- max(5, ceiling(max_age) + 1)
    x_max <- min(x_max, max(curves$age, na.rm = TRUE))
    curves <- curves[curves$age <= x_max, , drop = FALSE]

    # Etichette dei percentili all'estremo destro
    lab_df <- do.call(rbind, lapply(split(curves, curves$percentile), function(d) {
      d[which.max(d$age), , drop = FALSE]
    }))

    p <- ggplot(curves, aes(x = age, y = value, group = percentile)) +
      geom_line(aes(color = percentile), linewidth = 0.5, alpha = 0.8) +
      geom_text(data = lab_df,
                aes(label = percentile, color = percentile),
                hjust = -0.1, size = 3, show.legend = FALSE) +
      scale_color_manual(
        values = c("P3" = "#d73027", "P15" = "#fc8d59", "P50" = "#1a9850",
                   "P85" = "#fc8d59", "P97" = "#d73027"),
        name = t("plot_legend")
      ) +
      labs(title = t(paste0("tab_", item)), x = t("plot_x"),
           y = t(paste0("y_", item))) +
      coord_cartesian(xlim = c(0, x_max + 0.6), clip = "off") +
      theme_minimal(base_size = 13) +
      theme(plot.margin = margin(10, 30, 10, 10),
            legend.position = "bottom")

    if (nrow(pts) > 0) {
      p <- p +
        geom_line(data = pts, aes(x = age, y = value),
                  inherit.aes = FALSE, color = "#08519c", linewidth = 0.8) +
        geom_point(data = pts, aes(x = age, y = value),
                   inherit.aes = FALSE, color = "#08519c", size = 2.6)
    }
    p
  }

  output$plot_height <- renderPlot(draw_curve("height", "height_cm"))
  output$plot_weight <- renderPlot(draw_curve("weight", "weight_kg"))
  output$plot_bmi    <- renderPlot(draw_curve("bmi", "bmi"))

  # ---------------------------------------------------------------------------
  # Aggiunta misurazione
  # ---------------------------------------------------------------------------
  observeEvent(input$add_meas, {
    child <- current_child()
    req(child)
    if (is.na(input$height_cm) && is.na(input$weight_kg)) {
      showNotification(t("notif_need_value"), type = "warning")
      return()
    }
    add_measurement(child$id, input$meas_date, input$height_cm, input$weight_kg)
    updateNumericInput(session, "height_cm", value = NA)
    updateNumericInput(session, "weight_kg", value = NA)
    rv$meas <- rv$meas + 1
    showNotification(t("notif_meas_added"), type = "message")
  })

  # ---------------------------------------------------------------------------
  # Tabella storico
  # ---------------------------------------------------------------------------
  output$meas_table <- DT::renderDT({
    m <- meas_df()
    if (nrow(m) == 0) {
      df0 <- data.frame(x = t("no_meas")); names(df0) <- t("col_message")
      return(DT::datatable(df0, rownames = FALSE, options = list(dom = "t")))
    }
    out <- data.frame(
      m$id,
      fmt_date(m$meas_date),
      round(m$age, 2),
      round(m$height_cm, 1),
      round(m$height_perc),
      round(m$weight_kg, 1),
      round(m$weight_perc),
      round(m$bmi, 1),
      round(m$bmi_perc),
      check.names = FALSE
    )
    names(out) <- c("id", t("col_date"), t("col_age"), t("col_height"),
                    t("col_p_height"), t("col_weight"), t("col_p_weight"),
                    t("col_bmi"), t("col_p_bmi"))
    DT::datatable(
      out, rownames = FALSE, selection = "single",
      options = list(pageLength = 25, dom = "tip",
                     columnDefs = list(list(visible = FALSE, targets = 0)))
    )
  })

  observeEvent(input$del_meas, {
    sel <- input$meas_table_rows_selected
    m <- meas_df()
    if (length(sel) == 0 || nrow(m) == 0) {
      showNotification(t("notif_select_del"), type = "warning")
      return()
    }
    delete_measurement(m$id[sel])
    rv$meas <- rv$meas + 1
    showNotification(t("notif_meas_deleted"), type = "message")
  })

  # ---------------------------------------------------------------------------
  # Gestione figli
  # ---------------------------------------------------------------------------
  output$children_table <- DT::renderDT({
    df <- children_df()
    out <- data.frame(
      df$id,
      df$name,
      ifelse(df$sex == "male", t("opt_male"), t("opt_female")),
      fmt_date(df$birth_date),
      check.names = FALSE
    )
    names(out) <- c("id", t("col_name"), t("col_sex"), t("col_birth"))
    DT::datatable(
      out, rownames = FALSE, selection = "single",
      options = list(dom = "t",
                     columnDefs = list(list(visible = FALSE, targets = 0)))
    )
  })

  # Quando si seleziona una riga, popola il form
  observeEvent(input$children_table_rows_selected, {
    sel <- input$children_table_rows_selected
    df <- children_df()
    if (length(sel) == 0 || nrow(df) == 0) return()
    row <- df[sel, ]
    updateTextInput(session, "c_name", value = row$name)
    updateSelectInput(session, "c_sex", selected = row$sex)
    updateDateInput(session, "c_birth", value = as.Date(row$birth_date))
  })

  selected_child_id <- reactive({
    sel <- input$children_table_rows_selected
    df <- children_df()
    if (length(sel) == 0 || nrow(df) == 0) return(NULL)
    df$id[sel]
  })

  observeEvent(input$c_add, {
    if (!nzchar(input$c_name)) {
      showNotification(t("notif_need_name"), type = "warning"); return()
    }
    add_child(input$c_name, input$c_sex, input$c_birth)
    rv$children <- rv$children + 1
    showNotification(t("notif_child_added"), type = "message")
  })

  observeEvent(input$c_update, {
    id <- selected_child_id()
    if (is.null(id)) {
      showNotification(t("notif_select_child"), type = "warning"); return()
    }
    update_child(id, input$c_name, input$c_sex, input$c_birth)
    rv$children <- rv$children + 1
    showNotification(t("notif_changes_saved"), type = "message")
  })

  observeEvent(input$c_delete, {
    id <- selected_child_id()
    if (is.null(id)) {
      showNotification(t("notif_select_child"), type = "warning"); return()
    }
    delete_child(id)
    rv$children <- rv$children + 1
    rv$meas <- rv$meas + 1
    showNotification(t("notif_child_deleted"), type = "message")
  })
}
