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

    UnitPrice DECIMAL(19,4) NOT NULL,
    Quantity SMALLINT NOT NULL,
    Discount DECIMAL(9,6) NOT NULL,

    OrderRowVersion BINARY(8) NULL,
    OrderDetailRowVersion BINARY(8) NULL,

    CONSTRAINT PK_STD_Ventas
        PRIMARY KEY (OrderID, ProductID)
);
