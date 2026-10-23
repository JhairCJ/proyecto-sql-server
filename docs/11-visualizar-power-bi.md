# 11. Visualizar Power BI

## 1. Abrir

1. Inicia SQL Server Analysis Services y comprueba en SSMS que `localhost > Databases > NorthwindOLAP > Model` esté procesado.
2. Abre Power BI Desktop y selecciona **Archivo > Abrir > Examinar**: `Northwind.PowerBI/Northwind.pbix`. Versión comprobada: **2.159.883.0**.
3. Si aparece el diálogo de credenciales, usa tu identidad Windows con lectura del modelo y pulsa **Connect**. Si falta acceso, pide al administrador del modelo un rol con permiso **Read** para tu cuenta; no basta un rol de procesamiento.

**Resultado:** conexión en vivo y páginas **Resumen comercial**, **Productos y clientes** y **Logística**. Sin filtros: 1.265.792,76 netos, 830 pedidos, 51.317 unidades, ticket 1.525,05 y descuento 6,55 %. La configuración regional puede mostrar punto decimal y coma de miles.

## 2. Filtrar y restablecer

1. Selecciona **Año del pedido = 1996** y **Categoría = Beverages**: neto **47.919,00**.
2. Cambia de página mediante las pestañas inferiores; conserva año, categoría y cliente.
3. Selecciona **Restablecer** y pulsa **Ctrl+Enter**, o usa **Ctrl+clic**: vuelve a todos los datos. Los botones superiores de navegación también requieren Ctrl+clic en Desktop.
4. En **Logística**, selecciona **Pedido = 10248**: un pedido, tres líneas, 27 unidades, neto 440,00 y flete 32,3800.

## 3. Crear una copia y configurar otro destino

1. Abre `Northwind.PowerBI/Northwind.pbit` desde Desktop; espera a que aparezcan las tres páginas.
2. En **Home / Inicio**, abre la **flecha** de **Transform data > Data source settings**. En el diálogo **SQL Server Analysis Services database**, revisa **Server** y **Database**. Destino principal: `localhost` y `NorthwindOLAP`.
3. Para una copia con otro modelo compatible, escribe su servidor y base, pulsa **Tab > OK**, selecciona **Model > OK** en **Navigator**, y comprueba nuevamente el destino en **Data source settings** antes de guardarla.
4. Usa **F12** para guardar un PBIX con otro nombre. Conserva el archivo principal conectado a `NorthwindOLAP`.

## 4. Actualizar

1. Ejecuta la carga y el procesamiento siguiendo [10. Ejecutar job](10-ejecutar-job.md).
2. En Desktop pulsa **Home > Refresh** y comprueba las tarjetas. Actualizar el informe consulta SSAS; el procesamiento se realiza en el paso anterior.
