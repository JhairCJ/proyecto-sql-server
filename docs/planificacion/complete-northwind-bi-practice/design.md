# Design

## Context

La motivación y el alcance están en `proposal.md`. Este diseño se incluye porque el cambio afecta cuatro proyectos, la estructura de hechos, servicios de integración y análisis y la recuperación de cargas.

Estado observado el 11 de octubre de 2026:

- `Northwind.slnx` contiene solamente `Northwind.OLTP/Northwind.OLTP.sqlproj`, cuyo proveedor de esquema es Sql170. Los scripts DW y de control figuran como `None`, no como objetos compilados del OLTP.
- El motor local reporta versión 17.0.1000.7, Enterprise Developer. NorthWind contiene 91 clientes, 9 empleados, 77 productos, 3 transportistas, 830 pedidos, 2.155 líneas y 51.317 unidades. No se observaron pedidos con cliente, empleado o fecha de pedido nulos, aunque su esquema permite nulos.
- Northwind_DW existe con cinco dimensiones, Fact_Ventas, cinco tablas `std` y PackageConfig. Las tablas comerciales están vacías. Están registrados los dos procedimientos de control y cuatro DW_MergeDim existentes; no aparece la carga de hechos.
- `Scripts/DW_Merge.sql` ya define altas y actualizaciones de las cuatro dimensiones. `Esquema_y_tablas.sql` ya incluye la adición de SupervisorName a `std.Empleado`; se integrará como columna declarativa, no se asumirá que sigue faltando.
- La extracción de clientes contiene una unión demográfica incorrecta; la de empleados multiplica por territorios; la de productos usa relaciones internas sobre claves opcionales y no entrega todos los atributos de staging.
- El calendario necesita cubrir al menos del 4 de julio de 1996 al 11 de junio de 1998, considerando las tres fechas, no solamente el último pedido.
- La referencia BikeStores contiene proyectos SQL OLTP/DW, cinco paquetes SSIS, un modelo tabular y un job. Su proyecto SSIS declara destino SQLServer2022; no se copiará ese destino sin verificar compatibilidad con el runtime local.
- Están instalados Visual Studio Community 2026 y SSMS 22. Existen carpetas de extensiones SSIS/SSAS y están activos motor, Integration Services 170, Analysis Services y Agent. Esto no demuestra aún compilación compatible, modo tabular de SSAS ni permisos de despliegue.
- No se encontraron pruebas o documentación de la práctica fuera de OpenSpec, ni grafo graphify. No hay capacidades principales previas.

Estos conteos son una referencia observada, no constantes para cualquier copia de Northwind. Las verificaciones posteriores capturarán la referencia del origen utilizado.

## Goals / Non-Goals

**Goals:**
- Mantener una correspondencia rastreable entre línea operativa, hecho y medida analítica.
- Integrar los objetos existentes en proyectos compilables y reutilizar los procedimientos de dimensiones, corrigiendo su contrato donde corresponda.
- Separar preparación temporal, aplicación final y avance para que las cargas puedan reintentarse.
- Hacer que un principiante pueda ejecutar y demostrar el recorrido con resultados concretos.

**Non-Goals:**
- No ofrecer consistencia temporal distribuida ni una fotografía histórica exacta bajo escrituras concurrentes continuas; la reconciliación total usa un origen estable. Las extracciones sí deben evitar lecturas no confirmadas y perder cambios diferidos.
- No versionar atributos (SCD 2), sincronizar borrados físicos ni analizar territorios/demografía como dimensiones adicionales.
- No automatizar instalaciones, cambios de edición o modo de SSAS, ni restaurar NorthWind para resolver una incompatibilidad.
- No agregar frameworks ETL externos, una plataforma de observabilidad o un informe Power BI cerrado.

## Decisions

### D1. Arquitectura de BikeStores adaptada y nomenclatura mejorable

Dentro de `` se organizarán las responsabilidades operativa, DW, ETL y OLAP, inicialmente denominadas Northwind.OLTP, Northwind.DW (.sqlproj), Northwind.ETL (.dtproj) y Northwind.OLAP (.smproj y modelo .bim). Las tablas dbo.Dim_Cliente, Dim_Empleado, Dim_Producto, Dim_Transportista, Dim_Tiempo, Fact_Ventas, dbo.PackageConfig y el esquema std son el punto de partida, no una prohibición de mejorar la organización.

