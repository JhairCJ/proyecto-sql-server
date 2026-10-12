# 06. Comprobar y repetir la carga

## 1. Cargar

Ejecuta `CargarNorthwind.dtsx` con [07](07-ejecutar-ssis.md).

## 2. Comprobar en SSMS

Conecta al motor `localhost`. En **Nueva consulta**, ejecuta con **F5**:

```sql
USE Northwind_DW_Test;
SELECT COUNT(*) AS Lineas,COUNT(DISTINCT OrderID) AS Pedidos,
       SUM(CONVERT(bigint,Cantidad)) AS Unidades,SUM(ImporteNeto) AS Neto
FROM dbo.Fact_Ventas;
SELECT PackageName,LastRowVersion,LastSuccessfulLoad
FROM dbo.PackageConfig ORDER BY PackageName;
SELECT OrderID,ProductID,Cantidad,ImporteNeto
FROM dbo.Fact_Ventas WHERE OrderID=10248 ORDER BY ProductID;
```

**Resultado de referencia:** 2.155 líneas, 830 pedidos, 51.317 unidades, neto 1.265.792,76; cinco controles con fecha de éxito. Pedido 10248: tres líneas, 27 unidades y neto total 440,00.

## 3. Repetir

Vuelve a ejecutar el paquete principal y la consulta.

**Resultado sin cambios del origen:** mismos conteos e importes. Si falla, abre **Progreso / Progress**, corrige el primer error rojo y repite el paquete completo. Si indica «DW ocupado», espera a que termine la otra ejecución.
