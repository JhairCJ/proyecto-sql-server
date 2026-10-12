# 03. Preparar copias y publicar extractores

## 1. Crear copias en SSMS, solo si faltan

1. Conecta al motor `localhost` con autenticación Windows.
2. Clic derecho en `NorthWind` > **Tareas > Copia de seguridad**. Tipo **Completa**; guarda el `.bak` y pulsa **Aceptar**.
3. Clic derecho en **Bases de datos > Restaurar base de datos**. Selecciona **Dispositivo**, agrega ese `.bak` y escribe `Northwind_Test` como **Base de datos de destino**.
4. En **Archivos**, cambia las rutas de restauración de cada archivo para que usen nombres nuevos de `Northwind_Test`; no uses los archivos del original. Pulsa **Aceptar**.
5. Repite con `Northwind_DW`, restaurando como `Northwind_DW_Test` y usando archivos distintos del original.
6. En **Archivo > Abrir > Archivo**, abre `scripts/sql/Identify-NorthwindCopies.sql` y ejecuta con **F5**.

**Resultado:** ambas copias aparecen en Bases de datos y el script indica «Copias identificadas». Si ya estaban preparadas, omite la restauración.

## 2. Publicar procedimientos desde Visual Studio

1. Abre `Northwind.sln` y compila.
2. Clic derecho en `Northwind.OLTP` > **Publicar**.
3. Pulsa **Cargar perfil**, abre `Northwind.OLTP/Properties/PublishProfiles/Northwind_Test.publish.xml`.
4. Comprueba servidor `localhost` y destino `Northwind_Test`; pulsa **Generar script** para revisar el destino, luego **Publicar**.

**Resultado:** publicación correcta en la copia.

## 3. Comprobar en SSMS

En **Nueva consulta**, ejecuta con **F5**:

```sql
USE Northwind_Test;
SELECT COUNT(*) AS Clientes FROM dbo.Customers;
SELECT COUNT(*) AS Lineas FROM dbo.OrderDetails;
SELECT name FROM sys.procedures WHERE name LIKE N'%RowVersion%' ORDER BY name;
```

**Resultado de referencia:** 91 clientes, 2.155 líneas y ocho procedimientos. Continúa con [05](05-preparar-dw.md).
