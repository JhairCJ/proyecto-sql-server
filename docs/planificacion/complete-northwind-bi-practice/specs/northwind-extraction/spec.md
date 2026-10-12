# Spec Delta

## Purpose

Obtener datos operativos de Northwind con identidades estables y sin multiplicaciones o pérdidas causadas por relaciones opcionales, para alimentar el análisis de ventas.

## ADDED Requirements

### Requirement: NWX-01 Una fila por entidad de origen

La extracción SHALL devolver exactamente una fila por CustomerID, EmployeeID, ProductID y ShipperID seleccionados, con los atributos utilizados por las dimensiones. Las relaciones de territorios y datos demográficos no SHALL multiplicar ni excluir entidades; esos atributos no forman parte del análisis solicitado.

#### Scenario: Empleado con varios territorios
- **WHEN** un empleado pertenece a varios territorios y se extraen empleados
- **THEN** aparece una sola fila con su identidad y atributos, incluso si otro empleado no tiene territorios

#### Scenario: Cliente con varias clasificaciones
- **WHEN** un cliente tiene varias clasificaciones demográficas
- **THEN** la extracción conserva una sola fila del cliente

### Requirement: NWX-02 Atributos dependientes y relaciones opcionales

La extracción SHALL conservar productos sin categoría o proveedor y empleados sin supervisor. SHALL incluir los atributos disponibles de categoría, proveedor y supervisor, y volver a seleccionar las entidades afectadas cuando se modifiquen esos atributos dependientes.

#### Scenario: Cambio de nombre de categoría
- **WHEN** cambia una categoría dentro del intervalo de extracción
- **THEN** se devuelven los productos que la referencian con el nombre actualizado, aunque sus propias filas no hayan cambiado

#### Scenario: Producto sin proveedor
- **WHEN** un producto tiene SupplierID nulo
- **THEN** se devuelve el producto con los atributos de proveedor ausentes

#### Scenario: Cambio de nombre de supervisor
- **WHEN** cambia el nombre de un supervisor
- **THEN** se seleccionan sus empleados subordinados para actualizar el nombre de supervisor

### Requirement: NWX-03 Una fila por línea de pedido

La extracción de ventas SHALL combinar cabeceras y detalles y devolver una fila por pareja OrderID/ProductID, con identidades de cliente, empleado y transportista, tres fechas, precio vendido, cantidad y descuento. SHALL seleccionar la línea cuando cambie su detalle y todas las líneas afectadas cuando cambie su cabecera.

#### Scenario: Pedido 10248
- **WHEN** se extrae el pedido 10248 de la base de referencia
- **THEN** se obtienen tres líneas con productos 11, 42 y 72, sin confundirlas con tres pedidos

#### Scenario: Cambio de fecha de envío
- **WHEN** se actualiza solamente la fecha de envío de un pedido
- **THEN** todas sus líneas vuelven a seleccionarse

### Requirement: NWX-04 Intervalos de cambios confirmados

La extracción incremental SHALL aceptar una marca inferior exclusiva y superior inclusiva del mismo origen, procesar cambios confirmados y excluir datos no confirmados. Una modificación posterior al límite que se difiera SHALL permanecer elegible para la siguiente carga. Las marcas SHALL conservar íntegramente su valor durante las conversiones.

#### Scenario: Límites del intervalo
- **WHEN** una entidad tiene marca igual al límite inferior, otra al superior y otra posterior al superior
- **THEN** la primera no se selecciona, la segunda sí y la tercera permanece pendiente para el siguiente intervalo

#### Scenario: Transacción pendiente
- **WHEN** una modificación todavía no está confirmada al establecer el corte de carga
- **THEN** no se publica como dato confirmado ni se pierde cuando posteriormente se confirma

#### Scenario: Atributo actualizado después del corte
- **WHEN** un atributo dependiente cambia después del corte mientras se lee la entidad
- **THEN** se difiere la fila que no puede representarse dentro del corte y el cambio dependiente permite seleccionarla en una carga posterior