Los nombres y rutas de archivos, paquetes, proyectos y documentos indicados en este diseño y las tareas son propuestas iniciales. Se pueden cambiar, dividir, consolidar y mejorar sus contenidos por claridad o corrección. La implementación registrará ruta/nombre anterior, ruta/nombre final, responsabilidad y motivo; actualizará referencias, parámetros, conexiones y guía en el mismo cambio. Si afecta nombres de objetos publicados, preparará y comprobará la migración y consumidores, conservando identidades y resultados contractuales. Los nombres de claves de origen identifican conceptos que deben seguir siendo rastreables aunque cambie un archivo.

La correspondencia arquitectónica que se explicará en la guía es:

| Responsabilidad | BikeStores | Northwind |
|---|---|---|
| Operaciones | BikeStoresOLTP | Proyecto operativo de Northwind |
| Almacén | BikeStoresDW, staging, dimensiones, FactOrders, PackageConfig | Proyecto DW, std, dimensiones de Northwind, hechos de ventas y control |
| Carga | BikeStoresETL y paquetes de dimensiones/hechos | Proyecto ETL y paquetes para clientes, empleados, productos, transportistas y ventas |
| Análisis | BikeStoresOLAP, modelo .bim y medidas | Proyecto tabular de ventas Northwind |
| Programación | BikeStoresJob | Job propio de carga y procesamiento Northwind |

Se conservará la secuencia lógica origen -> preparación/DW -> carga de dimensiones antes de hechos -> procesamiento analítico -> consulta. La guía comparará también las dimensiones y claves: clientes, productos, empleados y fechas tienen responsabilidades similares; BikeStores tiene tiendas sin equivalente directo aquí, mientras Northwind incorpora transportistas. El control incremental y los lookups siguen responsabilidades semejantes, con contratos adaptados a las claves y líneas de Northwind. Las mejoras respecto al ejemplo se justificarán por corrección, claridad, integridad o compatibilidad.

Northwind.DW será la fuente declarativa de objetos DW; los scripts de ejecución manual se reorganizarán como preparación/migración claramente identificadas y dejarán de competir con el esquema compilado. Las filas iniciales de PackageConfig se crearán solo si faltan. Las publicaciones de esquema no ejecutarán una carga ni vaciarán destinos automáticamente.

Se conservará `.slnx` si las extensiones abren los cuatro tipos de proyecto. Si alguna solo acepta una solución `.sln`, se proporcionará esa entrada compatible para los mismos proyectos y se documentará cuál abrir, sin duplicar sus objetos.

Alternativa descartada: reunir todo en Northwind.OLTP y continuar ejecutando scripts `None` manualmente. Impide verificar qué despliega cada proyecto. Tampoco se copiará BikeStores sustituyendo nombres: sus entidades y claves no equivalen a Northwind.

### D2. Extracciones con una identidad y solo los atributos requeridos

Clientes se extraerán desde Customers, sin joins demográficos que no alimentan la dimensión. Empleados usarán Employees y una relación opcional con su supervisor, sin territorios. Productos conservarán relaciones opcionales con Categories/Suppliers e incluirán sus identificadores, nombres y país del proveedor. Se añadirá extracción de Shippers. Ventas combinará Orders/OrderDetails con clave OrderID/ProductID y ShipVia como ShipperID.

Cada extractor reconocerá cambios de las filas de las que toma atributos. En empleados, cambiar un supervisor vuelve a seleccionar sus subordinados. En productos se consideran las marcas de producto, categoría y proveedor; en ventas las de pedido y detalle. Los resultados tendrán los nombres y tipos esperados por std.

Alternativa descartada: conservar joins no utilizados y aplicar DISTINCT. DISTINCT no define qué hacer ante atributos diferentes ni evita perder entidades sin relación.

### D3. Dimensiones de tipo 1, fechas y referencias ausentes

Las dimensiones tendrán unicidad comercial por CustomerID, EmployeeID, ProductID y ShipperID. Las claves sustitutas serán estables en altas/actualizaciones. Se adaptarán los DW_MergeDim ya existentes; su aplicación será transaccional y serializada. MERGE no es un requisito externo: conservarlo o separar INSERT/UPDATE dependerá de la validación de esos procedimientos, sin modificar el contrato de tipo 1.

