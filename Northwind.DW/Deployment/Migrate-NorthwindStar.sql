-- Ejecutar una sola vez después de publicar el esquema aditivo y antes del ETL nuevo.
-- La operación usa el OLTP y el DW de esta misma instancia y bloquea las tablas fuente
-- mientras toma el corte y copia los datos. En caso de error, la transacción revierte todo.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @TargetDatabase SYSNAME=DB_NAME(),
        @SourceDatabase SYSNAME,
        @MigrationName NVARCHAR(80)=N'ReplaceNorthwindStarModel',
        @Stage NVARCHAR(20),
        @SourceCut BIGINT,
        @Sql NVARCHAR(MAX),
        @QuotedSource NVARCHAR(258),
        @LockRows BIGINT,
        @LockResult INT,
        @LegacyFactCount BIGINT,
        @LegacyCustomerCount BIGINT,
        @LegacyEmployeeCount BIGINT,
        @LegacyProductCount BIGINT,
        @LegacyShipperCount BIGINT,
        @LegacyDateCount BIGINT,
        @NewDateCount BIGINT,
        @IdentityInsertObject SYSNAME,
        @CalendarStart DATE,
        @CalendarEnd DATE;

IF @TargetDatabase=N'Northwind_DW_Test'
    SET @SourceDatabase=N'Northwind_Test';
ELSE IF @TargetDatabase=N'Northwind_DW'
    SET @SourceDatabase=N'NorthWind';
ELSE IF @TargetDatabase LIKE N'Northwind_DW[_]%[_]Test'
     AND EXISTS(SELECT 1 FROM sys.extended_properties
        WHERE class=0 AND name=N'NorthwindPracticeTestDatabase'
          AND CONVERT(NVARCHAR(128),value)=N'Northwind_DW')
    SET @SourceDatabase=N'Northwind_Test';
ELSE
    THROW 52120,'Migración rechazada: seleccione Northwind_DW o Northwind_DW_Test.',1;

IF OBJECT_ID(N'dbo.WarehouseMigrationState',N'U') IS NULL
   OR OBJECT_ID(N'dbo.FactSales',N'U') IS NULL
    THROW 52121,'Publique primero el esquema nuevo; no se encontró el modelo DW final.',1;

IF @SourceDatabase=N'Northwind_Test'
BEGIN
    IF NOT EXISTS(SELECT 1 FROM sys.extended_properties
        WHERE class=0 AND name=N'NorthwindPracticeTestDatabase'
          AND CONVERT(NVARCHAR(128),value)=N'Northwind_DW')
        THROW 52122,'La base destino de migración no es una copia DW marcada.',1;
    SET @Sql=N'IF NOT EXISTS(SELECT 1 FROM '+QUOTENAME(@SourceDatabase)+N'.sys.extended_properties
        WHERE class=0 AND name=N''NorthwindPracticeTestDatabase''
          AND CONVERT(NVARCHAR(128),value)=N''NorthWind'')
        THROW 52123,''La base origen no es la copia OLTP marcada.'',1;';
    EXEC sys.sp_executesql @Sql;
END;

IF DB_ID(@SourceDatabase) IS NULL
    THROW 52124,'No existe la base origen correspondiente en esta instancia.',1;

SELECT @Stage=Stage FROM dbo.WarehouseMigrationState
WHERE MigrationName=@MigrationName AND SchemaVersion=1;
IF @Stage IN(N'Validated',N'SkippedEmpty',N'Cutover')
BEGIN
    PRINT N'La sustitución ya está registrada en la etapa '+@Stage+N'; no se repitió la copia.';
    RETURN;
END;

IF OBJECT_ID(N'dbo.Fact_Ventas',N'U') IS NULL
BEGIN
    IF OBJECT_ID(N'dbo.Dim_Cliente',N'U') IS NOT NULL
       OR OBJECT_ID(N'dbo.Dim_Empleado',N'U') IS NOT NULL
       OR OBJECT_ID(N'dbo.Dim_Producto',N'U') IS NOT NULL
       OR OBJECT_ID(N'dbo.Dim_Tiempo',N'U') IS NOT NULL
       OR OBJECT_ID(N'dbo.Dim_Transportista',N'U') IS NOT NULL
        THROW 52128,'Migración detenida: el modelo antiguo está incompleto; revise el destino antes de continuar.',1;

    IF EXISTS(SELECT 1 FROM dbo.FactSales)
       OR EXISTS(SELECT 1 FROM dbo.DimCustomer WHERE CustomerKey<>0)
       OR EXISTS(SELECT 1 FROM dbo.DimEmployee WHERE EmployeeKey<>0)
       OR EXISTS(SELECT 1 FROM dbo.DimProduct)
       OR EXISTS(SELECT 1 FROM dbo.DimShipper WHERE ShipperKey<>0)
       OR EXISTS(SELECT 1 FROM dbo.DimSupplier WHERE SupplierKey<>0)
       OR EXISTS(SELECT 1 FROM dbo.DimGeography WHERE GeographyKey<>0)
       OR EXISTS(SELECT 1 FROM dbo.DimDate WHERE DateKey<>0)
        THROW 52126,'DW sin legado pero el modelo final ya contiene datos; revise su estado antes de continuar.',1;

    INSERT dbo.WarehouseMigrationState(MigrationName,SchemaVersion,Stage,SourceDatabase,SourceCut)
    VALUES(@MigrationName,1,N'SkippedEmpty',@SourceDatabase,0x0000000000000000);
    PRINT N'No hay tablas del modelo anterior ni filas comerciales que migrar.';
    RETURN;
