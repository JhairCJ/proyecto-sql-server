# Extracción de empleados y productos

## 1. Qué hace esta etapa

Un extractor es un procedimiento que entrega filas del origen con las columnas que recibirá staging, la zona intermedia del DW. Todavía no carga las dimensiones ni ejecuta paquetes SSIS. Aquí se corrigieron y probaron empleados y productos en `Northwind_Test`.

Cada empleado puede tener un supervisor: `ReportsTo` referencia otro empleado. Por eso el procedimiento consulta Employees dos veces, una para el empleado y otra para su supervisor. Usa LEFT JOIN: conserva al empleado aunque no tenga supervisor. No consulta territorios, porque un empleado con varios territorios produciría filas repetidas y uno sin territorios podría desaparecer.

Cada producto puede relacionarse con una categoría y un proveedor. Sus LEFT JOIN conservan el producto cuando falta alguna relación; los datos de esa relación salen NULL. NULL significa ausencia de valor, no cero ni una cadena vacía.

## 2. Cómo se detectan cambios relacionados

`rowversion` es una marca binaria de ocho bytes que cambia al escribir una fila; no es una fecha. El intervalo es **inicio excluido y fin incluido**. Los parámetros son BIGINT, con conversión comprobada a la marca binaria.

Un empleado se selecciona si cambia él o su supervisor. Si Andrew Fuller cambia de nombre, también necesitamos actualizar el nombre del supervisor de sus subordinados, aunque estos no hayan cambiado. SourceRowVersion sigue siendo la marca propia de cada empleado.

Un producto se selecciona si cambia él, su categoría o su proveedor. Para evitar combinar datos posteriores al corte, todas las relaciones presentes deben tener marcas menores o iguales al fin. Ejemplo: producto con marca 104, categoría con marca 106 y corte 105. Se difiere el producto; el siguiente intervalo que incluya 106 lo recupera por el cambio de categoría. Lo mismo sucede con supervisores y proveedores.

Las lecturas usan READ COMMITTED. Este mecanismo no conserva versiones históricas ni constituye una instantánea global de todas las tablas. Las eliminaciones físicas requieren otro mecanismo y quedan fuera de este contrato.

## 3. Qué columnas entrega cada procedimiento

El orden coincide con las tablas intermedias existentes del DW. Las pruebas insertan el resultado en tablas temporales tipadas para comprobar el contrato.

| Procedimiento | Columnas, en orden |
| --- | --- |
| GetEmployeeChangesByRowVersion | EmployeeID, FirstName, LastName, Title, City, Region, Country, ReportsTo, SourceRowVersion, SupervisorName |
| GetProductChangesByRowVersion | ProductID, ProductName, QuantityPerUnit, CategoryID, CategoryName, SupplierID, SupplierName, SupplierCountry, Discontinued, ProductRowVersion, CategoryRowVersion, SupplierRowVersion |

Los identificadores son INT; los textos conservan los tamaños del contrato de staging; Discontinued es BIT y las marcas son BINARY(8). SupervisorName admite 60 caracteres. Los precios históricos de ventas se obtendrán de las líneas de pedido en la etapa de ventas; este extractor entrega los atributos del producto definidos en std.Producto.

## 4. Preparar los procedimientos en la copia

**Objetivo:** reproducir la publicación ya ejecutada. **Programa y requisitos:** PowerShell, SQL Server en localhost, autenticación Windows y las [bases de prueba preparadas](03-pruebas-aisladas.md). La cuenta de publicación necesita permiso para alterar procedimientos.

1. Abre PowerShell y entra en tu carpeta del repositorio. La ruta siguiente es un ejemplo: reemplázala por la tuya.

```powershell
Set-Location -LiteralPath 'C:\Proyectos\proyecto-sql-server'
& '.\tests\Deploy-TestExtractors.ps1'
```

2. Comprueba ocho mensajes `Publicado en Northwind_Test: dbo...`: dos conversiones, el corte y los extractores de clientes, empleados, productos, transportistas y ventas.
3. En SSMS, actualiza Northwind_Test > Programmability / Programación > Stored Procedures / Procedimientos almacenados para verlos.

