# 01. Ejecutar el proyecto

**Requisitos:** SQL Server local, SSMS, PowerShell, Visual Studio 2026 con SSDT y bases NorthWind/Northwind_DW existentes. SSIS, SSAS y job todavía pendientes.

## 1. Abrir y compilar

En Visual Studio: **Archivo > Abrir > Proyecto o solución > Northwind.slnx**. Clic derecho en la solución > **Compilar**.

**Resultado:** Northwind.OLTP y Northwind.DW sin errores. [Configuración](02-entorno.md).

## 2. Preparar y cargar

En PowerShell, desde la carpeta que contiene Northwind.slnx:

```powershell
& '.\tests\Prepare-TestDatabases.ps1'
& '.\tests\Deploy-TestExtractors.ps1'
& '.\scripts\Publish-NorthwindWarehouse.ps1'
& '.\scripts\Load-NorthwindWarehouse.ps1'
& '.\scripts\Compare-NorthwindWarehouse.ps1'
```

**Resultado:** Northwind_Test con datos operativos; Northwind_DW_Test con dimensiones y ventas pobladas; cinco entidades «Confirmado» y todas las comparaciones True. [Preparación](03-pruebas-aisladas.md). [Carga](06-cargar-datos.md).

## 3. Comprobar en SSMS

Conecta al motor **localhost**, **Autenticación de Windows**. Abre **Nueva consulta**, pega y pulsa **F5**:

```sql
USE Northwind_DW_Test;
SELECT COUNT(*) AS Lineas,COUNT(DISTINCT OrderID) AS Pedidos,
 SUM(CONVERT(bigint,Cantidad)) AS Unidades,SUM(ImporteNeto) AS Neto
FROM dbo.Fact_Ventas;
SELECT OrderID,ProductID,Cantidad,ImporteNeto
FROM dbo.Fact_Ventas WHERE OrderID=10248 ORDER BY ProductID;
```

**Referencia:** 2.155 líneas, 830 pedidos, 51.317 unidades, neto 1.265.792,76. Pedido 10248: productos 11/42/72, 27 unidades, neto 440,00.
