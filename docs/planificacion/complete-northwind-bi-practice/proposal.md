# Proposal

## Why

La práctica Northwind ya tiene datos operativos, tablas de almacén y procedimientos parciales, pero todavía no permite recorrer el ciclo de carga y análisis que muestra BikeStores en `Data-Management-and-BI`. Completar ese ciclo con comprobaciones y una guía desde cero permitirá ejecutar la práctica y explicar de dónde salen sus resultados.

## What Changes

- Implementar por segmentos verificables elegidos por el asistente: cada petición de implementar o continuar seleccionará automáticamente unas pocas tareas pendientes relacionadas y con dependencias satisfechas, incluirá su verificación y documentación y terminará al cerrar esa unidad, sin exigir números de tarea ni ejecutar toda la lista de una vez.
- Organizar la solución siguiendo la lógica de BikeStores: base operativa, almacén con staging y modelo estrella, carga ETL, modelo tabular y programación. Adaptar esa arquitectura a Northwind y explicar las diferencias de entidades, claves y herramientas.
- Permitir renombrar, reorganizar, corregir y mejorar archivos y su contenido durante la implementación. Los nombres y rutas propuestos son puntos de partida: cada cambio deberá actualizar proyectos, referencias, conexiones y guía, y documentar su correspondencia anterior/nueva; los cambios de objetos desplegados tendrán una migración explícita.
- Completar las extracciones de clientes, empleados, productos, transportistas y líneas de pedido; eliminar multiplicaciones de registros y conservar relaciones opcionales.
- Integrar las cinco dimensiones, staging, control de cargas y los cuatro procedimientos de dimensiones existentes; completar la carga de calendario y hechos.
- **BREAKING**: ampliar Fact_Ventas con ProductID de origen, unicidad por pedido/producto y tipos decimales definidos para precio y descuento. El cambio afecta el esquema del DW y sus consumidores, no las claves ni los datos comerciales de Northwind.
- Construir paquetes SSIS para carga inicial e incremental, con reintentos sin duplicados y avance registrado solamente después de una carga correcta.
- Crear un modelo tabular SSAS con ventas brutas, descuentos, ventas netas, unidades y pedidos distintos, así como análisis por dimensiones y fechas.
- Preparar despliegue, trabajo de SQL Server Agent, procesamiento del modelo, verificaciones y guía didáctica estructurada desde la inicialización. Cada acción en Visual Studio o SQL Server/SSMS indicará prerrequisitos, aplicación, pasos numerados, rutas de menú verificadas, valores, propósito, resultado esperado y comprobación. Las intervenciones necesarias del usuario se explicarán antes de continuar con etapas que dependan de ellas.

## Capabilities

### New Capabilities

- `northwind-extraction`: extracción por identidad de origen y cambios confirmados, incluidos atributos dependientes.
- `northwind-warehouse`: modelo estrella, calendario, integridad y cálculo de medidas por línea de pedido.
- `northwind-etl`: paquetes SSIS, cargas incrementales, control de avance y recuperación de fallos.
- `northwind-analysis`: modelo tabular, relaciones temporales y medidas verificables.
- `northwind-practice-delivery`: solución mejorable basada en BikeStores, ejecución automatizada, comprobaciones y acompañamiento paso a paso desde la preparación del entorno.

### Modified Capabilities

Ninguna: no existen especificaciones principales registradas en OpenSpec.

## Impact

Se trabajará en ``, sus proyectos, scripts y documentación. Los despliegues posteriores afectarán los procedimientos de extracción de NorthWind, el esquema y contenido de Northwind_DW, el catálogo SSIS, un modelo SSAS propio y un job propio. El material BikeStores se conservará como referencia. Se reutilizarán los servicios locales existentes y se comprobará la compatibilidad entre Visual Studio 2026, las extensiones instaladas y SQL Server 17 antes de fijar destinos de compilación.

Fuera de alcance: SCD tipo 2, propagación de borrados físicos, análisis de inventario o beneficios, aplicación web, informe Power BI terminado, migración de motor y restauraciones destructivas. Las dimensiones usarán atributos actuales (SCD tipo 1), como la referencia.