END;

IF OBJECT_ID(N'dbo.Dim_Cliente',N'U') IS NULL
   OR OBJECT_ID(N'dbo.Dim_Empleado',N'U') IS NULL
   OR OBJECT_ID(N'dbo.Dim_Producto',N'U') IS NULL
   OR OBJECT_ID(N'dbo.Dim_Tiempo',N'U') IS NULL
   OR OBJECT_ID(N'dbo.Dim_Transportista',N'U') IS NULL
    THROW 52128,'Migración detenida: el modelo antiguo está incompleto; revise el destino antes de continuar.',1;

SELECT @LegacyFactCount=COUNT_BIG(*) FROM dbo.Fact_Ventas;
SELECT @LegacyCustomerCount=COUNT_BIG(*) FROM dbo.Dim_Cliente WHERE Cliente_SK<>0;
SELECT @LegacyEmployeeCount=COUNT_BIG(*) FROM dbo.Dim_Empleado WHERE Empleado_SK<>0;
SELECT @LegacyProductCount=COUNT_BIG(*) FROM dbo.Dim_Producto;
SELECT @LegacyShipperCount=COUNT_BIG(*) FROM dbo.Dim_Transportista;
SELECT @LegacyDateCount=COUNT_BIG(*) FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0;

IF @LegacyFactCount=0
BEGIN
    IF @LegacyCustomerCount<>0 OR @LegacyEmployeeCount<>0 OR @LegacyProductCount<>0
       OR @LegacyShipperCount<>0
        THROW 52125,'Migración detenida: hay dimensiones comerciales anteriores sin hechos.',1;
    IF EXISTS(SELECT 1 FROM dbo.FactSales)
       OR EXISTS(SELECT 1 FROM dbo.DimCustomer WHERE CustomerKey<>0)
       OR EXISTS(SELECT 1 FROM dbo.DimEmployee WHERE EmployeeKey<>0)
       OR EXISTS(SELECT 1 FROM dbo.DimProduct)
       OR EXISTS(SELECT 1 FROM dbo.DimShipper WHERE ShipperKey<>0)
       OR EXISTS(SELECT 1 FROM dbo.DimSupplier WHERE SupplierKey<>0)
       OR EXISTS(SELECT 1 FROM dbo.DimGeography WHERE GeographyKey<>0)
       OR EXISTS(SELECT 1 FROM dbo.DimDate WHERE DateKey<>0)
        THROW 52126,'DW vacío anterior pero el esquema nuevo ya tiene datos; se requiere revisar su estado.',1;
    INSERT dbo.WarehouseMigrationState(MigrationName,SchemaVersion,Stage,SourceDatabase,SourceCut)
    VALUES(@MigrationName,1,N'SkippedEmpty',@SourceDatabase,0x0000000000000000);
    PRINT N'No hay hechos anteriores que migrar. Continúe con la carga inicial del DW nuevo.';
    RETURN;
END;

IF EXISTS(SELECT 1 FROM dbo.FactSales)
   OR EXISTS(SELECT 1 FROM dbo.DimCustomer WHERE CustomerKey<>0)
   OR EXISTS(SELECT 1 FROM dbo.DimEmployee WHERE EmployeeKey<>0)
   OR EXISTS(SELECT 1 FROM dbo.DimProduct)
   OR EXISTS(SELECT 1 FROM dbo.DimShipper WHERE ShipperKey<>0)
   OR EXISTS(SELECT 1 FROM dbo.DimSupplier WHERE SupplierKey<>0)
   OR EXISTS(SELECT 1 FROM dbo.DimGeography WHERE GeographyKey<>0)
   OR EXISTS(SELECT 1 FROM dbo.DimDate WHERE DateKey<>0)
    THROW 52127,'DW nuevo ya contiene filas comerciales sin etapa de migración; no se copiará encima.',1;

