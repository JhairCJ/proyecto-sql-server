# Práctica SQL Server — Northwind

Rama `northwind`: proyecto OLTP existente, guía desde cero y herramientas de pruebas aisladas. Se completaron **4 de 41 tareas** del plan; la carga ETL, el modelo analítico y el job todavía están en desarrollo.

## Descargar y empezar

```powershell
git clone --branch northwind https://github.com/JhairCJ/practica-1-sql-server.git
Set-Location -LiteralPath '.\practica-1-sql-server'
```

Si ya tienes el repositorio, actualiza las referencias y cambia a `northwind` conservando antes cualquier trabajo local pendiente.

1. Lee la [guía inicial](docs/guia-practica.md) y el [entorno comprobado](docs/entorno.md). La configuración observada usa SQL Server 2025 Developer, Visual Studio 2026/SSDT y SSMS 22.
2. Abre `Northwind.slnx` desde la carpeta donde clonaste el repositorio. En las guías, `C:\Proyectos\practica-1-sql-server` es **una ruta de ejemplo**: reemplázala por tu carpeta real. Las versiones y permisos documentados corresponden al equipo donde se validó, no certifican tu instalación.
3. Para trabajar con pruebas necesitas primero las bases locales `NorthWind` y `Northwind_DW` preparadas en tu motor. Clonar el repositorio no las crea. `Files/NorthWind.bak` es material existente del proyecto; la inicialización y el despliegue completo en una computadora nueva se terminarán en las siguientes etapas.
4. Si vas a desarrollar o ejecutar fixtures y ya tienes esas bases, sigue la [guía de pruebas aisladas](docs/pruebas-aisladas.md). Ejecuta `tests/Prepare-TestDatabases.ps1` desde esta carpeta: crea `Northwind_Test` y `Northwind_DW_Test` en tu computadora y reutiliza las copias marcadas en ejecuciones posteriores.

Las bases de prueba son permanentes y separadas de las originales. Las escrituras de fixtures deben ejecutarse con `Northwind.TestTools.psm1`; sus guardas restringen los destinos. Las consultas manuales en SSMS con una cuenta administradora conservan los permisos de esa cuenta.

## Qué contiene esta rama

- `Northwind.OLTP/` y `Northwind.slnx`: proyecto SQL y scripts existentes.
- `tests/`: preparación, comparación de copias y pruebas de aislamiento.
- `docs/`: conceptos, pasos en programas, entorno y [resumen de validación](docs/validacion.md).
- `docs/planificacion/`: copia compartida de propuesta, diseño, requisitos y checklist.

Las guías y resultados resumidos se versionan para que el equipo pueda reproducir y revisar el trabajo. Las [evidencias crudas](docs/evidencias/README.md) se generan localmente y quedan excluidas de Git, junto con caches y resultados de compilación.

La organización prevista sigue las responsabilidades OLTP/DW/staging/ETL/OLAP/job del [repositorio BikeStores de referencia](https://github.com/mclaure/Data-Management-and-BI), adaptadas al negocio Northwind.