**Resultado:** solo se actualizan esos ocho procedimientos en la copia marcada. Repetirlo no recrea las bases. Si falta la copia o su marca, sigue la preparación de pruebas; si falta permiso, revisa la cuenta Windows. El usuario restringido NorthwindFixture se utiliza para datos de prueba, no para publicar procedimientos.

## 5. Consultar empleados y productos en SSMS

**Objetivo:** reconocer las filas extraídas. **Programa:** SSMS, conexión al motor localhost con autenticación Windows. Esta consulta solo lee datos.

1. Abre New Query / Nueva consulta.
2. Ejecuta el siguiente bloque completo. USE selecciona explícitamente la copia.

```sql
USE Northwind_Test;
DECLARE @cut TABLE (DBTS bigint);
INSERT INTO @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @end bigint = (SELECT DBTS FROM @cut);
EXEC dbo.GetEmployeeChangesByRowVersion @startRow = 0, @endRow = @end;
EXEC dbo.GetProductChangesByRowVersion @startRow = 0, @endRow = @end;
```

3. Revisa los dos resultados: **9 empleados y 77 productos** en la referencia actual, una fila por identificador. Andrew Fuller no tiene supervisor; Chai pertenece a Beverages y su proveedor es Exotic Liquids, de UK.

**Recuperación:** si no existe un procedimiento, repite la publicación de la ficha 4. Si hay otros conteos, comprueba instancia y base, y registra las diferencias antes de cambiar datos. El error 51104 indica un intervalo NULL, negativo o invertido. No reinicies marcas para evitarlo.

## 6. Repetir las pruebas automáticamente

**Objetivo:** comprobar relaciones opcionales, dependencias, límites y ausencia de duplicados. **Programa:** PowerShell en la raíz del repositorio, con las copias y procedimientos preparados.

1. Importa el módulo y ejecuta ambos archivos mediante su conexión restringida:

```powershell
Import-Module '.\tests\Northwind.TestTools.psm1' -Force
foreach ($name in @('Employee', 'Product')) {
    $sql = Get-Content -LiteralPath ".\tests\Test-${name}Extraction.sql" -Raw
    $result = Invoke-NorthwindTestSql -Database Northwind_Test -Sql $sql
    foreach ($table in $result.Tables) { $table | Format-Table -AutoSize }
}
```

2. Comprueba todos los resultados Passed: cinco grupos para empleados y siete para productos. Si aparece una excepción 513xx o 514xx, el escenario falló: conserva el mensaje para revisarlo.
3. Los cambios de datos se revierten automáticamente al terminar. Las marcas de la copia avanzan incluso con rollback; es normal que ya no coincidan con las del original.

Se probaron empleados sin territorios y con varios, sin supervisor y con supervisor renombrado; productos sin relaciones, con categoría/proveedor renombrados y con cambios posteriores al corte. Las tablas temporales de estas pruebas existen únicamente durante su conexión. Las bases Northwind_Test y Northwind_DW_Test son permanentes.

## 7. Revisar el proyecto en Visual Studio

**Objetivo:** comprobar que los archivos SQL compilan. **Programa:** Visual Studio 2026 con SSDT, solución Northwind.slnx.

1. Abre la solución desde tu carpeta del repositorio.
2. En Solution Explorer / Explorador de soluciones, abre Northwind.OLTP > dbo > Stored Procedures y los dos archivos GetEmployeeChangesByRowVersion.sql y GetProductChangesByRowVersion.sql.
3. Haz clic derecho en Northwind.OLTP > Build / Compilar y revisa Output / Salida y Error List / Lista de errores.

**Resultado comprobado:** compilación sin errores; persisten las 19 advertencias SQL71502 heredadas de referencias a Order Details. La [guía inicial](01-guia-practica.md) explica la configuración SSDT y cómo resolver un proyecto incompatible. La publicación de esta etapa se hace con la ficha 4, sobre la copia.

La organización conserva la separación OLTP, staging, DW y ETL de la referencia BikeStores. El [registro de validación](validacion.md) resume lo ejecutado. Estas son pruebas específicas de extractores; no pueblan el DW. Vuelve al [recorrido principal](01-guia-practica.md) para ejecutar lo disponible del proyecto.
