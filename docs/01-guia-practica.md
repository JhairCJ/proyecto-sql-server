# 01. Ejecutar el proyecto

**Requisitos:** SQL Server local, SSMS, PowerShell, Visual Studio con SSDT y bases NorthWind/Northwind_DW existentes. La carga comercial al DW, SSIS, SSAS y el job siguen pendientes.

## 1. Abrir y compilar

En Visual Studio: **Archivo > Abrir > Proyecto o solución > Northwind.slnx**. En el Explorador de soluciones, clic derecho en la solución > **Compilar**.

**Resultado:** proyectos Northwind.OLTP y Northwind.DW compilados sin errores. [Configuración](02-entorno.md).

## 2. Preparar y publicar

En PowerShell, desde la carpeta que contiene Northwind.slnx:

```powershell
& '.\tests\Prepare-TestDatabases.ps1'
& '.\tests\Deploy-TestExtractors.ps1'
& '.\scripts\Publish-NorthwindWarehouse.ps1'
```

**Resultado:** Northwind_Test con datos operativos y ocho procedimientos; Northwind_DW_Test con esquema, miembros desconocidos, controles y calendario poblado. [Preparación](03-pruebas-aisladas.md). [DW](05-preparar-dw.md).

## 3. Ejecutar y comprobar

En SSMS: **Conectar > Motor de base de datos**, servidor **localhost**, **Autenticación de Windows**. Abre **Nueva consulta**, pega el bloque completo y pulsa **F5**:

```sql
USE Northwind_Test;
DECLARE @cut TABLE(DBTS bigint);
INSERT @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @fin bigint=(SELECT DBTS FROM @cut);
EXEC dbo.GetSalesChangesByRowVersion 0,@fin;
USE Northwind_DW_Test;
SELECT COUNT(*) AS Dias,MIN(Fecha) AS Desde,MAX(Fecha) AS Hasta
FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0;
SELECT COUNT(*) AS VentasCargadas FROM dbo.Fact_Ventas;
```

**Resultado de referencia:** 2.155 líneas extraídas; calendario 1996-07-04 a 1998-06-11, 708 días; cero ventas comerciales cargadas. La extracción no puebla Fact_Ventas. [Ejecutar todos los extractores](04-ejecutar-extraccion.md).
