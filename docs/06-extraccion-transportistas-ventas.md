# Transportistas y ventas: una fila por línea de pedido

## 1. Qué se completó y qué sigue pendiente

Se crearon GetShipperChangesByRowVersion y GetSalesChangesByRowVersion y se probaron en Northwind_Test. Un procedimiento almacenado es una consulta guardada en la base que puedes ejecutar pasando parámetros. Estos procedimientos extraen datos; todavía no los cargan en staging ni en las dimensiones o hechos del DW.

El recorrido mantiene la lógica de BikeStores: origen operativo → staging → dimensiones y hechos → modelo analítico. En esta etapa seguimos trabajando en el origen. Este documento verifica los extractores; no carga el DW. El recorrido para ejecutar el proyecto está en [01](01-guia-practica.md).

## 2. Pedido, línea y transportista

Orders guarda la cabecera: quién compra, empleado, transportista y fechas. OrderDetails guarda los productos comprados: precio vendido, cantidad y descuento. OrderID identifica el pedido; la pareja OrderID/ProductID identifica una línea dentro de él. La clave de OrderDetails impide repetir esa pareja.

El pedido **10248 es un pedido con tres líneas**, correspondientes a los productos **11, 42 y 72**. Suma **27 unidades** y un importe bruto de **440,00**. Contar líneas como pedidos daría un resultado incorrecto.

Shippers guarda las empresas de transporte. Orders.ShipVia referencia Shippers.ShipperID; en el resultado se llama ShipperID para coincidir con staging. El extractor de ventas no necesita unir Shippers, Customers, Employees ni Products: toma sus identificadores del pedido y del detalle. Eso conserva líneas con cliente, empleado o transportista ausentes y evita multiplicaciones.

NULL significa que falta un valor. La extracción conserva esas ausencias. Más adelante el DW asignará miembros desconocidos a cliente, empleado y fecha de pedido, y conservará como ausentes transportista y fechas requerida/envío, según su contrato.

## 3. Precio vendido y selección de cambios

El precio vendido es **OrderDetails.UnitPrice**. Products.UnitPrice es el precio de catálogo actual: modificarlo no cambia el precio histórico de una línea. Freight pertenece a la cabecera y no se repite en cada venta.

Los parámetros @startRow y @endRow son BIGINT. El inicio se excluye y el fin se incluye. Cada fila tiene una marca rowversion, que es binaria y no una fecha. Las conversiones se comprueban y los procedimientos leen con READ COMMITTED.

- En transportistas, se seleccionan altas o cambios cuya marca esté dentro del intervalo.
- En ventas, cambiar una cabecera vuelve a seleccionar sus líneas; cambiar un detalle selecciona esa línea.
- Ambas marcas de la venta deben ser menores o iguales al fin. Si una cabecera o detalle cambia después del corte, la línea afectada se difiere y esa modificación la selecciona en el siguiente intervalo.

No se recuperan versiones históricas ni se promete una instantánea conjunta bajo escrituras continuas. Los borrados físicos requieren otro mecanismo fuera de este alcance.

## 4. Columnas y tipos

| Extractor | Columnas en el orden de staging |
| --- | --- |
| GetShipperChangesByRowVersion | ShipperID, CompanyName, Phone, SourceRowVersion |
| GetSalesChangesByRowVersion | OrderID, ProductID, CustomerID, EmployeeID, ShipperID, OrderDate, RequiredDate, ShippedDate, UnitPrice, Quantity, Discount, OrderRowVersion, OrderDetailRowVersion |

Transportistas usa INT, NVARCHAR(40), NVARCHAR(24) y BINARY(8). Ventas usa identificadores INT, CustomerID NCHAR(5), fechas DATETIME, precio MONEY, cantidad SMALLINT, descuento REAL y marcas BINARY(8). Estos son los tipos actuales de std.Ventas y del origen. La normalización decimal y el cálculo determinista de bruto/descuento/neto se implementarán en el DW; esta etapa conserva los valores vendidos del origen.

## 5. Preparar la copia desde PowerShell

**Objetivo:** publicar los extractores implementados. **Requisitos / programa:** PowerShell, SQL Server localhost, autenticación Windows con permiso de alterar procedimientos y [bases de prueba preparadas](03-pruebas-aisladas.md).

1. Abre PowerShell y entra en tu carpeta del repositorio. La siguiente ruta es un ejemplo; reemplázala por la real.

```powershell
Set-Location -LiteralPath 'C:\Proyectos\proyecto-sql-server'
& '.\tests\Deploy-TestExtractors.ps1'
```

2. Comprueba **ocho mensajes** de publicación: las dos conversiones, el corte y cinco extractores (clientes, empleados, productos, transportistas y ventas).
3. En SSMS, actualiza Northwind_Test > Programmability / Programación > Stored Procedures / Procedimientos almacenados. Deben aparecer los dos nuevos.

**Resultado:** se crean o actualizan ocho procedimientos únicamente en la copia marcada; no se recrean bases ni se publica el dacpac completo. Si falta la copia o su marca, sigue la preparación de pruebas. Si falta permiso, revisa la cuenta Windows de publicación; NorthwindFixture sirve para fixtures, no para desplegar.

