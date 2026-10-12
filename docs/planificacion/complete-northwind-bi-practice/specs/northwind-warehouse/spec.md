# Spec Delta

## Purpose

Representar las ventas de Northwind mediante dimensiones y hechos íntegros, con una granularidad y reglas monetarias explícitas que permitan reconciliar el análisis con su origen.

## ADDED Requirements

### Requirement: NWW-01 Identidad de dimensiones y actualización de atributos

El almacén SHALL mantener una sola fila por identidad comercial de cliente, empleado, producto y transportista, con una clave sustituta estable. Las actualizaciones de atributos SHALL conservar esa clave y reflejar los atributos actuales sin crear versiones históricas adicionales.

#### Scenario: Cliente actualizado
- **WHEN** cambia la ciudad de un cliente ya cargado
- **THEN** su dimensión refleja la ciudad actual y conserva su clave sustituta y una sola fila comercial

### Requirement: NWW-02 Granularidad e identidad de ventas

Cada hecho SHALL representar una línea de pedido y conservar OrderID y ProductID de origen. El almacén SHALL impedir más de una fila por esa pareja y permitir actualizar una línea existente sin duplicarla.

#### Scenario: Carga inicial de la referencia
- **WHEN** se cargan las 2.155 líneas de la base de referencia sin modificaciones
- **THEN** se obtienen 2.155 hechos y 830 pedidos distintos

#### Scenario: Repetición de línea
- **WHEN** se vuelve a cargar la misma pareja OrderID/ProductID
- **THEN** sigue existiendo un solo hecho para esa pareja

### Requirement: NWW-03 Calendario completo y tres funciones temporales

El calendario SHALL contener un día por fecha, con día, nombre de día, mes, nombre de mes, trimestre y año en español. SHALL cubrir el rango continuo de todas las fechas no nulas de pedido, requerida y envío, ampliarlo cuando aparezcan nuevas fechas y distinguir las tres funciones temporales en los hechos.

#### Scenario: Fecha requerida posterior al último pedido
- **WHEN** se carga la base de referencia, cuyo último pedido es del 6 de mayo de 1998 y última fecha requerida del 11 de junio de 1998
- **THEN** el calendario cubre también el 11 de junio y todas las fechas intermedias

#### Scenario: Extensión del rango
- **WHEN** aparece un pedido con una fecha fuera del calendario actual
- **THEN** el calendario se amplía antes de relacionar el hecho, sin duplicar fechas anteriores

### Requirement: NWW-04 Referencias nulas y datos inválidos

Los clientes, empleados y fechas de pedido nulos SHALL representarse con miembros identificados como desconocidos. Las fechas requerida y de envío y el transportista ausentes SHALL conservarse como ausentes. Una identidad no nula sin correspondencia, una cantidad no positiva, un precio negativo o un descuento fuera de 0 a 1 SHALL provocar un fallo identificable sin omitir silenciosamente la línea ni confirmar el avance de esa carga.

#### Scenario: Pedido pendiente de envío
- **WHEN** un pedido tiene fecha de envío nula
- **THEN** la venta permanece disponible y conserva la ausencia de fecha de envío

#### Scenario: Cliente legítimamente ausente
- **WHEN** el origen permite CustomerID nulo
- **THEN** la línea se carga con el cliente desconocido y su importe se incluye en el total

#### Scenario: Producto no resuelto
- **WHEN** la línea tiene un ProductID no nulo sin dimensión correspondiente
- **THEN** la carga falla indicando la línea y la referencia, sin perderla silenciosamente

### Requirement: NWW-05 Medidas monetarias deterministas

Los hechos SHALL utilizar el precio de OrderDetails, conservar cuatro decimales de precio y normalizar el descuento a seis decimales mediante conversión decimal. SHALL calcular bruto como cantidad por precio redondeado a dos decimales, descuento monetario como bruto por proporción redondeado a dos decimales y neto como bruto menos descuento monetario. El redondeo de empates SHALL alejarse de cero. Los totales SHALL sumar los importes ya calculados por línea, sin incluir Freight ni interpretar ventas como beneficio.

#### Scenario: Descuento del diez por ciento
- **WHEN** una línea tiene cantidad 10, precio 20 y descuento 0,10
- **THEN** registra bruto 200,00, descuento 20,00 y neto 180,00

#### Scenario: Precio de catálogo cambiado
- **WHEN** cambia Products.UnitPrice sin cambiar el detalle vendido
- **THEN** los importes de aquella venta conservan el precio del detalle

#### Scenario: Redondeo y sumatoria
- **WHEN** varias líneas producen fracciones de centavo
- **THEN** los totales coinciden con la suma de los importes individuales calculados bajo la misma regla

### Requirement: NWW-06 Reconciliación de origen y destino

La práctica SHALL permitir comparar líneas, pedidos distintos, cantidades e importes entre un origen estable y el almacén mediante las mismas reglas publicadas, e identificar duplicados y referencias inválidas. Las filas técnicas desconocidas SHALL excluirse del conteo de entidades comerciales.

#### Scenario: Reconciliación inicial
- **WHEN** finaliza la carga de la referencia sin cambios concurrentes
- **THEN** hay 91 clientes, 9 empleados, 77 productos y 3 transportistas comerciales, 2.155 líneas, 830 pedidos y 51.317 unidades, y los importes coinciden con el cálculo independiente del origen
