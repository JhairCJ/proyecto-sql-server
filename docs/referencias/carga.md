# Aplicación, staging y recuperación

La ruta principal ejecuta `CargarNorthwind.dtsx` desde Visual Studio o SSISDB sobre `NorthWind` → `Northwind_DW`. Sigue la secuencia de BikeStores: extracción, staging, dimensiones, hechos y control. `scripts/Load-NorthwindWarehouse.ps1` y las copias `_Test` sirven para pruebas automatizadas aisladas.

Las tablas std son permanentes en SQL Server, pero sus filas son preparación reconstruible. No son tablas temporales #. Cada intento reemplaza únicamente el staging de su entidad; dimensiones, hechos y controles permanecen. Staging puede quedar parcial si falla el transporte y se reconstruye al reintentar.

## Contrato por entidad

1. Abrir conexiones al origen configurado y al DW, y retener un bloqueo exclusivo de sesión, recurso Northwind.Warehouse.Load, en el DW. Un intento competidor falla sin modificar staging.
2. Fijar el corte confirmado con GetDatabaseRowVersion. Leer el control con GetLastPackageRowVersion; no inventa procesos ni interpreta controles ausentes como cero. Rechaza valores BINARY(8) no representables y destino comercial vacío con avance.
3. Extraer el intervalo (marca anterior, corte] y poblar std. Los cambios de dependencias pueden incluir una marca propia antigua. Por ello, la aplicación verifica que las marcas disponibles estén presentes y no superen el corte, sin exigir que todas sean mayores al inicio.
4. Llamar DW_ApplyPackage @PackageName, @StartRow, @EndRow, con marcas BIGINT. Acepta Cliente/Empleado/Producto/Transportista/Ventas y compara el inicio con el control actual. Un inicio incompatible, corte inferior o marca modificada aborta la carga.
5. En una sola transacción local del DW: aplicar la entidad y ejecutar UpdateLastPackageRowVersion con marca esperada. Solo al confirmar quedan visibles datos, nueva marca y LastSuccessfulLoad. Ante error se revierte la transacción. Los procedimientos internos de aplicación también son transaccionales y usan el mismo bloqueo.
6. Cerrar la conexión libera el bloqueo incluso ante error. El principal detiene las entidades dependientes; las entidades confirmadas antes del fallo conservan su éxito.

No se usa una transacción distribuida con el origen ni se promete una fotografía histórica conjunta bajo escrituras concurrentes. No hay propagación de borrados físicos. Detectar un corte inferior al control evita seguir tras ciertos reinicios/restauraciones del origen; no identifica toda sustitución de origen con marcas numéricamente compatibles.

## Aplicación

DW_MergeDimCliente/Empleado/Producto/Transportista reutilizan la identidad comercial para actualizar atributos tipo 1 e insertar solo identidades nuevas, conservando SK. Las claves reservadas de cliente/empleado no pueden entrar como entidades comerciales.

DW_MergeFactVentas valida cantidad/precio/descuento, resuelve dimensiones y las tres fechas mediante LEFT JOIN y falla con OrderID/ProductID y referencia cuando una identidad no nula falta. Los nulos legítimos de cliente/empleado/fecha de pedido se relacionan con SK 0; transportista/requerida/envío permanecen NULL. Una fecha real 1900-01-01 se rechaza porque está reservada. El calendario abarca el rango combinado existente y las nuevas fechas para no dejar huecos al extenderlo.

Cada línea se aplica por OrderID/ProductID y conserva Venta_SK. Actualizaciones de cabecera cambian sus referencias/fechas; cambios de detalle recalculan las medidas con DW_CalculateAmounts. Ventas normaliza REAL a DECIMAL(9,6) en SQL antes de BulkCopy y utiliza el precio vendido de OrderDetails, nunca el catálogo.

UpdateLastPackageRowVersion es una operación interna: exige transacción, proceso registrado, valor representable, avance no descendente y control esperado. No crea controles nuevos ni se utiliza directamente para adelantar una carga.

## Verificación y recuperación

tests/Test-Application.sql contiene las pruebas SQL de altas, cambios, repetición, claves y nulos; Test-Application.ps1 las ejecuta con staging de referencia y rollback, e inyecta fallos de aplicación/control y estados incompatibles. Test-Load.ps1 verifica el cargador real, competencia, fallo y reintento incremental. La inyección de fallo usa un trigger solo en DW de prueba marcado, retirado en finally. Las modificaciones comerciales de origen de Test-Load se restauran y se cargan de nuevo; rowversion avanza solamente en la copia.

Comandos técnicos desde la raíz del repo:

```powershell
& '.\tests\Test-Application.ps1'
& '.\tests\Test-Load.ps1'
& '.\scripts\Compare-NorthwindWarehouse.ps1'
```

Si falla una entidad, corregir el diagnóstico y repetir el cargador completo. No truncar finales ni reiniciar marcas. Destino vacío con avance requiere investigar cómo se vació y planificar una reconstrucción explícita; la sincronización incremental no puede reconstruir filas antiguas omitidas por la marca.

[Guía operativa](../06-cargar-datos.md). [Evidencias](../validacion.md).
