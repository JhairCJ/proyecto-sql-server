IF NOT EXISTS(SELECT 1 FROM dbo.Dim_Cliente WHERE Cliente_SK=0)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Cliente ON;
    INSERT dbo.Dim_Cliente(Cliente_SK,CustomerID,NombreEmpresa) VALUES(0,N'~UNK~',N'Desconocido');
    SET IDENTITY_INSERT dbo.Dim_Cliente OFF;
END;
IF NOT EXISTS(SELECT 1 FROM dbo.Dim_Empleado WHERE Empleado_SK=0)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Empleado ON;
    INSERT dbo.Dim_Empleado(Empleado_SK,EmployeeID,NombreCompleto) VALUES(0,0,N'Desconocido');
    SET IDENTITY_INSERT dbo.Dim_Empleado OFF;
END;
IF NOT EXISTS(SELECT 1 FROM dbo.Dim_Tiempo WHERE Tiempo_SK=0)
    INSERT dbo.Dim_Tiempo(Tiempo_SK,Fecha,Dia,NombreDia,Mes,NombreMes,Trimestre,Anio)
    VALUES(0,'19000101',0,N'Desconocido',0,N'Desconocido',0,0);
INSERT dbo.PackageConfig(PackageName)
SELECT PackageName FROM (VALUES(N'Cliente'),(N'Empleado'),(N'Producto'),(N'Transportista'),(N'Ventas')) p(PackageName)
WHERE NOT EXISTS(SELECT 1 FROM dbo.PackageConfig c WHERE c.PackageName=p.PackageName);
