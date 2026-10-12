# 03. Publicar los extractores en NorthWind

## 1. Publicar desde Visual Studio

1. Abre `Northwind.sln` y recompílala.
2. En el Explorador de soluciones, clic derecho en `Northwind.OLTP` > **Publicar**.
3. En la ventana, selecciona **Cargar perfil** y abre `Northwind.OLTP/Properties/PublishProfiles/NorthWind.publish.xml`.
4. Comprueba servidor `localhost` y destino `NorthWind`.
5. Pulsa **Generar script**. Confirma que el destino sea `NorthWind`; después pulsa **Publicar**.

El perfil conserva datos y objetos ajenos: bloquea cambios con posible pérdida de datos y no elimina objetos que no estén en el proyecto.

## 2. Comprobar en SSMS

Conecta al motor `localhost`, abre **Nueva consulta** y ejecuta con **F5**:

```sql
USE NorthWind;
SELECT name FROM sys.procedures
WHERE name IN (N'GetDatabaseRowVersion',N'GetCustomerChangesByRowVersion',
 N'GetEmployeeChangesByRowVersion',N'GetProductChangesByRowVersion',
 N'GetShipperChangesByRowVersion',N'GetSalesChangesByRowVersion',
 N'RowVersionToBigInt',N'BigIntToRowVersion')
ORDER BY name;
SELECT COUNT(*) AS Pedidos FROM dbo.Orders;
SELECT COUNT(*) AS Lineas FROM dbo.OrderDetails;
```

**Resultado:** ocho procedimientos; 830 pedidos y 2.155 líneas. La publicación agrega o actualiza procedimientos; no cambia esas filas comerciales.
