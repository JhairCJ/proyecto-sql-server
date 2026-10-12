# 01. Abrir y ejecutar el proyecto Northwind

La solución actual contiene Northwind.OLTP. Sus extractores pueden ejecutarse en la copia Northwind_Test. **La carga completa de Northwind_DW, los paquetes ETL, el modelo analítico y el job todavía no están terminados.**

## 1. Comprobar los requisitos

Necesitas SQL Server local, SSMS, PowerShell y Visual Studio con SSDT. En este equipo se usan SQL Server 2025 Developer, SSMS 22 y Visual Studio 2026. [02-entorno.md](02-entorno.md) explica cómo comprobar la conexión y compilar si aparece un problema.

1. Abre SSMS.
2. Selecciona **Conectar > Motor de base de datos**.
3. Servidor: **localhost**. Autenticación: **Windows**.
4. Pulsa **Conectar**. Para un error de certificado en este servidor local, activa **Confiar en el certificado del servidor** y reintenta.
5. Abre **Nueva consulta** y ejecuta:

```sql
SELECT name,state_desc FROM sys.databases
WHERE name IN(N'NorthWind',N'Northwind_DW');
```

**Resultado:** dos filas con estado ONLINE. Estas bases ya existen en este equipo. Si faltan en otra computadora, la inicialización completa de esa instalación sigue pendiente; descargar el repo no crea ni puebla las bases.

## 2. Abrir la solución

1. Abre Visual Studio > **Archivo > Abrir > Proyecto o solución**.
2. Selecciona Northwind.slnx en la carpeta del repositorio.
3. En **Explorador de soluciones**, clic derecho en **Northwind.OLTP > Compilar**.
4. Revisa **Ver > Salida** y **Ver > Lista de errores**.

**Resultado:** compilación sin errores; actualmente hay 19 advertencias heredadas SQL71502. Se genera Northwind.OLTP/bin/Debug/Northwind.OLTP.dacpac. Compilar no puebla ninguna base. Este proyecto SQL no se ejecuta como una aplicación con F5; sus procedimientos se ejecutan en SQL Server.

## 3. Preparar el destino que funciona actualmente

Abre PowerShell y ejecuta en este equipo:

```powershell
Set-Location -LiteralPath 'C:\Users\Admin\Desktop\practica sql\practica sql server'
& '.\tests\Prepare-TestDatabases.ps1'
& '.\tests\Deploy-TestExtractors.ps1'
```

En otra ubicación, sustituye la ruta por la carpeta que contiene Northwind.slnx.

**Resultado:** las bases Northwind_Test y Northwind_DW_Test se crean copiando sus originales, o se reutilizan si ya existen y están marcadas. Después aparecen ocho mensajes de publicación en Northwind_Test: dos conversiones, el corte y cinco extractores. [03](03-pruebas-aisladas.md) detalla esta preparación si falla.

La copia Northwind_Test se puebla mediante la copia de seguridad/restauración del origen existente; no mediante una carga ETL. Northwind_DW_Test conserva el estado del DW original: si está vacío, la copia también queda vacía.

## 4. Ejecutar la extracción disponible

En SSMS, abre **Nueva consulta**, pega el bloque completo y pulsa **F5**:

```sql
USE Northwind_Test;
DECLARE @cut TABLE(DBTS bigint);
INSERT INTO @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @fin bigint=(SELECT DBTS FROM @cut);
EXEC dbo.GetCustomerChangesByRowVersion 0,@fin;
EXEC dbo.GetEmployeeChangesByRowVersion 0,@fin;
EXEC dbo.GetProductChangesByRowVersion 0,@fin;
EXEC dbo.GetShipperChangesByRowVersion 0,@fin;
EXEC dbo.GetSalesChangesByRowVersion 0,@fin;
```

**Resultado:** cinco conjuntos de datos: 91 clientes, 9 empleados, 77 productos, 3 transportistas y 2.155 líneas de venta en la referencia actual. Los procedimientos leen datos; no insertan esas filas en el DW.

El intervalo va de cero al corte actual. Ese corte identifica las escrituras que puede extraer el procedimiento; no es una fecha.

## 5. Comprobar si el DW está poblado

```sql
USE Northwind_DW_Test;
SELECT COUNT(*) AS ClientesCargados FROM dbo.Dim_Cliente;
SELECT COUNT(*) AS LineasCargadas FROM dbo.Fact_Ventas;
SELECT PackageName,LastRowVersion,LastSuccessfulLoad
FROM dbo.PackageConfig ORDER BY PackageName;
```

**Resultado actual de referencia:** cero clientes y cero hechos; cinco controles con marca cero y fecha NULL. Obtener filas en el paso 4 no cambia estos conteos.

## 6. Punto donde se detiene la ejecución actual

Todavía falta implementar y verificar el recorrido **extracción → staging → dimensiones/calendario/hechos → procesamiento analítico → job**. Los scripts DW existentes no equivalen a una carga completa validada.

Por tanto, actualmente no hay un paquete principal ni un comando terminado que pueble todo y procese el modelo. Las instrucciones de carga inicial, carga incremental, procesamiento y ejecución programada se incorporarán cuando existan esos componentes y se pueda ejecutar el recorrido real.

Los documentos [04](04-extraccion-clientes.md), [05](05-extraccion-empleados-productos.md) y [06](06-extraccion-transportistas-ventas.md) son referencias y pruebas específicas de extractores; no son pasos adicionales necesarios para poblar el sistema. El historial de cambios y verificaciones está separado en [validacion.md](validacion.md).
