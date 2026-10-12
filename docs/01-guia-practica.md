# 01. Ejecutar el proyecto

La ruta principal trabaja con las bases reales `NorthWind` y `Northwind_DW`. Si es una computadora nueva o no existen las bases, empieza por los pasos 01 y 02 de la [guía paso a paso](<guia paso a paso.md>). Las copias `_Test` se reservan para pruebas automatizadas.

## 1. Preparar una vez

En Visual Studio, recompila `Northwind.sln`. Publica los extractores de OLTP siguiendo [03](03-preparar-origen.md) y prepara el DW siguiendo [05](05-preparar-dw.md).

## 2. Ejecutar la carga desde Visual Studio

Abre `Northwind.ETL`, confirma `NorthWind` como origen y `Northwind_DW` como destino, y ejecuta `CargarNorthwind.dtsx` siguiendo [07](07-ejecutar-ssis.md).

## 3. Comprobar

En SSMS, revisa la carga en [06](06-cargar-datos.md).

**Resultado:** 2.155 líneas, 830 pedidos, 51.317 unidades y 1.265.792,76 netos. Repetir la carga mantiene esos totales si el origen no cambió.

## 4. Publicar y automatizar

Publica SSIS en [08](08-publicar-ssis.md), implementa y consulta el modelo en [09](09-procesar-y-consultar-olap.md), y prueba el job de [10](10-ejecutar-job.md).

**Destinos:** `NorthWind` (origen), `Northwind_DW` (almacén SQL), `NorthwindOLAP` (modelo de Analysis Services). No restaures ni reinicies las bases reales para repetir la práctica.
