# Spec Delta

## Purpose

Ejecutar cargas iniciales e incrementales de Northwind de forma observable y recuperable, preservando la identidad de las ventas y el avance correcto de cada proceso.

## ADDED Requirements

### Requirement: NWE-01 Recorrido completo de carga

La solución SHALL ofrecer paquetes ejecutables para clientes, empleados, productos, transportistas y ventas, así como un proceso principal que prepare el calendario y cargue las dimensiones antes de los hechos. Las conexiones SHALL poder configurarse para el entorno local y para pruebas aisladas.

#### Scenario: Primera ejecución
- **WHEN** se ejecuta el proceso principal contra el almacén preparado y vacío
- **THEN** carga las dimensiones y el calendario antes de cargar los hechos y entrega un resultado verificable

### Requirement: NWE-02 Avance confirmado por proceso

Cada proceso SHALL registrar su marca y fecha de última carga correcta solamente cuando sus modificaciones de destino se confirmen. La aplicación de cambios finales y su marca SHALL ser atómicas. Los fallos SHALL conservar el avance previo de ese proceso. Un destino vacío con una marca no inicial SHALL generar un error de estado en vez de declararse cargado.

#### Scenario: Error al aplicar cambios
- **WHEN** falla la actualización de una dimensión o hechos antes de confirmar la operación
- **THEN** se deshacen sus cambios finales y su marca y fecha de éxito permanecen como estaban

#### Scenario: Error al guardar el avance
- **WHEN** no puede guardarse la nueva marca después de aplicar los cambios dentro de la operación
- **THEN** la operación no se confirma parcialmente

#### Scenario: Destino vaciado por fuera del proceso
- **WHEN** la marca de un proceso indica avance previo pero su destino comercial está vacío
- **THEN** se informa la inconsistencia y no se omite la carga inicial silenciosamente

### Requirement: NWE-03 Repetición y recuperación sin duplicados

Las cargas SHALL poder repetirse sin duplicar entidades ni líneas ni alterar importes de filas sin cambios. La preparación temporal de un intento fallido SHALL poder limpiarse y reconstruirse en el siguiente intento sin vaciar tablas finales ni reiniciar marcas exitosas automáticamente.

#### Scenario: Ejecución sin cambios
- **WHEN** se repite una carga correcta y el origen no ha cambiado
- **THEN** las entidades, líneas, claves e importes finales permanecen iguales

#### Scenario: Reintento tras fallo
- **WHEN** se corrige la causa de una carga fallida y se reintenta
- **THEN** se incorporan sus cambios pendientes una sola vez

### Requirement: NWE-04 Cambios operativos y dependientes

La carga incremental SHALL incorporar nuevas entidades y líneas, actualizar entidades y líneas modificadas y reflejar cambios de categoría, proveedor, supervisor y cabecera de pedido en los registros afectados. No SHALL utilizar el precio actual de producto para revalorizar ventas pasadas.

#### Scenario: Nuevo pedido con cliente nuevo
- **WHEN** se agregan un cliente, un pedido suyo y sus líneas en el origen de prueba
- **THEN** el proceso principal carga el cliente antes de las líneas y suma solamente los nuevos importes

#### Scenario: Actualización de cantidad
- **WHEN** cambia la cantidad de una línea existente
- **THEN** se actualizan su cantidad e importes sin agregar otro hecho

### Requirement: NWE-05 Serialización y fallos observables

La solución SHALL impedir ejecuciones simultáneas de carga sobre el mismo destino, incluidos procesos iniciados manualmente. SHALL registrar entidad o etapa, resultado y contexto suficiente para localizar errores sin publicar secretos. Si falla una etapa, el proceso principal SHALL fallar y detener sus etapas dependientes.

#### Scenario: Dos ejecuciones simultáneas
- **WHEN** se intenta iniciar otra carga sobre el mismo destino durante una ejecución activa
- **THEN** la segunda no modifica staging, hechos ni marcas y devuelve un estado de carga ocupada

#### Scenario: Dimensión fallida
- **WHEN** falla la carga de productos
- **THEN** no se ejecutan los hechos ni se reporta éxito global y se identifica la etapa fallida
