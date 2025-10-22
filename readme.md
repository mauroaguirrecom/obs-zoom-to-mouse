# OBS Zoom to Mouse (Modo Automático y Asimétrico) v2.5

Este es un script Lua para OBS Studio que modifica el script original "Zoom to Mouse", optimizándolo para un flujo de trabajo rápido y automático, e introduciendo la capacidad de realizar zoom asimétrico (ancho y alto independientes).

Ha sido simplificado y reenfocado para funcionar específicamente en **OBS 30+ en Windows**.

## Agradecimientos

Este script es una modificación y simplificación del increíble trabajo original realizado por **BlankSourceCode**. Todo el crédito por la lógica base de FFI y el manejo de filtros de recorte pertenece al autor original.

Puedes encontrar el repositorio original (v1.x) aquí:
* **Repositorio Original:** [github.com/BlankSourceCode/obs-zoom-to-mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse)

## Características Principales (Versión 2.5-Mod)

Esta versión se diferencia significativamente del original al enfocarse en la automatización:

* 🖱️ **Clic para Zoom:** Simplemente haz clic en cualquier parte de la pantalla y el script hará zoom automáticamente a esa posición.
* 📐 **Zoom Asimétrico:** Define factores de zoom independientes para el **Ancho (W)** y el **Alto (H)**. Perfecto para monitores ultrawide o para enfocar áreas específicas.
* 💨 **Paneo Suave (Auto-Pan):** Una vez hecho el zoom, el script seguirá suavemente el cursor del ratón (sin la complejidad de "safe-zones" de la v1).
* ⏱️ **Zoom-Out por Inactividad:** Si el ratón permanece inactivo (sin clics) durante un tiempo configurable, el script volverá automáticamente a la vista completa (zoom-out).
* ✅ **Compatibilidad Total:** Diseñado y probado para **OBS 30 y versiones superiores**.
* 🖥️ **Solo Windows:** Utiliza FFI de Windows para la detección de clics y posición del ratón. Se ha eliminado el soporte para Linux y macOS para simplificar el código.
* 🚫 **Sin Dependencias:** No requiere Python ni plugins externos.

## Instalación

1.  Descarga el archivo `obs-zoom-to-mouse.lua` (el código que has proporcionado).
2.  Abre OBS Studio.
3.  Ve al menú `Herramientas` > `Scripts`.
4.  Haz clic en el botón `+` (Añadir) en la ventana de Scripts.
5.  Selecciona el archivo `obs-zoom-to-mouse.lua` que descargaste.
6.  El script aparecerá en la lista y sus opciones de configuración estarán disponibles.

## Configuración

Una vez cargado el script, verás las siguientes opciones:

* **Zoom Source:** La fuente de "Captura de Pantalla" (o `monitor_capture`) a la que se aplicará el zoom. El script intentará detectarla automáticamente si se deja en `<Auto>`.
* **Zoom Factor (Ancho):** El nivel de zoom para el ancho (e.g., `2` significa que el ancho será 1/2 del original).
* **Zoom Factor (Alto):** El nivel de zoom para el alto (e.g., `3` significa que el alto será 1/3 del original).
* **Zoom Speed:** La velocidad de la animación de zoom-in y zoom-out.
* **Idle Timeout (ms):** El tiempo en milisegundos que el script esperará sin clics antes de hacer zoom-out. **Pon este valor en `0` para desactivar el zoom-out automático.**
* **Auto Pan Speed:** La suavidad con la que la cámara sigue al ratón cuando ya está en modo zoom.
* **Enable debug logging:** Activa mensajes en el log de OBS (útil para depuración).
* **🔘 Iniciar Zoom:** Un botón para activar/desactivar el zoom manualmente, igual que el atajo de teclado original.

## Resumen de Cambios (vs. v1.0.2 Original)

Esta versión es un *fork* enfocado y no un reemplazo directo. Para lograr la simplicidad y el flujo de trabajo automático, se eliminaron varias características de la v1.x:

### ⛔ Eliminado

* **Soporte Multiplataforma:** Se eliminó el código para Linux (X11) y macOS (OSX). Este script es **solo para Windows**.
* **Seguimiento Remoto:** Se eliminó toda la lógica de servidor de sockets (UDP) para el ratón remoto.
* **Lógica de Seguimiento Compleja:** Se eliminó el sistema de "Follow Border", "Lock Sensitivity" y "Auto Lock". Se reemplazó por un paneo automático simple.
* **Manejo Manual de Escenas:** Se eliminó la lógica compleja para convertir transformaciones de escena (`sceneitem`) en filtros de recorte. Este script asume que usará su propio filtro de recorte (`obs-zoom-to-mouse-crop`).

### ✨ Añadido

* **Zoom Asimétrico (Ancho/Alto).**
* **Activación por Clic del Ratón.**
* **Zoom-Out automático por Inactividad.**
* **Paneo automático simplificado** que siempre sigue el ratón mientras está con zoom.
* **Botón de "Iniciar Zoom"** en la interfaz de configuración.