Se reservará SK 0 en cliente y empleado con etiqueta Desconocido. En Dim_Tiempo se reservará Tiempo_SK 0, Fecha 1900-01-01 y atributos identificados como desconocidos; la guía y el modelo excluirán esa fila del calendario real. Las fechas conocidas usarán clave entera AAAAMMDD. Transportista, fecha requerida y fecha de envío legítimamente nulos conservarán NULL. Una clave comercial no nula sin dimensión será un error, no un miembro desconocido automático.

El calendario real se generará como rango continuo desde la mínima hasta la máxima de las tres fechas no nulas del origen; será repetible y extensible. Nombres españoles y cálculos de día de semana no dependerán de la configuración accidental de la sesión.

Alternativas descartadas: SCD 2, que requiere versiones y relaciones por vigencia; usar claves comerciales como sustitutas; sustituir una fecha de envío ausente por la fecha del pedido. Todas introducen un significado diferente del previsto.

### D4. Identidad de hechos y política monetaria

Fact_Ventas mantendrá Venta_SK y añadirá ProductID, además de unicidad por OrderID/ProductID. Conserva las siete relaciones de dimensiones/fechas actuales. Se registran PrecioUnitario como DECIMAL(19,4), Descuento como DECIMAL(9,6) e importes como DECIMAL(18,2). Cantidad se conserva como entero con restricción positiva; precio no negativo y proporción en 0..1. El redondeo y fórmulas normativos están en NWW-05; las transformaciones usarán decimales con precisión intermedia suficiente.

La carga resolverá las claves desde identidades comerciales. Un cambio de cliente/empleado/transportista en la cabecera actualizará esas relaciones en todas sus líneas. Freight no se repetirá en los hechos. Las medidas tabulares sumarán importes almacenados, sin recalcularlos con precios de catálogo o reglas diferentes.

Alternativas descartadas: identificar una venta únicamente por Venta_SK, que permite duplicados de origen; conservar REAL en operaciones monetarias, que hace menos explícita la precisión; contar hechos como pedidos.

### D5. Carga serializada, staging y confirmación por entidad

Northwind.ETL contendrá paquetes Cliente, Empleado, Producto, Transportista y Ventas y un principal CargarNorthwind. Cada proceso seguirá el mismo recorrido: comprobar estado, leer marca, fijar límite, limpiar solo su staging, extraer filas, validar, aplicar cambios finales y confirmar marca/fecha en la misma transacción del DW.

Una tarea SQL de aplicación ejecutará la operación final y la actualización de PackageConfig dentro de una única transacción local, con tratamiento de errores que revierta ambas. No se dependerá de una transacción distribuida entre servicios. Staging es temporal y puede reconstruirse; las tablas finales no se truncarán. Si ya se confirmó una dimensión y luego fallan los hechos, esa dimensión conserva su éxito y el reintento vuelve a ejecutar el principal sin duplicados.

Un bloqueo de aplicación por destino en SQL Server impedirá que dos cargas usen el mismo staging. Se utilizará una conexión de control retenida y compartida por la ejecución principal y sus subordinados; los paquetes independientes deberán adquirir el mismo bloqueo cuando sean el punto de entrada. Se verificará esa herencia de conexión en integración. La sesión mantiene el bloqueo hasta finalizar; cierre por fallo también lo libera. Un intento concurrente se rechazará, sin esperar indefinidamente ni modificar datos.

Los errores de validación fallarán la entidad completa y mostrarán claves de las filas afectadas; no habrá cuarentena silenciosa. Se usará logging nativo SSIS y registro del job con etapa, resultado y conteos disponibles.

Alternativas descartadas: nuevos registros directamente al destino y cambios a staging, que introduce dos caminos de confirmación; reiniciar marcas tras errores; depender únicamente de que Agent no repita el mismo job, que no cubre ejecuciones manuales.

### D6. Marcas y límites sin perder cambios

PackageConfig conservará BINARY(8). Los procedimientos de origen existentes usan BIGINT; las conversiones para variables Int64 y parámetros SSIS serán explícitas, con comprobación de ida y vuelta y error si un valor no es representable, sin conversiones flotantes. No se compararán marcas de bases distintas. Las pruebas deberán cubrir estos enlaces reales, no solo las consultas en SSMS.

El límite exclusivo de transacciones pendientes se obtendrá de MIN_ACTIVE_ROWVERSION; se derivará el límite superior inclusivo que necesita el contrato actual. Las lecturas se ejecutarán con aislamiento READ COMMITTED explícito; se retirará el efecto READ UNCOMMITTED del prototipo de GetDatabaseRowVersion para que no contamine la conexión reutilizada.

