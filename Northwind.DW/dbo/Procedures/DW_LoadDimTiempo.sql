CREATE PROCEDURE dbo.DW_LoadDimTiempo
    @FechaInicio DATE = NULL,
    @FechaFin DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @FechaInicio IS NULL OR @FechaFin IS NULL
    BEGIN
        DECLARE @Min DATE,@Max DATE;
        SELECT @Min=MIN(Fecha),@Max=MAX(Fecha)
        FROM std.Ventas
        CROSS APPLY (VALUES(CONVERT(DATE,OrderDate)),(CONVERT(DATE,RequiredDate)),(CONVERT(DATE,ShippedDate))) d(Fecha);
        SET @FechaInicio=COALESCE(@FechaInicio,@Min);
        SET @FechaFin=COALESCE(@FechaFin,@Max);
    END;
    IF @FechaInicio IS NULL OR @FechaFin IS NULL OR @FechaInicio>@FechaFin
        THROW 52001,'Calendario: indique un rango valido o cargue fechas en std.Ventas.',1;
    IF @FechaInicio<='19000101' AND @FechaFin>='19000101'
        THROW 52002,'Calendario: 1900-01-01 esta reservada para fecha desconocida.',1;
    BEGIN TRY
        BEGIN TRANSACTION;
        ;WITH Dias AS
        (
            SELECT @FechaInicio AS Fecha
            UNION ALL SELECT DATEADD(DAY,1,Fecha) FROM Dias WHERE Fecha<@FechaFin
        )
        INSERT dbo.Dim_Tiempo(Tiempo_SK,Fecha,Dia,NombreDia,Mes,NombreMes,Trimestre,Anio)
        SELECT YEAR(Fecha)*10000+MONTH(Fecha)*100+DAY(Fecha),Fecha,DAY(Fecha),
            CHOOSE(((DATEDIFF(DAY,CONVERT(DATE,'19000101'),Fecha)%7+7)%7)+1,
                N'Lunes',N'Martes',N'Miércoles',N'Jueves',N'Viernes',N'Sábado',N'Domingo'),
            MONTH(Fecha),CHOOSE(MONTH(Fecha),N'Enero',N'Febrero',N'Marzo',N'Abril',N'Mayo',N'Junio',
                N'Julio',N'Agosto',N'Septiembre',N'Octubre',N'Noviembre',N'Diciembre'),
            DATEPART(QUARTER,Fecha),YEAR(Fecha)
        FROM Dias d WHERE NOT EXISTS
            (SELECT 1 FROM dbo.Dim_Tiempo WITH(UPDLOCK,HOLDLOCK) WHERE Fecha=d.Fecha)
        OPTION(MAXRECURSION 0);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
