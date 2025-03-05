# Cargar librerías necesarias
library(tidyverse)
library(readr)
library(readxl)
library(openxlsx)
library(tcltk)
library(writexl)

# Función para cargar archivos CSV o Excel
cargar_archivo <- function(ruta) {
  if (grepl("\\.csv$", ruta, ignore.case = TRUE)) {
    df <- read_csv(ruta, show_col_types = FALSE)
    if (ncol(df) == 1) df <- read_delim(ruta, delim = ";", show_col_types = FALSE)
    if (ncol(df) == 1) df <- read_delim(ruta, delim = "\t", show_col_types = FALSE)
  } else if (grepl("\\.xlsx$", ruta, ignore.case = TRUE)) {
    df <- read_excel(ruta)
  } else {
    stop("Formato no compatible")
  }
  
  colnames(df) <- tolower(str_trim(colnames(df)))
  return(df)
}

# Función para detectar si un valor es una dirección IP
es_ip <- function(valor) {
  return(grepl("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", valor) | grepl("^([0-9a-fA-F:]+)$", valor))
}

# Función para limpiar dominios y correos electrónicos, manteniendo IPs
limpiar_dominio <- Vectorize(function(valor) {
  valor <- tolower(str_trim(valor))
  
  if (es_ip(valor)) {
    return(valor)
  }
  
  valor <- gsub("@.*", "", valor)  # Eliminar correos electrónicos
  valor <- gsub("www\\.|https?://", "", valor)  # Remover prefijos de URLs
  valor <- gsub("\\..*", "", valor)  # Eliminar dominios después del primer punto
  
  return(valor)
})

# Función para limpiar columnas clave
limpiar_columnas_clave <- function(df, columnas_clave) {
  if (length(columnas_clave) == 0) return(df)
  
  df <- df %>%
    mutate(across(all_of(columnas_clave), ~ limpiar_dominio(.))) %>%
    mutate(across(all_of(columnas_clave), ~ iconv(., from = "UTF-8", to = "ASCII//TRANSLIT"))) %>%
    mutate(across(all_of(columnas_clave), ~ str_trim(.)))
  
  return(df)
}

# Función para seleccionar columnas clave con checkboxes en disposición 4x4 y scrollbar
seleccionar_columnas_clave <- function(columnas_disponibles, titulo = "Seleccionar Columnas Clave") {
  if (length(columnas_disponibles) == 0) return(character(0))
  
  tt <- tktoplevel()
  tkwm.title(tt, titulo)
  
  # Crear marco principal y canvas para el scrollbar
  frame_principal <- tkframe(tt)
  canvas <- tkcanvas(frame_principal, width = 400, height = 200)
  
  # Scrollbars horizontal y vertical
  scrollbar_x <- tkscrollbar(frame_principal, orient = "horizontal", command = function(...) tkxview(canvas, ...))
  scrollbar_y <- tkscrollbar(frame_principal, orient = "vertical", command = function(...) tkyview(canvas, ...))
  
  frame_secundario <- tkframe(canvas)
  frame_contenedor <- tkframe(frame_secundario)
  tkpack(frame_contenedor, expand = TRUE, fill = "both")
  
  check_vars <- vector("list", length(columnas_disponibles))
  cols_por_fila <- 4  # Columnas por fila
  padding_x <- 10  # Espaciado horizontal
  check_width <- 100  # Ancho estimado de cada checkbox
  
  total_filas <- ceiling(length(columnas_disponibles) / cols_por_fila)
  total_columnas <- min(cols_por_fila, length(columnas_disponibles))
  
  # Crear los checkboxes organizados en filas y columnas
  for (i in seq_along(columnas_disponibles)) {
    check_vars[[i]] <- tclVar("0")
    fila <- floor((i - 1) / cols_por_fila)
    columna <- (i - 1) %% cols_por_fila
    tkgrid(tkcheckbutton(frame_contenedor, text = columnas_disponibles[i], variable = check_vars[[i]]), 
           row = fila, column = columna, padx = padding_x, pady = 5, sticky = "w")
  }
  
  # Configurar el tamaño del área de scroll
  ancho_total <- total_columnas * (check_width + padding_x)
  alto_total <- total_filas * 30
  
  tkcreate(canvas, "window", 0, 0, anchor = "nw", window = frame_secundario)
  tkconfigure(canvas, scrollregion = c(0, 0, ancho_total, alto_total))
  
  # Empaquetar elementos
  tkpack(canvas, side = "top", fill = "both", expand = TRUE)
  tkpack(scrollbar_x, side = "bottom", fill = "x")
  tkpack(scrollbar_y, side = "right", fill = "y")
  tkpack(frame_principal, fill = "both", expand = TRUE)
  
  # Botón para confirmar selección
  seleccionadas <- c()
  boton_ok <- tkbutton(tt, text = "Aceptar", command = function() {
    seleccionadas <<- columnas_disponibles[sapply(check_vars, function(var) as.integer(tclvalue(var))) == 1]
    tkdestroy(tt)
  })
  tkpack(boton_ok, pady = 10)
  
  # Esperar hasta que el usuario confirme la selección
  tkwait.window(tt)
  return(seleccionadas)
}