Si alguna fila que aporta atributos ya tiene una marca posterior al corte, su resultado se diferirá. Esa misma dependencia tendrá que poder seleccionarla en el siguiente intervalo, evitando mezclar valores nuevos con una marca de carga anterior. Esto no recupera versiones históricas ni promete una fotografía conjunta de todos los paquetes. La carga inicial y sus conteos de aceptación se comprobarán con origen estable.

La preparación distinguirá destino vacío/marca cero de destino vacío/marca avanzada. No se intentará reconstruir un destino vaciado utilizando solo los últimos cambios; se dará un diagnóstico para una reconstrucción explícita.

Alternativas descartadas: capturar exclusivamente @@DBTS sin considerar transacciones pendientes, leer datos no confirmados o adelantar marcas tras aplicar parcialmente los cambios.

### D7. Modelo tabular y funciones de fecha

Northwind.OLAP importará las cinco dimensiones y Fact_Ventas de Northwind_DW. Las relaciones serán de dimensión a hechos, con cardinalidad uno a muchos. FechaPedido será activa; FechaRequerida y FechaEnvio serán inactivas. Medidas explícitas por requerida/envío activarán la relación correspondiente y desactivarán la de pedido para evitar intersecciones accidentales. Las medidas por envío eliminarán fechas ausentes.

Se crearán ventas brutas, descuentos, ventas netas, unidades y pedidos distintos mediante DAX sobre los hechos cargados. Las columnas técnicas y claves se ocultarán del uso habitual; nombres y formatos serán comprensibles en español. Año/trimestre/mes y categoría/producto facilitarán demostraciones. Se incluirán consultas de verificación ejecutables sobre el modelo, sin exigir un informe externo.

Alternativas descartadas: un cubo multidimensional o sustituir SSAS por un archivo Power BI, que se apartan del modelo tabular de la referencia; calcular importes con reglas diferentes en DAX.

### D8. Entorno, automatización y guía

Se comprobarán las versiones reales de extensiones, SSDT/MSBuild, runtime SSIS y modo/compatibilidad SSAS. La carpeta de extensión o el servicio activo no se aceptarán como prueba de compilación. Se fijarán destinos soportados tras esa comprobación, sin heredar SQLServer2022 automáticamente ni instalar componentes durante una prueba.

Se parametrizarán servidores y bases: origen NorthWind, destino Northwind_DW, proyecto/carpeta SSIS propios y modelo NorthwindOLAP. Autenticación integrada será el valor inicial local; cuentas de ejecución y permisos se documentarán sin secretos.

Un script repetible de NorthwindBIJob creará o actualizará solo el job de esta práctica. Ejecutará el principal y luego el procesamiento tabular; se entregará deshabilitado con programación configurable y valor didáctico inicial de una ejecución diaria, sin adoptar el minuto del ejemplo. El operador podrá ejecutar manualmente y habilitarlo después de validar. No alterará jobs de BikeStores.

Se añadirá una guía, inicialmente `docs/guia-practica.md`, con glosario, mapa de archivos finales y correspondencia con BikeStores. La estructura y el acompañamiento se detallan en D9. La documentación de validación distinguirá evidencia ejecutada de pendiente. Sus nombres y distribución pueden mejorarse según D1.

Alternativa descartada: dejar la ejecución y las verificaciones en instrucciones dispersas sin correspondencia con archivos ni valores esperados.

### D9. Guía estructurada desde la inicialización y acompañamiento durante la ejecución

La guía se completará junto con cada grupo de implementación, no solamente al final. Se organizará en etapas numeradas:

1. Preparar el entorno: distinguir SQL Server de SSMS y Visual Studio, comprobar versiones/extensiones, servicios y modo tabular; describir cómo preparar un componente ausente cuando se requiera intervención del usuario, sin instalarlo automáticamente.
2. Conectar y revisar: servidor, tipo de autenticación, permisos, bases existentes, tablas y contexto de consultas. Indicar qué pasos de creación se omiten porque NorthWind/Northwind_DW ya existen y cómo comprobarlo.
3. Abrir y configurar la solución: ruta final, proyecto y propiedades pertinentes, destino de compilación, conexiones y forma de compilar; explicar los mensajes esperados.
4. Preparar/publicar el esquema del DW, los objetos iniciales y calendario; indicar archivo, orden, servidor y base de ejecución, distinguiendo creación, migración y carga.
5. Configurar, desplegar y ejecutar los paquetes SSIS y revisar parámetros, origen, destino y resultados de Control Flow/Data Flow.
6. Desplegar/procesar el modelo tabular, ejecutar medidas y comprobar el resultado contra el DW.
7. Preparar el job y permisos, ejecutarlo manualmente, consultar historial y habilitar o detener la programación cuando corresponda.
8. Demostrar el pedido 10248 y filtros analíticos y diagnosticar los errores frecuentes de cada etapa.

