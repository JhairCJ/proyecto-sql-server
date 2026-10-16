CREATE TABLE std.Producto
(
    ProductID INT NOT NULL,
    ProductName NVARCHAR(40) NULL,
    QuantityPerUnit NVARCHAR(20) NULL,
    CategoryID INT NULL,
    CategoryName NVARCHAR(15) NULL,
    CategoryDescription NVARCHAR(MAX) NULL,
    SupplierID INT NULL,
    UnitsInStock SMALLINT NULL,
    UnitsOnOrder SMALLINT NULL,
    ReorderLevel SMALLINT NULL,
    Discontinued BIT NULL,
    ProductRowVersion BINARY(8) NULL,
    CategoryRowVersion BINARY(8) NULL,
    CONSTRAINT PK_STD_Producto PRIMARY KEY (ProductID)
);
