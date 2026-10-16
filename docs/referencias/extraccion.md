# Extracción operativa: mapa y contrato

| Tabla de origen | Clave | Procedimiento | Staging |
| --- | --- | --- | --- |
| Customers | CustomerID | GetCustomerChangesByRowVersion | std.Cliente |
| Employees, supervisor opcional en Employees | EmployeeID; ReportsTo → EmployeeID | GetEmployeeChangesByRowVersion | std.Empleado |
| Products y Categories opcionales | ProductID; CategoryID; SupplierID | GetProductChangesByRowVersion | std.Producto |
| Shippers | ShipperID | GetShipperChangesByRowVersion | std.Transportista |
| Suppliers | SupplierID | GetSupplierChangesByRowVersion | std.Proveedor |
| Orders + OrderDetails + Products.SupplierID | OrderID + ProductID | GetSalesChangesByRowVersion | std.Ventas |

Orders contiene la cabecera; OrderDetails una línea por producto. El pedido 10248 tiene productos 11/42/72, 27 unidades y bruto/neto 440,00. ShipVia se entrega como ShipperID; el precio vendido viene de OrderDetails, no del catálogo. Freight y destino de envío también proceden de Orders; SupplierID procede del producto actual. Los extractores no cargan el DW.

Todos reciben BIGINT: inicio excluido y fin incluido. GetDatabaseRowVersion deriva un corte inclusivo anterior a transacciones pendientes. Las conversiones a BINARY(8) comprueban rango/ida y vuelta. Todas las filas contribuyentes deben quedar dentro del corte; un cambio de supervisor/categoría vuelve a seleccionar sus dependientes y un cambio de detalle, pedido o producto vuelve a seleccionar el pedido completo. Una dependencia posterior al corte difiere el pedido completo y permanece elegible en el siguiente intervalo. Un cambio descriptivo de proveedor se extrae de forma independiente.

La lectura usa READ COMMITTED. No representa una instantánea histórica global, no propaga borrados físicos ni mezcla marcas de distintas bases. Sin territorios ni demografía se conserva una fila por entidad. Las relaciones opcionales y los NULL del pedido permanecen disponibles para las políticas del DW.

| Prueba | Ejecución desde raíz del repo |
| --- | --- |
| Clientes | Test-CustomerExtraction.sql mediante Invoke-NorthwindTestSql |
| Marcas/concurrencia | tests/Test-RowVersion.ps1 |
| Empleados | Test-EmployeeExtraction.sql mediante Invoke-NorthwindTestSql |
| Productos | Test-ProductExtraction.sql mediante Invoke-NorthwindTestSql |
| Transportistas | Test-ShipperExtraction.sql mediante Invoke-NorthwindTestSql |
| Proveedores | Test-SupplierExtraction.sql mediante Invoke-NorthwindTestSql |
| Ventas | Test-SalesExtraction.sql mediante Invoke-NorthwindTestSql |

Los fixtures se ejecutan en copias marcadas con Northwind.TestTools.psm1; los SQL se revierten. La prueba de concurrencia confirma cambios en la copia y restaura sus nombres. Los resultados ejecutados están en [validación](../validacion.md).
