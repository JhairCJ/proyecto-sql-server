# Registro de validación

## Alcance de la validación y destino actual

Las ejecuciones y evidencias históricas de este registro se hicieron con `Northwind_Test` y `Northwind_DW_Test`; no demuestran que se haya cargado el almacén real. La configuración principal del proyecto ahora apunta a `NorthWind`, `Northwind_DW` y `NorthwindOLAP`. Al revisar el equipo antes de este cambio, `NorthWind` estaba en línea con 830 pedidos y 2.155 líneas, y `Northwind_DW` estaba en línea pero sin hechos cargados. `NorthwindBIJob` y `NorthwindOLAP_Test` todavía apuntaban a las copias; no se modificaron las bases reales durante esta actualización de archivos. Para publicar y ejecutar el recorrido real, sigue [la guía paso a paso](<guia paso a paso.md>).

## Segmento 01 — Entorno y referencia inicial

Fecha: 11 de octubre de 2026. Tareas: **1.1, 1.2 y 1.4**. Consultas de lectura y compilación local; no se publicaron esquemas ni se ejecutaron cargas en las bases del usuario.

| Comprobación | Resultado | Evidencia |
| --- | --- | --- |
| Versiones VS, SSMS, SSDT, extensiones y runtime | Identificadas; destinos previstos SQL Server/SSIS 2025 y SSAS 1700 | `evidencias/segmento-01/visual-studio.json`, `herramientas.json` |
| Servicios, SSAS tabular y permisos administrativos | Servicios Running, SSAS tabular 17.0.25.218, Admin miembro directo de Administrators | `servicios-ssas.json` |
| Permisos motor y bases | sysadmin y CREATE ANY DATABASE; origen 160 y DW 170 ONLINE; SSISDB ausente | `referencia-sql.txt` |
| Identidad de lectura futura del modelo | Login explícito de cuenta de servicio SSAS ausente; acceso efectivo pendiente de preparar/probar | `permisos-procesamiento.txt` |
| Compilación OLTP inicial | Salida 0; dacpac generado; 19 advertencias SQL71502, no una publicación validada | `compilacion.txt` |
| Tablas, columnas, procedimientos, índices, relaciones DW, conteos y marcas | Captura nueva, no reutilización del supuesto del diseño | `referencia-sql.txt`, consulta en `consulta-referencia.txt` |
| Guía inicial D9 | Fichas con estado preparado/pendiente, programas, pasos, valores, resultado y recuperación | `01-guia-practica.md` |

Los archivos de evidencia están bajo `evidencias/segmento-01/`. La captura SQL usa conteos `COUNT_BIG(*)` sobre cada tabla; contiene definición de todos los procedimientos y metadatos de columnas, índices y relaciones DW. La consulta es de lectura. Las instrucciones de interfaz siguen documentación oficial enlazada en la guía; **no se afirma haber operado ni observado las ventanas de Visual Studio/SSMS**. Las conexiones y compilación se comprobaron mediante herramientas locales.

### Referencia de datos

| Origen NorthWind | Filas |
| --- | ---: |
| Customers | 91 |
| Employees | 9 |
| Products | 77 |
| Shippers | 3 |
| Categories | 8 |
| Suppliers | 29 |
| Orders | 830 |
| OrderDetails | 2155 |
| Region | 4 |
| Territories | 53 |
| EmployeeTerritories | 49 |
| CustomerDemographics / CustomerCustomerDemo | 0 / 0 |

Unidades: **51.317**. Pedido 10248: productos 11, 42, 72; cantidades 12, 10, 5; precios 14, 9,8, 34,8; descuento cero; 27 unidades y 440 de importe. Fechas de pedido: 1996-07-04 a 1998-05-06; requeridas: 1996-07-24 a 1998-06-11; envío: 1996-07-10 a 1998-05-06.

En Northwind_DW, las cinco dimensiones, Fact_Ventas y las cinco tablas std tienen **cero filas**. PackageConfig tiene **cinco filas**, todas con marca binaria cero y LastSuccessfulLoad NULL. Esto describe únicamente esta captura; antes de futuras migraciones se comprobará otra vez para conservar datos si el usuario carga el DW.

### Diferencias y riesgos encontrados respecto a la planificación

- Se confirmó `std.Empleado.SupervisorName`, `nvarchar(60)`, 120 bytes. Ya existen los cuatro `DW_MergeDim...`.
- Ahora también existen `DW_LoadDimTiempo` y `DW_MergeFactVentas`, tanto en el servidor como en el antiguo `Scripts/DW_Merge.sql` (reorganizado posteriormente; véase referencias/modelo-dw.md). No se consideran tareas implementadas por nosotros: no se han ejecutado sus escenarios de aceptación.
- El calendario existente inserta solo fechas presentes en staging y usa DATENAME dependiente del idioma de sesión. Queda pendiente convertirlo en calendario continuo y nombres españoles estables (3.3).
- La aplicación de ventas empareja por OrderID/Producto_SK, no guarda ProductID en el hecho, excluye filas sin cliente/empleado resuelto o fecha de pedido y calcula importes con fórmulas que deben ajustarse al contrato. Se adaptará y probará en 3.4/4.2, conservando el trabajo existente como punto de partida.
- OLTP compila con 19 advertencias por referencias heredadas a `Order Details`; el nombre actual es `OrderDetails`. Pendiente resolver referencias antes de una publicación validada.
- Los extractores actuales conservan problemas de joins y límites identificados en el diseño; no fueron modificados ni probados en este segmento.
- No hay catálogo SSISDB, modelos SSAS ni job Northwind. No hay prueba aún de compilación de nuevos proyectos SSIS/SSAS, de acceso SQL de la identidad de procesamiento ni de ejecución bajo Agent. Se comprobarán en sus etapas.

### Cierre y siguiente unidad

Tareas 1.1, 1.2 y 1.4 completas para su alcance de diagnóstico, captura y guía inicial. Las funcionalidades ETL, calendario, hechos y modelo siguen pendientes. Progreso: **3 de 41**. No se confunde herramienta instalada, procedimiento existente o instrucción entregada con ejecución aprobada de la práctica.

Próxima unidad recomendada: **1.3**, preparación reproducible de pruebas aisladas y guardas de escritura. Después, comenzar extracción incremental. Si llega una nueva petición, se seleccionará la unidad automáticamente según dependencias y estado actualizado.

## Segmento 02 — Copias y ejecutor de fixtures aislados

Tarea: **1.3**. El usuario confirmó que siguió la guía del segmento 01 y que los pasos funcionaron; esa confirmación acompaña la comprobación automatizada previa, sin afirmar observación directa de su interfaz.

Se crearon Northwind_Test y Northwind_DW_Test mediante backup COPY_ONLY/restauración con MOVE a archivos nuevos. No se usó REPLACE ni se eliminó ninguna base. La preparación repetida reutiliza únicamente copias con marca y usuario correctos, sin reset de datos o controles.

