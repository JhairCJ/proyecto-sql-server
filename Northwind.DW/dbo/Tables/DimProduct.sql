CREATE TABLE dbo.DimProduct
(
    ProductKey INT IDENTITY(1,1) NOT NULL,
    ProductID INT NOT NULL,
    ProductName NVARCHAR(40) NOT NULL,
    CategoryID INT NULL,
    CategoryName NVARCHAR(15) NULL,
    CategoryDescription NVARCHAR(MAX) NULL,
    QuantityPerUnit NVARCHAR(20) NULL,
    UnitsInStock SMALLINT NULL,
    UnitsOnOrder SMALLINT NULL,
    ReorderLevel SMALLINT NULL,
    Discontinued BIT NOT NULL,
    CONSTRAINT PK_DimProduct PRIMARY KEY (ProductKey),
    CONSTRAINT UQ_DimProduct_ProductID UNIQUE (ProductID),
    CONSTRAINT CK_DimProduct_UnitsInStock CHECK (UnitsInStock IS NULL OR UnitsInStock>=0),
    CONSTRAINT CK_DimProduct_UnitsOnOrder CHECK (UnitsOnOrder IS NULL OR UnitsOnOrder>=0),
    CONSTRAINT CK_DimProduct_ReorderLevel CHECK (ReorderLevel IS NULL OR ReorderLevel>=0)
);
