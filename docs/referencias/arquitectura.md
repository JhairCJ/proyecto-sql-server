# Correspondencia con BikeStores

| Responsabilidad | BikeStores | Northwind | Adaptación |
| --- | --- | --- | --- |
| Origen operativo | OLTP | Northwind.OLTP / NorthWind | Clientes, empleados, productos, transportistas y pedidos; sin equivalente a tiendas |
| Extracción incremental | Procedimientos por entidad | DW_Get*ByRowVersion | Corte estable y cambios indirectos de cabeceras, categorías y proveedores |
| Almacén, staging y control | DW | Northwind.DW / Northwind_DW | Estrella de líneas de pedido; dimensiones tipo 1 y tres fechas |
| Transferencia y aplicación | ETL | Northwind.ETL / CargarNorthwind.dtsx | Cinco grupos de secuencia, dimensiones antes de ventas, bloqueo por almacén |
| Modelo analítico | OLAP tabular | Northwind.OLAP / NorthwindOLAP | Pedidos distintos, unidades e importes; fechas de pedido, requerida y envío |
| Publicación SSIS | Catálogo y carpeta propios | SSISDB / Northwind / Northwind.ETL | Entorno Northwind, autenticación de Windows, bases reales |
| Automatización | BikeStoresJob | NorthwindBIJob | Dos etapas nativas: SSIS y procesamiento tabular; horario diario configurable, deshabilitado inicialmente |

Los proyectos son fuentes editables; los `.dacpac`, `.ispac` y archivos de despliegue tabular son resultados de compilación. Los perfiles de la guía usan las bases reales y autenticación integrada; bloquean cambios con posible pérdida y no eliminan objetos ajenos. Las pruebas automatizadas trabajan con copias marcadas `_Test`.

## Nombres y ubicación

| Nombre anterior o artefacto | Nombre final | Referencia |
| --- | --- | --- |
| Scripts del DW dentro de OLTP | Northwind.DW/dbo y std | [Mapa SQL](modelo-dw.md) |
| Artefacto SSIS | Northwind.ispac (Visual Studio); Northwind.ETL.ispac (script) | Ambos contienen el proyecto Northwind.ETL; la guía usa el archivo nativo |
| Solución de apertura | Northwind.sln; Northwind.slnx alternativa | Cuatro proyectos; la guía usa Northwind.sln |
| Guías sin orden de ejecución | docs/01…10 | [Índice](../../README.md) |
| Job de la referencia BikeStores | NorthwindBIJob | Create-NorthwindBIJob.ps1; el job de referencia no se modifica |
| Datos de la práctica | NorthWind y Northwind_DW | Origen existente y almacén real de esta práctica |

La planificación OpenSpec vive fuera del repositorio. Los registros, contraseñas protegidas, evidencias y compilados se conservan localmente y se excluyen de Git.
