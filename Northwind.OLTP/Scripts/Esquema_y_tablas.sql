USE Northwind_DW;
GO

CREATE SCHEMA std;
GO

CREATE TABLE std.Cliente
(
    CustomerID NCHAR(5) NOT NULL,
    CompanyName NVARCHAR(40) NULL,
    ContactName NVARCHAR(30) NULL,
    ContactTitle NVARCHAR(30) NULL,
    City NVARCHAR(15) NULL,
    Region NVARCHAR(15) NULL,
    PostalCode NVARCHAR(10) NULL,
    Country NVARCHAR(15) NULL,
    SourceRowVersion BINARY(8) NULL,

    CONSTRAINT PK_STD_Cliente
        PRIMARY KEY (CustomerID)
);
GO

CREATE TABLE std.Empleado
(
    EmployeeID INT NOT NULL,

    FirstName NVARCHAR(10) NULL,
    LastName NVARCHAR(20) NULL,
    Title NVARCHAR(30) NULL,

    City NVARCHAR(15) NULL,
    Region NVARCHAR(15) NULL,
    Country NVARCHAR(15) NULL,

    ReportsTo INT NULL,

    SourceRowVersion BINARY(8) NULL,

    CONSTRAINT PK_STD_Empleado
        PRIMARY KEY (EmployeeID)
);
GO

CREATE TABLE std.Producto
(
    ProductID INT NOT NULL,

    ProductName NVARCHAR(40) NULL,
    QuantityPerUnit NVARCHAR(20) NULL,

    CategoryID INT NULL,
    CategoryName NVARCHAR(15) NULL,

    SupplierID INT NULL,
    SupplierName NVARCHAR(40) NULL,
    SupplierCountry NVARCHAR(15) NULL,

    Discontinued BIT NULL,

    ProductRowVersion BINARY(8) NULL,
    CategoryRowVersion BINARY(8) NULL,
    SupplierRowVersion BINARY(8) NULL,

    CONSTRAINT PK_STD_Producto
        PRIMARY KEY (ProductID)
);
GO



CREATE TABLE std.Transportista
(
    ShipperID INT NOT NULL,

    CompanyName NVARCHAR(40) NULL,
    Phone NVARCHAR(24) NULL,

    SourceRowVersion BINARY(8) NULL,

    CONSTRAINT PK_STD_Transportista
        PRIMARY KEY (ShipperID)
);
GO

CREATE TABLE std.Ventas
(
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,

    CustomerID NCHAR(5) NULL,
    EmployeeID INT NULL,
    ShipperID INT NULL,

    OrderDate DATETIME NULL,
    RequiredDate DATETIME NULL,
    ShippedDate DATETIME NULL,

    UnitPrice MONEY NOT NULL,
    Quantity SMALLINT NOT NULL,
    Discount REAL NOT NULL,

    OrderRowVersion BINARY(8) NULL,
    OrderDetailRowVersion BINARY(8) NULL,

    CONSTRAINT PK_STD_Ventas
        PRIMARY KEY (OrderID, ProductID)
);
GO

CREATE TABLE dbo.PackageConfig
(
    PackageName NVARCHAR(100) NOT NULL,

    LastRowVersion BINARY(8) NOT NULL
        CONSTRAINT DF_PackageConfig_RowVersion
        DEFAULT (0x0000000000000000),

    LastSuccessfulLoad DATETIME2 NULL,

    CONSTRAINT PK_PackageConfig
        PRIMARY KEY (PackageName)
);
GO