| Escenario | Resultado ejecutado | Evidencia en `evidencias/segmento-02/` |
| --- | --- | --- |
| Primera creación | Dos copias nuevas; backups propios registrados | `preparacion-*.json` con Action Created |
| Comparación inicial | Todas las tablas coinciden en conteos y valores, incluidas claves y rowversions; contadores IDENTITY conservados | `comparacion-copias.txt` |
| Preparación repetida | Reused para ambas copias; sin sobreescritura | `repeticion-preparacion.txt`, JSON con Action Reused |
| Destinos NorthWind/Northwind_DW/BikeStores/master | Rechazo antes de ejecutar SQL | `aislamiento.txt` |
| UPDATE en copia | Identidad NorthwindFixture, dato visible dentro del batch; rollback confirmado desde nueva conexión | `aislamiento.txt` |
| Fixture con commit | Inserción visible desde otra sesión; borrada al terminar la prueba | `aislamiento.txt` |
| SQL que intenta escribir en NorthWind o cambiar a Northwind_DW | Rechazo por contexto sin acceso fuera de la copia | `aislamiento.txt` |
| Intento de REVERT | Rechazo por contexto no revertible | `aislamiento.txt` |
| Referencia de originales antes/después | NorthWind conserva @@DBTS, cliente VINET, 830 pedidos, 2.155 líneas y 51.317 unidades; DW conserva cero hechos y sus cinco marcas/fechas | `originales-antes.txt`, `originales-despues.txt` |

Validación de scripts: parser de PowerShell sin errores y pruebas reales SQL/PowerShell satisfactorias. Se ejecutó `graphify update .`; su extracción SQL avisó que falta `tree_sitter_sql`. Esa limitación del índice de navegación no sustituye ni afecta las pruebas del motor; no se instalaron dependencias adicionales.

La comparación exacta corresponde al instante inicial anterior a los fixtures. Las modificaciones de prueba avanzan rowversion en Northwind_Test incluso con rollback, por lo que esa copia deja de ser idéntica en marcas al original, aunque se conserve su contenido comercial. El diseño de extracción utilizará cortes del origen de prueba actual. No se copiaron marcas avanzadas de otro origen ni se reiniciaron controles.

La [guía de pruebas](03-pruebas-aisladas.md) contiene fichas con programas, valores, pasos, resultados y recuperación. Esta etapa se ejecutó automáticamente; las instrucciones permiten aprender y reproducirla sin exigir que el usuario vuelva a crear las bases. No se modificó la solución de Visual Studio ni se publicaron proyectos.

Tarea 1.3 completa. Progreso: **4 de 41**. Pendientes: corregir extractores y contratos, construir DW/ETL/OLAP y validar despliegues y job. Próxima unidad recomendada: **2.1 y 2.2**, marcas y clientes con casos de límites y transacciones pendientes en copias aisladas.

## Segmento 03 — Contrato de marcas y clientes

Tareas **2.1 y 2.2**. Se corrigieron GetDatabaseRowVersion y GetCustomerChangesByRowVersion, se añadieron las dos conversiones comprobadas y se publicaron solo esos cuatro procedimientos en Northwind_Test. Se mantiene NorthWind sin publicación de estos cambios hasta su fase de despliegue.

| Escenario | Resultado ejecutado | Evidencia local en `evidencias/segmento-03/` |
| --- | --- | --- |
| Compilación SQL | Salida 0; se mantienen las 19 advertencias heredadas SQL71502, sin errores nuevos | `compilacion.txt` |
| Publicación acotada | Cuatro procedimientos en origen de prueba; repetición sin reset | `despliegue.txt` |
| Referencia / contrato de staging | 91 clientes únicos; INSERT EXEC compatible con las nueve columnas de std.Cliente | `clientes.txt` |
| Conversiones | 0, 1, 9007199254740993 y máximo Int64 preservados; NULL, negativo y binario 0x8000... rechazados | `clientes.txt`, `rowversion.txt` |
| Límites | Inferior excluido, superior incluido, posterior recuperado, intervalo vacío sin filas; intervalos inválidos rechazados | `clientes.txt` |
| Demografía | Clientes con cero y varias clasificaciones conservados una vez; cambios demográficos no seleccionan entidades | `clientes.txt` |
| Transacción pendiente + commit posterior | Corte anterior a ambas escrituras; lectura RC no publica la pendiente; después del commit ambos clientes se seleccionan una vez | `rowversion.txt` |
| Conexión reutilizada | GetDatabaseRowVersion y extracción conservan RC del llamador; prueba desde RU confirmó RC dentro del extractor | `rowversion.txt` |
| Parámetros reales | ADO.NET Binary(8)/BigInt y variables Int64 sin pérdida; prueba SSIS queda en 5.1 | `rowversion.txt` |
| Guardas tras ampliar herramienta | Destinos originales y escapes SQL rechazados; rollback/commit comprobados | `aislamiento.txt` |
| Originales / limpieza | Valores de referencia, @@DBTS y hashes de procedimientos del origen, así como controles/hechos DW, sin diferencias antes/después; fixtures eliminados y nombres restaurados en copia | `originales-antes-validacion.txt`, `originales-despues-validacion.txt`, `limpieza.txt` |

Parser PowerShell y pruebas de motor ejecutados sobre los scripts. El timeout deliberado de lectura sobre la fila pendiente se reconoció específicamente como SqlException -2, no como un fallo de conexión aceptado silenciosamente. Los errores esperados de rango se verificaron por número SQL. El fixture SQL desactiva XACT_ABORT solo dentro de su batch para capturar esos rechazos y termina con rollback; la herramienta lo activa por defecto para ejecuciones normales.

Se amplió el módulo con New-NorthwindTestConnection para compartir las guardas en pruebas de múltiples sesiones. Los procedimientos SQL restauran el nivel de aislamiento del llamador al salir; no se interpreta que SET dentro del prototipo alterase permanentemente una sesión RC. El problema corregido es la lectura interna READ UNCOMMITTED y el contrato sin validación.

La [guía de esta etapa](referencias/extraccion.md) contiene explicación y fichas D9 de publicación en copia, consulta y pruebas. No requiere intervención manual para completar lo ya ejecutado. Todavía no hay ETL de clientes, aplicación de staging ni paquete SSIS comprobados.

Progreso: **6 de 41**. Próxima unidad recomendada: **2.3 y 2.4**, empleados y productos con atributos dependientes y relaciones opcionales.

## Segmento 04 — Empleados y productos

Tareas **2.3 y 2.4**. Ambos extractores entregan las columnas de staging en su orden definido. Empleados conserva supervisor opcional sin joins de territorios; productos conserva categoría y proveedor opcionales. Un cambio en una relación selecciona las entidades dependientes, conservando sus marcas propias. Todos los contribuyentes presentes deben estar dentro del corte.

