DECLARE @packages TABLE(Name nvarchar(100));
INSERT @packages VALUES(N'Cliente'),(N'Empleado'),(N'Producto'),(N'Transportista'),(N'Ventas');
DECLARE @name nvarchar(100),@mark binary(8),@start bigint;
DECLARE p CURSOR LOCAL FAST_FORWARD FOR SELECT Name FROM @packages;
OPEN p; FETCH NEXT FROM p INTO @name;
WHILE @@FETCH_STATUS=0
BEGIN
 EXEC dbo.GetLastPackageRowVersion @name,@mark OUTPUT;
 SET @start=CONVERT(bigint,@mark);
 EXEC dbo.DW_ApplyPackage @name,@start,@cut;
 FETCH NEXT FROM p INTO @name;
END;
CLOSE p; DEALLOCATE p;
IF (SELECT COUNT(*) FROM dbo.Fact_Ventas)<>2155
 OR (SELECT COUNT(DISTINCT OrderID) FROM dbo.Fact_Ventas)<>830
 OR (SELECT SUM(Cantidad) FROM dbo.Fact_Ventas)<>51317
 OR (SELECT COUNT(*) FROM dbo.Fact_Ventas WHERE OrderID=10248)<>3
 OR (SELECT SUM(ImporteNeto) FROM dbo.Fact_Ventas WHERE OrderID=10248)<>440
 THROW 52501,'Carga inicial o pedido 10248 incorrectos.',1;
IF EXISTS(SELECT 1 FROM dbo.PackageConfig WHERE LastRowVersion<>CONVERT(binary(8),@cut) OR LastSuccessfulLoad IS NULL)
 THROW 52502,'Control no confirmado junto con cada entidad.',1;
DECLARE @keys TABLE(Entity nvarchar(30),Id nvarchar(30),SK bigint);
INSERT @keys SELECT N'Cliente' AS Entity,CONVERT(nvarchar(30),CustomerID) AS Id,CONVERT(bigint,Cliente_SK) AS SK FROM dbo.Dim_Cliente WHERE Cliente_SK<>0
 UNION ALL SELECT N'Empleado',CONVERT(nvarchar(30),EmployeeID),Empleado_SK FROM dbo.Dim_Empleado WHERE Empleado_SK<>0
 UNION ALL SELECT N'Producto',CONVERT(nvarchar(30),ProductID),Producto_SK FROM dbo.Dim_Producto
 UNION ALL SELECT N'Transportista',CONVERT(nvarchar(30),ShipperID),Transportista_SK FROM dbo.Dim_Transportista
 UNION ALL SELECT N'Ventas',CONCAT(OrderID,N'/',ProductID),Venta_SK FROM dbo.Fact_Ventas;
UPDATE std.Cliente SET City=N'Ciudad prueba' WHERE CustomerID=N'VINET';
UPDATE std.Empleado SET SupervisorName=N'Supervisor prueba' WHERE EmployeeID=1;
UPDATE std.Producto SET CategoryName=N'Categoria test' WHERE ProductID=11;
UPDATE std.Transportista SET Phone=N'555-TEST' WHERE ShipperID=1;
INSERT std.Cliente(CustomerID,CompanyName,SourceRowVersion) VALUES(N'TEST4',N'Cliente prueba',CONVERT(binary(8),@cut));
INSERT std.Empleado(EmployeeID,FirstName,LastName,SourceRowVersion) VALUES(-901,N'Empleado',N'Prueba',CONVERT(binary(8),@cut));
INSERT std.Producto(ProductID,ProductName,ProductRowVersion) VALUES(-901,N'Producto prueba',CONVERT(binary(8),@cut));
INSERT std.Transportista(ShipperID,CompanyName,SourceRowVersion) VALUES(-901,N'Transportista prueba',CONVERT(binary(8),@cut));
EXEC dbo.DW_ApplyPackage N'Cliente',@cut,@cut;
EXEC dbo.DW_ApplyPackage N'Empleado',@cut,@cut;
EXEC dbo.DW_ApplyPackage N'Producto',@cut,@cut;
EXEC dbo.DW_ApplyPackage N'Transportista',@cut,@cut;
EXEC dbo.DW_ApplyPackage N'Cliente',@cut,@cut;
EXEC dbo.DW_ApplyPackage N'Empleado',@cut,@cut;
EXEC dbo.DW_ApplyPackage N'Producto',@cut,@cut;
EXEC dbo.DW_ApplyPackage N'Transportista',@cut,@cut;
IF (SELECT COUNT(*) FROM dbo.Dim_Cliente WHERE Cliente_SK<>0)<>92
 OR (SELECT COUNT(*) FROM dbo.Dim_Empleado WHERE Empleado_SK<>0)<>10
 OR (SELECT COUNT(*) FROM dbo.Dim_Producto)<>78
 OR (SELECT COUNT(*) FROM dbo.Dim_Transportista)<>4
 OR (SELECT Ciudad FROM dbo.Dim_Cliente WHERE CustomerID=N'VINET')<>N'Ciudad prueba'
 OR (SELECT NombreSupervisor FROM dbo.Dim_Empleado WHERE EmployeeID=1)<>N'Supervisor prueba'
 OR (SELECT Categoria FROM dbo.Dim_Producto WHERE ProductID=11)<>N'Categoria test'
 OR (SELECT Telefono FROM dbo.Dim_Transportista WHERE ShipperID=1)<>N'555-TEST'
 THROW 52503,'Altas, atributos o repeticion de dimensiones incorrectos.',1;
