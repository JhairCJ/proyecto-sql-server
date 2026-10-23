# Instrucciones de trabajo

- Implementar por secciones funcionales completas: extracción, DW, aplicación/carga, SSIS, análisis y despliegue/job. No limitarse a una a tres tareas ni separar procedimientos equivalentes en entregas diminutas. Elegir la sección automáticamente y terminar sus comprobaciones.
- El recorrido principal de la práctica se ejecuta desde las interfaces de Visual Studio y SSMS; los scripts de consola quedan como apoyo para automatización y pruebas.
- Guías numeradas desde 01, muy concisas: solo cómo abrir, configurar, poblar y ejecutar, con valores/comandos y resultado esperado. Sin historial de cambios, decisiones del asistente, próximos segmentos ni comentarios extra. Conceptos, mapas, contratos y evidencias van en referencias separadas.
- No hacer commit ni push sin petición expresa. «Commit push y siguiente» publica lo acumulado y luego continúa localmente; no concede permiso permanente para publicar.
- No incorporar planificación OpenSpec al repositorio. Mantenerla en el directorio del workspace ya existente.
- Conservar la separación OLTP/DW/ETL/OLAP/job de BikeStores adaptada a Northwind. Probar modificaciones de datos sobre copias identificadas, con guardas y limpieza.
- Mantener el árbol limpio: experimentos y diagnósticos desechables en el temporal del sistema; no dejar logs sueltos, índices generados, cachés ni copias de recuperación. Al terminar, retirar los intermedios propios y conservar solo fuentes, pruebas mantenidas, datos necesarios, entregables finales y evidencia útil. Mantener las exclusiones de Git actualizadas; ignorar un archivo no sustituye limpiar lo innecesario. Conservar las copias de validación pendientes hasta cerrar su prueba.