| Escenario | Resultado ejecutado | Evidencia local en `evidencias/segmento-04/` |
| --- | --- | --- |
| Compilación OLTP | Sin errores; 19 advertencias SQL71502 heredadas | `compilacion.txt` |
| Publicación acotada | Seis procedimientos implementados en Northwind_Test | `despliegue.txt` |
| Empleados y contrato | 9 identidades únicas, INSERT EXEC compatible con std.Empleado; empleado sin supervisor conservado | `Employee.txt` |
| Territorios | Empleados sin territorios y con varios conservados una vez; cambios de territorios no seleccionan empleados | `Employee.txt` |
| Supervisor | Cambio de nombre selecciona supervisor y subordinados; marca propia de subordinados intacta; relación NULL conservada | `Employee.txt` |
| Productos y contrato | 77 identidades únicas, INSERT EXEC compatible con std.Producto; categoría/proveedor ausentes conservados | `Product.txt` |
| Dependencias | Renombre de categoría y nombre/país de proveedor seleccionan todos sus productos sin cambiar la marca propia | `Product.txt` |
| Cortes | Supervisor, categoría o proveedor posterior al fin difiere la fila; siguiente intervalo la recupera. Producto posterior al corte también se recupera | `Employee.txt`, `Product.txt` |
| Intervalos | Vacío sin filas; negativo, invertido y NULL rechazados específicamente con 51104 | `Employee.txt`, `Product.txt` |
| Originales y rollback | Captura de originales idéntica antes/después; atributos probados y territorios sin diferencias respecto al origen; copia conserva 9 empleados, 77 productos y 49 asociaciones de territorios | `originales-antes.txt`, `originales-despues.txt`, `limpieza.txt` |

Las pruebas de corte de este segmento simulan escrituras sucesivas alrededor de un corte capturado dentro del fixture; no se presentan como prueba de una instantánea global ni como nuevas pruebas de múltiples sesiones. Los fixtures revierten sus datos y las marcas de la copia avanzan normalmente. El parser del script PowerShell de publicación pasó.

La [guía de empleados y productos](referencias/extraccion.md) contiene conceptos, preparación, consulta en SSMS, pruebas y compilación en Visual Studio. No se cargó staging ni se construyeron paquetes SSIS en esta etapa. Se mantiene retirada la planificación del repositorio; no se hizo commit ni push.

Progreso: **8 de 41**. Próxima unidad recomendada: **2.5 y 2.6**, transportistas y ventas.

## Numeración de las guías

Por petición del usuario, las guías paso a paso se numeraron desde 01 para indicar su orden de lectura. Se actualizaron sus enlaces y el README. No se renombraron objetos SQL.

| Nombre anterior | Nombre final | Responsabilidad |
| --- | --- | --- |
| guia-practica.md | 01-guia-practica.md | Conceptos iniciales y recorrido |
| entorno.md | 02-entorno.md | Herramientas, servicios y configuración comprobada |
| pruebas-aisladas.md | 03-pruebas-aisladas.md | Preparación y ejecución de pruebas |
| extraccion-clientes.md | 04-extraccion-clientes.md | Marcas y clientes |
| extraccion-empleados-productos.md | 05-extraccion-empleados-productos.md | Relaciones de empleados y productos |
| Nuevo | 06-extraccion-transportistas-ventas.md | Transportistas y granularidad de ventas |

validacion.md conserva su nombre como registro de resultados, y evidencias/README.md explica los archivos locales. La eliminación de la planificación, el segmento anterior y la numeración 01–05 se publicaron con autorización expresa del usuario en el commit **4fda102**, rama northwind. El segmento 05 siguiente queda como cambios locales posteriores a ese commit.

## Segmento 05 — Transportistas y ventas

Tareas **2.5 y 2.6**. Se crearon GetShipperChangesByRowVersion y GetSalesChangesByRowVersion y se incluyeron como Build en Northwind.OLTP. Ventas combina exclusivamente Orders/OrderDetails, con identidad OrderID/ProductID, ShipVia como ShipperID y precio del detalle vendido. Se preservan referencias y fechas NULL. Todas las marcas contribuyentes deben estar dentro del corte, y cualquier cambio de cabecera o detalle puede seleccionar la línea.

| Escenario | Resultado ejecutado | Evidencia local en `evidencias/segmento-05/` |
| --- | --- | --- |
| Compilación y publicación | Compila sin errores, 19 advertencias heredadas SQL71502; ocho procedimientos publicados únicamente en Northwind_Test | `compilacion.txt`, `despliegue.txt` |
| Transportistas | 3 identidades únicas y columnas compatibles con std.Transportista; actualización con teléfono NULL | `Shipper.txt` |
| Alta y límites | Alta posterior al corte excluida y recuperada en el siguiente intervalo; inferior excluido/superior incluido | `Shipper.txt` |
| Ventas de referencia | 2.155 líneas únicas, 830 pedidos, 51.317 unidades; todas las columnas comparadas con consulta independiente en ambos sentidos | `Sales.txt` |
| Pedido 10248 | Productos 11/42/72, 27 unidades y bruto 440,00 | `Sales.txt` |
| Precio de catálogo | Actualizar Products.UnitPrice no selecciona ventas ni altera el precio vendido | `Sales.txt` |
| Cabecera y detalle | Fechas/cliente/empleado/transportista en cabecera seleccionan sus tres líneas; cambiar precio/cantidad/descuento en detalle selecciona una línea | `Sales.txt` |
| Cambios posteriores | Cabecera posterior difiere líneas y las recupera; detalle posterior difiere solo su línea y la recupera | `Sales.txt` |
| Ausencias | Cliente, empleado, transportista y tres fechas NULL conservan las tres líneas del pedido | `Sales.txt` |
| Intervalos | Vacíos sin filas; negativos, invertidos y NULL rechazados específicamente con 51104 | `Shipper.txt`, `Sales.txt` |
| Originales y limpieza | Originales sin diferencias antes/después; todas las columnas comerciales de Orders, OrderDetails, Products y Shippers de copia coinciden en ambos sentidos con origen, excluida rowversion | `originales-antes.txt`, `originales-despues.txt`, `limpieza.txt` |

Se corrigió un conflicto de intercalación de las tablas temporales de prueba con COLLATE DATABASE_DEFAULT y se volvieron a ejecutar ambos fixtures: cuatro grupos Passed de transportistas y ocho de ventas. No se cambió la intercalación de las bases. El parser de PowerShell de publicación pasó; los ejemplos de la guía y sus enlaces locales se comprobaron. Los cambios de datos se revirtieron; rowversion y el IDENTITY de la alta de prueba avanzan solamente en la copia.

Las pruebas de corte usan escrituras sucesivas dentro de un fixture, sin afirmar una nueva comprobación de múltiples sesiones ni una instantánea global. std.Ventas conserva por ahora MONEY/REAL como el origen; tipos decimales y cálculo de importes del DW corresponden a tareas posteriores. No se cargaron staging, hechos ni paquetes SSIS.

La [guía 06](referencias/extraccion.md) explica conceptos, columnas, pasos PowerShell/SSMS/Visual Studio, resultados y recuperación. Progreso: **10 de 41**. Próxima unidad recomendada: **2.7**, mapa de tablas, claves y extractores, antes del proyecto DW.

