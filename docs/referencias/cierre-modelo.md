# Cierre del modelo estrella — 22 de octubre de 2026

El modelo inglés está implementado, publicado y procesado en las bases principales de este equipo. Los proyectos fuente, scripts y guía apuntan a FactSales y sus siete dimensiones. Las etiquetas y medidas analíticas se mantienen en español.

## Estado comprobado

| Componente | Resultado |
| --- | --- |
| DW principal Northwind_DW | Ocho tablas finales, nueve claves foráneas; migración Validated |
| SSIS publicado | Siete paquetes; seis procesos con Proveedor antes de Producto y Ventas |
| NorthwindOLAP | Ocho tablas, nueve relaciones y 21 medidas |
| NorthwindBIJob | Ambos pasos correctos; ejecución de 8 segundos, 22/10/2026 03:52:11 hora local |
| Datos conciliados OLTP → DW → SSAS | 2.155 líneas, 830 pedidos, 51.317 unidades |
| Importes | Bruto 1.354.458,59; descuentos 88.665,83; neto 1.265.792,76; flete 64.942,69 |
| Conservación | Igualdad bidireccional de claves, líneas e importes anteriores; controles conservados y avanzados mediante carga |
| Power BI | Consultas correctas mediante el rol Read NorthwindPowerBIReader, incluida categoría Beverages/año 1996: 47.919,00 |

## Pruebas ejecutadas

Pasaron Test-Warehouse, Test-Application, Test-Load, Test-WarehouseMigration, Test-FreshWarehouseInstall (incluye Test-NorthwindOLAP), Test-SSIS y Test-DeploymentJob. Cubren instalación nueva, migración cargada, publicación repetida, cargas incrementales, proveedor y destino, tres fechas, flete por pedido, nulos/cero, precisión, concurrencia, fallos con rollback y reintento. El ensayo del job comprobó que un fallo de ETL impide procesar OLAP y que un fallo de procesamiento permite reintentar conservando la carga confirmada.

También se ejecutaron las consultas SQL de scripts/sql/Consultas-Analisis-Northwind.sql, los comparadores DW y OLAP contra las bases principales y la consulta DAX de la guía con el rol de lectura. Se corrigió la compilación del DW para evitar que la caché de SSDT reincorpore tablas retiradas; la instalación nueva y la retirada/republicación en copia lo verifican.

Los registros completos, resultados JSON y capturas de configuración anteriores están en [evidencias locales](../evidencias/cierre-modelo-20261022/), excluidas de Git. No contienen una verificación visual del diseñador de Power BI. La extracción fue verificada en la sección de extracción del cambio y se mantuvieron sus contratos y pruebas.

## Recuperación y acciones innecesarias

Antes de migrar se creó y verificó un respaldo COPY_ONLY del DW principal. La ruta efectiva está en [respaldo-dw.txt](../evidencias/cierre-modelo-20261022/dw-principal/respaldo-dw.txt); también se guardaron las definiciones previas de extractores, el modelo SSAS y el estado del principal.

- La eliminación física de las tablas anteriores **no se realizó por ser innecesaria para la entrega y Power BI**. Se mantienen para recuperación, sin usarlas en el modelo final. El script de retirada está implementado y probado en copia, incluida la republicación sin recrearlas.
- La activación automática del horario **no se realizó por ser innecesaria para la entrega**. El job y su horario siguen deshabilitados; su ejecución manual ya fue comprobada.
- Duplicar relaciones y medidas en Power BI **no se realizó por ser innecesario** con conexión en vivo al modelo publicado.

## Uso en Power BI y alcance pendiente

Sigue [guía, paso 12.4](../guia%20paso%20a%20paso.md#124-conecta-power-bi-desktop): SQL Server Analysis Services, servidor localhost, base NorthwindOLAP y Conectar en vivo. El usuario Windows necesita lectura; Configure-NorthwindPowerBIAccess.ps1 concede ese permiso sin otorgar administración. Cada integrante debe publicar el código actualizado en su propio servidor antes de conectarse a su localhost.

Este cierre corresponde a replace-northwind-star-model. El dashboard y sus archivos PBIX/PBIT pertenecen al cambio separado add-northwind-powerbi-dashboard y todavía no se han construido.
