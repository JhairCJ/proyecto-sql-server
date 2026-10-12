# Instrucciones de trabajo

- Implementar por secciones funcionales completas: extracción, DW, aplicación/carga, SSIS, análisis y despliegue/job. No limitarse a una a tres tareas ni separar procedimientos equivalentes en entregas diminutas. Elegir la sección automáticamente y terminar sus comprobaciones.
- Guías numeradas desde 01, muy concisas: solo cómo abrir, configurar, poblar y ejecutar, con valores/comandos y resultado esperado. Sin historial de cambios, decisiones del asistente, próximos segmentos ni comentarios extra. Conceptos, mapas, contratos y evidencias van en referencias separadas.
- No hacer commit ni push sin petición expresa. «Commit push y siguiente» publica lo acumulado y luego continúa localmente; no concede permiso permanente para publicar.
- No incorporar planificación OpenSpec al repositorio. Mantenerla en el directorio del workspace ya existente.
- Conservar la separación OLTP/DW/ETL/OLAP/job de BikeStores adaptada a Northwind. Probar modificaciones de datos sobre copias identificadas, con guardas y limpieza.