# Función para mapear columnas entre archivos
mapeo_columnas_por_archivo <- function(columnas_base, columnas_segundo, archivo) {
  if (length(columnas_base) == 0 || length(columnas_segundo) == 0) return(setNames(character(0), columnas_base))
  
  tt <- tktoplevel()
  tkwm.title(tt, paste("Mapeo de columnas para:", archivo))
  
  mapeo <- list()
  for (i in seq_along(columnas_base)) {
    tkpack(tklabel(tt, text = paste("Columna en", archivo, "para:", columnas_base[i])), anchor = "w")
    
    var <- tclVar(columnas_segundo[1])
    combo <- ttkcombobox(tt, values = columnas_segundo, textvariable = var, state = "readonly")
    tkpack(combo, pady = 5)
    
    mapeo[[columnas_base[i]]] <- var
  }
  
  boton_ok <- tkbutton(tt, text = "Aceptar", command = function() {
    mapeo_final <<- setNames(sapply(mapeo, tclvalue), columnas_base)
    tkdestroy(tt)
  })
  
  tkpack(boton_ok, pady = 10)
  tkwait.window(tt)
  
  return(mapeo_final)
}

# Selección de archivos mediante interfaz gráfica
ruta_base <- tk_choose.files(caption = "Selecciona el archivo principal")
if (length(ruta_base) == 0) stop("No se seleccionó un archivo principal.")

base <- cargar_archivo(ruta_base)
columnas_base <- colnames(base)

# Seleccionar columnas clave con scrollbar
columnas_clave <- seleccionar_columnas_clave(columnas_base)
if (length(columnas_clave) == 0) stop("No se seleccionaron columnas clave.")

# Selección de archivos de segundo ingreso
rutas_segundo_ingreso <- tk_choose.files(caption = "Selecciona los archivos a comparar")
if (length(rutas_segundo_ingreso) == 0) stop("No se seleccionaron archivos para comparar.")

segundo_ingreso_list <- list()

# Procesar cada archivo de segundo ingreso
for (ruta in rutas_segundo_ingreso) {
  segundo_ingreso <- cargar_archivo(ruta)
  columnas_segundo <- colnames(segundo_ingreso)
  
  # Mapear columnas con la base
  columnas_mapeadas <- mapeo_columnas_por_archivo(columnas_clave, columnas_segundo, basename(ruta))
  
  # Renombrar columnas según el mapeo
  for (col_base in names(columnas_mapeadas)) {
    col_segundo <- columnas_mapeadas[[col_base]]
    if (col_segundo %in% colnames(segundo_ingreso)) {
      colnames(segundo_ingreso)[colnames(segundo_ingreso) == col_segundo] <- col_base
    }
  }
  
  # Limpiar las columnas clave en ambos datasets
  base <- limpiar_columnas_clave(base, columnas_clave)
  segundo_ingreso <- limpiar_columnas_clave(segundo_ingreso, columnas_clave)
  
  segundo_ingreso_list[[ruta]] <- segundo_ingreso
}

# Unir todos los archivos comparados
segundo_ingreso <- bind_rows(segundo_ingreso_list)

# Comparación con lógica OR (al menos una columna clave debe coincidir)
segundo_ingreso <- segundo_ingreso %>%
  rowwise() %>%
  mutate(estado = if_else(any(c_across(all_of(columnas_clave)) %in% unlist(base[columnas_clave], use.names = FALSE)), 
                          "En Base", "No en Base")) %>%
  ungroup()
# Verificar que 'segundo_ingreso' tiene datos antes de continuar
if (!exists("segundo_ingreso") || nrow(segundo_ingreso) == 0) {
  stop("No hay datos disponibles para exportar. Verifique que los datos fueron procesados correctamente.")
}

# Filtrar datos "En Base"
en_base <- filter(segundo_ingreso, estado == "En Base")

# Filtrar datos "No en Base"
no_en_base <- filter(segundo_ingreso, estado == "No en Base")

# Crear ventana principal de resultados
ventana_resultados <- tktoplevel()
tkwm.title(ventana_resultados, "Resultados de Comparación")

# Frame principal donde se mostrarán las vistas
frame_contenedor <- tkframe(ventana_resultados)
tkpack(frame_contenedor, fill = "both", expand = TRUE)

# === ÁREA DE TEXTO CON SCROLL === #
text_area <- tktext(frame_contenedor, wrap = "none", height = 20, width = 100)
scrollbar_y_text <- tkscrollbar(frame_contenedor, orient = "vertical", command = function(...) tkyview(text_area, ...))
scrollbar_x_text <- tkscrollbar(frame_contenedor, orient = "horizontal", command = function(...) tkxview(text_area, ...))
tkconfigure(text_area, yscrollcommand = function(...) tkset(scrollbar_y_text, ...))
tkconfigure(text_area, xscrollcommand = function(...) tkset(scrollbar_x_text, ...))