CREATE TABLE #SourceCustomers
(
    CustomerID NCHAR(5) COLLATE DATABASE_DEFAULT NOT NULL,
    CompanyName NVARCHAR(40) COLLATE DATABASE_DEFAULT NOT NULL,
    ContactName NVARCHAR(30) COLLATE DATABASE_DEFAULT NULL,
    ContactTitle NVARCHAR(30) COLLATE DATABASE_DEFAULT NULL,
    [Address] NVARCHAR(60) COLLATE DATABASE_DEFAULT NULL,
    City NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
    Region NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
    PostalCode NVARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
    Country NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
    Phone NVARCHAR(24) COLLATE DATABASE_DEFAULT NULL,
    Fax NVARCHAR(24) COLLATE DATABASE_DEFAULT NULL
);
CREATE TABLE #SourceEmployees
(
    EmployeeID INT NOT NULL,
    FirstName NVARCHAR(10) COLLATE DATABASE_DEFAULT NOT NULL,
    LastName NVARCHAR(20) COLLATE DATABASE_DEFAULT NOT NULL,
    Title NVARCHAR(30) COLLATE DATABASE_DEFAULT NULL,
    TitleOfCourtesy NVARCHAR(25) COLLATE DATABASE_DEFAULT NULL,
    BirthDate DATETIME NULL,
    HireDate DATETIME NULL,
    [Address] NVARCHAR(60) COLLATE DATABASE_DEFAULT NULL,
    City NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
    Region NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
    Country NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
    PostalCode NVARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
    ReportsTo INT NULL,
    HomePhone NVARCHAR(24) COLLATE DATABASE_DEFAULT NULL,
    Extension NVARCHAR(4) COLLATE DATABASE_DEFAULT NULL
);
CREATE TABLE #SourceCategories
(
    CategoryID INT NOT NULL,
    CategoryName NVARCHAR(15) COLLATE DATABASE_DEFAULT NOT NULL,
    [Description] NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL
);
CREATE TABLE #SourceProducts
(
    ProductID INT NOT NULL,
    ProductName NVARCHAR(40) COLLATE DATABASE_DEFAULT NOT NULL,
    CategoryID INT NULL,
    SupplierID INT NULL,
    QuantityPerUnit NVARCHAR(20) COLLATE DATABASE_DEFAULT NULL,
    UnitsInStock SMALLINT NULL,
    UnitsOnOrder SMALLINT NULL,
    ReorderLevel SMALLINT NULL,
    Discontinued BIT NOT NULL
);
CREATE TABLE #SourceSuppliers
(
    SupplierID INT NOT NULL,
    CompanyName NVARCHAR(40) COLLATE DATABASE_DEFAULT NOT NULL,
    ContactName NVARCHAR(30) COLLATE DATABASE_DEFAULT NULL,
    ContactTitle NVARCHAR(30) COLLATE DATABASE_DEFAULT NULL,
    [Address] NVARCHAR(60) COLLATE DATABASE_DEFAULT NULL,
    City NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
    Region NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
    PostalCode NVARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
    Country NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
    Phone NVARCHAR(24) COLLATE DATABASE_DEFAULT NULL,
    Fax NVARCHAR(24) COLLATE DATABASE_DEFAULT NULL,
    HomePage NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL
);
CREATE TABLE #SourceShippers
(
    ShipperID INT NOT NULL,
    CompanyName NVARCHAR(40) COLLATE DATABASE_DEFAULT NOT NULL,
    Phone NVARCHAR(24) COLLATE DATABASE_DEFAULT NULL
);
CREATE TABLE #SourceOrders
(
    OrderID INT NOT NULL,
    CustomerID NCHAR(5) COLLATE DATABASE_DEFAULT NULL,
    EmployeeID INT NULL,
    OrderDate DATETIME NULL,
    RequiredDate DATETIME NULL,
    ShippedDate DATETIME NULL,
    ShipVia INT NULL,
    Freight MONEY NULL,
    ShipAddress NVARCHAR(60) COLLATE DATABASE_DEFAULT NULL,
    ShipCity NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
    ShipRegion NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
    ShipPostalCode NVARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
    ShipCountry NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL
);
CREATE TABLE #SourceOrderDetails
(
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    CONSTRAINT PK_SourceOrderDetails PRIMARY KEY (OrderID,ProductID)
);
CREATE TABLE #Destinations
(
    ShipAddress NVARCHAR(60) COLLATE DATABASE_DEFAULT NULL,
    ShipCity NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
    ShipRegion NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
    ShipPostalCode NVARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
    ShipCountry NVARCHAR(15) COLLATE DATABASE_DEFAULT NULL
);

