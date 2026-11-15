# W11 Pro Debloat

Script de PowerShell para dejar limpia una instalación nueva de **Windows 11**: quita apps basura, telemetría, IA (Copilot, Recall…), anuncios y la obligación de usar cuenta Microsoft, y te ofrece instalar tus programas de siempre en un par de pulsaciones.

**Se actualiza solo**: cada vez que arranca compara su versión con la de este repositorio y, si hay una más nueva, se reemplaza y se reinicia.

> ⚠️ Úsalo bajo tu responsabilidad. El script crea un punto de restauración antes de aplicar cambios, pero lo ideal es probarlo primero en una máquina virtual o en una instalación recién hecha.

---

## Índice

- [Uso rápido](#uso-rápido)
- [Menú principal](#menú-principal)
- [Categorías de debloat](#categorías-de-debloat)
- [Instalador de software](#instalador-de-software)
- [Cuenta local y autounattend.xml](#cuenta-local-y-autounattendxml)
- [Reaplicar automáticamente](#reaplicar-automáticamente)
- [Autoactualización](#autoactualización)
- [Parámetros](#parámetros)
- [Archivos y registros](#archivos-y-registros)
- [Cómo deshacer cambios](#cómo-deshacer-cambios)
- [Qué NO hace](#qué-no-hace)
- [Publicar una versión nueva](#publicar-una-versión-nueva)
- [Preguntas frecuentes](#preguntas-frecuentes)

---

## Uso rápido

Elige una de estas tres formas:

**1. Una línea (la más cómoda)** — abre *Terminal* o *PowerShell* y pega:

```powershell
irm https://raw.githubusercontent.com/hombrelobo2/w11prodebloat/main/install.ps1 | iex
```

Descarga la última versión a `C:\ProgramData\W11Debloat` y la abre como administrador.

**2. Con el .bat** — descarga [`Ejecutar.bat`](https://github.com/hombrelobo2/w11prodebloat/raw/main/Ejecutar.bat) y haz doble clic.
- Si `w11-debloat.ps1` está en la misma carpeta, usa ese (y se autoactualiza).
- Si no está, descarga la última versión de GitHub. Puedes llevar **solo el .bat** en un USB.

**3. Manual** — descarga el repositorio (*Code → Download ZIP*), descomprime y ejecuta:

```powershell
powershell -ExecutionPolicy Bypass -File .\w11-debloat.ps1
```

El script pide permisos de administrador él solo. Si Windows SmartScreen avisa al abrir el `.bat`, pulsa *Más información → Ejecutar de todas formas*.

---

## Menú principal

| Opción | Qué hace |
|---|---|
| **1. Debloat rápido** | Aplica las categorías recomendadas (las marcadas por defecto) y luego te ofrece instalar software. |
| **2. Debloat personalizado** | Eliges qué categorías aplicar marcándolas y desmarcándolas. La selección se guarda. |
| **3. Instalar software** | Instalador por lotes con `winget`. |
| **4. Cuenta local / autounattend.xml** | Crear cuenta local, bloquear cuentas Microsoft o generar el archivo de instalación desatendida. |
| **5. Reaplicar automáticamente** | Crea/quita una tarea que reaplica el debloat al iniciar sesión. |
| **6. Actualizar programas** | `winget upgrade --all` para poner al día todo lo instalado. |
| **7. Punto de restauración** | Crea uno manualmente. |

En la cabecera verás tu usuario, si es cuenta **Local** o **MicrosoftAccount**, y el estado de la autoactualización y la tarea programada.

---

## Categorías de debloat

Todos los ajustes de usuario se aplican **a tu usuario y al perfil por defecto**, así que las cuentas que crees después ya nacen limpias. Las apps se quitan para todos los usuarios y se *desaprovisionan* para que no vuelvan.

| # | Categoría | Por defecto | Detalle |
|---|---|:-:|---|
| 1 | **Apps preinstaladas** | ✅ | Noticias, Tiempo, Bing, Teams, Outlook (nuevo), Clipchamp, Solitario, To Do, Mapas, Centro de opiniones, Power Automate, Vínculo móvil, Dev Home, Cortana, Familia, Tips… y apps de terceros "de regalo" (Candy Crush, TikTok, Spotify, Disney+, Netflix, Instagram, Facebook, LinkedIn, McAfee, Norton…). **Se conservan**: Store, Calculadora, Fotos, Paint, Bloc de notas, Terminal, Recortes, Cámara, Reproductor multimedia, Notas rápidas. |
| 2 | **Telemetría** | ✅ | Políticas de diagnóstico al mínimo, servicios `DiagTrack` y `dmwappushservice` desactivados, ID de publicidad, historial de actividad, experiencias personalizadas, recogida de escritura/tinta, informes de errores, CEIP, inventario de compatibilidad y las tareas programadas de recopilación. |
| 3 | **IA** | ✅ | Copilot (política, botón, app y menú contextual "Preguntar a Copilot"), **Recall** (políticas + desinstalación de la característica), **Click to Do**, agente de Configuración, IA de **Paint** (Cocreator, relleno/borrado generativo, quitar fondo), IA del **Bloc de notas** y Copilot/barra lateral de **Edge**. |
| 4 | **Anuncios y sugerencias** | ✅ | Apps instaladas en silencio, sugerencias en Inicio/Configuración/pantalla de bloqueo, recomendaciones de Inicio, "Terminemos de configurar tu dispositivo", resultados de **Bing/web en la búsqueda**, Cortana, y en Edge el asistente de compras y recomendaciones. |
| 5 | **Barra de tareas** | ✅ | Fuera Widgets y Chat, búsqueda como icono y opción **"Finalizar tarea"** en el clic derecho de la barra. |
| 6 | **OneDrive** | ✅ | Desinstala OneDrive, lo quita del panel del Explorador y evita que se reinstale en usuarios nuevos. Tus archivos siguen en la nube. |
| 7 | **Solo cuenta local** | ✅ | Impide **añadir** cuentas Microsoft (las existentes siguen funcionando para no dejarte fuera), quita los avisos de "inicia sesión con tu cuenta Microsoft" y activa `BypassNRO` por si restableces el PC. |
| 8 | **Explorador clásico** | ✅ | Muestra extensiones, **menú contextual clásico** (clic derecho completo), abre en "Este equipo" y oculta recientes/frecuentes en Inicio rápido. |
| 9 | **Barra a la izquierda** | ⬜ | Alinea el botón Inicio a la izquierda, como en Windows 10. |
| 10 | **Xbox** | ⬜ | Quita la app Xbox, Game Bar y Game DVR. Desmarcado por defecto: **déjalo así si usas Game Pass**. Xbox Identity Provider se mantiene para no romper juegos. |

---

## Instalador de software

Usa **winget** (viene con Windows 11). Si en una instalación limpia aún no está activo, el script lo registra o lo descarga de Microsoft.

Al entrar verás la lista numerada. Puedes escribir:

- Números sueltos o rangos: `1 4 7` · `1,3,5-9`
- `B` → **pack básico**: Chrome, VLC, WinRAR, Steam, qBittorrent, Avast y Visual C++ x64/x86
- `T` → todo

Catálogo actual:

| Categoría | Programas |
|---|---|
| Navegadores | Google Chrome ★, Firefox (es-ES), Brave |
| Multimedia | VLC ★, OBS Studio, Audacity |
| Compresión | WinRAR ★, 7-Zip |
| Juegos | Steam ★, Epic Games, GOG Galaxy, Discord |
| Descargas | qBittorrent ★ |
| Seguridad | Avast Free Antivirus ★, Malwarebytes, Bitwarden |
| Utilidades | Notepad++, PowerToys, Everything, ShareX, CPU-Z, HWiNFO, CrystalDiskInfo |
| Comunicación | Telegram, WhatsApp |
| Oficina | LibreOffice, Adobe Acrobat Reader, SumatraPDF |
| Runtimes | Visual C++ 2015-2022 x64 ★ / x86 ★, .NET Desktop Runtime 8, DirectX |
| Desarrollo | Visual Studio Code, Git |

★ = incluido en el pack básico.

Notas:
- Si un programa falla por su ID, el script reintenta buscándolo por nombre. Al final muestra qué se instaló y qué falló.
- **Avast** desactiva Microsoft Defender automáticamente al instalarse (es lo normal con cualquier antivirus). Durante su instalación puede ofrecer software extra: revísalo.
- Spotify no está en la lista porque su instalador se niega a ejecutarse como administrador; instálalo desde su web o la Store.

**Añadir un programa**: edita el array `$Software` en `w11-debloat.ps1`. Cada línea es `@('Categoría', 'Nombre', 'Id.De.Winget', 'winget' o 'msstore', $true/$false para el pack básico)`. Busca IDs con `winget search nombre`.

---

## Cuenta local y autounattend.xml

### Ya tienes Windows instalado con cuenta Microsoft

1. Menú **4 → 1**: crea una cuenta local de administrador.
2. Cierra sesión y entra con la cuenta nueva.
3. Copia tus archivos desde `C:\Users\<usuario anterior>`.
4. Borra la cuenta Microsoft en *Configuración → Cuentas → Otros usuarios*.
5. Menú **4 → 2**: bloquea las cuentas Microsoft del todo (ni añadir ni iniciar sesión). El script se niega a hacerlo si sigues dentro de una cuenta Microsoft, para que no te quedes fuera.

### Vas a instalar Windows desde cero (recomendado)

Microsoft ha ido eliminando los trucos clásicos (`oobe\bypassnro`, `ms-cxh:localonly`…) para saltarse la cuenta Microsoft. Lo que sigue funcionando es un **archivo de respuestas**:

1. Menú **4 → 3**: indica usuario, contraseña e idioma (por defecto `es-ES`).
2. Se genera `autounattend.xml` en tu Escritorio.
3. Crea el USB con la ISO oficial (Media Creation Tool o Rufus) y copia `autounattend.xml` en la **raíz** del USB.
4. Instala normalmente. Windows creará tu cuenta local de administrador, saltará la pantalla de cuenta Microsoft y la de red obligatoria, bloqueará las cuentas Microsoft e iniciará sesión una vez automáticamente.
5. Si respondiste **Sí** a "ejecutar el script en el primer inicio", al entrar por primera vez se abrirá W11 Pro Debloat (te pedirá confirmar con UAC).

> ⚠️ La contraseña queda **en texto plano** dentro del USB. Bórralo o formatéalo después. No uses los caracteres `< > & " % ^ |` en usuario ni contraseña.

---

## Reaplicar automáticamente

Las actualizaciones grandes de Windows suelen reinstalar apps, reactivar Copilot o resetear ajustes. Con el menú **5**:

- El script se copia a `C:\ProgramData\W11Debloat\`.
- Se crea la tarea programada **`W11Debloat-Reaplicar`**, que se ejecuta **2 minutos después de iniciar sesión**, oculta y con privilegios elevados.
- Cada vez: comprueba si hay versión nueva en GitHub → se actualiza → reaplica **en silencio** las categorías que guardaste.
- En modo automático **no** se quitan las apps de terceros (Spotify, WhatsApp, Netflix…), para no borrar algo que hayas instalado tú a propósito; solo las de Microsoft.

Para quitarla: vuelve al menú **5** y elige **Q**.

---

## Autoactualización

- La versión está en la variable `$ScriptVersion` del script.
- Al arrancar descarga `w11-debloat.ps1` de la rama `main` de este repo y compara versiones.
- Si la remota es mayor: **comprueba que no tenga errores de sintaxis**, guarda una copia `w11-debloat.ps1.bak`, se reemplaza, actualiza también la copia de `ProgramData` y se reinicia.
- Si no hay Internet o algo falla, sigue con la versión local sin más.
- Para desactivarla en una ejecución: `-NoUpdate`.

---

## Parámetros

```powershell
.\w11-debloat.ps1            # menú interactivo
.\w11-debloat.ps1 -Auto      # aplica las categorías guardadas sin preguntar (lo usa la tarea)
.\w11-debloat.ps1 -NoUpdate  # no busca actualizaciones
```

También funcionan con el .bat: `Ejecutar.bat -NoUpdate`.

---

## Archivos y registros

Todo vive en `C:\ProgramData\W11Debloat\`:

| Ruta | Contenido |
|---|---|
| `config.json` | Categorías elegidas (las usa `-Auto`). |
| `w11-debloat.ps1` | Copia instalada (si usaste el instalador de una línea o la opción 5). |
| `logs\*.log` | Registro completo de cada ejecución (se guardan las 15 últimas). |

---

## Cómo deshacer cambios

- **Punto de restauración**: se crea uno antes de cada debloat. *Inicio → "Crear un punto de restauración" → Restaurar sistema*.
- **Apps quitadas**: reinstálalas desde Microsoft Store.
- **OneDrive**: `winget install Microsoft.OneDrive`, y borra el valor `DisableFileSyncNGSC` en `HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive`.
- **Cuentas Microsoft**: pon `NoConnectedUser` a `0` en `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`.
- **Menú contextual nuevo de W11**: borra la clave `HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}` y reinicia el Explorador.
- **Políticas en general**: casi todo está en `HKLM\SOFTWARE\Policies\...` y `HKCU\Software\Policies\...`; borrar el valor lo devuelve al comportamiento normal.

---

## Qué NO hace

- **No desinstala Edge**: quitarlo rompe partes de Windows (WebView2, widgets, ayuda…). Solo le quita Copilot, compras y recomendaciones.
- **No toca Windows Update ni Defender** (salvo que Defender se apaga solo si instalas otro antivirus).
- **No deja la telemetría a cero en Home/Pro**: Microsoft solo permite el nivel 0 en Enterprise/Education. Queda en el mínimo posible de tu edición.
- No quita Microsoft Store ni el Instalador de aplicaciones (winget lo necesita).

---

## Publicar una versión nueva

1. Edita `w11-debloat.ps1`.
2. **Sube el número** en `$ScriptVersion = 'x.y.z'` (si no lo subes, nadie se actualizará).
3. Guarda el archivo en **UTF-8 con BOM** (en VS Code: *Guardar con codificación → UTF-8 with BOM*). Windows PowerShell 5.1 necesita el BOM para leer bien las tildes.
4. Haz commit y push a `main`. Todos los equipos se actualizan en su siguiente ejecución (GitHub puede tardar ~5 min en servir la versión nueva).

---

## Preguntas frecuentes

**¿Funciona en Windows 11 Home?** Sí. Casi todo se aplica mediante registro, no hace falta el editor de directivas.

**¿Puedo ejecutarlo varias veces?** Sí, es idempotente: lo que ya está aplicado se queda igual.

**La consola muestra caracteres raros.** Ejecútalo con `Ejecutar.bat` o `powershell -File`; no lo copies y pegues a mano en la consola.

**winget falla en una instalación recién hecha.** Abre Microsoft Store, actualiza "Instalador de aplicaciones", y vuelve a intentarlo. Hace falta conexión a Internet.

**Una actualización de Windows me ha devuelto Copilot.** Activa la opción 5 (reaplicar automáticamente) o vuelve a ejecutar el debloat.
