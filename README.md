# Práctica Northwind en SQL Server

Abre la [guía de ejecución](docs/01-guia-practica.md) para configurar el entorno, abrir la solución, preparar las copias y ejecutar lo que funciona actualmente.

**Estado:** el proyecto OLTP y sus cinco extractores están implementados. La carga completa al DW, los paquetes ETL, el modelo analítico y el job siguen pendientes. No existe todavía una ejecución completa que pueble y procese todo el sistema.

## Descargar

```powershell
git clone --branch northwind https://github.com/JhairCJ/proyecto-sql-server.git
Set-Location -LiteralPath '.\proyecto-sql-server'
```

Descargar el repositorio no crea las bases. La guía utiliza NorthWind y Northwind_DW existentes en este equipo; la preparación completa en una computadora nueva sigue pendiente. Los cambios locales posteriores al último push tampoco se obtienen al clonar.

## Documentación

| Documento | Uso |
| --- | --- |
| [01. Ejecución](docs/01-guia-practica.md) | Recorrido principal y límite actual de funcionamiento |
| [02. Entorno](docs/02-entorno.md) | Comprobar conexión y compilación |
| [03. Preparación](docs/03-pruebas-aisladas.md) | Preparar copias y publicar extractores |
| [04. Clientes](docs/04-extraccion-clientes.md) | Prueba específica del extractor |
| [05. Empleados y productos](docs/05-extraccion-empleados-productos.md) | Pruebas de relaciones dependientes |
| [06. Transportistas y ventas](docs/06-extraccion-transportistas-ventas.md) | Pruebas por pedido y línea |
| [Validación](docs/validacion.md) | Historial de desarrollo y comprobaciones |

La arquitectura prevista sigue la separación OLTP/DW/ETL/OLAP/job de BikeStores, adaptada a Northwind. Las [evidencias crudas](docs/evidencias/README.md) son locales y están excluidas de Git.
