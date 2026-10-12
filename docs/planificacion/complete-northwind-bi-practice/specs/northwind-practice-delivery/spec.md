# Spec Delta

## Purpose

Entregar una práctica Northwind reproducible y explicada desde cero, con proyectos identificables, ejecución manual y programada y evidencias que permitan demostrar su funcionamiento.

## ADDED Requirements

### Requirement: NWP-01 Solución y despliegue reproducibles

La entrega SHALL incluir proyectos identificables de base operativa, almacén, carga y análisis, junto con instrucciones para abrir, compilar, configurar y desplegar cada uno en herramientas compatibles. Los nombres, rutas y contenido de los archivos SHALL ser revisables para mejorar claridad, corrección y organización, sin imponer la conservación literal de los archivos existentes. Cada renombre o reorganización SHALL mantener coherentes las referencias de proyectos, conexiones, despliegue y documentación y registrar la correspondencia anterior/nueva. Si afecta objetos desplegados, SHALL incluir su migración y comprobación. La entrega SHALL evitar la restauración o eliminación automática de NorthWind y mantener intacto el material BikeStores.

#### Scenario: Apertura y despliegue
- **WHEN** se siguen las instrucciones en un entorno compatible
- **THEN** se pueden abrir y compilar los proyectos, desplegar sus objetos y localizar cada etapa de la práctica

#### Scenario: Despliegue repetido
- **WHEN** se despliega otra vez sobre un DW ya cargado
- **THEN** no se vacían datos ni se reinician marcas exitosas como efecto incidental

#### Scenario: Archivo renombrado y mejorado
- **WHEN** se divide, renombra o corrige un script o paquete de la práctica
- **THEN** proyectos, referencias y guía utilizan sus nombres finales, se explica la mejora y no quedan instrucciones que apunten a archivos retirados

#### Scenario: Renombre de objeto desplegado
- **WHEN** una mejora de nomenclatura afecta un objeto ya publicado
- **THEN** existe una migración documentada que conserva los datos y actualiza los consumidores y las comprobaciones

### Requirement: NWP-02 Dependencias y configuración explícitas

La entrega SHALL identificar versiones y componentes necesarios, conexiones, permisos y destinos. SHALL utilizar autenticación y parámetros de entorno sin incrustar contraseñas en archivos versionados. Una incompatibilidad de herramientas SHALL identificarse antes de publicar un despliegue como exitoso.

#### Scenario: Herramienta incompatible
- **WHEN** una extensión o runtime no permite abrir o ejecutar un proyecto
- **THEN** se identifica el componente y la incompatibilidad y se documenta el requisito sin cambiar automáticamente de motor

### Requirement: NWP-03 Ejecución programada con resultado del ciclo

La entrega SHALL incluir un job propio de Northwind que ejecute la carga y después el procesamiento analítico, se detenga ante fallos y registre su resultado. Su periodicidad SHALL ser configurable y el job SHALL entregarse deshabilitado hasta completar una ejecución manual validada.

#### Scenario: Primera habilitación
- **WHEN** el ciclo manual pasa las comprobaciones y el operador habilita la programación
- **THEN** el job puede ejecutar el mismo ciclo y dejar evidencia de su resultado

#### Scenario: Fallo de carga programada
- **WHEN** falla la carga del DW dentro del job
- **THEN** no se procesa el modelo como si la carga hubiera terminado correctamente y el job queda fallido

### Requirement: NWP-04 Guía didáctica y demostración

La entrega SHALL explicar en español base de datos, tablas, relaciones, claves, SQL, SQL Server, OLTP, DW, granularidad, staging, dimensiones, hechos, ETL, rowversion, modelo tabular y programación. SHALL asociar cada concepto con los archivos finales de la práctica e incluir una demostración del pedido 10248 desde origen hasta medidas y un recorrido filtrado por dimensión y fecha.

La guía SHALL organizarse por etapas en orden de dependencia, desde preparación e inicialización hasta verificación del ciclo completo. Cada procedimiento SHALL contener objetivo, prerrequisitos, programa y versión compatible, pasos numerados, ubicación o menú verificado, valores a introducir, archivo o script y contexto de ejecución cuando corresponda, explicación de su propósito, resultado esperado, comprobación y solución de errores frecuentes. SHALL cubrir comprobación de componentes/servicios, conexión a SQL Server y selección de base, apertura/configuración/compilación de proyectos, preparación del DW, conexiones SSIS, carga, despliegue/procesamiento tabular y ejecución del job. Los pasos de inicialización SHALL distinguir componentes ya preparados de componentes ausentes, sin duplicar ni reiniciar lo existente.

#### Scenario: Persona principiante
- **WHEN** una persona que no conoce Northwind sigue la guía
- **THEN** puede distinguir pedido de línea, ubicar cada proyecto y repetir el recorrido con resultados esperados y sin instrucciones que presuponen conocimientos no explicados

#### Scenario: Preparación inicial en los programas
- **WHEN** una persona necesita configurar una conexión en Visual Studio o iniciar la práctica desde SSMS
- **THEN** dispone de pasos ordenados que indican dónde realizar cada acción, qué servidor, autenticación y base elegir, por qué se necesita y cómo comprobar que funcionó

