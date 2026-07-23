# Windows Cleanup Pro

Herramienta de mantenimiento para Windows orientada a soporte TI, estaciones corporativas y uso personal. Limpia archivos temporales y caches de forma segura, auditable y configurable.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4?logo=windows)](https://www.microsoft.com/windows)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Características

- Tres niveles de limpieza: `Quick`, `Standard` y `Deep`.
- Simulación segura mediante `-WhatIf`.
- Confirmación de operaciones de alto impacto con `-Confirm`.
- Limpieza de caches de Chrome, Edge y Firefox por perfil.
- Protección explícita de rutas críticas.
- Papelera excluida por defecto y disponible solo bajo petición.
- Detención y restauración controlada de servicios de Windows.
- Limpieza opcional del almacén de componentes con DISM.
- Logs legibles y reporte JSON para inventario, soporte o RMM.
- Compatible con Windows PowerShell 5.1 y PowerShell 7.

El script **no elimina** documentos, descargas, perfiles, archivos de OneDrive ni datos de navegación como contraseñas, marcadores o historial.

## Modos

| Modo | Alcance | Administrador |
|---|---|---|
| `Quick` | Temporales del usuario, shaders y miniaturas | No |
| `Standard` | Quick + temporales del sistema, crash dumps y caches de navegadores | Recomendado |
| `Deep` | Standard + Windows Update, Delivery Optimization y DISM | Sí |

## Uso rápido

Descarga `LimpiezaWindows.ps1`, abre PowerShell en su carpeta y comienza con una simulación:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\LimpiezaWindows.ps1 -Mode Standard -WhatIf
```

Cuando hayas revisado las acciones propuestas:

```powershell
.\LimpiezaWindows.ps1 -Mode Standard
```

Limpieza profunda con confirmación:

```powershell
.\LimpiezaWindows.ps1 -Mode Deep -IncludeRecycleBin -Confirm
```

Cerrar navegadores para conseguir una limpieza más completa:

```powershell
.\LimpiezaWindows.ps1 -Mode Standard -CloseBrowsers
```

Usar una carpeta personalizada para los reportes:

```powershell
.\LimpiezaWindows.ps1 -LogDirectory 'C:\Logs\WindowsCleanup'
```

## Parámetros

| Parámetro | Descripción | Valor predeterminado |
|---|---|---|
| `-Mode` | `Quick`, `Standard` o `Deep` | `Standard` |
| `-IncludeRecycleBin` | Vacía la papelera | Desactivado |
| `-CloseBrowsers` | Cierra Chrome, Edge y Firefox antes de limpiar | Desactivado |
| `-LogDirectory` | Carpeta de logs y reportes JSON | `C:\ProgramData\WindowsCleanupPro` |
| `-WhatIf` | Muestra lo que se haría sin eliminar archivos | Desactivado |
| `-Confirm` | Solicita confirmación antes de cada operación | Desactivado |

## Salida y auditoría

Cada ejecución crea dos archivos:

- `Cleanup_YYYYMMDD_HHMMSS.log`: detalle cronológico de operaciones.
- `Cleanup_YYYYMMDD_HHMMSS.json`: métricas estructuradas, espacio recuperado, errores y duración.

Código de salida:

- `0`: ejecución completada sin errores.
- `1`: una o más operaciones finalizaron con error.

## Recomendaciones para empresas

- Ejecuta primero con `-WhatIf` en un grupo piloto.
- Firma el script con un certificado de confianza antes de distribuirlo.
- Usa `Standard` para mantenimiento periódico y reserva `Deep` para ventanas de soporte.
- Distribúyelo mediante Intune, RMM, GPO o una tarea programada con una política de logs centralizada.
- No uses `-CloseBrowsers` sin avisar previamente al usuario.

## Seguridad

La eliminación se limita al contenido de carpetas de cache conocidas. Las rutas raíz, el perfil del usuario, Windows y Program Files están protegidos contra una eliminación accidental. Los archivos bloqueados se omiten y quedan registrados.

Revisa siempre el código antes de ejecutar scripts con privilegios elevados.

## Compatibilidad

- Windows 10 y Windows 11.
- Windows Server 2016, 2019, 2022 y versiones posteriores compatibles.
- Windows PowerShell 5.1 o PowerShell 7.

## Licencia

Distribuido bajo la licencia MIT. Consulta [LICENSE](LICENSE).
