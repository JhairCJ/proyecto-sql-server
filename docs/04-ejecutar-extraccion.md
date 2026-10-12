# 04. Ejecutar los extractores

**Requisitos:** extractores publicados siguiendo [03](03-preparar-origen.md).

En SSMS, conectado al motor localhost con autenticación Windows, abre **Nueva consulta**, pega y pulsa **F5**:

```sql
USE NorthWind;
DECLARE @cut TABLE(DBTS bigint);
INSERT @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @fin bigint=(SELECT DBTS FROM @cut);
EXEC dbo.GetCustomerChangesByRowVersion 0,@fin;
EXEC dbo.GetEmployeeChangesByRowVersion 0,@fin;
EXEC dbo.GetProductChangesByRowVersion 0,@fin;
EXEC dbo.GetShipperChangesByRowVersion 0,@fin;
EXEC dbo.GetSalesChangesByRowVersion 0,@fin;
```

**Resultado de referencia:** 91 clientes, 9 empleados, 77 productos, 3 transportistas y 2.155 líneas de venta. Si falta un procedimiento, repite la publicación de 03. Esta ejecución lee el origen; no carga el DW.
