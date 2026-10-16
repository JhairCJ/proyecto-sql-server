# Modelo tabular Northwind

`Northwind.OLAP` importa las ocho tablas de `Northwind_DW`. Las dimensiones y columnas físicas tienen nombres en inglés; las medidas y las instrucciones para el equipo aparecen en español.

| Tabla | Uso analítico |
| --- | --- |
| `DimDate` | Calendario compartido por pedido, requerida y envío |
| `DimProduct` | Producto, categoría e inventario actual |
| `DimCustomer` | Atributos y ubicación propia del cliente |
| `DimEmployee` | Empleado y supervisor actual |
| `DimShipper` | Transportista actual del pedido |
| `DimSupplier` | Proveedor actual del producto vendido |
| `DimGeography` | Destino del pedido, distinto de la ubicación del cliente |
| `FactSales` | Una fila por línea de pedido |

Las ocho tablas se relacionan directamente mediante nueve relaciones. `DimDate[DateKey]` filtra activamente `FactSales[OrderDateKey]`; RequiredDateKey y ShippedDateKey son relaciones inactivas que las medidas activan con `USERELATIONSHIP`. No hay relación directa entre dimensiones.

## Medidas

`Ventas brutas`, `Descuentos aplicados`, `Ventas netas`, `Unidades` y `Pedidos distintos` suman importes de línea o cuentan el OrderID distinto. Las variantes de ventas, descuentos, unidades y pedidos existen para fechas requerida y envío.

`Flete total` itera los pedidos visibles y toma el Freight del pedido una vez. `Pedidos sin flete informado` cuenta Freight NULL y diferencia ese caso de Freight igual a cero. Ambas tienen variantes por fecha requerida y fecha de envío. El comparador valida primero que todas las líneas de un pedido concuerden, incluso en NULL. Las columnas de importes físicos y Freight crudo están ocultas; los datos se exponen mediante medidas explícitas.

Freight se repite en las líneas. Al filtrar por proveedor o producto, el mismo pedido puede aparecer en varios grupos y su flete puede repetirse en esos subtotales; no se deben sumar los subtotales entre categorías. No se asigna Freight a productos ni se incorpora a Ventas netas. El inventario es actual y no tiene agregación automática. Supplier es la asociación actual del producto y no representa proveedor histórico por línea.

Las claves sustitutas permanecen ocultas. `DimDate[IsUnknown]` identifica la fila técnica de calendario; las claves cero de cliente, empleado, transportista, proveedor y destino también tienen etiqueta «Desconocido». La fila de producto no se inventa.

El modelo se publica como `NorthwindOLAP` en SSAS Tabular, compatibilidad 1700. La conexión de importación usa la cuenta del servicio SSAS, que recibe `SELECT` únicamente en las ocho tablas finales. Las pruebas publican `NorthwindOLAP_Test` sobre una copia DW marcada.

```DAX
EVALUATE
ROW(
    "Pedidos", CALCULATE([Pedidos distintos], FactSales[OrderID] = 10248),
    "Unidades", CALCULATE([Unidades], FactSales[OrderID] = 10248),
    "Bruto", CALCULATE([Ventas brutas], FactSales[OrderID] = 10248),
    "Neto", CALCULATE([Ventas netas], FactSales[OrderID] = 10248),
    "Flete", CALCULATE([Flete total], FactSales[OrderID] = 10248)
)
```

Resultado de referencia para pedido 10248: 1 pedido, 27 unidades, 440,00 bruto/neto y Freight una sola vez (32,38). La guía ejecutable es [09. Procesar y consultar el modelo tabular](../09-procesar-y-consultar-olap.md).