UPDATE std.Ventas SET Quantity=Quantity+1 WHERE OrderID=10248 AND ProductID=11;
UPDATE std.Ventas SET CustomerID=N'ANATR',EmployeeID=2,ShipperID=2,
 OrderDate='20000101',RequiredDate='20000201',ShippedDate='20000301' WHERE OrderID=10248;
EXEC dbo.DW_ApplyPackage N'Ventas',@cut,@cut;
EXEC dbo.DW_ApplyPackage N'Ventas',@cut,@cut;
IF (SELECT COUNT(*) FROM dbo.Fact_Ventas)<>2155
 OR (SELECT SUM(Cantidad) FROM dbo.Fact_Ventas WHERE OrderID=10248)<>28
 OR (SELECT SUM(ImporteNeto) FROM dbo.Fact_Ventas WHERE OrderID=10248)<>454
 OR EXISTS(SELECT 1 FROM dbo.Fact_Ventas f
  JOIN dbo.Dim_Cliente c ON c.Cliente_SK=f.Cliente_SK
  JOIN dbo.Dim_Empleado e ON e.Empleado_SK=f.Empleado_SK
  JOIN dbo.Dim_Transportista t ON t.Transportista_SK=f.Transportista_SK
  WHERE f.OrderID=10248 AND (c.CustomerID<>N'ANATR' OR e.EmployeeID<>2 OR t.ShipperID<>2
   OR f.FechaPedido_SK<>20000101 OR f.FechaRequerida_SK<>20000201 OR f.FechaEnvio_SK<>20000301))
 OR (SELECT COUNT(*) FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0)<>
  (SELECT DATEDIFF(day,MIN(Fecha),MAX(Fecha))+1 FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0)
 THROW 52504,'Actualizacion de cantidad/cabecera/calendario incorrecta.',1;
UPDATE std.Ventas SET CustomerID=NULL,EmployeeID=NULL,ShipperID=NULL,
 OrderDate=NULL,RequiredDate=NULL,ShippedDate=NULL WHERE OrderID=10248;
EXEC dbo.DW_ApplyPackage N'Ventas',@cut,@cut;
IF EXISTS(SELECT 1 FROM dbo.Fact_Ventas WHERE OrderID=10248 AND
 (Cliente_SK<>0 OR Empleado_SK<>0 OR FechaPedido_SK<>0 OR Transportista_SK IS NOT NULL
  OR FechaRequerida_SK IS NOT NULL OR FechaEnvio_SK IS NOT NULL))
 THROW 52505,'Referencias nulas legitimas no conservadas.',1;
IF EXISTS(SELECT 1 FROM @keys k WHERE NOT EXISTS(
 SELECT 1 FROM (
 SELECT N'Cliente' AS Entity,CONVERT(nvarchar(30),CustomerID) AS Id,CONVERT(bigint,Cliente_SK) AS SK FROM dbo.Dim_Cliente WHERE Cliente_SK<>0
 UNION ALL SELECT N'Empleado',CONVERT(nvarchar(30),EmployeeID),Empleado_SK FROM dbo.Dim_Empleado WHERE Empleado_SK<>0
 UNION ALL SELECT N'Producto',CONVERT(nvarchar(30),ProductID),Producto_SK FROM dbo.Dim_Producto
 UNION ALL SELECT N'Transportista',CONVERT(nvarchar(30),ShipperID),Transportista_SK FROM dbo.Dim_Transportista
 UNION ALL SELECT N'Ventas',CONCAT(OrderID,N'/',ProductID),Venta_SK FROM dbo.Fact_Ventas
 ) actual WHERE actual.Entity=k.Entity AND actual.Id=k.Id AND actual.SK=k.SK))
 THROW 52506,'Claves sustitutas cambiaron.',1;
