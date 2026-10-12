# 03. Preparar las copias y los procedimientos

**Requisitos:** localhost, NorthWind y Northwind_DW existentes, PowerShell en la raíz del repo y cuenta Windows con permisos de backup/restauración/publicación.

## 1. Crear o reutilizar copias

```powershell
& '.\tests\Prepare-TestDatabases.ps1'
```

**Resultado:** Created o Reused para Northwind_Test y Northwind_DW_Test. Si rechaza una copia sin marca, conserva el error; no la elimines ni cambies el destino al original.

## 2. Publicar extractores

```powershell
& '.\tests\Deploy-TestExtractors.ps1'
```

**Resultado:** ocho mensajes de publicación en Northwind_Test.

## 3. Comprobar

En SSMS, conectado al motor localhost, ejecuta:

```sql
USE Northwind_Test;
SELECT COUNT(*) AS Clientes FROM dbo.Customers;
SELECT COUNT(*) AS Lineas FROM dbo.OrderDetails;
SELECT name FROM sys.procedures WHERE name LIKE N'%RowVersion%' ORDER BY name;
```

**Resultado:** 91 clientes, 2.155 líneas y ocho procedimientos de soporte/extracción. Continúa con [04](04-ejecutar-extraccion.md) y [05](05-preparar-dw.md).
