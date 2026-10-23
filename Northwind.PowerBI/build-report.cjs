// Edita definiciones PBIR creadas por Desktop; el PBIX resultante se valida en Desktop.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const output = path.resolve(__dirname, 'Report');
const definitions = path.join(output, 'definition');
const read = p => JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
const write = (p, x) => { fs.mkdirSync(path.dirname(p), {recursive:true}); fs.writeFileSync(p, JSON.stringify(x,null,2)); };
const id = label => crypto.createHash('sha256').update(label).digest('hex').slice(0,20);
const literal = x => ({expr:{Literal:{Value:typeof x==='string'?"'"+x.replaceAll("'","''")+"'":typeof x==='boolean'?String(x):String(x)+(Number.isInteger(x)?'D':'')}}});
const color = c => ({solid:{color:literal(c)}});
const obj = properties => [{properties}];
const col = (entity, property) => ({Column:{Expression:{SourceRef:{Entity:entity}},Property:property}});
const measures = read(path.join(__dirname,'medidas-informe.json'));
for(const [name, entity, prop] of [['Rango producto','DimProduct','ProductName'],['Rango cliente','DimCustomer','CompanyName']]){
 if(!measures.some(m=>m.name===name))measures.push({name,formatString:'0',expression:`IF(NOT ISBLANK([Ventas netas]), RANKX(ALLSELECTED(${entity}[${prop}]), [Ventas netas], , DESC, DENSE))`});
}
write(path.join(__dirname,'medidas-informe.json'),measures);
const local = new Set(measures.map(m=>m.name));
const measure = name => ({Measure:{Expression:{SourceRef:local.has(name)?{Schema:'extension',Entity:'DimCustomer'}:{Entity:'FactSales'}},Property:name}});
const projection = (field,label) => {const x=field.Measure||field.Column;const format=field.Measure?(local.has(x.Property)?measures.find(m=>m.name===x.Property).formatString:['Unidades','Pedidos distintos','Pedidos sin flete informado'].includes(x.Property)?'#,0':x.Property==='Flete total'?'#,0.0000':'#,0.00'):undefined;return {field,...(format?{format}:{}),queryRef:x.Expression.SourceRef.Entity+'.'+x.Property,nativeQueryRef:x.Property,...(label?{displayName:label}:{})};};
const pages=['Resumen comercial','Productos y clientes','Logística'].map(displayName=>({name:id(displayName),displayName,visuals:[]}));
let z=0;
function visual(page,label,type,x,y,width,height,queryState,objects={}){
 const v={$schema:'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.4.0/schema.json',name:id(page.name+label),position:{x,y,z:z++,width,height,tabOrder:z},visual:{visualType:type,...(queryState?{query:{queryState}}:{}),objects,visualContainerObjects:{title:obj({show:literal(true),text:literal(label),fontColor:color('#213F3B'),fontSize:literal(12),bold:literal(true),fontFamily:literal('Segoe UI')}),background:obj({show:literal(true),color:color('#FFFFFF'),transparency:literal(0)}),border:obj({show:literal(false)})},drillFilterOtherVisuals:true}};
 page.visuals.push(v);return v;
}
function text(page,label,content,x,y,w,h,size=16,ink='#213F3B',fill='#F4F5F0'){
 const v=visual(page,label,'textbox',x,y,w,h,null,{general:obj({paragraphs:[{textRuns:[{value:content,textStyle:{fontFamily:'Segoe UI',fontSize:size+'pt',color:ink}}]}]})});
 v.visual.visualContainerObjects.title=obj({show:literal(false)});v.visual.visualContainerObjects.background=obj({show:literal(true),color:color(fill),transparency:literal(0)});return v;
}
function card(page,label,m,x,y,w=286,h=110,precision=2){
 const insight=m.startsWith('Insight');const format=insight?'':m==='Descuento porcentual'?'0.00%':precision===0?'#,0':'#,0.00';
 const v=visual(page,label,'cardVisual',x,y,w,h,{Data:{projections:[{...projection(measure(m)),...(format?{format}:{})}]}},{value:obj({fontColor:color('#173F38'),fontSize:literal(insight?12:27),labelDisplayUnits:literal(1),labelPrecision:literal(insight?0:m==='Descuento porcentual'?2:precision),textWrap:literal(true),...(format?{customFormatString:literal(format)}:{})}),label:obj({show:literal(false)}),padding:obj({paddingUniform:literal(insight?2:8),paddingIndividual:literal(false)}),layout:obj({paddingUniform:literal(0),cellPadding:literal(0)})});
 for(const key of ['value','label','padding','layout'])v.visual.objects[key][0].selector={id:'default'}; if(insight)v.visual.visualContainerObjects.title=obj({show:literal(false)});return v;
}
function slicer(page,label,e,p,x,y,w,group){const v=visual(page,label,'slicer',x,y,w,80,{Values:{projections:[projection(col(e,p),label)]}},{data:obj({mode:literal('Dropdown')}),selection:obj({singleSelect:literal(false),selectAllCheckboxEnabled:literal(true)})});if(group)v.visual.syncGroup={groupName:group,fieldChanges:true,filterChanges:true};return v;}
function bars(page,label,e,p,m,x,y,w,h){const f=measure(m);const v=visual(page,label,'clusteredBarChart',x,y,w,h,{Category:{projections:[projection(col(e,p))]},Y:{projections:[projection(f)]}},{dataPoint:obj({defaultColor:color('#237C68')}),categoryAxis:obj({fontSize:literal(10),showAxisTitle:literal(false)}),valueAxis:obj({fontSize:literal(10),showAxisTitle:literal(false),labelDisplayUnits:literal(1)}),labels:obj({show:literal(true),labelDisplayUnits:literal(0),labelPrecision:literal(0),fontSize:literal(10)})});v.visual.query.sortDefinition={sort:[{field:f,direction:'Descending'}]};return v;}
function rankFilter(v,name){v.filterConfig={filters:[{name:id(v.name+'rank'),field:measure(name),type:'Advanced',filter:{Version:2,From:[{Name:'r',Entity:'DimCustomer',Schema:'extension',Type:0}],Where:[{Condition:{Comparison:{ComparisonKind:4,Left:{Measure:{Expression:{SourceRef:{Source:'r'}},Property:name}},Right:{Literal:{Value:'10L'}}}}}]}}]};}
function table(page,label,fields,x,y,w,h){return visual(page,label,'tableEx',x,y,w,h,{Values:{projections:fields.map(([f,l])=>projection(f,l))}},{grid:obj({gridVertical:literal(false),gridHorizontal:literal(true),rowPadding:literal(5)}),columnHeaders:obj({fontSize:literal(10),fontColor:color('#213F3B'),backColor:color('#E8EEE7')}),values:obj({fontSize:literal(10)}),total:obj({totals:literal(false)})});}
function action(page,label,x,target,bookmark=false){
 const v=visual(page,label,'actionButton',x,34,172,38,null,{text:[{selector:{id:'default'},properties:{show:literal(true),text:literal(label),fontFamily:literal('Segoe UI'),fontSize:literal(10),fontColor:color('#FFFFFF')}}],fill:[{selector:{id:'default'},properties:{show:literal(true),fillColor:color('#173F38'),transparency:literal(0)}}],icon:[{selector:{id:'default'},properties:{show:literal(false)}}],outline:[{selector:{id:'default'},properties:{show:literal(false)}}]});
 v.visual.objects.text.push({properties:{show:literal(true)}});v.visual.visualContainerObjects.title=obj({show:literal(false)});v.visual.visualContainerObjects.visualLink=obj({show:literal(true),type:literal(bookmark?'Bookmark':'PageNavigation'),[bookmark?'bookmark':'navigationSection']:literal(target)});return v;
}
const reset=id('Restablecer filtros');
for(const page of pages){
 text(page,'Marca','NORTHWIND  /  ANÁLISIS DE VENTAS',32,9,600,24,10,'#55706A');
 text(page,'Título',page.displayName,32,36,640,50,26);
 action(page,'Resumen',830,pages[0].name);action(page,'Productos y clientes',1006,pages[1].name);action(page,'Logística',1182,pages[2].name);action(page,'Restablecer',1358,reset,true);
 slicer(page,'Año del pedido','DimDate','YearNumber',32,110,220,'NorthwindAño');
 slicer(page,'Categoría','DimProduct','CategoryName',268,110,380,'NorthwindCategoria');
 slicer(page,'Cliente','DimCustomer','CompanyName',664,110,570,'NorthwindCliente');
 text(page,'Nota de fecha','Fecha de pedido · todos los períodos disponibles',32,846,900,30,10,'#60736D');
 text(page,'Nota de moneda','Importes sin moneda atribuida',1200,846,368,30,10,'#60736D');
}
const p=pages[0];
[['Ventas netas','Ventas netas',2],['Pedidos distintos','Pedidos distintos',0],['Unidades','Unidades',0],['Ticket promedio','Ticket promedio',2],['Descuento sobre bruto','Descuento porcentual',4]].forEach(([l,m,d],i)=>card(p,l,m,32+i*308,218,292,120,d));
const trend=visual(p,'Ventas netas por año y mes','lineChart',32,364,914,348,{Category:{projections:[{...projection(col('DimDate','YearNumber'),'Año'),active:true},{...projection(col('DimDate','MonthNumber'),'Mes'),active:true}]},Y:{projections:[projection(measure('Ventas netas'))]}},{dataPoint:obj({defaultColor:color('#237C68')}),categoryAxis:obj({axisType:literal('Categorical'),concatenateLabels:literal(false),fontSize:literal(10)}),valueAxis:obj({labelDisplayUnits:literal(0),fontSize:literal(10)})});
trend.visual.query.sortDefinition={sort:[{field:col('DimDate','YearNumber'),direction:'Ascending'},{field:col('DimDate','MonthNumber'),direction:'Ascending'}]};
trend.visual.expansionStates=[{roles:['Category'],levels:[{queryRefs:['DimDate.YearNumber'],isCollapsed:false},{queryRefs:['DimDate.MonthNumber'],isCollapsed:false}],root:{isToggled:true}}];
bars(p,'Ventas netas por categoría','DimProduct','CategoryName','Ventas netas',970,364,598,348);
card(p,'Categoría líder en la selección','Insight comercial',32,732,1536,46,0);card(p,'Ticket y descuentos de la selección','Insight de ticket y descuento',32,788,1536,44,0);
const q=pages[1];
slicer(q,'Proveedor actual','DimSupplier','CompanyName',1250,110,318);
const products=bars(q,'Top 10 productos · ventas netas','DimProduct','ProductName','Ventas netas',32,218,752,280);rankFilter(products,'Rango producto');
const customers=bars(q,'Top 10 clientes · ventas netas','DimCustomer','CompanyName','Ventas netas',808,218,760,280);rankFilter(customers,'Rango cliente');
bars(q,'Participación por categoría','DimProduct','CategoryName','Participación de categoría',32,520,490,260);
bars(q,'Ventas por país del cliente','DimCustomer','Country','Ventas netas',546,520,490,260);
table(q,'Detalle de productos de la selección',[[col('DimProduct','ProductName'),'Producto'],[measure('Ventas netas'),'Neto'],[measure('Unidades'),'Unidades']],1060,520,508,260);
card(q,'Categoría líder de la selección','Insight comercial',32,775,1536,42,0);
text(q,'Alcance del proveedor','Proveedor actual del producto; no representa el proveedor histórico. País del cliente ≠ país de envío.',32,817,1536,24,10);
const l=pages[2];
slicer(l,'Pedido','FactSales','OrderID',32,342,330);
text(l,'Selección de pedido','Selecciona un pedido para contrastar sus líneas y su flete.',385,366,1183,44,11);
slicer(l,'Transportista','DimShipper','CompanyName',1250,110,318);
[['Flete por pedidos visibles','Flete total',2],['Promedio por pedido informado','Flete promedio informado',2],['Pedidos sin flete','Pedidos sin flete informado',0],['Pedidos sin fecha de envío','Pedidos sin fecha de envío',0]].forEach(([a,b,d],i)=>card(l,a,b,32+i*390,218,366,120,d));
bars(l,'Flete por transportista','DimShipper','CompanyName','Flete total',32,424,492,198);
bars(l,'Flete por país de envío','DimGeography','ShipCountry','Flete total',548,424,492,198);
table(l,'Destinos de envío',[[col('DimGeography','ShipCountry'),'País de envío'],[col('DimGeography','ShipCity'),'Ciudad de envío'],[measure('Pedidos distintos'),'Pedidos'],[measure('Flete total'),'Flete']],1064,424,504,198);
table(l,'Detalle por pedido',[[col('FactSales','OrderID'),'Pedido'],[measure('Pedidos distintos'),'Pedidos'],[measure('Líneas de pedido'),'Líneas'],[measure('Unidades'),'Unidades'],[measure('Ventas netas'),'Neto'],[measure('Flete total'),'Flete del pedido']],32,642,1008,182);
card(l,'Observación logística','Insight logístico',1064,642,504,106,0);
text(l,'Alcance del flete','El flete se cuenta una vez por pedido. Los subtotales por producto o proveedor pueden solaparse; no son un reparto de costos.',1064,756,504,70,10);
const report=read(path.join(definitions,'report.json'));
const extension={...{$schema:'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/reportExtension/1.0.0/schema.json',name:'extension'},entities:[{name:'DimCustomer',measures:measures.map(m=>({name:m.name,dataType:m.name.startsWith('Insight')?'Text':'Double',expression:m.expression,formatString:m.formatString,references:{measures:[...new Set([...m.expression.matchAll(/\[([^\]]+)\]/g)].map(x=>x[1]).filter(n=>local.has(n)||['Ventas netas','Pedidos distintos','Unidades','Flete total','Pedidos sin flete informado','Descuentos aplicados','Ventas brutas'].includes(n)))].map(name=>({entity:local.has(name)?'DimCustomer':'FactSales',name,...(local.has(name)?{schema:'extension'}:{})}))}}))}]};
write(path.join(definitions,'version.json'),read(path.join(definitions,'version.json')));
write(path.join(definitions,'report.json'),report);write(path.join(definitions,'reportExtensions.json'),extension);
write(path.join(definitions,'pages/pages.json'),{$schema:'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.1.0/schema.json',pageOrder:pages.map(p=>p.name),activePageName:pages[0].name});
const sections={};
for(const page of pages){
 write(path.join(definitions,'pages',page.name,'page.json'),{$schema:'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json',name:page.name,displayName:page.displayName,displayOption:'FitToPage',width:1600,height:900,objects:{background:obj({color:color('#F4F5F0'),transparency:literal(0)})}});
 const visualContainers={};
 for(const v of page.visuals){write(path.join(definitions,'pages',page.name,'visuals',v.name,'visual.json'),v); visualContainers[v.name]={filters:{byName:Object.fromEntries((v.filterConfig?.filters||[]).map(f=>[f.name,{name:f.name,type:f.type,expression:f.field,filter:f.filter}]))},singleVisual:{objects:{},...(v.visual.expansionStates?{expansionStates:v.visual.expansionStates}:{}),...(v.visual.query?{activeProjections:Object.fromEntries(Object.entries(v.visual.query.queryState).map(([k,r])=>[k,r.projections.map(p=>p.field)])),...(v.visual.query.sortDefinition?{orderBy:v.visual.query.sortDefinition.sort.map(q=>({Expression:q.field,Direction:q.direction==='Descending'?2:1}))}:{})}:{})}};}
 sections[page.name]={visualContainers};
}
write(path.join(definitions,'bookmarks',reset+'.bookmark.json'),{$schema:'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.0.0/schema.json',name:reset,displayName:'Restablecer filtros',options:{suppressDisplay:true,suppressActiveSection:true},explorationState:{version:'1.3',activeSection:pages[0].name,filters:{byName:{}},sections}});
write(path.join(definitions,'bookmarks/bookmarks.json'),{$schema:'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmarksMetadata/1.0.0/schema.json',items:[{name:reset}]});
console.log(JSON.stringify({pages:pages.map(p=>({name:p.displayName,visuals:p.visuals.length})),measures:measures.length}));
