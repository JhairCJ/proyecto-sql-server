# Modelo tabular Northwind

`Northwind.OLAP` reproduce la responsabilidad de análisis de `BikeStoresOLAP` en `Data-Management-and-BI/BikeStoresBI`, sobre el almacén `Northwind_DW`.

| BikeStores | Northwind | Adaptación |
| --- | --- | --- |
| Customer | Dim_Cliente | CustomerID y atributos actuales del cliente |
| Staff | Dim_Empleado | EmployeeID y supervisor actual |
| Product | Dim_Producto | ProductID; categoría y proveedor quedan como atributos |
| Store | Sin dimensión equivalente | Northwind no tiene tiendas en el modelo de ventas |
| Date | Dim_Tiempo | Una dimensión reutilizada para pedido, fecha requerida y envío |
| FactOrders | Fact_Ventas | Una fila por OrderID/ProductID; no se cuenta cada línea como pedido |
| BikeStoresOLAP | Northwind.OLAP | Modelo tabular SSAS en Northwind.OLAP.bim |

La estrella relaciona las cinco dimensiones con Fact_Ventas mediante claves sustitutas. Las claves técnicas permanecen ocultas; las claves de origen, nombres, país y categoría sirven para filtrar. Las jerarquías permiten explorar país/cliente, categoría/producto y año/trimestre/mes/fecha.

Las medidas suman los importes de línea ya calculados en el DW: `Ventas brutas = SUM(ImporteBruto)`, `Descuentos aplicados = SUM(ImporteDescuento)`, `Ventas netas = SUM(ImporteNeto)`, `Unidades = SUM(Cantidad)` y `Pedidos distintos = DISTINCTCOUNT(OrderID)`. No se recalculan precios con el catálogo ni se incluye flete.

`Dim_Tiempo[Tiempo_SK]` filtra activamente `FechaPedido_SK`. Las relaciones con `FechaRequerida_SK` y `FechaEnvio_SK` están inactivas. Las medidas con sufijo «por fecha requerida» o «por fecha de envío» activan la función correspondiente; por ejemplo, `[Ventas netas por fecha de envío]`. Al filtrar fechas reales, las líneas con envío ausente no se asignan a un mes.

Las dimensiones usan tipo 1: un cambio reemplaza el atributo anterior, por lo que una categoría o ciudad muestra su valor actual también para hechos antiguos. El precio vendido permanece histórico en Fact_Ventas. Las claves cero identifican miembros desconocidos; `Dim_Tiempo[TipoFecha]` separa la fila técnica de fechas reales.

El modelo se publica sobre SSAS tabular con compatibilidad 1700, disponible para SQL Server 2025. La conexión de importación usa la cuenta del servicio SSAS y permisos de solo lectura sobre las seis tablas del almacén de prueba. El script local solo autoriza `Northwind_DW_Test`.

```DAX
EVALUATE
ROW(
    "Pedidos", CALCULATE([Pedidos distintos], Fact_Ventas[OrderID] = 10248),
    "Unidades", CALCULATE([Unidades], Fact_Ventas[OrderID] = 10248),
    "Bruto", CALCULATE([Ventas brutas], Fact_Ventas[OrderID] = 10248),
    "Neto", CALCULATE([Ventas netas], Fact_Ventas[OrderID] = 10248)
)
```

Resultado de referencia: 1 pedido, 27 unidades, 440,00 bruto y 440,00 neto. La guía ejecutable es [09. Procesar y consultar el modelo tabular](../09-procesar-y-consultar-olap.md).
