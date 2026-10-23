# Evidencias locales del proyecto

Esta carpeta sirve para guardar comprobaciones realizadas en Visual Studio, SSMS, SSIS, SSAS y Power BI. El `.gitignore` excluye los archivos bajo `docs/evidencias/` excepto este `README.md`: no subir capturas ni logs que puedan contener nombres de equipos, cuentas, rutas o datos sensibles.

## Revisión de dashboards Power BI

Usa la [lista de verificación visual](../referencias/revision-visual-power-bi.md) para revisar las tres páginas del informe. Las capturas se generan **en Power BI Desktop**, en el equipo que ejecuta la prueba; este repositorio no da por válidas capturas de otra instalación.

Para cada comprobación, registrar localmente:

| Campo | Qué anotar |
| --- | --- |
| Fecha e integrante | Quién ejecutó la revisión y cuándo |
| Entorno | Instancia SSAS y base tabular utilizadas, sin contraseñas |
| Prueba | Identificador BI-01 a BI-06 |
| Estado | Aprobado, Fallido o No ejecutado |
| Evidencia | Archivo de captura y breve observación |

Nombre de archivos recomendado en la carpeta local `docs/evidencias/power-bi/`: `01-resumen.png`, `02-productos-clientes.png`, `03-logistica.png`; agregar sufijos para filtros o fallos si corresponde. Para compartir con el equipo, enviarlos por el canal acordado y describir qué se validó. No subir capturas ajenas presentándolas como ejecución propia.

El resumen de resultados puede enviarse al grupo así:

> Revisé el dashboard Northwind en mi equipo con el modelo [nombre de base] en [servidor]. Resumen comercial: [estado]; Productos y clientes: [estado]; Logística: [estado]. Adjunto capturas obtenidas en Power BI Desktop. Incidencias: [ninguna / detalle].