# === TABLA INTERACTIVA (TREEVIEW) CON SCROLL === #
tabla <- ttktreeview(frame_contenedor, columns = colnames(segundo_ingreso), show = "headings", height = 15)
scrollbar_y_tabla <- tkscrollbar(frame_contenedor, orient = "vertical", command = function(...) tkyview(tabla, ...))
scrollbar_x_tabla <- tkscrollbar(frame_contenedor, orient = "horizontal", command = function(...) tkxview(tabla, ...))
tkconfigure(tabla, yscrollcommand = function(...) tkset(scrollbar_y_tabla, ...))
tkconfigure(tabla, xscrollcommand = function(...) tkset(scrollbar_x_tabla, ...))

# Agregar encabezados a la tabla
for (col in colnames(segundo_ingreso)) {
  tcl(tabla, "heading", col, text = col)
  tcl(tabla, "column", col, width = 120, anchor = "center")
}

# Función para mostrar datos en texto
mostrar_todos_los_datos <- function(datos, tipo) {
  tkdelete(text_area, "1.0", "end")  # Limpiar área de texto
  
  tkinsert(text_area, "end", paste("=== Datos", tipo, "===\n"))
  
  if (nrow(datos) > 0) {
    texto <- capture.output(print(datos))
    for (linea in texto) {
      tkinsert(text_area, "end", paste(linea, "\n"))
    }
  } else {
    tkinsert(text_area, "end", "No hay datos en esta categoría.\n")
  }
  
  tkpack(text_area, side = "top", fill = "both", expand = TRUE)
  tkpack(scrollbar_x_text, side = "bottom", fill = "x")
  tkpack(scrollbar_y_text, side = "right", fill = "y")
  tkpack.forget(tabla)  # Oculta la tabla
  tkpack.forget(scrollbar_x_tabla)
  tkpack.forget(scrollbar_y_tabla)
}

# Función para mostrar datos en tabla interactiva
mostrar_tabla <- function(datos) {
  if (nrow(datos) == 0) {
    tkmessageBox(title = "Aviso", message = "No hay datos disponibles para mostrar.")
    return()
  }
  
  # Limpiar la tabla antes de insertar nuevos datos
  tcl(tabla, "delete", tcl(tabla, "children", ""))
  
  # Insertar datos en la tabla
  for (i in 1:nrow(datos)) {
    valores <- as.character(datos[i, ])
    tkinsert(tabla, "", "end", values = valores)
  }
  
  tkpack(tabla, side = "top", fill = "both", expand = TRUE)
  tkpack(scrollbar_x_tabla, side = "bottom", fill = "x")
  tkpack(scrollbar_y_tabla, side = "right", fill = "y")
  tkpack.forget(text_area)  # Oculta el área de texto
  tkpack.forget(scrollbar_x_text)
  tkpack.forget(scrollbar_y_text)
}

# === BOTONES PARA INTERACTUAR === #
btn_ver_texto_en_base <- tkbutton(ventana_resultados, text = "Ver En Base (Texto)", command = function() {
  mostrar_todos_los_datos(en_base, "En Base")
})
tkpack(btn_ver_texto_en_base, pady = 5)

btn_ver_texto_no_en_base <- tkbutton(ventana_resultados, text = "Ver No en Base (Texto)", command = function() {
  mostrar_todos_los_datos(no_en_base, "No en Base")
})
tkpack(btn_ver_texto_no_en_base, pady = 5)

btn_ver_tabla_en_base <- tkbutton(ventana_resultados, text = "Ver En Base (Tabla)", command = function() {
  mostrar_tabla(en_base)
})
tkpack(btn_ver_tabla_en_base, pady = 5)

btn_ver_tabla_no_en_base <- tkbutton(ventana_resultados, text = "Ver No en Base (Tabla)", command = function() {
  mostrar_tabla(no_en_base)
})
tkpack(btn_ver_tabla_no_en_base, pady = 5)

# === BOTONES PARA EXPORTAR A EXCEL === #
btn_excel_en_base <- tkbutton(ventana_resultados, text = "EXCEL En Base", command = function() {
  if (nrow(en_base) > 0) {
    write_xlsx(en_base, "en_base.xlsx")
    tkmessageBox(title = "Éxito", message = "Archivo 'en_base.xlsx' generado correctamente.")
  } else {
    tkmessageBox(title = "Aviso", message = "No hay datos 'En Base' para exportar.")
  }
})
tkpack(btn_excel_en_base, pady = 5)

btn_excel_no_en_base <- tkbutton(ventana_resultados, text = "EXCEL No en Base", command = function() {
  if (nrow(no_en_base) > 0) {
    write_xlsx(no_en_base, "no_en_base.xlsx")
    tkmessageBox(title = "Éxito", message = "Archivo 'no_en_base.xlsx' generado correctamente.")
  } else {
    tkmessageBox(title = "Aviso", message = "No hay datos 'No en Base' para exportar.")
  }
})
tkpack(btn_excel_no_en_base, pady = 5)

# Mantener la ventana abierta hasta que el usuario la cierre manualmente
tkwait.window(ventana_resultados)


# Mostrar resumen en consola
print(" Resumen de comparación:")
print(table(segundo_ingreso$estado))