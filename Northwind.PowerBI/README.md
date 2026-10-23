# Informe Northwind

Destino de entrega: conexión en vivo a `localhost/NorthwindOLAP`. La autoría comienza en `NorthwindOLAP_Test`. Power BI Desktop detectado: **2.159.883.0 (octubre de 2026)**.

Abre `Northwind.pbix` para consultar el informe o `Northwind.pbit` para crear uno nuevo. Sigue [11. Visualizar Power BI](../docs/11-visualizar-power-bi.md). Ambos archivos usan conexión en vivo, sin una copia importada del DW. Las medidas locales funcionan en la versión indicada; sus definiciones están en `medidas-informe.json`, sin modificar el BIM.

## Diccionario de cálculos

| Cálculo | Definición y alcance |
| --- | --- |
| Ticket promedio | Ventas netas / pedidos distintos; sin valor si no hay pedidos |
| Descuento porcentual | Descuentos monetarios / ventas brutas; sin valor si no hay bruto |
| Pedidos con flete informado | Pedidos distintos menos pedidos con Freight NULL; cero sí es informado |
| Flete promedio informado | Flete total / pedidos con flete informado; sin valor si no hay pedidos informados |
| Pedidos sin fecha de envío | Pedidos distintos cuyas líneas tienen ShippedDateKey NULL; no indica atraso actual |
| Participación de categoría | Neto de la categoría / neto de las categorías visibles, conservando los demás filtros |
| Insight comercial | Categoría de mayor neto entre las visibles; muestra todas las empatadas y su participación individual; mensaje explícito sin ventas |
| Insight de ticket y descuento | Ticket y descuento de la selección; mensaje explícito sin pedidos |
| Insight logístico | Ausencias de envío y flete de la selección; sin inferir retrasos |

Los visuales reutilizan `[Ventas netas]`, `[Pedidos distintos]`, `[Unidades]`, `[Flete total]` y `[Pedidos sin flete informado]` del modelo. No sumar Freight crudo: se repite en las líneas. Los subtotales de flete por producto/proveedor pueden solaparse. Proveedor e inventario representan el estado actual; país del cliente y país de envío son campos distintos.

El promedio informado divide el flete contado una vez por pedido visible entre los pedidos visibles con flete no nulo, incluido cero. En la referencia: 64.942,69 / 830 = 78,24. Un filtro de proveedor selecciona los pedidos que contienen sus productos; no reparte el flete entre proveedores.

## Páginas y filtros

- **Resumen comercial:** cinco tarjetas, evolución por año/mes y ventas por categoría.
- **Productos y clientes:** rankings por ventas netas, participación, país del cliente y detalle de neto/unidades. Los rangos se aplican solo a cada gráfico; las tarjetas del resumen conservan el total de la selección. Se incluyen empates en el rango 10.
- **Logística:** flete por pedido visible, promedio informado, ausencias, transportista, destinos y detalle por pedido.

Año de pedido, categoría y cliente se sincronizan entre las tres páginas. Proveedor se aplica en productos y clientes; transportista y pedido, en logística. Restablecer devuelve todos los períodos, categorías y clientes y limpia los controles específicos. En Desktop, selecciona el botón y pulsa **Ctrl+Enter**, o usa **Ctrl+clic**. Los botones superiores navegan de la misma forma; también puedes usar las pestañas inferiores.

El neto de la categoría se divide entre el neto de las categorías visibles mediante ALLSELECTED, conservando fecha, cliente y proveedor. El insight enumera los líderes empatados y su participación individual. Los ratios quedan vacíos sin denominador y los insights indican ausencia de datos. El calendario incluye un miembro técnico 1900, sin ventas; no es un período comercial.

## Revisión en otros equipos

Para comprobar el informe en una instalación diferente, utiliza la [lista de verificación visual](../docs/referencias/revision-visual-power-bi.md). El [registro de evidencias](../docs/evidencias/README.md) explica cómo documentar capturas obtenidas realmente sin publicar rutas, cuentas ni credenciales locales.

## Verificación local

`Northwind.pbix` se guardó, cerró y reabrió en Desktop con las tres páginas y datos de `localhost/NorthwindOLAP`. `Northwind.pbit` se exportó desde Desktop y abrió un informe nuevo con páginas y medidas; permitió guardar otro PBIX. El usuario completó manualmente la reconexión de `Northwind-desde-plantilla-Test.pbix`; se guardó y se verificó dentro del archivo `Initial Catalog=NorthwindOLAP_Test`. Los archivos principales conservan `NorthwindOLAP`. Aceptación integrada final completada: cifras, filtros, estados vacíos, restablecimiento y apertura de PBIX/PBIT comprobados. Registro: [aceptación final](../docs/evidencias/power-bi/aceptacion-final.md).

Cifras y capturas en [evidencias](../docs/evidencias/power-bi/); resultados en [validación](../docs/validacion.md). Estas comprobaciones son locales; no acreditan el equipo de otro integrante. `Report/`, `SSAS.Reference/` y `Northwind.pbip` conservan la fuente editable; `build-report.cjs` es un apoyo de autoría y no sustituye los archivos comprobados en Desktop.
