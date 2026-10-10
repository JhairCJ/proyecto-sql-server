-- Ejecutar en SQL Server los 1. y 2.
-- 1.Crear la nueva base de datos para el Data Warehouse
CREATE DATABASE Northwind_DW;
GO

-- 2. Usar la base de datos recién creada
USE Northwind_DW;
GO

-- =======================================================
-- ETAPA 1: CREACIÓN DE LAS TABLAS DE DIMENSIONES
-- =======================================================

-- Dimensión Cliente
CREATE TABLE Dim_Cliente (
    Cliente_SK INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID NCHAR(5) NOT NULL,

    NombreEmpresa NVARCHAR(40),
    NombreContacto NVARCHAR(30),
    TituloContacto NVARCHAR(30),

    Ciudad NVARCHAR(15),
    Region NVARCHAR(15),
    CodigoPostal NVARCHAR(10),
    Pais NVARCHAR(15)
);
GO

-- Dimensión Empleado
CREATE TABLE Dim_Empleado (
    Empleado_SK INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID INT NOT NULL,

    NombreCompleto NVARCHAR(60),
    Titulo NVARCHAR(30),

    Ciudad NVARCHAR(15),
    Region NVARCHAR(15),
    Pais NVARCHAR(15),

    ReportsTo INT,
    NombreSupervisor NVARCHAR(60)
);
GO

-- Dimensión Producto
CREATE TABLE Dim_Producto (
    Producto_SK INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL,

    NombreProducto NVARCHAR(40),
    CantidadPorUnidad NVARCHAR(20),

    CategoryID INT,
    Categoria NVARCHAR(15),

    SupplierID INT,
    Proveedor NVARCHAR(40),
    PaisProveedor NVARCHAR(15),

    Descontinuado BIT
);
GO
-- Dimensión Tiempo
CREATE TABLE Dim_Tiempo (
    Tiempo_SK INT PRIMARY KEY,
    Fecha DATE NOT NULL,

    Dia INT,
    NombreDia NVARCHAR(15),

    Mes INT,
    NombreMes NVARCHAR(15),

    Trimestre INT,
    Anio INT
);
GO

CREATE TABLE Dim_Transportista (
    Transportista_SK INT IDENTITY(1,1) PRIMARY KEY,
    ShipperID INT NOT NULL,

    NombreEmpresa NVARCHAR(40),
    Telefono NVARCHAR(24)
);
GO