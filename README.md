# Northwind en SQL Server

Abre [01. Ejecutar el proyecto](docs/01-guia-practica.md). La solución contiene OLTP y DW; puede publicar extractores y preparar el esquema/calendario. La carga comercial, SSIS, SSAS y el job siguen pendientes.

| Guía | Uso |
| --- | --- |
| [01](docs/01-guia-practica.md) | Ejecutar lo disponible |
| [02](docs/02-entorno.md) | Configurar conexión y compilación |
| [03](docs/03-pruebas-aisladas.md) | Preparar copias/publicar extractores |
| [04](docs/04-ejecutar-extraccion.md) | Ejecutar extracción |
| [05](docs/05-preparar-dw.md) | Publicar DW/poblar calendario |

[Mapa de extracción](docs/referencias/extraccion.md). [Modelo y reorganización DW](docs/referencias/modelo-dw.md). [Verificaciones](docs/validacion.md).

```powershell
git clone --branch northwind https://github.com/JhairCJ/proyecto-sql-server.git
```

Clonar no crea las bases originales. Esta instalación utiliza NorthWind y Northwind_DW existentes. Los cambios locales aún no publicados no se obtienen al clonar.