## Sección funcional: cierre de extracción y modelo/publicación DW

Se sustituyó el límite de una a tres tareas por secciones funcionales completas y se registró la preferencia de guías operativas concisas en AGENTS.md, la habilidad local y los artefactos OpenSpec externos al repo. El commit/push autorizado de lo acumulado fue **72849d2** en northwind. Los cambios de esta sección son posteriores y permanecen locales.

Tareas **2.7 y 3.1–3.7**. La solución contiene Northwind.OLTP y Northwind.DW, con propietarios separados. Se retiraron las definiciones DW duplicadas del OLTP y su PostDeploy que consultaba otro destino. Los cuatro merges de dimensiones y los procedimientos de control se integraron en DW; su endurecimiento transaccional corresponde a la sección de aplicación. El procedimiento antiguo de hechos quedó como Legacy fuera de Build y no se utiliza como carga validada.

| Comprobación ejecutada | Resultado | Evidencia local en `evidencias/seccion-dw/` |
| --- | --- | --- |
| Solución y límites de dacpac | Ambos proyectos compilan; OLTP tiene sus 13 tablas de origen, DW sus 12 tablas; ningún objeto DW en OLTP | `compilacion-solucion.txt`, `limites-y-guia.txt` |
| Extracción completa y pedido conocido | 91/9/77/3/2155; pedido 10248 con productos 11/42/72, 27 unidades y bruto/neto 440 | `pruebas-modelo.txt`, `limites-y-guia.txt` |
| Esquema y claves | Unicidad comercial en dimensiones, OrderID/ProductID único, FKs y validaciones de cantidad/precio/descuento; miembros desconocidos 0 | `pruebas-modelo.txt` |
| Tipo 1 | Actualización de ciudad refleja atributo y conserva Cliente_SK | `pruebas-modelo.txt` |
| Calendario | Rango continuo 1996-07-04 a 1998-06-11 (708 días), extensión de cuatro días repetible, nombres españoles bajo idiomas/DATEFIRST diferentes; rangos inválidos 52001/52002 rechazados | `pruebas-modelo.txt`, `limpieza.txt`, `limites-y-guia.txt` |
| Migración ambigua | Dos hechos legacy con la misma identidad derivada rechazados con 52013 antes de agregar ProductID; fixture revertido | `migracion-ambigua.txt` |
| Migración de datos y republicación | Hecho legacy de prueba conserva Venta_SK, importes, marca 0x7B y fecha; ProductID derivado de dimensión; segunda publicación conserva todo | `legacy-antes-republicar.txt`, `legacy-despues-republicar.txt`, `republicacion-con-datos.txt`, `republicacion/` |
| Regla monetaria | 10×20 y 10% → 200/20/180; precio 0,0050 → 0,01; descuento sobre bruto 1 con proporción 0,005000 → 0,01 | `pruebas-modelo.txt` |
| Reconciliación independiente sobre fixture completo | 91 clientes, 9 empleados, 77 productos, 3 transportistas, 2155 líneas, 830 pedidos, 51317 unidades; bruto 1354458,59, descuento 88665,83, neto 1265792,76 | `pruebas-modelo.txt` |
| Fixtures inválidos | Constraints rechazan duplicados y referencias/valores inválidos; comparación detecta neto incorrecto y ProductID incoherente con SK; ausencias legítimas admitidas con 0/NULL | `pruebas-modelo.txt` |
| Originales y limpieza | Capturas de originales idénticas; fixture legacy y marca temporal eliminados; fixture completo revertido. Copia DW conserva desconocidos/calendario, cero entidades/hechos comerciales y controles iniciales | `originales-antes.txt`, `originales-despues.txt`, `limpieza.txt` |

La primera publicación sobre datos se detuvo por BlockOnPossibleDataLoss ante REAL→decimal. Se corrigió mediante conversión explícita validada antes de publicar, manteniendo ese bloqueo activado. Se configuró la conservación de propiedades extendidas y opciones de base para no retirar la marca de prueba. En la carga del fixture, BulkCopy REAL→decimal produjo una diferencia de un centavo; se normalizó el descuento en SQL antes del transporte y la reconciliación independiente pasó. La sección SSIS debe conservar esa conversión; no se declara probada su integración.

Las comprobaciones de datos completos usan un fixture transaccional, no una carga de aplicación ya disponible. La sección DW prepara esquema, controles, desconocidos y calendario. La aplicación incremental, SSIS, modelo tabular y job permanecen pendientes. La publicación inicial y repetida se realizó únicamente en Northwind_DW_Test.

Las guías operativas quedan en 01–05. Las antiguas guías por entidad 04-extraccion-clientes, 05-extraccion-empleados-productos y 06-extraccion-transportistas-ventas se sustituyeron por una sola guía de ejecución de extractores y [referencias técnicas](referencias/extraccion.md). El [mapa DW](referencias/modelo-dw.md) registra propietarios, renombres, tres fechas, claves, tipo 1, importes y correspondencia BikeStores. La guía [05](05-preparar-dw.md) contiene únicamente publicación/comprobación. Se verificaron sus consultas y enlaces locales; parser PowerShell sin errores.

Progreso: **18 de 41**. Próxima sección funcional: **aplicación y carga de datos (grupo 4)**. No se hizo commit ni push de esta sección posterior a 72849d2.
## Sección funcional: aplicación y carga transaccional

El commit/push autorizado de la sección DW fue **79f8287**, publicado en northwind. Las tareas **4.1–4.4** se implementaron después y permanecen locales.

El cargador real Load-NorthwindWarehouse.ps1 puebla las cinco entidades sobre las copias marcadas. DW_ApplyPackage une aplicación final, marca y fecha en una transacción local por entidad. Las cuatro dimensiones conservan sus claves; hechos se aplican por pedido/producto y resuelven siete referencias con validación explícita. El bloqueo de sesión protege staging durante todo el principal; las aplicaciones SQL usan el mismo recurso. GetLastPackageRowVersion detecta control ausente, marca no representable y destino vacío con avance; el cargador rechaza corte anterior.

