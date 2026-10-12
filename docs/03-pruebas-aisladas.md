# 03. Preparar las bases y los procedimientos de prueba

**Requisitos:** motor localhost, NorthWind y Northwind_DW existentes, PowerShell en la raíz del repo como en [02](02-entorno.md). La cuenta Windows necesita permisos de backup, restauración y creación de base para preparar copias.

## 1. Crear o reutilizar las copias

En PowerShell ejecuta:

```powershell
& '.\tests\Prepare-TestDatabases.ps1'
```

**Comprueba:** Created o Reused para NorthWind → Northwind_Test y Northwind_DW → Northwind_DW_Test. Created crea una copia con archivos propios; Reused conserva la copia marcada existente. Son bases permanentes, separadas de las originales.

Si rechaza una base sin marca, conserva el error; no borres esa base ni cambies el destino al original. Si faltan las bases originales, revisa la conexión: este comando prepara copias, no inicializa una computadora sin las bases de la práctica.

## 2. Comprobar desde SSMS

Actualiza **Explorador de objetos > Bases de datos**, abre **Nueva consulta** y ejecuta con F5:

```sql
USE Northwind_Test;
SELECT DB_NAME() AS BaseActual;
SELECT COUNT(*) AS Clientes FROM dbo.Customers;
SELECT COUNT(*) AS Empleados FROM dbo.Employees;
SELECT COUNT(*) AS Productos FROM dbo.Products;
SELECT COUNT(*) AS Transportistas FROM dbo.Shippers;
SELECT COUNT(*) AS Pedidos FROM dbo.Orders;
SELECT COUNT(*) AS Lineas,SUM(CONVERT(bigint,Quantity)) AS Unidades FROM dbo.OrderDetails;
SELECT name,CONVERT(nvarchar(128),value) AS Origen FROM sys.extended_properties
WHERE class=0 AND name=N'NorthwindPracticeTestDatabase';
```

**Comprueba:** Northwind_Test; conteos 91/9/77/3/830/2155/51317 y propiedad de origen NorthWind. Estos valores corresponden a la referencia actual sin cambios comerciales persistentes.

## 3. Publicar los extractores

En PowerShell:

```powershell
& '.\tests\Deploy-TestExtractors.ps1'
```

**Comprueba:** ocho mensajes `Publicado en Northwind_Test: dbo...`. Publica dos conversiones, GetDatabaseRowVersion y cinco extractores. No uses Publicar del dacpac completo para este ejercicio.

En SSMS:

```sql
USE Northwind_Test;
SELECT name FROM sys.procedures
WHERE name IN(N'RowVersionToBigInt',N'BigIntToRowVersion',N'GetDatabaseRowVersion',
 N'GetCustomerChangesByRowVersion',N'GetEmployeeChangesByRowVersion',
 N'GetProductChangesByRowVersion',N'GetShipperChangesByRowVersion',N'GetSalesChangesByRowVersion')
ORDER BY name;
```

**Comprueba:** ocho filas. Si falta alguna, revisa el error del script antes de seguir.

## 4. Volver al recorrido de ejecución

Las copias y procedimientos están preparados. Continúa en [01, paso 4](01-guia-practica.md#4-ejecutar-la-extracción-disponible) para ejecutar los cinco extractores.

Esta preparación no carga el DW. Las copias son permanentes y conservan el contenido de sus originales. Las pruebas que provocan modificaciones quedan en los documentos específicos de extractores; no son un requisito para ejecutar el proyecto.