BEGIN TRY
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    BEGIN TRANSACTION;
    EXEC @LockResult=sys.sp_getapplock
        @Resource=N'Northwind.Warehouse.Load',@LockMode=N'Exclusive',
        @LockOwner=N'Transaction',@LockTimeout=0;
    IF @LockResult<0
        THROW 52128,'DW ocupado por una carga; no se inició la migración.',1;

    -- Detener escrituras concurrentes del origen hasta que termine la copia.
    SET @QuotedSource=QUOTENAME(@SourceDatabase);
    DECLARE @SourceTables TABLE(TableName SYSNAME NOT NULL);
    INSERT @SourceTables VALUES
        (N'Customers'),(N'Employees'),(N'Categories'),(N'Products'),
        (N'Suppliers'),(N'Shippers'),(N'Orders'),(N'OrderDetails');
    DECLARE @TableName SYSNAME;
    DECLARE SourceLockCursor CURSOR LOCAL FAST_FORWARD FOR SELECT TableName FROM @SourceTables;
    OPEN SourceLockCursor;
    FETCH NEXT FROM SourceLockCursor INTO @TableName;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @LockRows=0;
        SET @Sql=N'SELECT @Rows=COUNT_BIG(*) FROM '+@QuotedSource+N'.dbo.'+
            QUOTENAME(@TableName)+N' WITH (TABLOCKX,HOLDLOCK);';
        EXEC sys.sp_executesql @Sql,N'@Rows BIGINT OUTPUT',@Rows=@LockRows OUTPUT;
        FETCH NEXT FROM SourceLockCursor INTO @TableName;
    END;
    CLOSE SourceLockCursor;
    DEALLOCATE SourceLockCursor;

    DECLARE @Cut TABLE(DBTS BIGINT);
    SET @Sql=N'EXEC '+@QuotedSource+N'.dbo.GetDatabaseRowVersion;';
    INSERT @Cut(DBTS) EXEC sys.sp_executesql @Sql;
    SELECT @SourceCut=DBTS FROM @Cut;
    IF @SourceCut IS NULL OR @SourceCut<0
        THROW 52129,'No se pudo fijar un corte válido del origen.',1;

    SET @Sql=N'
        INSERT #SourceCustomers
        SELECT CustomerID,CompanyName,ContactName,ContactTitle,[Address],City,Region,
               PostalCode,Country,Phone,Fax FROM '+@QuotedSource+N'.dbo.Customers;
        INSERT #SourceEmployees
        SELECT EmployeeID,FirstName,LastName,Title,TitleOfCourtesy,BirthDate,HireDate,
               [Address],City,Region,Country,PostalCode,ReportsTo,HomePhone,Extension
        FROM '+@QuotedSource+N'.dbo.Employees;
        INSERT #SourceCategories SELECT CategoryID,CategoryName,[Description]
        FROM '+@QuotedSource+N'.dbo.Categories;
        INSERT #SourceProducts
        SELECT ProductID,ProductName,CategoryID,SupplierID,QuantityPerUnit,UnitsInStock,
               UnitsOnOrder,ReorderLevel,Discontinued FROM '+@QuotedSource+N'.dbo.Products;
        INSERT #SourceSuppliers
        SELECT SupplierID,CompanyName,ContactName,ContactTitle,[Address],City,Region,
               PostalCode,Country,Phone,Fax,HomePage FROM '+@QuotedSource+N'.dbo.Suppliers;
        INSERT #SourceShippers SELECT ShipperID,CompanyName,Phone FROM '+@QuotedSource+N'.dbo.Shippers;
        INSERT #SourceOrders
        SELECT OrderID,CustomerID,EmployeeID,OrderDate,RequiredDate,ShippedDate,ShipVia,Freight,
               ShipAddress,ShipCity,ShipRegion,ShipPostalCode,ShipCountry
        FROM '+@QuotedSource+N'.dbo.Orders;
        INSERT #SourceOrderDetails SELECT OrderID,ProductID
        FROM '+@QuotedSource+N'.dbo.OrderDetails;';
    EXEC sys.sp_executesql @Sql;

    IF EXISTS(SELECT CustomerID FROM dbo.Dim_Cliente GROUP BY CustomerID HAVING COUNT(*)>1)
       OR EXISTS(SELECT EmployeeID FROM dbo.Dim_Empleado GROUP BY EmployeeID HAVING COUNT(*)>1)
       OR EXISTS(SELECT ProductID FROM dbo.Dim_Producto GROUP BY ProductID HAVING COUNT(*)>1)
       OR EXISTS(SELECT ShipperID FROM dbo.Dim_Transportista GROUP BY ShipperID HAVING COUNT(*)>1)
       OR EXISTS(SELECT Fecha FROM dbo.Dim_Tiempo GROUP BY Fecha HAVING COUNT(*)>1)
        THROW 52130,'Migración detenida: hay identidades o fechas repetidas en el modelo anterior.',1;
    IF EXISTS(SELECT 1 FROM dbo.Dim_Cliente WHERE (Cliente_SK=0 AND CustomerID<>N'~UNK~') OR (CustomerID=N'~UNK~' AND Cliente_SK<>0))
       OR EXISTS(SELECT 1 FROM dbo.Dim_Empleado WHERE (Empleado_SK=0 AND EmployeeID<>0) OR (EmployeeID=0 AND Empleado_SK<>0))
       OR EXISTS(SELECT 1 FROM dbo.Dim_Transportista WHERE (Transportista_SK=0 AND ShipperID<>0) OR (ShipperID=0 AND Transportista_SK<>0))
       OR EXISTS(SELECT 1 FROM dbo.Dim_Tiempo WHERE (Tiempo_SK=0 AND Fecha<>'19000101') OR (Fecha='19000101' AND Tiempo_SK<>0))
        THROW 52131,'Migración detenida: colisión con una identidad anterior reservada.',1;
    IF EXISTS(SELECT 1 FROM dbo.Fact_Ventas f JOIN dbo.Dim_Producto p ON p.Producto_SK=f.Producto_SK
        WHERE f.ProductID<>p.ProductID)
       OR EXISTS(SELECT 1 FROM dbo.Fact_Ventas f
        LEFT JOIN #SourceOrders o ON o.OrderID=f.OrderID
        LEFT JOIN #SourceOrderDetails d ON d.OrderID=f.OrderID AND d.ProductID=f.ProductID
        LEFT JOIN #SourceProducts p ON p.ProductID=f.ProductID
        WHERE o.OrderID IS NULL OR d.OrderID IS NULL OR p.ProductID IS NULL)
        THROW 52132,'Migración detenida: una venta no se puede relacionar inequívocamente con el origen actual.',1;
    IF EXISTS(SELECT 1 FROM dbo.Fact_Ventas WHERE Cantidad<=0 OR PrecioUnitario<0 OR Descuento<0 OR Descuento>1)
        THROW 52133,'Migración detenida: cantidad, precio o descuento inválido.',1;
    IF EXISTS(SELECT 1 FROM dbo.Fact_Ventas f
        CROSS APPLY(VALUES(CONVERT(DECIMAL(19,2),ROUND(CONVERT(DECIMAL(5,0),Cantidad)*CONVERT(DECIMAL(19,4),PrecioUnitario),2)))) b(Bruto)
        CROSS APPLY(VALUES(CONVERT(DECIMAL(19,2),ROUND(b.Bruto*CONVERT(DECIMAL(9,6),Descuento),2)))) d(DescuentoImporte)
        WHERE f.ImporteBruto<>b.Bruto OR f.ImporteDescuento<>d.DescuentoImporte OR f.ImporteNeto<>b.Bruto-d.DescuentoImporte)
        THROW 52134,'Migración detenida: los importes existentes no siguen la regla de cálculo acordada.',1;

    IF EXISTS(SELECT CustomerID FROM dbo.Dim_Cliente WHERE Cliente_SK<>0
              EXCEPT SELECT CustomerID FROM #SourceCustomers)
       OR EXISTS(SELECT EmployeeID FROM dbo.Dim_Empleado WHERE Empleado_SK<>0
              EXCEPT SELECT EmployeeID FROM #SourceEmployees)
       OR EXISTS(SELECT ProductID FROM dbo.Dim_Producto
              EXCEPT SELECT ProductID FROM #SourceProducts)
       OR EXISTS(SELECT ShipperID FROM dbo.Dim_Transportista
              EXCEPT SELECT ShipperID FROM #SourceShippers)
        THROW 52135,'Migración detenida: falta en el origen una entidad comercial guardada en el DW.',1;
    IF EXISTS(SELECT 1 FROM #SourceProducts p LEFT JOIN #SourceCategories c ON c.CategoryID=p.CategoryID
              WHERE p.CategoryID IS NOT NULL AND c.CategoryID IS NULL)
       OR EXISTS(SELECT 1 FROM #SourceProducts p LEFT JOIN #SourceSuppliers s ON s.SupplierID=p.SupplierID
              WHERE p.SupplierID IS NOT NULL AND s.SupplierID IS NULL)
        THROW 52136,'Migración detenida: el origen tiene una categoría o proveedor sin correspondencia.',1;
    IF EXISTS(SELECT 1 FROM dbo.PackageConfig WHERE PackageName=N'Proveedor'
              AND CONVERT(BIGINT,LastRowVersion)>@SourceCut)
        THROW 52137,'La marca nueva de proveedor está más avanzada que el corte estable.',1;

    -- Conservar todas las claves sustitutas antiguas; completar los atributos con el origen actual.
    SET IDENTITY_INSERT dbo.DimCustomer ON;
    SET @IdentityInsertObject=N'DimCustomer';
    INSERT dbo.DimCustomer(CustomerKey,CustomerID,CompanyName,ContactName,ContactTitle,
        [Address],City,Region,PostalCode,Country,Phone,Fax)
    SELECT old.Cliente_SK,old.CustomerID,src.CompanyName,src.ContactName,src.ContactTitle,
        src.[Address],src.City,src.Region,src.PostalCode,src.Country,src.Phone,src.Fax
    FROM dbo.Dim_Cliente old JOIN #SourceCustomers src ON src.CustomerID=old.CustomerID
    WHERE old.Cliente_SK<>0;
    SET IDENTITY_INSERT dbo.DimCustomer OFF;
    SET @IdentityInsertObject=NULL;
    INSERT dbo.DimCustomer(CustomerID,CompanyName,ContactName,ContactTitle,[Address],City,Region,
        PostalCode,Country,Phone,Fax)
    SELECT src.CustomerID,src.CompanyName,src.ContactName,src.ContactTitle,src.[Address],src.City,
        src.Region,src.PostalCode,src.Country,src.Phone,src.Fax
    FROM #SourceCustomers src
    WHERE NOT EXISTS(SELECT 1 FROM dbo.DimCustomer currentDim WHERE currentDim.CustomerID=src.CustomerID);

    SET IDENTITY_INSERT dbo.DimEmployee ON;
    SET @IdentityInsertObject=N'DimEmployee';
    INSERT dbo.DimEmployee(EmployeeKey,EmployeeID,FirstName,LastName,FullName,Title,TitleOfCourtesy,
        BirthDate,HireDate,[Address],City,Region,Country,PostalCode,ReportsTo,SupervisorName,HomePhone,Extension)
    SELECT old.Empleado_SK,old.EmployeeID,src.FirstName,src.LastName,
        CONVERT(NVARCHAR(60),CONCAT(src.FirstName,N' ',src.LastName)),src.Title,src.TitleOfCourtesy,
        CONVERT(DATE,src.BirthDate),CONVERT(DATE,src.HireDate),src.[Address],src.City,src.Region,
        src.Country,src.PostalCode,src.ReportsTo,
        CASE WHEN supervisor.EmployeeID IS NULL THEN NULL
             ELSE CONVERT(NVARCHAR(60),CONCAT(supervisor.FirstName,N' ',supervisor.LastName)) END,
        src.HomePhone,src.Extension
    FROM dbo.Dim_Empleado old JOIN #SourceEmployees src ON src.EmployeeID=old.EmployeeID
    LEFT JOIN #SourceEmployees supervisor ON supervisor.EmployeeID=src.ReportsTo
    WHERE old.Empleado_SK<>0;
    SET IDENTITY_INSERT dbo.DimEmployee OFF;
    SET @IdentityInsertObject=NULL;
    INSERT dbo.DimEmployee(EmployeeID,FirstName,LastName,FullName,Title,TitleOfCourtesy,BirthDate,HireDate,
        [Address],City,Region,Country,PostalCode,ReportsTo,SupervisorName,HomePhone,Extension)
    SELECT src.EmployeeID,src.FirstName,src.LastName,CONVERT(NVARCHAR(60),CONCAT(src.FirstName,N' ',src.LastName)),
        src.Title,src.TitleOfCourtesy,CONVERT(DATE,src.BirthDate),CONVERT(DATE,src.HireDate),src.[Address],
        src.City,src.Region,src.Country,src.PostalCode,src.ReportsTo,
        CASE WHEN supervisor.EmployeeID IS NULL THEN NULL
             ELSE CONVERT(NVARCHAR(60),CONCAT(supervisor.FirstName,N' ',supervisor.LastName)) END,
        src.HomePhone,src.Extension
    FROM #SourceEmployees src
    LEFT JOIN #SourceEmployees supervisor ON supervisor.EmployeeID=src.ReportsTo
    WHERE NOT EXISTS(SELECT 1 FROM dbo.DimEmployee currentDim WHERE currentDim.EmployeeID=src.EmployeeID);

    SET IDENTITY_INSERT dbo.DimProduct ON;
    SET @IdentityInsertObject=N'DimProduct';
    INSERT dbo.DimProduct(ProductKey,ProductID,ProductName,CategoryID,CategoryName,CategoryDescription,
        QuantityPerUnit,UnitsInStock,UnitsOnOrder,ReorderLevel,Discontinued)
    SELECT old.Producto_SK,src.ProductID,src.ProductName,src.CategoryID,category.CategoryName,
        category.[Description],src.QuantityPerUnit,src.UnitsInStock,src.UnitsOnOrder,src.ReorderLevel,src.Discontinued
    FROM dbo.Dim_Producto old JOIN #SourceProducts src ON src.ProductID=old.ProductID
    LEFT JOIN #SourceCategories category ON category.CategoryID=src.CategoryID;
    SET IDENTITY_INSERT dbo.DimProduct OFF;
    SET @IdentityInsertObject=NULL;
    INSERT dbo.DimProduct(ProductID,ProductName,CategoryID,CategoryName,CategoryDescription,
        QuantityPerUnit,UnitsInStock,UnitsOnOrder,ReorderLevel,Discontinued)
    SELECT src.ProductID,src.ProductName,src.CategoryID,category.CategoryName,category.[Description],
        src.QuantityPerUnit,src.UnitsInStock,src.UnitsOnOrder,src.ReorderLevel,src.Discontinued
    FROM #SourceProducts src
    LEFT JOIN #SourceCategories category ON category.CategoryID=src.CategoryID
    WHERE NOT EXISTS(SELECT 1 FROM dbo.DimProduct currentDim WHERE currentDim.ProductID=src.ProductID);

    SET IDENTITY_INSERT dbo.DimShipper ON;
    SET @IdentityInsertObject=N'DimShipper';
    INSERT dbo.DimShipper(ShipperKey,ShipperID,CompanyName,Phone)
    SELECT old.Transportista_SK,src.ShipperID,src.CompanyName,src.Phone
    FROM dbo.Dim_Transportista old JOIN #SourceShippers src ON src.ShipperID=old.ShipperID
    WHERE old.Transportista_SK<>0;
    SET IDENTITY_INSERT dbo.DimShipper OFF;
    SET @IdentityInsertObject=NULL;
    INSERT dbo.DimShipper(ShipperID,CompanyName,Phone)
    SELECT src.ShipperID,src.CompanyName,src.Phone
    FROM #SourceShippers src
    WHERE NOT EXISTS(SELECT 1 FROM dbo.DimShipper currentDim WHERE currentDim.ShipperID=src.ShipperID);

    INSERT dbo.DimSupplier(SupplierID,CompanyName,ContactName,ContactTitle,[Address],City,Region,
        PostalCode,Country,Phone,Fax,HomePage)
    SELECT src.SupplierID,src.CompanyName,src.ContactName,src.ContactTitle,src.[Address],src.City,src.Region,
        src.PostalCode,src.Country,src.Phone,src.Fax,src.HomePage
    FROM #SourceSuppliers src
    WHERE NOT EXISTS(SELECT 1 FROM dbo.DimSupplier currentDim WHERE currentDim.SupplierID=src.SupplierID);

    SELECT @CalendarStart=MIN(calendar.FullDate),@CalendarEnd=MAX(calendar.FullDate)
    FROM
    (
        SELECT Fecha FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0
        UNION ALL SELECT CONVERT(DATE,OrderDate) FROM #SourceOrders WHERE OrderDate IS NOT NULL
        UNION ALL SELECT CONVERT(DATE,RequiredDate) FROM #SourceOrders WHERE RequiredDate IS NOT NULL
        UNION ALL SELECT CONVERT(DATE,ShippedDate) FROM #SourceOrders WHERE ShippedDate IS NOT NULL
    ) AS calendar(FullDate);
    IF @CalendarStart IS NULL OR @CalendarEnd IS NULL
        THROW 52138,'No se pudo determinar un rango de fechas para la migración.',1;
    IF EXISTS(SELECT 1 FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0
              AND Tiempo_SK<>YEAR(Fecha)*10000+MONTH(Fecha)*100+DAY(Fecha))
        THROW 52139,'Migración detenida: las claves antiguas de fecha no corresponden a YYYYMMDD.',1;
    EXEC dbo.DW_LoadDimDate @StartDate=@CalendarStart,@EndDate=@CalendarEnd;

    INSERT #Destinations(ShipAddress,ShipCity,ShipRegion,ShipPostalCode,ShipCountry)
    SELECT DISTINCT NULLIF(LTRIM(RTRIM(o.ShipAddress)),N''),
           NULLIF(LTRIM(RTRIM(o.ShipCity)),N''),NULLIF(LTRIM(RTRIM(o.ShipRegion)),N''),
           NULLIF(LTRIM(RTRIM(o.ShipPostalCode)),N''),NULLIF(LTRIM(RTRIM(o.ShipCountry)),N'')
    FROM #SourceOrders o
    JOIN (SELECT DISTINCT OrderID FROM dbo.Fact_Ventas) oldSales ON oldSales.OrderID=o.OrderID;
    INSERT dbo.DimGeography(ShipAddress,ShipCity,ShipRegion,ShipPostalCode,ShipCountry)
    SELECT d.ShipAddress,d.ShipCity,d.ShipRegion,d.ShipPostalCode,d.ShipCountry
    FROM #Destinations d
    WHERE (d.ShipAddress IS NOT NULL OR d.ShipCity IS NOT NULL OR d.ShipRegion IS NOT NULL
       OR d.ShipPostalCode IS NOT NULL OR d.ShipCountry IS NOT NULL)
      AND NOT EXISTS
      (
          SELECT 1 FROM dbo.DimGeography g
          WHERE ISNULL(g.ShipAddress,N'')=ISNULL(d.ShipAddress,N'')
            AND ISNULL(g.ShipCity,N'')=ISNULL(d.ShipCity,N'')
            AND ISNULL(g.ShipRegion,N'')=ISNULL(d.ShipRegion,N'')
            AND ISNULL(g.ShipPostalCode,N'')=ISNULL(d.ShipPostalCode,N'')
            AND ISNULL(g.ShipCountry,N'')=ISNULL(d.ShipCountry,N'')
      );

    IF EXISTS(SELECT 1 FROM dbo.Fact_Ventas f
        LEFT JOIN #SourceProducts p ON p.ProductID=f.ProductID
        LEFT JOIN dbo.DimSupplier s ON s.SupplierID=p.SupplierID
        WHERE p.ProductID IS NULL OR (p.SupplierID IS NOT NULL AND s.SupplierKey IS NULL))
       OR EXISTS(SELECT 1 FROM dbo.Fact_Ventas f
        LEFT JOIN #SourceOrders o ON o.OrderID=f.OrderID
        WHERE o.OrderID IS NULL)
        THROW 52140,'Migración detenida: no se pueden enriquecer proveedor o encabezado de una venta.',1;

    SET IDENTITY_INSERT dbo.FactSales ON;
    SET @IdentityInsertObject=N'FactSales';
    INSERT dbo.FactSales(SalesKey,OrderID,OrderDateKey,RequiredDateKey,ShippedDateKey,
        ProductKey,CustomerKey,EmployeeKey,ShipperKey,SupplierKey,GeographyKey,
        Quantity,UnitPrice,Discount,Freight,GrossAmount,DiscountAmount,NetAmount)
    SELECT old.Venta_SK,old.OrderID,old.FechaPedido_SK,old.FechaRequerida_SK,old.FechaEnvio_SK,
        old.Producto_SK,old.Cliente_SK,old.Empleado_SK,COALESCE(old.Transportista_SK,0),
        COALESCE(supplier.SupplierKey,0),COALESCE(geography.GeographyKey,0),
        old.Cantidad,old.PrecioUnitario,old.Descuento,CONVERT(DECIMAL(19,4),orderHeader.Freight),
        CONVERT(DECIMAL(19,2),old.ImporteBruto),CONVERT(DECIMAL(19,2),old.ImporteDescuento),
        CONVERT(DECIMAL(19,2),old.ImporteNeto)
    FROM dbo.Fact_Ventas old
    JOIN #SourceOrders orderHeader ON orderHeader.OrderID=old.OrderID
    JOIN dbo.DimDate orderDate ON orderDate.DateKey=old.FechaPedido_SK
    JOIN dbo.DimProduct product ON product.ProductKey=old.Producto_SK
        AND product.ProductID=old.ProductID
    JOIN dbo.DimCustomer customer ON customer.CustomerKey=old.Cliente_SK
    JOIN dbo.DimEmployee employee ON employee.EmployeeKey=old.Empleado_SK
    LEFT JOIN dbo.DimSupplier supplier ON supplier.SupplierID=
        (SELECT sourceProduct.SupplierID FROM #SourceProducts sourceProduct WHERE sourceProduct.ProductID=old.ProductID)
    CROSS APPLY (VALUES
        (NULLIF(LTRIM(RTRIM(orderHeader.ShipAddress)),N''),
         NULLIF(LTRIM(RTRIM(orderHeader.ShipCity)),N''),
         NULLIF(LTRIM(RTRIM(orderHeader.ShipRegion)),N''),
         NULLIF(LTRIM(RTRIM(orderHeader.ShipPostalCode)),N''),
         NULLIF(LTRIM(RTRIM(orderHeader.ShipCountry)),N''))) AS destination
         (ShipAddress,ShipCity,ShipRegion,ShipPostalCode,ShipCountry)
    LEFT JOIN dbo.DimGeography geography
        ON (geography.ShipAddress=destination.ShipAddress
            OR (geography.ShipAddress IS NULL AND destination.ShipAddress IS NULL))
       AND (geography.ShipCity=destination.ShipCity
            OR (geography.ShipCity IS NULL AND destination.ShipCity IS NULL))
       AND (geography.ShipRegion=destination.ShipRegion
            OR (geography.ShipRegion IS NULL AND destination.ShipRegion IS NULL))
       AND (geography.ShipPostalCode=destination.ShipPostalCode
            OR (geography.ShipPostalCode IS NULL AND destination.ShipPostalCode IS NULL))
       AND (geography.ShipCountry=destination.ShipCountry
            OR (geography.ShipCountry IS NULL AND destination.ShipCountry IS NULL))
    WHERE
        (old.FechaRequerida_SK IS NULL OR EXISTS(SELECT 1 FROM dbo.DimDate d WHERE d.DateKey=old.FechaRequerida_SK))
        AND (old.FechaEnvio_SK IS NULL OR EXISTS(SELECT 1 FROM dbo.DimDate d WHERE d.DateKey=old.FechaEnvio_SK));
    SET IDENTITY_INSERT dbo.FactSales OFF;
    SET @IdentityInsertObject=NULL;

    -- Corregir la dimensión de destino con la tupla completa y comprobar cada fila.
    IF (SELECT COUNT_BIG(*) FROM dbo.FactSales)<>@LegacyFactCount
       OR EXISTS(SELECT SalesKey,OrderID,ProductKey,CustomerKey,EmployeeKey,Quantity,UnitPrice,Discount,GrossAmount,DiscountAmount,NetAmount
                 FROM dbo.FactSales
                 EXCEPT SELECT Venta_SK,OrderID,Producto_SK,Cliente_SK,Empleado_SK,Cantidad,PrecioUnitario,Descuento,
                         CONVERT(DECIMAL(19,2),ImporteBruto),CONVERT(DECIMAL(19,2),ImporteDescuento),CONVERT(DECIMAL(19,2),ImporteNeto)
                 FROM dbo.Fact_Ventas)
       OR EXISTS(SELECT Venta_SK,OrderID,Producto_SK,Cliente_SK,Empleado_SK,Cantidad,PrecioUnitario,Descuento,
                         CONVERT(DECIMAL(19,2),ImporteBruto),CONVERT(DECIMAL(19,2),ImporteDescuento),CONVERT(DECIMAL(19,2),ImporteNeto)
                 FROM dbo.Fact_Ventas
                 EXCEPT SELECT SalesKey,OrderID,ProductKey,CustomerKey,EmployeeKey,Quantity,UnitPrice,Discount,GrossAmount,DiscountAmount,NetAmount
                 FROM dbo.FactSales)
        THROW 52141,'Migración incompleta: las identidades o importes del hecho no coinciden.',1;

    IF EXISTS
    (
        SELECT 1 FROM dbo.FactSales f
        JOIN #SourceOrders o ON o.OrderID=f.OrderID
        WHERE (o.Freight IS NULL AND f.Freight IS NOT NULL)
           OR (o.Freight IS NOT NULL AND f.Freight IS NULL)
           OR (o.Freight IS NOT NULL AND f.Freight<>CONVERT(DECIMAL(19,4),o.Freight))
    )
        THROW 52142,'Migración incompleta: el flete no coincide con el encabezado de origen.',1;
    IF EXISTS(SELECT 1 FROM dbo.FactSales GROUP BY OrderID HAVING MIN(Freight)<>MAX(Freight)
        OR (COUNT(Freight)>0 AND COUNT(Freight)<COUNT_BIG(*)))
        THROW 52143,'Migración incompleta: las líneas de un pedido tienen fletes distintos.',1;

    UPDATE dbo.PackageConfig
    SET LastRowVersion=CONVERT(BINARY(8),@SourceCut),LastSuccessfulLoad=SYSUTCDATETIME()
    WHERE PackageName=N'Proveedor';
    IF @@ROWCOUNT<>1
        THROW 52144,'Migración incompleta: falta el control Proveedor creado por la publicación.',1;
    INSERT dbo.WarehouseMigrationState(MigrationName,SchemaVersion,Stage,SourceDatabase,SourceCut)
    VALUES(@MigrationName,1,N'Validated',@SourceDatabase,CONVERT(BINARY(8),@SourceCut));

    COMMIT TRANSACTION;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    PRINT N'Migración validada. Filas copiadas: '+CONVERT(NVARCHAR(30),@LegacyFactCount)+
        N'; corte de origen: '+CONVERT(NVARCHAR(30),@SourceCut)+N'.';
END TRY
BEGIN CATCH
    IF CURSOR_STATUS('local','SourceLockCursor')>=0 CLOSE SourceLockCursor;
    IF CURSOR_STATUS('local','SourceLockCursor')>-3 DEALLOCATE SourceLockCursor;
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    IF @IdentityInsertObject IS NOT NULL
    BEGIN TRY
        SET @Sql=N'SET IDENTITY_INSERT dbo.'+QUOTENAME(@IdentityInsertObject)+N' OFF;';
        EXEC sys.sp_executesql @Sql;
    END TRY
    BEGIN CATCH
    END CATCH;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    THROW;
END CATCH;