Cada procedimiento utilizará la misma ficha: **objetivo y por qué**, **prerrequisitos**, **programa/versión**, **qué está preparado y qué falta**, **pasos numerados con menú o ubicación**, **valores a introducir**, **archivo/contexto de ejecución si aplica**, **resultado esperado**, **comprobación**, **errores frecuentes y recuperación**. Los valores se referirán al entorno seleccionado; no se mezclará NorthWind con una base de prueba. Los menús y nombres de opciones se verificarán en la versión real o documentación oficial; una ruta no verificada quedará identificada, no inventada.

Si una acción requiere al usuario, el asistente dará esa ficha en el chat antes de la acción, identificará cuándo regresar y qué resultado comprobar, y esperará la intervención necesaria antes de seguir con etapas dependientes. Si puede ejecutar una acción autorizada y verificarla, lo hará y explicará el resultado con los pasos equivalentes para aprendizaje. Dar instrucciones no contará como ejecución ni como validación.

Alternativa descartada: indicaciones como «configura SSIS» o «publica el proyecto» sin aclarar programa, ubicación, valores, orden y verificación; entregar documentación únicamente después de que el usuario ya necesitó realizar la acción.

### D10. Selección autónoma de segmentos verificables

La implementación avanzará por unidades elegidas automáticamente al recibir «implementa», «continúa» o una instrucción equivalente. No se exigirá un rango de tareas. Antes de cada unidad se leerán el checklist y el estado real de archivos, herramientas y comprobaciones; se retomará primero cualquier unidad incompleta. La selección respetará las dependencias y el orden funcional del diseño y priorizará el siguiente resultado comprobable.

Un segmento contendrá normalmente de una a tres tareas relacionadas, más sus comprobaciones y documentación necesarias. Esa cantidad es una orientación, no una excusa para cortar una unidad antes de verificarla ni para agrupar un proyecto entero. No se impondrán bloques fijos por número de grupo: un grupo grande se dividirá en unidades y una tarea demasiado extensa se acotará en pasos con entregables explícitos; su checkbox seguirá pendiente hasta cumplir su criterio completo. Solo se ampliará el segmento cuando sea indispensable para cerrar su resultado observable, explicándolo brevemente.

Al inicio se comunicará objetivo, tareas y comprobación prevista y se procederá sin una nueva aprobación de ese alcance ya autorizado. Se completarán implementación, comprobaciones relevantes, corrección de fallos y actualización de la guía que corresponda. Al cerrar la unidad se actualizarán los checkboxes que realmente pasaron y la documentación de validación con tareas, resultado, evidencias, pendientes y siguiente unidad recomendada. Después se terminará la petición; no se encadenará automáticamente el resto del cambio.

Si una intervención requerida impide comprobar el resultado, se aplicará D9 y quedará registrada la unidad pendiente para retomarla. Si falta autorización para una acción concreta, no se deducirá de la elección automática del segmento. Una petición posterior con un alcance explícito sustituirá este tamaño predeterminado. Esta política organiza la ejecución por turnos; no crea una automatización programada ni inicia implementación durante la edición del plan.

Alternativas descartadas: pedir al usuario los números de tarea en cada turno, ejecutar todos los pendientes con una sola petición genérica o detenerse después de editar archivos sin verificar el resultado.

## Risks / Trade-offs

