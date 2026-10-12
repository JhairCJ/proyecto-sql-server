# Spec Delta

## Purpose

Permitir analizar las ventas cargadas mediante un modelo tabular con medidas y relaciones comprensibles, cuyos resultados coincidan con el almacén de datos.

## ADDED Requirements

### Requirement: NWA-01 Modelo analítico relacionado

El modelo SHALL exponer hechos y las cinco dimensiones y permitir filtrar ventas por cliente y su país, empleado, producto y su categoría o proveedor, transportista y tiempo. Los miembros desconocidos SHALL tener una etiqueta identificable y las filas técnicas de calendario SHALL distinguirse del calendario real.

#### Scenario: Ventas por categoría y año
- **WHEN** se filtran una categoría y un año de pedido
- **THEN** las medidas incluyen únicamente las líneas relacionadas con ambos filtros

### Requirement: NWA-02 Medidas de ventas y pedidos

El modelo SHALL proporcionar ventas brutas, descuentos monetarios, ventas netas, unidades y pedidos distintos. Los pedidos SHALL contarse por identidad de pedido y no por cantidad de líneas; los importes SHALL sumar las medidas de línea del almacén.

#### Scenario: Pedido con tres líneas
- **WHEN** se analiza únicamente el pedido 10248 de la referencia
- **THEN** el conteo de pedidos es 1, las unidades son 27 y las ventas brutas y netas son 440,00

#### Scenario: Totales de referencia
- **WHEN** se analiza la referencia completa cargada y procesada
- **THEN** el conteo de pedidos es 830, las unidades son 51.317 y los importes coinciden con el almacén

### Requirement: NWA-03 Selección explícita de fecha

El análisis temporal predeterminado SHALL usar la fecha de pedido. La solución SHALL ofrecer análisis explícitos por fecha requerida y de envío sin combinar accidentalmente funciones temporales. El análisis por envío SHALL excluir pedidos sin fecha de envío cuando se seleccionen fechas de envío reales.

#### Scenario: Fechas en meses distintos
- **WHEN** un pedido se hizo en un mes y se envió en otro
- **THEN** el análisis predeterminado lo agrupa por el mes de pedido y el análisis de envío por el mes de envío

#### Scenario: Pedido no enviado
- **WHEN** se analizan ventas enviadas en un mes concreto
- **THEN** no se atribuyen a ese mes líneas sin fecha de envío

### Requirement: NWA-04 Actualización y evidencia del modelo

El modelo SHALL disponer de un procesamiento reproducible posterior a la carga y de una comprobación de sus medidas contra el DW. Una modificación del DW no SHALL declararse disponible en el modelo de importación antes de su procesamiento correcto.

#### Scenario: Modelo actualizado
- **WHEN** una carga agrega una venta y luego se procesa el modelo correctamente
- **THEN** las medidas reflejan la nueva venta y coinciden con el DW

#### Scenario: Fallo de procesamiento
- **WHEN** la carga del DW termina pero falla el procesamiento del modelo
- **THEN** se informa el fallo analítico y no se declara el ciclo completo actualizado