| Verificación ejecutada | Resultado | Evidencia local en evidencias/seccion-carga/ |
| --- | --- | --- |
| Compilación/publicación | Ambos SQL compilan sin errores; DW sin advertencias, referencia SSDT a master.dacpac 170 para bloqueos; publicación inicial y repetida sobre copia cargada | compilacion-solucion.txt, compilacion-publicacion.txt, republicacion/ |
| Carga real inicial | Cliente 91, Empleado 9, Producto 77, Transportista 3, Ventas 2155; cinco entidades confirmadas | carga-inicial.txt |
| Reconciliación independiente | 830 pedidos, 51317 unidades, bruto 1354458,59, descuento 88665,83, neto 1265792,76; cero referencias/importes inválidos y duplicados | reconciliacion.txt, pruebas-cargador.txt |
| Cuatro dimensiones | Altas, cambio de atributos, repetición y conservación de todas las SK originales | pruebas-aplicacion.txt, pruebas-sobre-dw-cargado.txt |
| Ventas | Pedido 10248: tres líneas, 27 unidades, neto 440; cambio a 28 unidades/neto 454; cabecera y tres fechas actualizadas; calendario extendido sin huecos; nulos legítimos 0/NULL; Venta_SK estable | pruebas-sobre-dw-cargado.txt |
| Aplicación inválida | Referencia no resuelta 52407 revierte datos/control; diagnóstico incluye identidad de línea | pruebas-sobre-dw-cargado.txt |
| Control incompatible | Destino vacío avanzado 52404, intervalo 52401, marca no representable 52411, proceso desconocido 52409, control ausente 52410, inicio modificado 52403, staging posterior 52405 y clave reservada 52408; datos/marcas/fechas preservados | pruebas-sobre-dw-cargado.txt |
| Fallo después de aplicar | Trigger de prueba rechaza actualización de control 52520; atributos, claves, marca y fecha previos conservados; trigger retirado | pruebas-sobre-dw-cargado.txt, pruebas-cargador.txt |
| Repetición real | Cero filas extraídas en las cinco entidades; comparación completa de claves, atributos, calendario, hechos/importes y marcas idéntica, excluida la nueva fecha de ejecución correcta | repeticion.txt, pruebas-cargador.txt |
| Reintento incremental real | Cambiar ciudad en origen de prueba, fallar en control de Cliente, conservar cinco controles y detener dependientes; retirar fallo y cargar pendiente una sola vez con misma SK; restaurar ciudad y recargar | pruebas-cargador.txt |
| Competencia | Otra conexión retiene bloqueo; segundo cargador falla antes de modificar staging, finales o controles, incluida fecha | pruebas-cargador.txt |
| Regresión del modelo | Suite del DW aprobada antes de la carga persistente; fixtures completos revertidos | regresion-modelo.txt |
| Originales | Captura de rowversion/conteos/procedimientos/control idéntica a la sección anterior; solo la copia operativa avanzó rowversion por fixtures | originales-despues.txt |

Los fixtures SQL se revirtieron, incluidos calendario futuro y dimensiones nuevas. La prueba incremental restaura la ciudad operativa original de la copia y vuelve a sincronizar el DW. No quedan triggers de fallo. El DW de prueba queda comercialmente poblado, no vacío; controles conservan el último avance real. Las pruebas no escribieron NorthWind/Northwind_DW.

La guía 01 ahora ejecuta el cargador y comprueba ventas; 06 contiene carga, repetición y recuperación indispensable. Los contratos de staging/transacciones quedan en referencias/carga.md. Se retiró Legacy/DW_MergeFactVentas.sql y su responsabilidad pasó al procedimiento declarativo compilado de hechos; proyectos y mapa actualizados.

Progreso: **22 de 41**. SSIS, tabular y job siguen pendientes; el éxito del cargador PowerShell no se presenta como ejecución SSIS. La sección permanece sin commit/push posterior a 79f8287.

## Inicio de sección SSIS: bloqueo de herramientas

La sección de aplicación se publicó mediante el commit **969e1be** en northwind. La sección SSIS empezó comprobando los ejecutores reales antes de crear paquetes comerciales.

Se generó un paquete de diagnóstico con un Data Flow vacío y sin conexiones, SQL ni acceso a bases. El ejecutor del motor, 170/DTS/Binn/DTExec.exe versión 17.0.1000.7, lo ejecutó con DTSER_SUCCESS. El ejecutor de Visual Studio, CommonExtensions/Microsoft/SSIS/170/Binn/DTExec.exe versión 17.0.1016.0, falló antes de ejecutar con «Could not create DTS.Application because of error 0x80040154». Una prueba adicional del SDK privado produjo incompatibilidad IDTSApplication170. La carpeta 160 no contiene DTExec.exe; no se declaró probado un destino alternativo.

tests/Test-SsisRuntime.ps1 reproduce la comprobación sin modificar datos y genera los registros locales SQLServer.txt y VisualStudio.txt en evidencias/seccion-ssis. La evidencia confirma el fallo del ejecutor del diseñador, no demuestra por sí sola el estado de todos los menús/editor de Visual Studio. No se atribuye todavía una causa raíz concreta.

El registro de programas instalados identifica Microsoft SQL Server Integration Services Projects, versión 17.0.1016.0, y su instalador de mantenimiento. La guía 07 documenta su apertura, reparación manual y comprobación posterior. La reparación no se ejecutó. Conforme a D8, no se instalaron componentes ni se modificó el registro automáticamente. Los requisitos de herramientas se contrastaron con la ficha oficial de Microsoft:
https://marketplace.visualstudio.com/items?itemName=SSIS.MicrosoftDataToolsIntegrationServices

En ese punto las tareas 5.1–5.7 permanecían pendientes, con progreso **22 de 41**. El diagnóstico de la utilidad privada resultó insuficiente para concluir que el diseñador no podía ejecutar paquetes; la comprobación y el cierre siguientes sustituyen esa conclusión.

## Sección funcional SSIS: ejecución nativa y recuperación

El usuario ejecutó en Visual Studio su proyecto PruebaSSIS con destino SQL Server 2025 y proveedor MSOLEDBSQL.1. Se comprobó además ese paquete con el DTExec del motor, con DTSER_SUCCESS. SQLNCLI11 no está registrado y la utilidad privada DTExec de la extensión continúa fallando al crear DTS.Application; eso no invalida el diseñador ni el ejecutor del motor. No se realizó otra reparación, instalación ni modificación del registro.

Northwind.ETL incorpora cinco paquetes independientes, dos conexiones de proyecto parametrizadas y CargarNorthwind con cinco grupos nativos de secuencia, dimensiones antes de Ventas. Todos ejecutan tareas Execute SQL y flujos OLE DB reales. El principal conserva la sesión de control entre grupos, verificada mediante CONTEXT_INFO. La alternativa Execute Package Task no compartió sesión física en la prueba y se descartó. Las marcas se enlazan como Int64 y las medidas transportan decimales. Cada ejecución tiene un registro nativo propio.

