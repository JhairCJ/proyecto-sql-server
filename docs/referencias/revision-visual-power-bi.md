# Revisión visual de Power BI por integrante

Este procedimiento sirve para comprobar **en cada equipo** el informe `Northwind.PowerBI/Northwind.pbix`. Es una lista de pruebas pendientes de ejecutar, no una certificación de ejecución. Las cifras de referencia proceden de la [guía de Power BI](../11-visualizar-power-bi.md) y solo son comparables si el modelo contiene el mismo conjunto de datos.

## Preparación

1. Actualizar el repositorio y verificar que el modelo tabular `NorthwindOLAP` esté publicado y procesado en SQL Server Analysis Services.
2. Abrir `Northwind.PowerBI/Northwind.pbix` en Power BI Desktop. Confirmar que la conexión en vivo apunta al **servidor SSAS real del integrante**; `localhost` en la documentación corresponde al equipo donde se preparó el informe, no a todos los equipos.
3. Si el servidor es distinto, ajustar **Inicio > Transformar datos > Configuración de origen de datos** y comprobar la base `NorthwindOLAP`. No subir cambios de PBIX realizados únicamente para adaptar una dirección o credenciales locales.
4. Confirmar permisos de lectura del modelo, que las visualizaciones cargan y que no aparecen errores de credenciales ni de relaciones.

## Casos de revisión

| ID | Página | Acción | Resultado esperado de referencia |
| --- | --- | --- | --- |
| BI-01 | Resumen comercial | Restablecer filtros; comprobar tarjetas | 830 pedidos, 51.317 unidades, ventas netas 1.265.792,76 y ticket 1.525,05 |
| BI-02 | Resumen comercial | Filtrar año de pedido 1996 y categoría Beverages | Ventas netas 47.919,00 |
| BI-03 | Productos y clientes | Verificar rankings, detalle y filtros de año/categoría/cliente | Los gráficos responden sin errores; los filtros sincronizados mantienen su selección |
| BI-04 | Logística | Filtrar pedido 10248 | 1 pedido, 3 líneas, 27 unidades, ventas netas 440,00 y flete 32,38 |
| BI-05 | Todas | Usar **Restablecer** (Ctrl+clic o Ctrl+Enter en Desktop) | Vuelven los valores globales y se eliminan los filtros específicos |
| BI-06 | Todas | Navegar por las tres páginas | No hay imágenes vacías inesperadas, visuales cortados ni mensajes de error |

**Nota:** comparar decimales según configuración regional. Si los valores difieren, registrar primero el servidor, el modelo y el momento de la última carga/procesamiento; no cambiar medidas DAX solo para hacer coincidir una captura.

## Capturas y registro

- Tomar una captura legible de cada página **tras restablecer los filtros**: `01-resumen.png`, `02-productos-clientes.png` y `03-logistica.png`.
- Tomar, si se requiere, capturas de los casos filtrados BI-02 y BI-04; dejar visibles los filtros seleccionados y los KPI afectados.
- Registrar fecha, integrante, servidor/modelo (sin credenciales), versión de Power BI, ID de prueba, resultado **Aprobado / Fallido / No ejecutado** y observación.
- Enviar al grupo las capturas obtenidas realmente. No recrear capturas ni marcar pruebas aprobadas sin abrir Power BI.
- Mantener las evidencias locales en `docs/evidencias/power-bi/`: Git ignora esa carpeta para evitar publicar rutas, cuentas y capturas del equipo. Ver [manejo de evidencias](../evidencias/README.md).

Si alguna prueba falla, adjuntar el mensaje exacto y distinguir si es un error de **conexión/SSAS**, de **datos/actualización**, o del **visual/filtros**. No editar el informe principal hasta identificar la causa.
