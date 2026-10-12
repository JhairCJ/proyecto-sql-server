# 05. Publicar el DW y poblar el calendario

**Requisitos:** [03](03-pruebas-aisladas.md) completada; Visual Studio 2026/SSDT y SqlPackage de esa instalación; PowerShell en la raíz del repo.

## 1. Publicar

```powershell
& '.\scripts\Publish-NorthwindWarehouse.ps1'
```

**Resultado:** mensaje «DW publicado en Northwind_DW_Test». Se prepara el esquema, los miembros desconocidos y el calendario. Repetirlo conserva datos y controles. Si falta SqlPackage, pasa su ruta mediante `-SqlPackagePath`; si falla la migración, revisa el mensaje y docs/evidencias/seccion-dw/publicacion.txt.

## 2. Comprobar en SSMS

Conecta al motor localhost con autenticación Windows y ejecuta:

```sql
USE Northwind_DW_Test;
SELECT COUNT(*) AS Dias,MIN(Fecha) AS Desde,MAX(Fecha) AS Hasta
FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0;
SELECT Cliente_SK,CustomerID FROM dbo.Dim_Cliente WHERE Cliente_SK=0;
SELECT Empleado_SK,EmployeeID FROM dbo.Dim_Empleado WHERE Empleado_SK=0;
SELECT PackageName,LastRowVersion,LastSuccessfulLoad FROM dbo.PackageConfig ORDER BY PackageName;
SELECT COUNT(*) AS VentasCargadas FROM dbo.Fact_Ventas;
```

**Resultado inicial de referencia:** 708 días, 1996-07-04 a 1998-06-11; cliente/empleado desconocidos en SK 0; cinco controles con marca cero/fecha NULL; cero ventas. La carga de entidades comerciales requiere la sección de aplicación aún pendiente.
