CREATE PROCEDURE dbo.DW_MergeFactVentas
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @lock int;
  EXEC @lock=sys.sp_getapplock @Resource=N'Northwind.Warehouse.Load',
   @LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=0;
  IF @lock<0 THROW 52402,'DW ocupado por otra carga.',1;
  DECLARE @message nvarchar(2048);
  SELECT TOP(1) @message=CONCAT(N'Ventas: OrderID=',OrderID,N', ProductID=',ProductID,
   N'; cantidad, precio, descuento o fecha reservada invalidos.')
  FROM std.Ventas WHERE Quantity<=0 OR UnitPrice<0 OR Discount<0 OR Discount>1
   OR CONVERT(date,OrderDate)='19000101' OR CONVERT(date,RequiredDate)='19000101'
   OR CONVERT(date,ShippedDate)='19000101' ORDER BY OrderID,ProductID;
  IF @message IS NOT NULL THROW 52406,@message,1;
  DECLARE @min date,@max date;
  SELECT @min=MIN(Fecha),@max=MAX(Fecha) FROM
  (
   SELECT Fecha FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0
   UNION ALL SELECT f.Fecha FROM std.Ventas
    CROSS APPLY(VALUES(CONVERT(date,OrderDate)),(CONVERT(date,RequiredDate)),(CONVERT(date,ShippedDate))) f(Fecha)
  ) dates;
  IF EXISTS(SELECT 1 FROM std.Ventas WHERE OrderDate IS NOT NULL OR RequiredDate IS NOT NULL OR ShippedDate IS NOT NULL)
   EXEC dbo.DW_LoadDimTiempo @min,@max;
  SELECT x.OrderID,x.ProductID,x.Quantity,x.UnitPrice,x.Discount,
   c.Cliente_SK,e.Empleado_SK,p.Producto_SK,s.Transportista_SK,
   t.Tiempo_SK AS FechaPedido_SK,r.Tiempo_SK AS FechaRequerida_SK,v.Tiempo_SK AS FechaEnvio_SK,
   CASE WHEN c.Cliente_SK IS NULL THEN N'Cliente'
    WHEN e.Empleado_SK IS NULL THEN N'Empleado'
    WHEN p.Producto_SK IS NULL THEN N'Producto'
    WHEN x.ShipperID IS NOT NULL AND s.Transportista_SK IS NULL THEN N'Transportista'
    WHEN t.Tiempo_SK IS NULL THEN N'FechaPedido'
    WHEN x.RequiredDate IS NOT NULL AND r.Tiempo_SK IS NULL THEN N'FechaRequerida'
    WHEN x.ShippedDate IS NOT NULL AND v.Tiempo_SK IS NULL THEN N'FechaEnvio' END AS MissingReference
  INTO #Resolved
  FROM std.Ventas x
  LEFT JOIN dbo.Dim_Cliente c ON (x.CustomerID IS NULL AND c.Cliente_SK=0) OR c.CustomerID=x.CustomerID
  LEFT JOIN dbo.Dim_Empleado e ON (x.EmployeeID IS NULL AND e.Empleado_SK=0) OR e.EmployeeID=x.EmployeeID
  LEFT JOIN dbo.Dim_Producto p ON p.ProductID=x.ProductID
  LEFT JOIN dbo.Dim_Transportista s ON s.ShipperID=x.ShipperID
  LEFT JOIN dbo.Dim_Tiempo t ON (x.OrderDate IS NULL AND t.Tiempo_SK=0) OR (t.Tiempo_SK<>0 AND t.Fecha=CONVERT(date,x.OrderDate))
  LEFT JOIN dbo.Dim_Tiempo r ON r.Tiempo_SK<>0 AND r.Fecha=CONVERT(date,x.RequiredDate)
  LEFT JOIN dbo.Dim_Tiempo v ON v.Tiempo_SK<>0 AND v.Fecha=CONVERT(date,x.ShippedDate);
  SELECT TOP(1) @message=CONCAT(N'Ventas: OrderID=',OrderID,N', ProductID=',ProductID,
   N'; referencia no resuelta: ',MissingReference,N'. Cargue dimensiones antes de ventas.')
  FROM #Resolved WHERE MissingReference IS NOT NULL ORDER BY OrderID,ProductID;
  IF @message IS NOT NULL THROW 52407,@message,1;
  MERGE dbo.Fact_Ventas WITH(HOLDLOCK) AS D
  USING (SELECT x.*,a.ImporteBruto,a.ImporteDescuento,a.ImporteNeto
   FROM #Resolved x CROSS APPLY dbo.DW_CalculateAmounts(x.Quantity,x.UnitPrice,x.Discount) a) AS S
  ON D.OrderID=S.OrderID AND D.ProductID=S.ProductID
  WHEN MATCHED THEN UPDATE SET
   Cliente_SK=S.Cliente_SK,Empleado_SK=S.Empleado_SK,Producto_SK=S.Producto_SK,
   Transportista_SK=S.Transportista_SK,FechaPedido_SK=S.FechaPedido_SK,
   FechaRequerida_SK=S.FechaRequerida_SK,FechaEnvio_SK=S.FechaEnvio_SK,
   Cantidad=S.Quantity,PrecioUnitario=S.UnitPrice,Descuento=S.Discount,
   ImporteBruto=S.ImporteBruto,ImporteDescuento=S.ImporteDescuento,ImporteNeto=S.ImporteNeto
  WHEN NOT MATCHED THEN INSERT
   (OrderID,ProductID,Cliente_SK,Empleado_SK,Producto_SK,Transportista_SK,
    FechaPedido_SK,FechaRequerida_SK,FechaEnvio_SK,Cantidad,PrecioUnitario,Descuento,
    ImporteBruto,ImporteDescuento,ImporteNeto)
  VALUES(S.OrderID,S.ProductID,S.Cliente_SK,S.Empleado_SK,S.Producto_SK,S.Transportista_SK,
   S.FechaPedido_SK,S.FechaRequerida_SK,S.FechaEnvio_SK,S.Quantity,S.UnitPrice,S.Discount,
   S.ImporteBruto,S.ImporteDescuento,S.ImporteNeto);
  COMMIT TRANSACTION;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH;
END;
