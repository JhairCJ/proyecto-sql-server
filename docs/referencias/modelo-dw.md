# Modelo y migración del DW

`Northwind.DW` administra esquema, staging, aplicación y controles de `Northwind_DW`. El modelo final contiene una tabla de hechos a nivel de línea y siete dimensiones, todas en inglés. Los nombres para informes y guías permanecen en español.

| Tabla | Uso | Identidad de negocio |
| --- | --- | --- |
| `DimDate` | Fecha de pedido, requerida y envío | `FullDate`; `DateKey` usa YYYYMMDD |
| `DimProduct` | Producto, categoría e inventario actual | `ProductID` |
| `DimCustomer` | Cliente y ubicación propia | `CustomerID` |
| `DimEmployee` | Empleado y supervisor actual | `EmployeeID` |
| `DimShipper` | Transportista actual | `ShipperID` |
| `DimSupplier` | Proveedor actual | `SupplierID` |
| `DimGeography` | Destino de envío de la orden | Tupla de cinco campos `Ship*` |
| `FactSales` | Una fila por `OrderID` y `ProductKey` | `OrderID` + `ProductKey` |

`FactSales` tiene nueve claves foráneas: tres roles de fecha y una hacia cada una de las otras seis dimensiones. Producto conserva su `ProductID` mediante `DimProduct`; no hay `FactOrder`, ni relación directa entre dimensiones. Customer representa la ubicación del cliente; Geography representa el destino de cada pedido.

## Medidas y semántica

- `GrossAmount = ROUND(Quantity * UnitPrice, 2)`; `DiscountAmount = ROUND(GrossAmount * Discount, 2)`; `NetAmount = GrossAmount - DiscountAmount`. Los tres valores son `DECIMAL(19,2)` calculados por línea.
- `Freight` es el importe del encabezado de Orders, `DECIMAL(19,4)` y puede ser NULL. Se repite en las líneas para poder filtrar la venta, por lo que al totalizar se suma una vez por pedido después de comprobar que todas las líneas del pedido tienen el mismo valor, incluyendo la distinción NULL/cero. No se distribuye entre productos ni se suma a NetAmount.
- `DimProduct` contiene el inventario actual, no inventario histórico. `DimSupplier` refleja el proveedor actual del producto. Cambiar ese proveedor corrige la asociación de las ventas recargadas, pero el origen no registra el proveedor histórico de cada unidad.
- Las dimensiones comerciales usan cambios tipo 1: se conserva la clave sustituta y se actualizan atributos actuales. No se modelan historial tipo 2 ni borrados físicos del origen.

Los miembros desconocidos usan clave cero para fechas, clientes, empleados, transportistas, proveedores y geografía. No existe producto ficticio: una línea con ProductID sin resolver se rechaza. Las fechas requerida y envío y el Freight desconocido permanecen NULL. Los destinos se normalizan quitando espacios externos y tratando cadena vacía como NULL; la combinación completa se reutiliza, sin sobrescribir otros pedidos.

## Publicación y migración

La publicación DACPAC es aditiva (`BlockOnPossibleDataLoss=True`, `DropObjectsNotInSource=False`) y los seeds son condicionales. `Migrate-NorthwindStar.sql` registra una etapa simple en `WarehouseMigrationState`. En un DW vacío registra `SkippedEmpty`; con hechos anteriores carga desde la copia estable del OLTP, conserva `SalesKey`, claves existentes, importes y marcas previas, y registra `Validated`. La operación de copia es transaccional, se puede reintentar y detiene ambigüedades o referencias no recuperables. La marca de Proveedor se inicializa al corte solo tras la carga completa.

La migración conserva las tablas anteriores para recuperación y consumidores activos. Solo se retiran después de actualizar ETL/SSAS/permisos y conciliar el corte. La publicación normal nunca borra esas tablas.

## Retirada explícita del modelo anterior

La retirada es un paso manual posterior al corte, no forma parte de la publicación normal. Antes, completa la carga de los seis procesos y comprueba el comparador DW contra el OLTP; procesa `NorthwindOLAP`, confirma que sus ocho tablas y medidas coinciden con el DW, y actualiza los permisos y consumidores que aún usen nombres anteriores. Conserva una copia de seguridad y el resultado de conciliación.

Después, abre `Northwind.DW/Deployment/Retire-LegacyWarehouse.sql` en SSMS conectado a la base que vas a retirar. Revisa el destino y cambia `@ConfirmCutover` de `0` a `1` solo para ese corte aprobado. Ejecuta el script una vez y comprueba `WarehouseMigrationState.Stage = 'Cutover'`. El script exige la etapa de migración validada (o almacén vacío), los seis procesos cargados y Freight coherente por pedido; si alguna condición falla, se detiene. Luego publica de nuevo el DACPAC con el perfil habitual y verifica que el esquema final sigue teniendo las ocho tablas y seis controles.

| Anterior | Final |
| --- | --- |
| `Dim_Tiempo` / `Tiempo_SK` | `DimDate` / `DateKey` |
| `Dim_Producto` / `Producto_SK` | `DimProduct` / `ProductKey` |
| `Dim_Cliente` / `Cliente_SK` | `DimCustomer` / `CustomerKey` |
| `Dim_Empleado` / `Empleado_SK` | `DimEmployee` / `EmployeeKey` |
| `Dim_Transportista` / `Transportista_SK` | `DimShipper` / `ShipperKey` |
| — | `DimSupplier` / `SupplierKey` |
| — | `DimGeography` / `GeographyKey` |
| `Fact_Ventas` / `Venta_SK` | `FactSales` / `SalesKey` |

```sql
SELECT MigrationName, SchemaVersion, Stage, SourceDatabase,
       CONVERT(bigint, SourceCut) AS SourceCut, UpdatedAt
FROM dbo.WarehouseMigrationState
WHERE MigrationName=N'ReplaceNorthwindStarModel';
SELECT t.name AS TableName
FROM sys.tables AS t
WHERE t.name IN (N'DimDate',N'DimProduct',N'DimCustomer',N'DimEmployee',
 N'DimShipper',N'DimSupplier',N'DimGeography',N'FactSales')
ORDER BY t.name;
```

La ruta de publicación está en [05](../05-preparar-dw.md); los pasos de carga y su transacción están en [carga](carga.md).
