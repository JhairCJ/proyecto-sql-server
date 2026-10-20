-- Miembros técnicos del modelo final; las claves cero están reservadas.
IF EXISTS(SELECT 1 FROM dbo.DimDate WHERE DateKey=0 AND (FullDate<>'19000101' OR IsUnknown=0))
   OR EXISTS(SELECT 1 FROM dbo.DimDate WHERE FullDate='19000101' AND DateKey<>0)
    THROW 52101,'DimDate: colision con la fecha técnica reservada.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.DimDate WHERE DateKey=0)
    INSERT dbo.DimDate(DateKey,FullDate,DayNumber,DayName,MonthNumber,MonthName,
        QuarterNumber,YearNumber,WeekNumber,IsWeekend,IsUnknown)
    VALUES(0,'19000101',1,N'Desconocido',1,N'Desconocido',1,1900,NULL,NULL,1);

IF EXISTS(SELECT 1 FROM dbo.DimCustomer WHERE CustomerKey=0 AND CustomerID<>N'~UNK~')
   OR EXISTS(SELECT 1 FROM dbo.DimCustomer WHERE CustomerID=N'~UNK~' AND CustomerKey<>0)
    THROW 52102,'DimCustomer: identidad técnica reservada en uso.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.DimCustomer WHERE CustomerKey=0)
BEGIN
    SET IDENTITY_INSERT dbo.DimCustomer ON;
    INSERT dbo.DimCustomer(CustomerKey,CustomerID,CompanyName)
    VALUES(0,N'~UNK~',N'Desconocido');
    SET IDENTITY_INSERT dbo.DimCustomer OFF;
END;

IF EXISTS(SELECT 1 FROM dbo.DimEmployee WHERE EmployeeKey=0 AND EmployeeID<>0)
   OR EXISTS(SELECT 1 FROM dbo.DimEmployee WHERE EmployeeID=0 AND EmployeeKey<>0)
    THROW 52103,'DimEmployee: identidad técnica reservada en uso.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.DimEmployee WHERE EmployeeKey=0)
BEGIN
    SET IDENTITY_INSERT dbo.DimEmployee ON;
    INSERT dbo.DimEmployee(EmployeeKey,EmployeeID,FirstName,LastName,FullName)
    VALUES(0,0,N'NA',N'NA',N'Desconocido');
    SET IDENTITY_INSERT dbo.DimEmployee OFF;
END;

IF EXISTS(SELECT 1 FROM dbo.DimShipper WHERE ShipperKey=0 AND ShipperID<>0)
   OR EXISTS(SELECT 1 FROM dbo.DimShipper WHERE ShipperID=0 AND ShipperKey<>0)
    THROW 52104,'DimShipper: identidad técnica reservada en uso.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.DimShipper WHERE ShipperKey=0)
BEGIN
    SET IDENTITY_INSERT dbo.DimShipper ON;
    INSERT dbo.DimShipper(ShipperKey,ShipperID,CompanyName)
    VALUES(0,0,N'Desconocido');
    SET IDENTITY_INSERT dbo.DimShipper OFF;
END;

IF EXISTS(SELECT 1 FROM dbo.DimSupplier WHERE SupplierKey=0 AND SupplierID<>0)
   OR EXISTS(SELECT 1 FROM dbo.DimSupplier WHERE SupplierID=0 AND SupplierKey<>0)
    THROW 52105,'DimSupplier: identidad técnica reservada en uso.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.DimSupplier WHERE SupplierKey=0)
BEGIN
    SET IDENTITY_INSERT dbo.DimSupplier ON;
    INSERT dbo.DimSupplier(SupplierKey,SupplierID,CompanyName)
    VALUES(0,0,N'Desconocido');
    SET IDENTITY_INSERT dbo.DimSupplier OFF;
END;

IF EXISTS(SELECT 1 FROM dbo.DimGeography WHERE GeographyKey=0
          AND (ShipAddress IS NOT NULL OR ShipCity IS NOT NULL OR ShipRegion IS NOT NULL
               OR ShipPostalCode IS NOT NULL OR ShipCountry IS NOT NULL))
   OR EXISTS(SELECT 1 FROM dbo.DimGeography WHERE GeographyKey<>0
          AND ShipAddress IS NULL AND ShipCity IS NULL AND ShipRegion IS NULL
          AND ShipPostalCode IS NULL AND ShipCountry IS NULL)
    THROW 52106,'DimGeography: destino técnico reservado en uso.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.DimGeography WHERE GeographyKey=0)
BEGIN
    SET IDENTITY_INSERT dbo.DimGeography ON;
    INSERT dbo.DimGeography(GeographyKey,ShipAddress,ShipCity,ShipRegion,ShipPostalCode,ShipCountry)
    VALUES(0,NULL,NULL,NULL,NULL,NULL);
    SET IDENTITY_INSERT dbo.DimGeography OFF;
END;

-- No se crea una fila de producto ficticia. Una referencia sin producto real falla al cargar.
INSERT dbo.PackageConfig(PackageName)
SELECT PackageName FROM (VALUES(N'Cliente'),(N'Empleado'),(N'Producto'),
    (N'Transportista'),(N'Proveedor'),(N'Ventas')) p(PackageName)
WHERE NOT EXISTS(SELECT 1 FROM dbo.PackageConfig c WHERE c.PackageName=p.PackageName);