| Comprobación | Resultado | Evidencia local en docs/evidencias/ssis/ |
| --- | --- | --- |
| Solución Visual Studio | Northwind.OLTP/DW/ETL: 3 proyectos correctos, 0 fallidos, 0 omitidos; configuración Debug mapea SSIS a Development. Advertencias SQL71502 heredadas del OLTP; mensajes de caché dbmdl bloqueada por la instancia abierta, sin error de compilación | solucion-build-final.txt |
| Compilación nativa del proyecto | Consistencia correcta y exportación de los seis paquetes; ejecución del .ispac nativo con DTSER_SUCCESS | visual-studio-build.txt y bin/Development/Northwind.ispac |
| Compilación desde fuentes | Build-NorthwindETL empaqueta fuentes editables sin regenerarlas; ejecución con parámetros reales de servidores, bases y carpeta de registro | bin/Development/Northwind.ETL.ispac e integracion.txt |
| Carga inicial independiente | DW nuevo vacío: 2155 líneas, 830 pedidos, cinco controles confirmados; conteos/importes coinciden con cálculo independiente | integracion.txt, 8a5e956a/Northwind.ETL-*.log |
| Repetición | Principal y cinco entradas independientes conservan todas las SK, atributos, medidas, staging y marcas | integracion.txt |
| Incrementos reales | Cliente y pedido nuevos; detalle, descuento, cabecera, empleado, transportista, categoría/proveedor y ampliación de calendario; identidad estable y reconciliación | integracion.txt |
| Fallo/reintento | Trigger exclusivo de fixture rechaza marca de Cliente: finales y cinco controles/fechas intactos; dependientes detenidos; retirada del trigger y reintento correcto | integracion.txt y registros OnError |
| Competencia real | Principal retenido 20 segundos antes de staging; otras seis entradas rechazadas por DW ocupado, sin cambios de staging/finales/control; carga activa termina correctamente | integracion.txt y registros OnError |
| Precisión SSIS | Inicio y fin reales conservan 9223372036854775807 en dos ejecuciones de Cliente; se restauran el procedimiento de corte y el control previos de la copia exclusiva | integracion.txt |
| Registro | Inicio/fin y error identificables por ejecución; registro independiente evita que un bloqueo de archivo simule un rechazo de carga | 8a5e956a/Northwind.ETL-*.log |
| Copias del usuario | Reconciliación posterior: 91/9/77/3 entidades, 2155 líneas, 830 pedidos, 51317 unidades, neto 1265792.76; 14 comprobaciones correctas | reconciliacion-final.txt |
| Originales | NorthWind conserva 91 clientes, 830 pedidos y 2155 líneas; Northwind_DW sigue vacío con cinco marcas 0 y fechas NULL | originales-final.txt |

Reproducción de integración: `& '.\tests\Test-SSIS.ps1'`. Cada ejecución crea destinos propios con sufijo aleatorio y conserva las bases y backups para inspección; no sustituye ni vacía las copias del usuario. La ejecución final usó Northwind_SSIS_OLTP_8a5e956a/Northwind_SSIS_DW_8a5e956a. Los triggers de fallo y la modificación temporal del procedimiento de corte se retiraron; pruebas previas incompletas también conservan sus bases identificadas. Las evidencias no se versionan.

