CREATE PROCEDURE dbo.DW_MergeFactVentas
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @message NVARCHAR(2048),@startDate DATE,@endDate DATE;

    IF EXISTS
    (
        SELECT 1 FROM std.Ventas
        WHERE Quantity<=0 OR UnitPrice<0 OR Discount<0 OR Discount>1
           OR CONVERT(DATE,OrderDate)='19000101'
           OR CONVERT(DATE,RequiredDate)='19000101'
           OR CONVERT(DATE,ShippedDate)='19000101'
    )
        THROW 52406,'Ventas: cantidad, precio, descuento o fecha reservada inválidos.',1;

    IF EXISTS
    (
        SELECT headers.OrderID
        FROM
        (
            SELECT DISTINCT OrderID,CustomerID,EmployeeID,ShipperID,OrderDate,RequiredDate,ShippedDate,
                Freight,ShipAddress,ShipCity,ShipRegion,ShipPostalCode,ShipCountry
            FROM std.Ventas
        ) AS headers
        GROUP BY headers.OrderID
        HAVING COUNT_BIG(*)>1
    )
        THROW 52416,'Ventas: las líneas de un pedido tienen encabezados o fletes distintos.',1;

    SELECT TOP(1) @message=CONCAT(N'Ventas: OrderID=',sales.OrderID,N', ProductID=',sales.ProductID,
        N'; no existe el producto en DimProduct.')
    FROM std.Ventas AS sales
    LEFT JOIN dbo.DimProduct AS product ON product.ProductID=sales.ProductID
    WHERE product.ProductKey IS NULL
    ORDER BY sales.OrderID,sales.ProductID;
    IF @message IS NOT NULL THROW 52417,@message,1;

    SELECT @startDate=MIN(dateValue),@endDate=MAX(dateValue)
    FROM
    (
        SELECT CONVERT(DATE,OrderDate) AS dateValue FROM std.Ventas WHERE OrderDate IS NOT NULL
        UNION ALL SELECT CONVERT(DATE,RequiredDate) FROM std.Ventas WHERE RequiredDate IS NOT NULL
        UNION ALL SELECT CONVERT(DATE,ShippedDate) FROM std.Ventas WHERE ShippedDate IS NOT NULL
    ) AS dates;
    IF @startDate IS NOT NULL
        EXEC dbo.DW_LoadDimDate @StartDate=@startDate,@EndDate=@endDate;

    SELECT DISTINCT sales.OrderID,
        NULLIF(LTRIM(RTRIM(sales.ShipAddress)),N'') AS ShipAddress,
        NULLIF(LTRIM(RTRIM(sales.ShipCity)),N'') AS ShipCity,
        NULLIF(LTRIM(RTRIM(sales.ShipRegion)),N'') AS ShipRegion,
        NULLIF(LTRIM(RTRIM(sales.ShipPostalCode)),N'') AS ShipPostalCode,
        NULLIF(LTRIM(RTRIM(sales.ShipCountry)),N'') AS ShipCountry
    INTO #Destinations
    FROM std.Ventas AS sales;

    INSERT dbo.DimGeography(ShipAddress,ShipCity,ShipRegion,ShipPostalCode,ShipCountry)
    SELECT DISTINCT destination.ShipAddress,destination.ShipCity,destination.ShipRegion,
        destination.ShipPostalCode,destination.ShipCountry
    FROM #Destinations AS destination
    WHERE (destination.ShipAddress IS NOT NULL OR destination.ShipCity IS NOT NULL
        OR destination.ShipRegion IS NOT NULL OR destination.ShipPostalCode IS NOT NULL
        OR destination.ShipCountry IS NOT NULL)
      AND NOT EXISTS
      (
          SELECT 1 FROM dbo.DimGeography AS existing WITH(UPDLOCK,HOLDLOCK)
          WHERE (existing.ShipAddress=destination.ShipAddress OR (existing.ShipAddress IS NULL AND destination.ShipAddress IS NULL))
            AND (existing.ShipCity=destination.ShipCity OR (existing.ShipCity IS NULL AND destination.ShipCity IS NULL))
            AND (existing.ShipRegion=destination.ShipRegion OR (existing.ShipRegion IS NULL AND destination.ShipRegion IS NULL))
            AND (existing.ShipPostalCode=destination.ShipPostalCode OR (existing.ShipPostalCode IS NULL AND destination.ShipPostalCode IS NULL))
            AND (existing.ShipCountry=destination.ShipCountry OR (existing.ShipCountry IS NULL AND destination.ShipCountry IS NULL))
      );

    SELECT sales.OrderID,sales.ProductID,sales.CustomerID,sales.EmployeeID,sales.ShipperID,
        sales.SupplierID,sales.OrderDate,sales.RequiredDate,sales.ShippedDate,sales.UnitPrice,
        sales.Quantity,sales.Discount,sales.Freight,destination.ShipAddress,destination.ShipCity,
        destination.ShipRegion,destination.ShipPostalCode,destination.ShipCountry,
        product.ProductKey,customer.CustomerKey,employee.EmployeeKey,shipper.ShipperKey,
        supplier.SupplierKey,geography.GeographyKey,
        orderDate.DateKey AS OrderDateKey,requiredDate.DateKey AS RequiredDateKey,
        shippedDate.DateKey AS ShippedDateKey
    INTO #Resolved
    FROM std.Ventas AS sales
    JOIN dbo.DimProduct AS product ON product.ProductID=sales.ProductID
    LEFT JOIN dbo.DimCustomer AS customer ON customer.CustomerID=sales.CustomerID
    LEFT JOIN dbo.DimEmployee AS employee ON employee.EmployeeID=sales.EmployeeID
    LEFT JOIN dbo.DimShipper AS shipper ON shipper.ShipperID=sales.ShipperID
    LEFT JOIN dbo.DimSupplier AS supplier ON supplier.SupplierID=sales.SupplierID
    JOIN #Destinations AS destination ON destination.OrderID=sales.OrderID
    LEFT JOIN dbo.DimGeography AS geography
      ON (geography.ShipAddress=destination.ShipAddress OR (geography.ShipAddress IS NULL AND destination.ShipAddress IS NULL))
     AND (geography.ShipCity=destination.ShipCity OR (geography.ShipCity IS NULL AND destination.ShipCity IS NULL))
     AND (geography.ShipRegion=destination.ShipRegion OR (geography.ShipRegion IS NULL AND destination.ShipRegion IS NULL))
     AND (geography.ShipPostalCode=destination.ShipPostalCode OR (geography.ShipPostalCode IS NULL AND destination.ShipPostalCode IS NULL))
     AND (geography.ShipCountry=destination.ShipCountry OR (geography.ShipCountry IS NULL AND destination.ShipCountry IS NULL))
    LEFT JOIN dbo.DimDate AS orderDate ON orderDate.FullDate=CONVERT(DATE,sales.OrderDate)
    LEFT JOIN dbo.DimDate AS requiredDate ON requiredDate.FullDate=CONVERT(DATE,sales.RequiredDate)
    LEFT JOIN dbo.DimDate AS shippedDate ON shippedDate.FullDate=CONVERT(DATE,sales.ShippedDate);

    SELECT TOP(1) @message=CONCAT(N'Ventas: OrderID=',OrderID,N', ProductID=',ProductID,
        N'; falta una referencia de cliente, empleado, transportista, proveedor, destino o fecha.')
    FROM #Resolved
    WHERE (CustomerID IS NOT NULL AND CustomerKey IS NULL)
       OR (EmployeeID IS NOT NULL AND EmployeeKey IS NULL)
       OR (ShipperID IS NOT NULL AND ShipperKey IS NULL)
       OR (SupplierID IS NOT NULL AND SupplierKey IS NULL)
       OR (GeographyKey IS NULL AND (ShipAddress IS NOT NULL OR ShipCity IS NOT NULL
           OR ShipRegion IS NOT NULL OR ShipPostalCode IS NOT NULL OR ShipCountry IS NOT NULL))
       OR (OrderDate IS NOT NULL AND OrderDateKey IS NULL)
       OR (RequiredDate IS NOT NULL AND RequiredDateKey IS NULL)
       OR (ShippedDate IS NOT NULL AND ShippedDateKey IS NULL)
    ORDER BY OrderID,ProductID;
    IF @message IS NOT NULL THROW 52407,@message,1;

    MERGE dbo.FactSales WITH(HOLDLOCK) AS target
    USING
    (
        SELECT resolved.OrderID,resolved.ProductKey,
            COALESCE(resolved.OrderDateKey,0) AS OrderDateKey,
            resolved.RequiredDateKey,resolved.ShippedDateKey,
            COALESCE(resolved.CustomerKey,0) AS CustomerKey,
            COALESCE(resolved.EmployeeKey,0) AS EmployeeKey,
            COALESCE(resolved.ShipperKey,0) AS ShipperKey,
            COALESCE(resolved.SupplierKey,0) AS SupplierKey,
            COALESCE(resolved.GeographyKey,0) AS GeographyKey,
            resolved.Quantity,resolved.UnitPrice,resolved.Discount,resolved.Freight,
            amounts.GrossAmount,amounts.DiscountAmount,amounts.NetAmount
        FROM #Resolved AS resolved
        CROSS APPLY dbo.DW_CalculateAmounts(resolved.Quantity,resolved.UnitPrice,resolved.Discount) AS amounts
    ) AS source
      ON target.OrderID=source.OrderID AND target.ProductKey=source.ProductKey
    WHEN MATCHED THEN UPDATE SET
        OrderDateKey=source.OrderDateKey,
        RequiredDateKey=source.RequiredDateKey,
        ShippedDateKey=source.ShippedDateKey,
        CustomerKey=source.CustomerKey,
        EmployeeKey=source.EmployeeKey,
        ShipperKey=source.ShipperKey,
        SupplierKey=source.SupplierKey,
        GeographyKey=source.GeographyKey,
        Quantity=source.Quantity,
        UnitPrice=source.UnitPrice,
        Discount=source.Discount,
        Freight=source.Freight,
        GrossAmount=source.GrossAmount,
        DiscountAmount=source.DiscountAmount,
        NetAmount=source.NetAmount
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (OrderID,OrderDateKey,RequiredDateKey,ShippedDateKey,ProductKey,CustomerKey,EmployeeKey,
         ShipperKey,SupplierKey,GeographyKey,Quantity,UnitPrice,Discount,Freight,
         GrossAmount,DiscountAmount,NetAmount)
    VALUES
        (source.OrderID,source.OrderDateKey,source.RequiredDateKey,source.ShippedDateKey,
         source.ProductKey,source.CustomerKey,source.EmployeeKey,source.ShipperKey,
         source.SupplierKey,source.GeographyKey,source.Quantity,source.UnitPrice,source.Discount,
         source.Freight,source.GrossAmount,source.DiscountAmount,source.NetAmount);
END;
