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