#### Scenario: Entorno parcialmente preparado
- **WHEN** las bases o servicios requeridos ya existen
- **THEN** la guía indica cómo verificar y reutilizar ese estado y reserva los pasos de creación o instalación para los componentes ausentes

### Requirement: NWP-05 Verificación aislada y evidencia completa

La entrega SHALL incluir comprobaciones de carga inicial, repetición, inserciones, actualizaciones, atributos dependientes, nulos, redondeo, fallo y reintento, límites de cambios y ejecución simultánea, junto con reconciliación del modelo. Las pruebas que modifiquen datos SHALL ejecutarse sobre destinos de prueba identificados y no sobre las bases del usuario. La evidencia SHALL distinguir verificaciones ejecutadas de verificaciones pendientes.

#### Scenario: Suite de integración
- **WHEN** se ejecutan las pruebas con origen y destino aislados
- **THEN** se documentan resultados y conteos sin alterar las bases NorthWind y Northwind_DW del usuario

#### Scenario: Comprobación no ejecutable
- **WHEN** falta un componente para una verificación
- **THEN** se registra la limitación y la verificación pendiente, sin declarar que pasó

### Requirement: NWP-06 Referencia arquitectónica BikeStores

La solución SHALL seguir una lógica de organización y ejecución similar a `Data-Management-and-BI/BikeStoresBI`: proyecto operativo, proyecto de almacén con staging/dimensiones/hechos/control, proyecto de carga, modelo tabular y programación posterior. SHALL documentar la correspondencia entre etapas de BikeStores y Northwind y explicar las adaptaciones necesarias por entidades, granularidad, claves y compatibilidad. La similitud no SHALL exigir copiar literalmente archivos, nombres, errores o entidades que Northwind no tiene.

#### Scenario: Comparación de ambas prácticas
- **WHEN** se consulta el mapa de arquitectura de la guía
- **THEN** se identifica qué proyecto y etapa de Northwind corresponde a cada responsabilidad del ejemplo y por qué las tiendas de BikeStores no se copian como una dimensión inexistente de Northwind

### Requirement: NWP-07 Acompañamiento de acciones manuales

Durante la implementación, cuando una etapa requiera intervención del usuario en Visual Studio, SSMS u otra herramienta necesaria, el asistente SHALL explicar antes de esa acción los pasos del procedimiento definido en NWP-04, qué parte ya está hecha y qué debe realizar el usuario. SHALL indicar cuándo regresar y qué resultado verificar; no SHALL continuar una etapa dependiente ni declarar éxito basándose únicamente en haber entregado las instrucciones. Las acciones que el asistente pueda ejecutar dentro del alcance autorizado no SHALL delegarse al usuario sin necesidad.

#### Scenario: Acción manual necesaria para continuar
- **WHEN** una configuración o ejecución requiere intervención del usuario en una interfaz
- **THEN** recibe instrucciones concretas, numeradas y contextualizadas, y la etapa dependiente espera su realización y la comprobación del resultado

#### Scenario: Procedimiento automatizable
- **WHEN** el asistente puede ejecutar una etapa autorizada y verificarla por herramientas disponibles
- **THEN** realiza la etapa, explica qué hizo y deja los pasos equivalentes para aprendizaje sin exigir repetirla manualmente

### Requirement: NWP-08 Implementación por segmentos seleccionados automáticamente

Ante una petición de implementar o continuar sin números de tarea, el asistente SHALL seleccionar por cuenta propia un segmento pequeño y coherente de tareas pendientes cuyas dependencias estén satisfechas, con un resultado observable y una comprobación concreta. SHALL anunciar brevemente el objetivo y las tareas elegidas y comenzar sin pedir al usuario que elija o confirme ese segmento. La petición SHALL abarcar su implementación, comprobaciones necesarias, corrección de fallos dentro del segmento y documentación correspondiente, sin implicar ejecución de toda la lista pendiente.

Al concluir el segmento, el asistente SHALL marcar solo las tareas realmente terminadas y verificadas, registrar alcance, evidencia y pendientes y explicar el resultado y la próxima unidad recomendada. SHALL terminar esa petición después de cerrar la unidad; una nueva petición de continuar iniciará la siguiente. Si existe un segmento incompleto por fallo o intervención necesaria, SHALL priorizar su recuperación antes de abrir otro que dependa de él. Una solicitud explícita de otro alcance SHALL prevalecer sobre esta selección predeterminada.

#### Scenario: Implementación sin indicar tareas
- **WHEN** el usuario dice «implementa» sin especificar números
- **THEN** el asistente elige y anuncia una unidad pendiente verificable, la implementa y comprueba y termina con un resumen, sin preguntar cuáles tareas realizar ni recorrer toda la lista

#### Scenario: Continuación después de un segmento correcto
- **WHEN** el usuario vuelve a pedir continuar tras completar una unidad
- **THEN** el asistente consulta el estado real, elige la siguiente unidad cuyas dependencias estén satisfechas y conserva los avances ya verificados

#### Scenario: Comprobación fallida o intervención pendiente
- **WHEN** una comprobación falla o se necesita una acción del usuario para terminar el segmento
- **THEN** las tareas afectadas siguen pendientes, se corrige lo posible o se explica la intervención según NWP-07 y no se presenta el segmento como completado ni se inicia una unidad dependiente
