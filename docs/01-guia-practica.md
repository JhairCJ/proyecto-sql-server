# 01. Ejecutar el proyecto

## 1. Abrir y compilar

En Visual Studio: **Archivo > Abrir > Proyecto o solución**, selecciona `Northwind.sln`. Después **Compilar > Recompilar solución**.

**Resultado:** cuatro proyectos correctos y cero errores. Si falta alguno, sigue [02](02-entorno.md).

## 2. Preparar las bases, solo una vez

Sigue [03. Copias y extractores](03-pruebas-aisladas.md) y [05. Preparar DW](05-preparar-dw.md). Si ya tienes las copias publicadas y cargadas, omite este paso.

## 3. Cargar y comprobar

Ejecuta `CargarNorthwind.dtsx` desde Visual Studio siguiendo [07](07-ejecutar-ssis.md). Comprueba las ventas en SSMS con [06](06-cargar-datos.md).

**Resultado:** 2.155 líneas, 830 pedidos, 51.317 unidades y neto 1.265.792,76 con los datos originales de Northwind.

## 4. Publicar y consultar

Sigue [08. Publicar SSIS](08-publicar-ssis.md) y [09. Publicar y consultar OLAP](09-procesar-y-consultar-olap.md).

**Resultado:** paquete disponible en SSISDB y consultas DAX con los mismos totales.

## 5. Ejecutar el ciclo completo

Sigue [10. Ejecutar el job](10-ejecutar-job.md).

**Resultado:** carga y procesamiento correctos en el historial. Habilita el horario solo después de comprobar la ejecución manual.
