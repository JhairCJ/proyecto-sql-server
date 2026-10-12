CREATE TABLE dbo.Dim_Tiempo (
    Tiempo_SK INT NOT NULL,
    Fecha DATE NOT NULL,

    Dia INT,
    NombreDia NVARCHAR(15),

    Mes INT,
    NombreMes NVARCHAR(15),

    Trimestre INT,
    Anio INT,
    CONSTRAINT PK_Dim_Tiempo PRIMARY KEY (Tiempo_SK),
    CONSTRAINT UQ_Dim_Tiempo_Fecha UNIQUE (Fecha)
);
