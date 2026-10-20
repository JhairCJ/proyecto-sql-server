# 07. Ejecutar SSIS

## 1. Preparar las bases

Completa [03](03-preparar-origen.md) y [05](05-preparar-dw.md). El proyecto está configurado para `NorthWind` y `Northwind_DW`; cambia los parámetros solo si tus bases tienen otros nombres.

## 2. Revisar el proyecto

1. Abre `Northwind.sln` en Visual Studio y expande `Northwind.ETL`.
2. Abre `Project.params` y comprueba `SourceServer = localhost`, `SourceDatabase = NorthWind`, `WarehouseServer = localhost`, `WarehouseDatabase = Northwind_DW` y `LogDirectory = .`.
3. En **Connection Managers**, comprueba `Origen.conmgr` y `DW.conmgr`. Usan `MSOLEDBSQL.1` y autenticación integrada de Windows.
4. Si cambiaste servidor o base, actualiza también ambas conexiones y usa **Probar conexión**.

## 3. Cargar los datos

1. Abre `Northwind.ETL > SSIS Packages > CargarNorthwind.dtsx`.
2. En **Control Flow**, el paquete organiza seis contenedores: `Cargar Cliente`, `Cargar Empleado`, `Cargar Proveedor`, `Cargar Producto`, `Cargar Transportista` y `Cargar Ventas`.
3. Los primeros cinco actualizan dimensiones; Ventas carga las líneas del pedido con fechas, cliente, empleado, transportista, proveedor, destino, importes y Freight del encabezado.
4. Para ver un flujo, expande su contenedor y abre **Extraer a staging**. Vuelve a **Control Flow** al terminar.
5. Clic derecho en el fondo y selecciona **Ejecutar paquete**. Espera `Package execution completed with success` y detén la depuración con **Mayús+F5**.

El principal ya ejecuta los seis procesos en el orden necesario. No lances otro paquete de carga mientras esté activo.

## 4. Comprobar y repetir

En SSMS, conecta al motor `localhost`, abre una consulta en `Northwind_DW` y ejecuta:

```sql
USE Northwind_DW;
SELECT COUNT_BIG(*) AS Lines,
       COUNT(DISTINCT OrderID) AS Orders,
       SUM(CONVERT(bigint,Quantity)) AS Units,
       SUM(GrossAmount) AS GrossAmount,
       SUM(DiscountAmount) AS DiscountAmount,
       SUM(NetAmount) AS NetAmount
FROM dbo.FactSales;

SELECT PackageName,CONVERT(bigint,LastRowVersion) AS RowVersion,
       LastSuccessfulLoad
FROM dbo.PackageConfig ORDER BY PackageName;

SELECT OrderID,ProductKey,Quantity,Freight,NetAmount
FROM dbo.FactSales WHERE OrderID=10248 ORDER BY ProductKey;
```

Resultado de referencia: **2.155 líneas, 830 pedidos y 51.317 unidades**. Los importes netos suman **1.265.792,76**. Hay seis controles de carga con fecha de éxito. Para el pedido 10248, Freight es **32,38** en sus tres líneas porque pertenece al pedido; las medidas analíticas lo cuentan una sola vez.

Ejecuta `CargarNorthwind.dtsx` otra vez y repite la consulta. Sin cambios en el origen, los conteos e importes se mantienen. No trunques tablas ni reinicies las marcas de `PackageConfig`.

## 5. Si ocurre un error

En Visual Studio abre **Progress** y revisa el primer error rojo. Si el proveedor no está registrado, instala OLE DB Driver 18 x64 y confirma `MSOLEDBSQL.1`. Si falla una conexión, revisa los parámetros y administradores de conexión. Si el DW está ocupado, espera a que finalice la otra carga antes de reintentar.
