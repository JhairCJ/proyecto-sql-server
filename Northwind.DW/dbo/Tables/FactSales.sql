CREATE TABLE dbo.FactSales
(
    SalesKey BIGINT IDENTITY(1,1) NOT NULL,
    OrderID INT NOT NULL,
    OrderDateKey INT NOT NULL,
    RequiredDateKey INT NULL,
    ShippedDateKey INT NULL,
    ProductKey INT NOT NULL,
    CustomerKey INT NOT NULL,
    EmployeeKey INT NOT NULL,
    ShipperKey INT NOT NULL,
    SupplierKey INT NOT NULL,
    GeographyKey INT NOT NULL,
    Quantity SMALLINT NOT NULL,
    UnitPrice DECIMAL(19,4) NOT NULL,
    Discount DECIMAL(9,6) NOT NULL,
    Freight DECIMAL(19,4) NULL,
    GrossAmount DECIMAL(19,2) NOT NULL,
    DiscountAmount DECIMAL(19,2) NOT NULL,
    NetAmount DECIMAL(19,2) NOT NULL,
    CONSTRAINT PK_FactSales PRIMARY KEY (SalesKey),
    CONSTRAINT UQ_FactSales_Order_Product UNIQUE (OrderID, ProductKey),
    CONSTRAINT CK_FactSales_Quantity CHECK (Quantity>0),
    CONSTRAINT CK_FactSales_UnitPrice CHECK (UnitPrice>=0),
    CONSTRAINT CK_FactSales_Discount CHECK (Discount>=0 AND Discount<=1),
    CONSTRAINT CK_FactSales_Amounts CHECK
        (GrossAmount>=0 AND DiscountAmount>=0 AND NetAmount>=0
         AND GrossAmount-DiscountAmount=NetAmount),
    CONSTRAINT FK_FactSales_DimDate_Order
        FOREIGN KEY (OrderDateKey) REFERENCES dbo.DimDate(DateKey),
    CONSTRAINT FK_FactSales_DimDate_Required
        FOREIGN KEY (RequiredDateKey) REFERENCES dbo.DimDate(DateKey),
    CONSTRAINT FK_FactSales_DimDate_Shipped
        FOREIGN KEY (ShippedDateKey) REFERENCES dbo.DimDate(DateKey),
    CONSTRAINT FK_FactSales_DimProduct
        FOREIGN KEY (ProductKey) REFERENCES dbo.DimProduct(ProductKey),
    CONSTRAINT FK_FactSales_DimCustomer
        FOREIGN KEY (CustomerKey) REFERENCES dbo.DimCustomer(CustomerKey),
    CONSTRAINT FK_FactSales_DimEmployee
        FOREIGN KEY (EmployeeKey) REFERENCES dbo.DimEmployee(EmployeeKey),
    CONSTRAINT FK_FactSales_DimShipper
        FOREIGN KEY (ShipperKey) REFERENCES dbo.DimShipper(ShipperKey),
    CONSTRAINT FK_FactSales_DimSupplier
        FOREIGN KEY (SupplierKey) REFERENCES dbo.DimSupplier(SupplierKey),
    CONSTRAINT FK_FactSales_DimGeography
        FOREIGN KEY (GeographyKey) REFERENCES dbo.DimGeography(GeographyKey)
);
GO
CREATE INDEX IX_FactSales_OrderDateKey ON dbo.FactSales(OrderDateKey);
GO
CREATE INDEX IX_FactSales_RequiredDateKey ON dbo.FactSales(RequiredDateKey);
GO
CREATE INDEX IX_FactSales_ShippedDateKey ON dbo.FactSales(ShippedDateKey);
GO
CREATE INDEX IX_FactSales_ProductKey ON dbo.FactSales(ProductKey);
GO
CREATE INDEX IX_FactSales_CustomerKey ON dbo.FactSales(CustomerKey);
GO
CREATE INDEX IX_FactSales_EmployeeKey ON dbo.FactSales(EmployeeKey);
GO
CREATE INDEX IX_FactSales_ShipperKey ON dbo.FactSales(ShipperKey);
GO
CREATE INDEX IX_FactSales_SupplierKey ON dbo.FactSales(SupplierKey);
GO
CREATE INDEX IX_FactSales_GeographyKey ON dbo.FactSales(GeographyKey);