- [Extensiones o modo SSAS incompatibles] -> Preflight concreto antes del despliegue; registrar el componente y detener esa fase si no se cumple, sin cambiar automáticamente de stack.
- [Datos modificados mientras se valida] -> Capturar conteos contra origen estable; usar límites y dependencias para no perder cambios diferidos. No prometer aislamiento distribuido.
- [Tipo 1 altera etiquetas de análisis histórico] -> Explicar que ciudades, categorías y otros atributos representan su estado actual; precios vendidos y fechas proceden del detalle/cabecera.
- [MERGE existente o conversiones de marcas fallan bajo el runtime real] -> Probar altas, actualizaciones, reintentos y parámetros reales; serializar escrituras y usar la transacción final de entidad.
- [Publicación declarativa propone cambios destructivos] -> Revisar el script de despliegue, mantener bloqueo ante pérdida de datos y preparar una migración explícita. No desactivar protecciones para forzar el despliegue.
- [DW dejó de estar vacío antes de aplicar] -> Releer el estado antes de migrar; verificar relación Producto_SK/ProductID y duplicados para conservar hechos, en vez de reconstruir por defecto.
- [Pruebas contaminan las bases del usuario] -> Origen y destino aislados y guardas de nombres antes de cualquier fixture de escritura.
- [Origen restaurado o marcas reiniciadas por fuera del proceso] -> Detectar marcas incompatibles y detener; la sincronización incremental no cubre restauraciones automáticas.
- [Renombres dejan proyectos o guía desactualizados] -> Mapa anterior/nuevo, actualización conjunta de referencias y comprobaciones de compilación, publicación y rutas documentadas.
- [Menús de una versión difieren de la guía o una acción manual sigue pendiente] -> Verificar opciones del entorno real, adaptar los pasos y no declarar ni ejecutar etapas dependientes antes de comprobar la acción requerida.

## Migration Plan

1. Registrar herramientas, estado del origen/destino y objetos actuales; conservar una copia recuperable de los archivos que se reorganizarán. Generar scripts de despliegue revisables antes de ejecutarlos.
2. Crear los proyectos nuevos e incorporar los objetos existentes. Mover el conocimiento de los scripts a definiciones declarativas y migraciones explícitas; no desplegar las tablas DW como parte del OLTP.
3. Para el DW vacío observado, añadir ProductID, restricciones y tipos directamente. Si ya hay hechos al aplicar, derivar ProductID de Dim_Producto y validar correspondencia y unicidad antes de declarar NOT NULL/unicidad; si hay ambigüedad, detener y reportar las filas sin eliminarlas.
4. Desplegar extractores y DW; insertar controles faltantes y miembros desconocidos de forma repetible. No reiniciar marcas existentes.
5. Compilar/publicar ETL a su carpeta/proyecto SSIS; cargar manualmente calendario, dimensiones y hechos; reconciliar conteos e importes.
6. Compilar/desplegar/procesar NorthwindOLAP y ejecutar consultas de medidas y de fechas. Crear el job deshabilitado y probar su ejecución manual.
7. Completar guía y evidencias. La habilitación del horario queda como acción explícita del operador.

Ante un fallo, detener el job propio, conservar diagnósticos y reintentar entidades desde su último avance correcto después de corregir la causa. Una reversión de despliegue se realizará con los scripts/copia previos y revisión de diferencias; no se restaurarán ni eliminarán bases automáticamente. Si las columnas nuevas ya contienen datos, no se hará un rollback destructivo por defecto.

## Validation Strategy

Se crearán Northwind_Test y Northwind_DW_Test con el esquema y una copia de datos o fixtures controlados, además de un modelo/proyecto SSIS de prueba con nombres propios. Las herramientas de prueba rechazarán NorthWind y Northwind_DW como destinos de escritura. La comprobación final de las bases del usuario será de lectura sobre los despliegues autorizados en la fase de implementación.

La matriz de pruebas enlazará los IDs NWX/NWW/NWE/NWA/NWP con resultados. Se verificarán: compilación de los cuatro proyectos; carga completa y repetición; pedido 10248; conteos comerciales excluyendo SK 0; cantidad e importes con un cálculo independiente del origen; claves huérfanas y duplicadas; precio vendido frente a catálogo; nulos y redondeo; inserciones/actualizaciones y dependencias; actualización de cabecera; intervalos, transacción pendiente y cambio posterior al corte; fallo antes de aplicación, fallo de guardado de avance y reintento; doble ejecución; medidas por las tres fechas; despliegue repetido sin reset; fallo de procesamiento y resultado del job.

No se considerará terminada la implementación si solo pasan las consultas SQL: deberá existir evidencia real de ejecución de paquetes, procesamiento tabular y ciclo manual del job. Si algo no puede ejecutarse, quedará identificado como pendiente. Se comprobarán además la correspondencia arquitectónica con BikeStores (NWP-06), que toda instrucción utiliza los nombres finales y las fichas numeradas de inicialización (NWP-01/NWP-04), y que una acción requerida al usuario se explica antes de necesitarla y su resultado se verifica antes de continuar (NWP-07).
