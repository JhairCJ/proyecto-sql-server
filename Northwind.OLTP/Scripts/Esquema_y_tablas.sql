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

--Danitza has el 12 y 14
