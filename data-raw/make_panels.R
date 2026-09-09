# =====================================================================
# data-raw/make_panels.R
# Genera los datasets de panel que shippea weightflow. Correr UNA vez:
#   source("data-raw/make_panels.R")
# Escribe data/panel_puro.rda, panel_cl.rda, panel_ine.rda, panel_us.rda
#
# Los cuatro comparten estructura (formato LARGO, una fila por persona-ola presente):
#   id_hogar, id_persona, nper      claves persistentes entre olas (linkean el panel)
#   estrato, psu                    diseño (PSU anidada en estrato; >=2 PSU por estrato)
#   region, sexo, edad              covariables / dominios
#   ola                             ola / mes (entero)
#   grupo_rotacion, mes_en_muestra  estructura rotativa
#   w_base                          peso de diseño (base)
#   disp                            disposición entre olas: "R" respondió,
#                                   "NR" no respuesta elegible, "OS" salió del universo
#                                   (inelegible sobrevenido), "UNK" elegibilidad desconocida
#   condicion                       status laboral (emp/unemp/inact) en la PET; NA si no R
#   ocupado, desocupado, ingreso    variables de interés (repetidas entre olas; NA si no R)
#
# Difieren SOLO en el sistema de rotación (el calendario grupo -> olas):
#   panel_puro : panel PURO, sin rotación (todas las unidades todas las olas; solo atrición)
#   panel_cl   : Chile ENE, 2-2-2 (in-out-in): traslape ~1/2 y unidades que REGRESAN
#   panel_ine  : INE Uruguay ECH / StatCan LFS, rotación 6 meses (1/6 rota): traslape ~5/6
#   panel_us   : US CPS 4-8-4: traslape ~3/4 y una cohorte que REGRESA tras el hueco
# =====================================================================

set.seed(2026)

## ---- constructores compartidos ----------------------------------------------

make_households <- function(n_hh, regions) {
  estrato <- sample(seq_len(6L), n_hh, TRUE)
  psu     <- estrato * 100L + sample(seq_len(10L), n_hh, TRUE)  # PSU anidada en estrato
  data.frame(id_hogar = seq_len(n_hh),
             estrato = estrato, psu = psu,
             region = sample(regions, n_hh, TRUE),
             w_base = round(runif(n_hh, 70, 220), 1),
             stringsAsFactors = FALSE)
}

make_persons <- function(hh) {
  np  <- sample(seq_len(4L), nrow(hh), TRUE, prob = c(.25, .35, .25, .15))
  idx <- rep(seq_len(nrow(hh)), np)
  p   <- hh[idx, c("id_hogar", "estrato", "psu", "region", "w_base")]
  p$nper       <- unlist(lapply(np, seq_len))
  p$id_persona <- p$id_hogar * 100L + p$nper
  n <- nrow(p)
  p$sexo <- sample(c("F", "M"), n, TRUE)
  p$edad <- sample(18:80, n, TRUE)
  p$lf   <- rbinom(n, 1, 0.72)                         # en la fuerza de trabajo
  rownames(p) <- NULL
  p
}

# emplea a la persona en la ola, con persistencia 0.85 respecto de la ola previa
sim_emp <- function(prev, base) {
  ifelse(is.na(prev),
         rbinom(length(base), 1, base),
         ifelse(runif(length(base)) < 0.85, prev, rbinom(length(base), 1, base)))
}

