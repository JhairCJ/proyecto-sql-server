# Evidencias locales

Los subdirectorios `segmento-01/`, `segmento-02/`, etc. contienen capturas de ejecución del equipo que realiza las pruebas. **No se suben a Git**: pueden incluir rutas absolutas, cuentas Windows, identificadores y metadatos de bases.

El resumen compartido está en [validacion.md](../validacion.md). Sus referencias a archivos de evidencia describen resultados ejecutados localmente; un clon nuevo no incluirá esos archivos. Ejecutar las herramientas de prueba genera evidencia propia y no convierte los resultados de otra computadora en resultados locales.

`tests/Prepare-TestDatabases.ps1` escribe registros de preparación. Para guardar resultados de aislamiento, desde la raíz del repositorio puedes ejecutar:

```powershell
& '.\tests\Test-Isolation.ps1' | Tee-Object '.\docs\evidencias\segmento-02\aislamiento.txt'
```

La comparación `tests/Verify-TestCopies.sql` debe ejecutarse inmediatamente después de crear copias y antes de modificar fixtures, según la [guía de pruebas aisladas](../referencias/pruebas-aisladas.md).
