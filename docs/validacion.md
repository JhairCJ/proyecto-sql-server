# Registro de validación

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
- Ahora también existen `DW_LoadDimTiempo` y `DW_MergeFactVentas`, tanto en el servidor como en `Scripts/DW_Merge.sql`. No se consideran tareas implementadas por nosotros: no se han ejecutado sus escenarios de aceptación.
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

La [guía de esta etapa](04-extraccion-clientes.md) contiene explicación y fichas D9 de publicación en copia, consulta y pruebas. No requiere intervención manual para completar lo ya ejecutado. Todavía no hay ETL de clientes, aplicación de staging ni paquete SSIS comprobados.

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

La [guía de empleados y productos](05-extraccion-empleados-productos.md) contiene conceptos, preparación, consulta en SSMS, pruebas y compilación en Visual Studio. No se cargó staging ni se construyeron paquetes SSIS en esta etapa. Se mantiene retirada la planificación del repositorio; no se hizo commit ni push.

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

La [guía 06](06-extraccion-transportistas-ventas.md) explica conceptos, columnas, pasos PowerShell/SSMS/Visual Studio, resultados y recuperación. Progreso: **10 de 41**. Próxima unidad recomendada: **2.7**, mapa de tablas, claves y extractores, antes del proyecto DW.
