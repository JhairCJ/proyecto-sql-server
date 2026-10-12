# Modelo y publicación del DW

Northwind.DW es el propietario declarativo de los objetos del almacén. Northwind.OLTP contiene únicamente el origen. La solución Northwind.slnx compila ambos SQL; ETL/OLAP/job son responsabilidades posteriores, como en BikeStores.

| Tabla | Identidad comercial | Clave del DW | Relación con hechos |
| --- | --- | --- | --- |
| Dim_Cliente | CustomerID único | Cliente_SK | Cliente_SK obligatorio; 0 si falta cliente |
| Dim_Empleado | EmployeeID único | Empleado_SK | Empleado_SK obligatorio; 0 si falta empleado |
| Dim_Producto | ProductID único | Producto_SK | Producto_SK obligatorio; referencia no resuelta es error |
| Dim_Transportista | ShipperID único | Transportista_SK | NULL si falta transportista |
| Dim_Tiempo | Fecha única | AAAAMMDD; 0 desconocido | Pedido obligatorio; requerida/envío admiten NULL |
| Fact_Ventas | OrderID/ProductID único | Venta_SK | Una fila por línea, siete relaciones a dimensiones |

Cliente desconocido: SK 0, CustomerID ~UNK~. Empleado desconocido: SK 0, EmployeeID 0. Fecha desconocida: SK 0, 1900-01-01, excluida del calendario real. Los controles y miembros se crean solo si faltan. Las dimensiones son tipo 1: cambian atributos conservando SK, sin historia. Precio y descuento son DECIMAL(19,4)/DECIMAL(9,6), cantidad SMALLINT positiva. Las restricciones rechazan duplicados, precio negativo, descuento fuera de 0..1 y claves inexistentes.

DW_LoadDimTiempo usa el rango de las tres fechas de staging o parámetros explícitos; genera días continuos, nombres españoles independientes de idioma/DATEFIRST y amplía sin duplicar. La publicación prepara el rango observado en Northwind_Test.

Regla monetaria por línea: bruto = ROUND(cantidad × precio,2); descuento monetario = ROUND(bruto × proporción normalizada a seis decimales,2); neto = bruto − descuento monetario. SQL ROUND aleja los empates de cero. Los totales suman resultados por línea. DW_CalculateAmounts aplica la regla; las verificaciones calculan una referencia independiente sobre OrderDetails. Freight no se repite y el precio de catálogo no interviene. Ejemplo: cantidad 10, precio 20, descuento 0,1 → 200/20/180. Precio 0,0050 por una unidad → bruto 0,01; bruto 1 con proporción 0,005000 → descuento 0,01.

La transferencia REAL → decimal de BulkCopy puede truncar valores; la carga normaliza en SQL antes del transporte. Los paquetes deberán conservar esa conversión explícita; no se considera integración SSIS probada.

La migración deriva ProductID desde Dim_Producto antes de hacerla obligatoria, rechaza identidades ambiguas o importes incompatibles y convierte explícitamente los tipos. La publicación conserva BlockOnPossibleDataLoss=True, propiedades extendidas y opciones de base. No elimina objetos ajenos ni reinicia datos/marcas. Las opciones se basan en [SqlPackage Publish](https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-publish).

| Archivo anterior | Propietario/archivo final | Cambio |
| --- | --- | --- |
| OLTP/Scripts/DW y dimensiones.sql, Fact.sql, Indices_Fact.sql | Northwind.DW/dbo/Tables/*.sql | Definiciones compiladas, claves y restricciones |
| OLTP/Scripts/Esquema_y_tablas.sql | Northwind.DW/std/Schema.sql y Tables/*.sql | SupervisorName declarativo; tipos decimales de ventas |
| OLTP/Scripts/Control/PackageConfig.sql | Northwind.DW/dbo/Tables/PackageConfig.sql y Deployment/Seed.sql | Esquema y filas iniciales separados/repetibles |
| OLTP/Scripts/Control y Procedures/GetLast/UpdateLastPackageRowVersion.sql | Northwind.DW/dbo/Procedures/*.sql | Un propietario; control estricto y avance transaccional |
| OLTP/Scripts/DW_Merge.sql | Northwind.DW/dbo/Procedures/DW_MergeDim*.sql, DW_LoadDimTiempo.sql | Reutilizar dimensiones; calendario corregido |
| OLTP/Scripts/DW_Merge.sql, procedimiento de hechos | Northwind.DW/dbo/Procedures/DW_MergeFactVentas.sql | Aplicación compilada, claves validadas y actualización por pedido/producto |
| OLTP/PostDeploy VerificarPackages.sql | Retirado | El OLTP no consulta ni configura el DW al publicarse |

La publicación actualiza el procedimiento de hechos al contrato compilado. Publicar prepara esquema/calendario; Load-NorthwindWarehouse.ps1 puebla entidades comerciales mediante DW_ApplyPackage. El contrato de aplicación y recuperación está en [carga](carga.md).

BikeStores: OLTP ↔ Northwind.OLTP; DW/staging/control ↔ Northwind.DW; ETL ↔ futura carga/paquetes; tabular ↔ futuro Northwind.OLAP; Agent ↔ futuro job propio. No hay tiendas equivalentes; Northwind usa transportistas.

[Guía de publicación](../05-preparar-dw.md). [Resultados](../validacion.md).