## 6. Consultar la extracción en SSMS

**Objetivo:** comprobar conteos y reconocer las columnas. **Programa / requisitos:** SSMS, conexión al motor localhost con autenticación Windows y procedimientos publicados en Northwind_Test.

1. Selecciona New Query / Nueva consulta.
2. Ejecuta este bloque completo; USE selecciona explícitamente la copia.

```sql
USE Northwind_Test;
DECLARE @cut TABLE(DBTS bigint);
INSERT INTO @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @end bigint = (SELECT DBTS FROM @cut);
EXEC dbo.GetShipperChangesByRowVersion @startRow=0, @endRow=@end;
EXEC dbo.GetSalesChangesByRowVersion @startRow=0, @endRow=@end;
```

3. Revisa los resultados: **3 transportistas y 2.155 líneas** en la referencia actual. En ventas, localiza las tres filas del pedido 10248: se repite el pedido porque cada fila corresponde a un producto.
4. Para consultar ese pedido y comprobar sus totales sin escribir datos, ejecuta:

```sql
USE Northwind_Test;
SELECT o.OrderID, d.ProductID, o.CustomerID, o.EmployeeID,
       o.ShipVia AS ShipperID, o.OrderDate, o.RequiredDate, o.ShippedDate,
       d.UnitPrice, d.Quantity, d.Discount
FROM dbo.Orders AS o
JOIN dbo.OrderDetails AS d ON d.OrderID=o.OrderID
WHERE o.OrderID=10248
ORDER BY d.ProductID;
SELECT COUNT(*) AS Lineas, COUNT(DISTINCT OrderID) AS Pedidos,
       SUM(CONVERT(bigint,Quantity)) AS Unidades,
       SUM(CONVERT(decimal(19,4),UnitPrice)*Quantity) AS Bruto
FROM dbo.OrderDetails WHERE OrderID=10248;
```

**Resultado esperado:** productos 11/42/72; 3 líneas, 1 pedido, 27 unidades y bruto 440,00. El extractor ya fue comparado contra una consulta independiente de todas las líneas y columnas.

**Errores / recuperación:** si falta un procedimiento, repite la ficha 5. Si cambian conteos, comprueba servidor/base y registra las diferencias antes de editar datos. El error 51104 identifica un intervalo NULL, negativo o invertido: corrige sus parámetros, no las marcas guardadas.

## 7. Ejecutar las pruebas con rollback

**Objetivo:** comprobar altas, actualizaciones, dependencias, nulos y cortes. **Programa:** PowerShell en la raíz del repositorio con las copias preparadas.

1. Ejecuta los dos fixtures mediante el módulo restringido:

```powershell
Import-Module '.\tests\Northwind.TestTools.psm1' -Force
foreach ($name in @('Shipper','Sales')) {
    $sql = Get-Content -LiteralPath ".\tests\Test-${name}Extraction.sql" -Raw
    $result = Invoke-NorthwindTestSql -Database Northwind_Test -Sql $sql
    foreach ($table in $result.Tables) { $table | Format-Table -AutoSize }
}
```

2. Comprueba todos los resultados Passed: cuatro grupos de transportistas y ocho de ventas. Las excepciones 515xx/516xx son fallos de escenario; conserva el mensaje para revisarlo.
3. El ejecutor revierte automáticamente los cambios. Las marcas y el contador IDENTITY de Shippers avanzan incluso con rollback: una repetición puede usar otro identificador de prueba, sin dejar una fila persistente. No se reinician estos contadores.

Las tablas temporales usan COLLATE DATABASE_DEFAULT para comparar textos con Northwind aunque tempdb tenga otra intercalación. Se probaron cambios de cabecera y detalle a ambos lados del corte, precio de catálogo, relaciones/fechas NULL y límites inválidos. Los cortes de estos fixtures simulan escrituras sucesivas dentro de una transacción; no representan una nueva prueba de múltiples sesiones.

## 8. Compilar en Visual Studio

**Objetivo:** comprobar que los nuevos archivos forman parte del proyecto. **Requisitos / programa:** Visual Studio 2026 con SSDT, solución Northwind.slnx; consulta [entorno](02-entorno.md) si falta un componente.

1. Abre Northwind.slnx desde tu carpeta del repositorio.
2. En Solution Explorer / Explorador de soluciones, busca Northwind.OLTP > dbo > Stored Procedures y abre GetShipperChangesByRowVersion.sql y GetSalesChangesByRowVersion.sql.
3. Haz clic derecho en Northwind.OLTP > Build / Compilar.
4. Revisa Output / Salida y Error List / Lista de errores.

**Resultado ejecutado:** compilación sin errores, con las 19 advertencias SQL71502 heredadas de Order Details. Los dos archivos están incluidos como Build en el proyecto SQL. La publicación de esta etapa se reproduce con la ficha 5 sobre la copia.

El [registro de validación](validacion.md) contiene resultados y evidencias. Para ejecutar lo disponible del proyecto, vuelve a [01](01-guia-practica.md).