# Construye el data.frame largo dado un calendario `sched` (grupo -> olas en muestra).
# `disp_probs` rige las disposiciones desde la 2a ola; OS saca al hogar del universo
# de forma permanente (no vuelve). Los que ROTAN out por calendario pueden regresar.
build_long <- function(persons, sched, disp_probs, seed) {
  set.seed(seed)
  n_hh   <- max(persons$id_hogar)
  groups <- names(sched)
  waves  <- sort(unique(unlist(sched)))
  # asignacion BALANCEADA (round-robin): cohortes de rotacion de igual tamano, como en un
  # panel de igual probabilidad -> no dispara PN-02 espurio. (posicion = id de hogar)
  hh_group <- rep_len(groups, n_hh)
  emp_prev <- stats::setNames(rep(NA_integer_, nrow(persons)), persons$id_persona)
  gone     <- rep(FALSE, n_hh)                          # hogares que salieron del universo (OS)
  rows <- list()

  for (t in waves) {
    in_hh <- which(vapply(seq_len(n_hh), function(h) t %in% sched[[hh_group[h]]],
                          logical(1)) & !gone)
    if (!length(in_hh)) next
    dp <- if (t == min(waves)) c(R = 0.95, NR = 0.05, OS = 0, UNK = 0) else disp_probs
    disp_hh <- sample(names(dp), length(in_hh), TRUE, prob = dp)
    names(disp_hh) <- in_hh

    pin  <- persons[persons$id_hogar %in% in_hh, ]
    dsp  <- unname(disp_hh[as.character(pin$id_hogar)])
    grp  <- hh_group[pin$id_hogar]
    mis  <- vapply(seq_len(nrow(pin)),
                   function(i) which(sched[[grp[i]]] == t), integer(1))
    base <- stats::plogis(1.2 - 0.02 * (pin$edad - 40))
    prev <- emp_prev[as.character(pin$id_persona)]
    emp  <- ifelse(pin$lf == 1L, sim_emp(prev, base), 0L)
    emp_prev[as.character(pin$id_persona)] <- ifelse(pin$lf == 1L, emp, NA_integer_)

    respond    <- dsp == "R" & pin$lf == 1L
    ocupado    <- ifelse(respond, emp, NA_integer_)
    desocupado <- ifelse(respond, 1L - emp, NA_integer_)
    # labour status within the working-age population, observed only for respondents
    # (like real ECH/LFS microdata): emp / unemp inside the labour force, inact outside;
    # NA for non-respondents. This is the `status` argument of step_cre().
    condicion  <- ifelse(dsp != "R", NA_character_,
                  ifelse(pin$lf == 1L, ifelse(emp == 1L, "emp", "unemp"), "inact"))
    ingreso    <- ifelse(dsp == "R" & !is.na(ocupado) & ocupado == 1L,
                         round(exp(stats::rnorm(nrow(pin),
                                                10 + 0.2 * (pin$region == pin$region[1]), 0.5))),
                         ifelse(dsp == "R", 0, NA_real_))

    rows[[length(rows) + 1L]] <- data.frame(
      id_hogar = pin$id_hogar, id_persona = pin$id_persona, nper = pin$nper,
      estrato = pin$estrato, psu = pin$psu, region = pin$region,
      sexo = pin$sexo, edad = pin$edad,
      ola = t, grupo_rotacion = grp, mes_en_muestra = mis,
      w_base = pin$w_base, disp = dsp, condicion = condicion,
      ocupado = ocupado, desocupado = desocupado, ingreso = ingreso,
      stringsAsFactors = FALSE)

    gone[in_hh[disp_hh == "OS"]] <- TRUE                # OS: salen del universo, no vuelven
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out$condicion <- factor(out$condicion, levels = c("emp", "unemp", "inact"))
  out
}

disp_probs <- c(R = 0.85, NR = 0.08, OS = 0.04, UNK = 0.03)

## ---- 1) panel PURO (sin rotación; solo atrición) ----------------------------
persons_puro <- make_persons(make_households(1000, c("Urbano", "Rural")))
sched_puro   <- list(panel = 1:4)                      # todas las unidades, 4 olas
panel_puro   <- build_long(persons_puro, sched_puro, disp_probs, seed = 101)

## ---- 2) panel CHILE ENE 2-2-2 (in-out-in; ~1/2; regresan) -------------------
# g2 está en olas 1 y 3 pero NO en 2: es la firma "regresa" del 2-2-2.
persons_cl <- make_persons(make_households(900, c("Norte", "Centro", "Sur")))   # 3 GR x 300
sched_cl   <- list(g1 = c(1, 2), g2 = c(1, 3), g3 = c(2, 3))
panel_cl   <- build_long(persons_cl, sched_cl, disp_probs, seed = 102)

## ---- 3) panel INE/StatCan 6 meses (1/6 rota; ~5/6) --------------------------
# grupo g presente cuando  g-5 <= ola <= g  (ventana deslizante de 6): traslape 5/6.
persons_ine <- make_persons(make_households(1200, c("Montevideo", "Interior")))  # 8 GR x 150
sched_ine   <- stats::setNames(
  lapply(1:8, function(g) seq(max(1L, g - 5L), min(3L, g))),
  paste0("g", 1:8))
panel_ine   <- build_long(persons_ine, sched_ine, disp_probs, seed = 103)

## ---- 4) panel US CPS 4-8-4 (~3/4; cohorte que regresa) ----------------------
# A-D núcleo (3 olas); E,F salen; G sale en la 2 y REGRESA en la 3 (hueco 8 meses);
# I,J entran; H solo ola 1; K solo ola 3.  Traslape consecutivo 6/8.
persons_us <- make_persons(make_households(1408,                                 # 11 GR x 128
                    c("Northeast", "South", "West", "Midwest")))
sched_us   <- list(A = 1:3, B = 1:3, C = 1:3, D = 1:3,
                   E = c(1, 2), F = c(1, 2), G = c(1, 3), H = c(1),
                   I = c(2, 3), J = c(2, 3), K = c(3))
panel_us   <- build_long(persons_us, sched_us, disp_probs, seed = 104)

## ---- guardar ----------------------------------------------------------------
# Escribir DIRECTO a la carpeta data/ del paquete. NO usar usethis::use_data(): detecta
# el "proyecto activo" desde getwd(), y si se corre desde ~/Desktop guarda los .rda en
# ~/Desktop/data/ (carpeta equivocada) dejando el paquete con los datos viejos.
pkg_data <- path.expand("~/Desktop/weightflow_en_desarrollo/data")
if (!dir.exists(pkg_data))
  stop("No encuentro la carpeta data/ del paquete: ", pkg_data, call. = FALSE)
save(panel_puro, file = file.path(pkg_data, "panel_puro.rda"), compress = "xz")
save(panel_cl,   file = file.path(pkg_data, "panel_cl.rda"),   compress = "xz")
save(panel_ine,  file = file.path(pkg_data, "panel_ine.rda"),  compress = "xz")
save(panel_us,   file = file.path(pkg_data, "panel_us.rda"),   compress = "xz")
cat(sprintf("Guardados 4 .rda en %s\n", pkg_data))

## chequeo rápido (imprime traslape observado por par de olas)
overlap_check <- function(df, key = "id_persona") {
  ws <- sort(unique(df$ola))
  for (i in seq_len(length(ws) - 1L)) {
    a <- unique(df[[key]][df$ola == ws[i]])
    b <- unique(df[[key]][df$ola == ws[i + 1L]])
    cat(sprintf("  olas %s->%s : traslape %.2f  (n1=%d, n2=%d)\n",
                ws[i], ws[i + 1L], length(intersect(a, b)) / length(a),
                length(a), length(b)))
  }
}
cat("panel_puro:\n"); overlap_check(panel_puro)
cat("panel_cl:\n");   overlap_check(panel_cl)
cat("panel_ine:\n");  overlap_check(panel_ine)
cat("panel_us:\n");   overlap_check(panel_us)
