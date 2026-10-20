# Aplicación, staging y recuperación

La ruta principal es `CargarNorthwind.dtsx` en Visual Studio o SSISDB: `NorthWind` → staging `std` → `Northwind_DW`. `Load-NorthwindWarehouse.ps1` es el ejecutor de apoyo para pruebas aisladas.

## Contrato de carga

1. El paquete principal toma un bloqueo exclusivo de sesión en el DW antes de cambiar staging. Las cargas que compiten se detienen sin reemplazar staging.
2. El corte se obtiene con `GetDatabaseRowVersion`; `PackageConfig` conserva una marca por proceso. Los seis procesos son `Cliente`, `Empleado`, `Proveedor`, `Producto`, `Transportista` y `Ventas`.
3. La extracción carga el intervalo incremental a `std`. Para Ventas, los pedidos afectados se devuelven completos, con datos de Orders, líneas y proveedor actual del producto. Si alguna dependencia está fuera del corte, se difiere el pedido completo.
4. `DW_ApplyPackage` valida inicio/corte y aplica la dimensión o el hecho junto con el avance de la marca en la misma transacción. Un error revierte esos cambios y detiene los procesos dependientes.
5. El orden es Cliente, Empleado, Proveedor, Producto, Transportista y Ventas. Las ventas resuelven referencias, fechas y destino en su transacción. Los importes usan `OrderDetails.UnitPrice`, nunca el precio actual del catálogo.

Staging puede quedar parcialmente poblado después de un error de transporte y se reconstruye al reintentar. No se usa transacción distribuida con el OLTP ni se capturan borrados físicos.

## Hechos, destinos y freight

`DW_MergeFactVentas` inserta o actualiza por `OrderID` + `ProductKey`, conservando `SalesKey`. Un cambio de cabecera vuelve a aplicar el pedido completo; una modificación del destino de una orden no modifica otros pedidos que compartan la misma dirección. Geography normaliza cinco componentes `Ship*`, reutiliza la tupla completa y usa GeographyKey cero cuando todos son desconocidos.

SupplierKey es la asociación actual del producto. Una reasignación de proveedor cambia la dimensión ligada al hecho al recargar la orden; GrossAmount, DiscountAmount y NetAmount permanecen basados en la línea vendida. No se afirma que SupplierKey sea una fotografía histórica.

Freight viene de `Orders` y se replica por línea para permitir filtros analíticos. Debe ser idéntico en todas las líneas de cada pedido, incluso cuando el valor es NULL. En informes se suma una vez por OrderID; NULL significa no informado y cero es un importe explícito. Nunca se agrega al neto de ventas.

Las marcas anteriores se conservan al migrar. Solo el nuevo proceso Proveedor parte del corte fuente una vez completada su carga inicial. El estado de migración se inspecciona en `WarehouseMigrationState`; no se reinician controles para recuperar una carga.

## Comprobaciones y apoyo

La prueba de aplicación cubre SK estables, importes, resolución de referencias, destino compartido y reasignación de proveedor. La prueba de carga cubre repetición, competencia antes de staging, rollback de marca/hechos y reintento.

```powershell
& '.\tests\Test-Application.ps1'
& '.\tests\Test-Load.ps1'
& '.\scripts\Compare-NorthwindWarehouse.ps1'
```

Estos scripts validan exclusivamente copias identificadas. Una carga real se ejecuta desde Visual Studio/SSIS siguiendo [06](../06-cargar-datos.md).
