-- Lectura solamente. Ejecutar después de la primera preparación, antes de fixtures persistentes.
SET NOCOUNT ON;
CREATE TABLE #Results (SourceDatabase sysname, TargetDatabase sysname,
    TableName nvarchar(260), SourceRows bigint, TargetRows bigint, DifferentRows bit);
DECLARE @source sysname, @target sysname;
DECLARE pairs CURSOR LOCAL FAST_FORWARD FOR
    SELECT N'NorthWind',N'Northwind_Test' UNION ALL SELECT N'Northwind_DW',N'Northwind_DW_Test';
OPEN pairs;
FETCH NEXT FROM pairs INTO @source,@target;
WHILE @@FETCH_STATUS=0
BEGIN
    DECLARE @sql nvarchar(max)=N'USE '+QUOTENAME(@source)+N';
DECLARE @schema sysname,@table sysname,@columns nvarchar(max),@batch nvarchar(max);
DECLARE tables_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT SCHEMA_NAME(schema_id),name FROM sys.tables ORDER BY schema_id,name;
OPEN tables_cursor;
FETCH NEXT FROM tables_cursor INTO @schema,@table;
WHILE @@FETCH_STATUS=0
BEGIN
    SELECT @columns=STRING_AGG(CONVERT(nvarchar(max),
        CASE WHEN TYPE_NAME(system_type_id) IN (''image'',''timestamp'')
            THEN N''CONVERT(varbinary(max),''+QUOTENAME(name)+N'') AS ''+QUOTENAME(name)
        WHEN TYPE_NAME(system_type_id) IN (''text'',''ntext'',''xml'')
            THEN N''CONVERT(nvarchar(max),''+QUOTENAME(name)+N'') AS ''+QUOTENAME(name)
        ELSE QUOTENAME(name) END),N'','') WITHIN GROUP (ORDER BY column_id)
    FROM sys.columns WHERE object_id=OBJECT_ID(QUOTENAME(@schema)+N''.''+QUOTENAME(@table));
    DECLARE @a nvarchar(800)=QUOTENAME(@source)+N''.''+QUOTENAME(@schema)+N''.''+QUOTENAME(@table),
            @b nvarchar(800)=QUOTENAME(@target)+N''.''+QUOTENAME(@schema)+N''.''+QUOTENAME(@table);
    SET @batch=N''INSERT #Results SELECT @source,@target,@schema+N''''.''''+@table,
        (SELECT COUNT_BIG(*) FROM ''+@a+N''),(SELECT COUNT_BIG(*) FROM ''+@b+N''),
        CASE WHEN EXISTS (SELECT ''+@columns+N'' FROM ''+@a+N'' EXCEPT SELECT ''+@columns+N'' FROM ''+@b+N'')
          OR EXISTS (SELECT ''+@columns+N'' FROM ''+@b+N'' EXCEPT SELECT ''+@columns+N'' FROM ''+@a+N'') THEN 1 ELSE 0 END;'';
    EXEC sys.sp_executesql @batch,N''@source sysname,@target sysname,@schema sysname,@table sysname'',@source,@target,@schema,@table;
    FETCH NEXT FROM tables_cursor INTO @schema,@table;
END;
CLOSE tables_cursor;
DEALLOCATE tables_cursor;';
    EXEC sys.sp_executesql @sql,N'@source sysname,@target sysname',@source,@target;
    DECLARE @identitySql nvarchar(max)=N'
IF EXISTS (
    SELECT t.name,c.name,CONVERT(decimal(38,0),c.seed_value),CONVERT(decimal(38,0),c.increment_value),CONVERT(decimal(38,0),c.last_value)
    FROM '+QUOTENAME(@source)+N'.sys.identity_columns c JOIN '+QUOTENAME(@source)+N'.sys.tables t ON t.object_id=c.object_id
    EXCEPT
    SELECT t.name,c.name,CONVERT(decimal(38,0),c.seed_value),CONVERT(decimal(38,0),c.increment_value),CONVERT(decimal(38,0),c.last_value)
    FROM '+QUOTENAME(@target)+N'.sys.identity_columns c JOIN '+QUOTENAME(@target)+N'.sys.tables t ON t.object_id=c.object_id
) THROW 51013,''Los contadores IDENTITY no coinciden.'',1;';
    EXEC sys.sp_executesql @identitySql;
    FETCH NEXT FROM pairs INTO @source,@target;
END;
CLOSE pairs;
DEALLOCATE pairs;
SELECT * FROM #Results ORDER BY SourceDatabase,TableName;
IF EXISTS (SELECT 1 FROM #Results WHERE SourceRows<>TargetRows OR DifferentRows<>0)
    THROW 51010,'Las copias difieren del origen actual: revisar captura; no borrar ni reiniciar.',1;
-- El EXCEPT compara también las claves y rowversions de las filas, no solo cantidades.
PRINT 'PASS: conteos y valores de todas las tablas coinciden con sus originales.';
PRINT 'PASS: semillas, incrementos y últimos valores IDENTITY conservados.';
