# Northwind en SQL Server

Abre [01. Ejecutar el proyecto](docs/01-guia-practica.md). La práctica carga las copias de Northwind con SSIS y analiza las ventas con un modelo tabular SSAS. NorthwindBIJob ejecuta carga y procesamiento desde el servidor.

Para seguir todo el proceso con detalle, abre la [guía paso a paso](<guia paso a paso.md>).

| Guía | Uso |
| --- | --- |
| [01](docs/01-guia-practica.md) | Ejecutar el proyecto |
| [02](docs/02-entorno.md) | Configurar conexión y compilación |
| [03](docs/03-pruebas-aisladas.md) | Preparar copias/publicar extractores |
| [04](docs/04-ejecutar-extraccion.md) | Ejecutar extracción |
| [05](docs/05-preparar-dw.md) | Publicar DW/poblar calendario |
| [06](docs/06-cargar-datos.md) | Cargar dimensiones/ventas y repetir |
| [07](docs/07-ejecutar-ssis.md) | Abrir, configurar y ejecutar SSIS |
| [08](docs/08-publicar-ssis.md) | Publicar en el catálogo del servidor |
| [09](docs/09-procesar-y-consultar-olap.md) | Publicar, procesar y consultar el modelo tabular |
| [10](docs/10-ejecutar-job.md) | Ejecutar, comprobar y programar el job |

[Arquitectura y BikeStores](docs/referencias/arquitectura.md). [Extracción](docs/referencias/extraccion.md). [Modelo DW](docs/referencias/modelo-dw.md). [Modelo OLAP](docs/referencias/modelo-olap.md). [Contrato de carga](docs/referencias/carga.md). [SSIS](docs/referencias/ssis.md). [Verificaciones](docs/validacion.md).

```powershell
git clone --branch northwind https://github.com/JhairCJ/proyecto-sql-server.git
```

Clonar no crea las bases originales. Esta instalación utiliza NorthWind y Northwind_DW existentes. Los cambios locales aún no publicados no se obtienen al clonar.
