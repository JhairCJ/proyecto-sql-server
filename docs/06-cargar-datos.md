# 06. Cargar y comprobar el DW

## Ejecutar

1. En Visual Studio, abre `Northwind.ETL`, confirma `NorthWind` como origen y `Northwind_DW` como destino en los parámetros del proyecto.
2. Ejecuta `CargarNorthwind.dtsx`. La secuencia aplica Cliente, Empleado, Proveedor, Producto, Transportista y Ventas.
3. Si una tarea falla, corrige el primer error y vuelve a ejecutar el paquete principal. No reinicies las marcas de `PackageConfig`.

## Comprobar

En SSMS, ejecuta:

```sql
USE Northwind_DW;
SELECT COUNT_BIG(*) AS Lineas,
       COUNT(DISTINCT OrderID) AS Pedidos,
       SUM(CONVERT(bigint, Quantity)) AS Unidades,
       SUM(GrossAmount) AS Bruto,
       SUM(DiscountAmount) AS Descuento,
       SUM(NetAmount) AS Neto
FROM dbo.FactSales;
SELECT PackageName, CONVERT(bigint, LastRowVersion) AS LastRowVersion,
       LastSuccessfulLoad
FROM dbo.PackageConfig ORDER BY PackageName;
SELECT f.OrderID, p.ProductID, f.Quantity, f.GrossAmount,
       f.DiscountAmount, f.NetAmount, f.Freight
FROM dbo.FactSales AS f
JOIN dbo.DimProduct AS p ON p.ProductKey=f.ProductKey
WHERE f.OrderID=10248 ORDER BY p.ProductID;
```

**Resultado de referencia:** 2.155 líneas, 830 pedidos y 51.317 unidades; bruto 1.354.458,59, descuento 88.665,83 y neto 1.265.792,76. Para el modelo, reglas de repetición y suma de flete, consulta [aplicación y recuperación](referencias/carga.md).