Las guías 01 y 07 ejecutan el proyecto; 08 contiene la preparación y publicación en catálogo con menús contrastados con la documentación de Microsoft. SSISDB no existe todavía en este equipo: creación del catálogo, publicación y ejecución desde SSISDB no se han realizado y quedan para la sección 7. La carga local funciona sin catálogo. Referencias de publicación: [asistente SSMS](https://learn.microsoft.com/en-us/sql/integration-services/ssis-quickstart-deploy-ssms?view=sql-server-ver17) y [catálogo](https://learn.microsoft.com/en-us/sql/integration-services/catalog/ssis-catalog?view=sql-server-ver17).

Sección 5 completada: **29 de 41 tareas**. SSAS y despliegue/job pendientes. Cambios locales, sin commit ni push posterior a 969e1be.

## Sección funcional: modelo tabular OLAP

Northwind.OLAP implementa el análisis tabular de BikeStores sobre `Northwind_DW_Test`. El proyecto se compiló y se desplegó en Analysis Services Tabular local. La guía [09](09-procesar-y-consultar-olap.md) prepara Visual Studio/SSAS, publica y procesa el modelo, reconcilia medidas y muestra consultas filtradas; [02](02-entorno.md) contiene los pasos de instalación y conexión.

| Comprobación ejecutada | Resultado | Evidencia local en `evidencias/olap/` |
| --- | --- | --- |
| Compilación y despliegue | `Northwind.OLAP.smproj` compila; se publicó `NorthwindOLAP_Test` desde `Northwind_DW_Test` en `localhost` | `build-olap.txt`, `procesamientos/`, `NorthwindOLAP-*.log` |
| Medidas y pedido conocido | 830 pedidos, 51.317 unidades, bruto 1.354.458,59, descuento 88.665,83, neto 1.265.792,76; pedido 10248: 1 pedido, 27 unidades, 440,00 bruto/neto | `comparacion-20261012-020024-277.json` |
| Filtros | Beverages/1996 = 47.919,00 netos; Alemania/ALFKI = 6 pedidos y 4.273,00 netos | `comparacion-20261012-020024-277.json` |
| Fechas alternativas | Venta de fixture: pedido en julio = 90, fecha requerida en agosto = 90, envío en septiembre = 90; envío sin fecha no se asigna a septiembre | `integracion-20261012-020024-283.json` |
| Error de proceso y recuperación | Fallo real registrado como `FAILED`; origen restaurado; segundo procesamiento y reconciliación completados | `NorthwindOLAP-20261012-020011-186.log`, `integracion-20261012-020024-283.json` |
| Aislamiento y limpieza | Filas temporales eliminadas, resultado vuelve a las cifras iniciales; Northwind_DW original sin cambios | `integracion-20261012-020024-283.json` |

La prueba usó dos pedidos temporales en `Northwind_DW_Test`; se retiraron después del procesamiento y se verificó la limpieza. El login del servicio SSAS recibe `SELECT` únicamente sobre las seis tablas de esa copia. El proyecto OLAP se compila de forma independiente. Su inclusión en la compilación integral de los cuatro proyectos, SSISDB y el job se verifica en la siguiente sección de despliegue.

Sección 6 completada: **34 de 41 tareas**. Los cambios OLAP permanecen locales, sin commit ni push posterior a `dc373de`.

## Sección funcional: despliegue y job

El modelo OLAP anterior se publicó en la rama `northwind` mediante `e7abd5e`. Esta sección permanece local. Las guías 01–10 usan Visual Studio y SSMS como recorrido principal; los comandos PowerShell apoyan automatización y pruebas.

| Comprobación | Resultado | Evidencia |
| --- | --- | --- |
| Abrir solución y recompilar desde Visual Studio | Confirmado por el usuario: 4 succeeded, 0 failed, 0 skipped; 0 errores y 0 advertencias | Mensaje del usuario del 12-10-2026, compilación 11:14 |
| Compilación completa desde segunda instancia CLI | No aprobada: esa instancia omite OLAP; el helper detecta el fallo, sin usar artefactos antiguos para declarar éxito | evidencias/despliegue/build-solution-final.txt |
| Perfiles SQL nativos | XML y generación real de planes de publicación aprobados para las dos copias | profile-source.txt, profile-warehouse.txt |
| Catálogo y publicación SSIS | SSISDB creado, proyecto propio con seis paquetes y cinco parámetros asociados al entorno | evidencias/despliegue/ |
| Scripts SSMS repetidos | Configuración del entorno y creación del job ejecutadas dos veces correctamente; mismos objetos | verify-gui-scripts.ps1 |
| Job principal manual | SSIS y procesamiento correctos; job y horario diario 02:00 deshabilitados | main-job.json |
| Job repetible, fallos y recuperación | Mismo job al crearlo dos veces; fallo ETL impide etapa analítica y conserva marcas; fallo analítico registra error y se recupera; fixtures retirados | integration-windows-powershell.txt, job-20261012-111024-610.json |
| Republicación analítica | Roles y miembros conservados; procesamiento y reconciliación aprobados | redeploy.txt |
| Originales y aislamiento | Pruebas sobre copias identificadas, TRUSTWORTHY y DB_CHAINING desactivados; originales conservados | Prueba Test-DeploymentJob.ps1 |

Los archivos de evidencia, contraseña protegida y compilados se excluyen de Git. La confirmación del usuario acredita la compilación desde la interfaz; las operaciones de publicación automatizadas no se presentan como acciones manuales del usuario. El recorrido gráfico de publicación y ejecución del job todavía requiere su comprobación manual. La sección 7 se publicó en `northwind` con `a5426ae`. La sección 8 registra el cierre integrado; queda pendiente confirmar el historial del job y la consulta DAX desde SSMS en el recorrido gráfico.

Publicación final comprobada: ambos perfiles nativos se ejecutaron con SqlPackage sobre las copias; se publicó el `Northwind.ispac` generado por la compilación gráfica confirmada por el usuario. La integración completa volvió a aprobarse con ese artefacto, incluidos fallos, recuperación, limpieza y originales conservados. Evidencia: `evidencias/despliegue/native-publication.txt`, `job-20261012-113125-602.json`, `comparacion-20261012-113125-769.json`. Los cuatro scripts SQL de SSMS pasaron TSql170Parser; los scripts PowerShell, perfiles XML y enlaces locales pasaron revisión.

Sección 7 completada y publicada: **38 de 41 tareas**, commit `a5426ae`. La sección 8 permanece local.


## Sección 8: validación integrada y matriz final

| Requisito | Escenario comprobado | Evidencia y resultado |
| --- | --- | --- |
| NWX-01 | Empleados con varios o ningún territorio y clientes con varias clasificaciones producen una fila por identidad | pruebas de extracción de segmento 3 y 4 |
| NWX-02 | Categoría, proveedor y supervisor modificados vuelven a seleccionar entidades dependientes; relaciones opcionales conservan nulos | segmento 4, pruebas Product y Employee |
| NWX-03 | Pedido 10248, cambio de detalle/cabecera, fechas e identidad y líneas modificadas | segmento 4, pruebas Sales |
| NWX-04 | Límite inferior/exclusivo y superior/inclusivo; transacción abierta; cambio confirmado posterior al corte aparece en el intervalo siguiente | `evidencias/despliegue/final-rowversion.txt`; `evidencias/segmento-03/rowversion.txt` |
| NWE-01 | Primera carga SSIS de cinco entidades, dimensiones antes de ventas y cinco controles confirmados | `evidencias/seccion-ssis/integracion.txt`; reconciliación final |
| NWE-02 | Fallo al guardar marca no confirma aplicación ni fecha; marcas previas se conservan | `evidencias/seccion-carga/pruebas-cargador.txt`; `evidencias/despliegue/final-load.txt` |
| NWE-03 | Repetición sin cambios y reintento no duplican filas ni alteran claves | `evidencias/despliegue/final-load.txt` |
| NWE-04 | Altas y cambios de dimensiones, pedidos, líneas, cabeceras, categorías y proveedores | `evidencias/seccion-ssis/integracion.txt` |
| NWE-05 | Una segunda carga concurrente se rechaza antes de modificar staging; fallo de etapa detiene dependientes y deja error localizable | `evidencias/despliegue/final-load.txt`; `integration-windows-powershell.txt` |
| NWW-01–03 | Claves estables, dimensiones tipo 1, calendario continuo y fechas de pedido/requerida/envío | `evidencias/seccion-carga/pruebas-sobre-dw-cargado.txt`; `evidencias/olap/integracion-20261012-020024-283.json` |
| NWW-04–05 | Nulos permitidos, referencias inválidas rechazadas, precio vendido y redondeo por línea | `evidencias/seccion-carga/pruebas-sobre-dw-cargado.txt`; `evidencias/seccion-carga/pruebas-aplicacion.txt` |
| NWW-06 | Conteos, claves e importes del origen y DW coinciden; cero duplicados o referencias inválidas | `evidencias/despliegue/final-compare-dw.txt` |
| NWA-01–03 | Filtros por categoría/año y cliente/país; medidas y funciones de fecha | `evidencias/olap/comparacion-20261012-020024-277.json` |
| NWA-04 | Proceso actualizado, venta conocida reconciliada; fallo registrado y recuperación posterior | `evidencias/olap/integracion-20261012-020024-283.json`; `evidencias/despliegue/final-compare-olap.txt` |
| NWP-01–02 | Solución 4/4 en Visual Studio según confirmación del usuario; perfiles publican a copias; contraseñas fuera del repositorio | Confirmación de compilación del usuario; `evidencias/despliegue/native-publication.txt` |
| NWP-03 | Job propio ejecutado a pedido con sus dos pasos correctos, recuperación ante fallos verificada y horario/job deshabilitados | `evidencias/despliegue/final-main-job.txt`; `job-20261012-113125-602.json` |
| NWP-04, NWP-07 | Guías 01–10 usan pasos de Visual Studio y SSMS; el usuario confirmó historial y DAX correctos desde SSMS | [guía 10](10-ejecutar-job.md), paso 3; confirmación del usuario |
| NWP-05 | Fixtures aislados, pruebas y limpieza; copias reconciliadas y bases originales conservadas | `evidencias/despliegue/final-load.txt`; `job-20261012-113125-602.json` |
| NWP-06 | Correspondencia de etapas, modelo y adaptaciones con BikeStores | [arquitectura](referencias/arquitectura.md) |
| NWP-08 | Continuación por secciones, con tareas/evidencia fuera de las guías | Cambios OpenSpec en el workspace; guía 01 como entrada |

La compilación de Visual Studio fue ejecutada y confirmada por el usuario: cuatro proyectos correctos, cero fallos y cero omitidos. El job principal se ejecutó manualmente con el horario apagado; la carga y el procesamiento finalizaron bien. La reconciliación final da 2.155 líneas, 830 pedidos, 51.317 unidades y neto 1.265.792,76; pedido 10248 da 27 unidades y neto 440,00. Las cifras de DW y OLAP coinciden.

El resultado del motor ya está comprobado. El usuario confirmó en SSMS que los dos pasos del historial son correctos y que DAX coincide con 830 pedidos, 51.317 unidades y 1.265.792,76 netos. El job y el horario permanecen deshabilitados.

La evidencia de sesión y los artefactos generados se mantienen locales y excluidos de Git. El commit `a5426ae` publica la sección 7; estas notas de validación de la sección 8 todavía no están publicadas.


Sección 8 completada: **41 de 41 tareas**. Confirmación gráfica final del usuario registrada; la validación queda local y sin commit/push.

Durante el cierre, la primera repetición de Test-Load detectó una diferencia inmediatamente después de la prueba de rowversion. Se ejecutó una carga de estabilización, dos cargas consecutivas dieron estados idénticos y la suite completa de repetición, concurrencia, fallo/reintento y reconciliación pasó. La comparación final del origen y DW y la consulta OLAP también pasaron. La diferencia inicial no volvió a reproducirse; no se atribuye una causa sin evidencia.

## Sustitución Northwind — extracción OLTP

Validación ejecutada sobre `Northwind_Test`, copia marcada creada desde `NorthWind`. `NorthWind` y `Northwind_DW` no fueron destinos de escritura. La compilación de `Northwind.OLTP.sqlproj` terminó sin errores y generó su DACPAC; permanecen las advertencias heredadas SQL71502 de procedimientos de ejemplo que hacen referencia a `Order Details`, tabla no declarada en este proyecto.

| Comprobación | Resultado ejecutado |
| --- | --- |
| Cliente, empleado, producto y transportista | 91, 9, 77 y 3 identidades; pruebas completas aprobadas, incluidas relaciones opcionales, atributos, categoría, territorios/demografía y calendario independiente |
| Proveedor | 29 en la referencia; prueba aprobada con proveedor sin productos, atributos nulos, HomePage de 1.200 caracteres, cambio descriptivo e intervalo vacío/inválido |
| Ventas | 2.155 líneas, 830 pedidos y 51.317 unidades; pedido 10248 conserva productos 11/42/72, 27 unidades y 440,00 bruto |
| Cabecera | Freight `17,1234` y destino se entregan igual en las tres líneas; los NULL de flete, fechas, identidades y destino también se conservan |
| Dependencias incrementales | Cambio de detalle o producto devuelve todas las líneas; una dependencia posterior al corte difiere el pedido y el intervalo siguiente lo recupera completo |
| Precio vendido | Cambiar el precio de catálogo vuelve a seleccionar los pedidos del producto, sin cambiar el precio de sus líneas vendidas |
| Marcas y concurrencia | `Test-RowVersion.ps1` aprobó aislamiento READ COMMITTED, corte frente a transacción pendiente, recuperación tras commit, límites Int64 y parámetros Binary(8)/BigInt |

Se ejecutaron `Test-CustomerExtraction.sql`, `Test-EmployeeExtraction.sql`, `Test-ProductExtraction.sql`, `Test-ShipperExtraction.sql`, `Test-SupplierExtraction.sql`, `Test-SalesExtraction.sql` y `Test-RowVersion.ps1`. Los fixtures SQL finalizaron con rollback; la prueba de concurrencia restauró los nombres de clientes en `Northwind_Test`. Las guías y el mapa de contratos se actualizaron para el proveedor nuevo y la extracción coherente de pedidos.

## Sustitución del modelo estrella — implementación actual

Fecha: 16 de octubre de 2026. Se implementó en el árbol de trabajo el modelo final con `FactSales`, siete dimensiones en inglés y seis procesos de carga. Se mantuvieron `GrossAmount`, `DiscountAmount`, `NetAmount` y `Freight`; no se agregó `FreightAmount` ni un segundo hecho. Se incorporaron la migración aditiva, el corte explícito del legado, las consultas y guías actualizadas.

| Comprobación de compilación | Resultado |
| --- | --- |
| `Northwind.OLTP.sqlproj` | Compilación correcta; se generó DACPAC. |
| `Northwind.DW.sqlproj` | Compilación correcta; se generó DACPAC. |
| Proyecto `Northwind.ETL` | Compilación correcta; se generó `Northwind.ETL.ispac` con seis paquetes. |
| Scripts PowerShell principales y pruebas adaptadas | Parser de PowerShell sin errores. |
| Cambios de texto | `git diff --check` sin errores de whitespace. |

Los scripts de migración y retirada no se ejecutaron contra `Northwind` ni `Northwind_DW`, y no se publicaron cambios en esas bases. La aceptación runtime del nuevo ciclo completo, incluida la migración en copia cargada, repetición SSIS y corte del legado, queda pendiente de ejecutarse en las copias identificadas; los archivos de prueba correspondientes ya están adaptados.

## Reparación de NorthwindBIJob — 21 de octubre de 2026

La ejecución de las 23:05 falló en extracción con `VS_NEEDSNEWMETADATA`. El proyecto publicado en SSISDB seguía siendo del 12 de octubre y no contenía `Proveedor.dtsx`. Se guardó una copia del ISPAC anterior y de los pasos del job, se recompiló el proyecto actual y se publicó mediante `Publish-NorthwindETL.ps1` con el entorno `Northwind_Test`. El catálogo contiene ahora siete paquetes: el principal y los seis procesos de carga.

Se ejecutó manualmente el propio `NorthwindBIJob`, con la identidad de SQL Server Agent. La ejecución iniciada a las 23:10:14 terminó correctamente en 17 segundos: paso 1 de carga correcto (SSIS ejecución 10061), paso 2 de procesamiento correcto y resultado global correcto (historial 2179–2181). Las conciliaciones posteriores OLTP/DW y DW/OLAP aprobaron: 2.155 líneas, 830 pedidos, 51.317 unidades y neto 1.265.792,76.

Los destinos se conservaron: `Northwind_Test`, `Northwind_DW_Test` y `NorthwindOLAP_Test`. El job y su horario siguen deshabilitados para ejecución automática; puede iniciarse manualmente desde SSMS. Esta reparación no valida un despliegue del nuevo modelo en las bases principales.

Evidencias locales en `evidencias/reparacion-job-20261021/`: `Northwind.ETL-antes.ispac`, `job-antes.xml`, `publicacion.txt`, `job-despues.xml`, `conciliacion-dw.txt`, `conciliacion-olap.txt` y el JSON de comparación OLAP. No se modificaron los pasos ni la programación del job.

## Consultas de la guía paso a paso — 21 de octubre de 2026

Se revisaron los ocho bloques SQL y los dos bloques DAX de `guia paso a paso.md`. Se corrigió la detección de los modelos anterior y actual en 07.1, se completaron las comprobaciones de migración y miembros técnicos en 07.4, y se actualizaron el detalle monetario de 10.1 y la conciliación de medidas de 12.3. Los nombres antiguos solo se usan para detectar el legado. Se corrigió también la comprobación de siete paquetes publicados.

Los ocho bloques SQL se ejecutaron sustituyendo únicamente los nombres de las bases principales por `Northwind_Test` y `Northwind_DW_Test`, con comprobación de sus marcas y rollback, incluida la carga del calendario. Ambos bloques DAX se ejecutaron sobre `NorthwindOLAP_Test`. Todos terminaron correctamente. Se comprobaron los totales de referencia, seis procesos, tres líneas del pedido 10248, 708 días de calendario y 47.919,00 para Beverages en 1996. Las bases principales no se modificaron.

Evidencia SQL local: `evidencias/consultas-guia-20261021/sql.json` y `sql-1.xml` a `sql-8.xml`. Los resultados DAX quedaron registrados en la salida de la comprobación.
