# PROMPT MAESTRO — SafeLoot (WoW: Forever)

> Nombre público: **SafeLoot** (libre en CurseForge, WoWInterface y GitHub el 24-11-2026; Wago sin comprobar). Comandos: `/safeloot` y `/sl`, con palabras en inglés (`test`, `alarm`, `mark`, `summary`, `rules`, `players`, `journal`, `settings`) y alias en español (`prueba`, `alarma`, `marca`, `resumen`, `reglas`, `jugadores`, `diario`, `ajustes`).

> Documento rector del proyecto. Cualquier persona o IA que trabaje en SafeLoot **lo lee entero antes de tocar código** y lo sigue al pie de la letra. Si algo de aquí choca con la realidad del juego, se corrige este documento primero y el código después.

---

## 0. Cómo trabajar en este proyecto (reglas innegociables)

1. **Verdad antes que velocidad.** Nada "funciona" hasta que se ha visto funcionar **en el cliente real de Forever**. Los tests en Lua puro validan la lógica, no la integración. Si algo no se ha probado en el juego, se dice literalmente "no verificado en el juego".
2. **Ninguna API se usa sin comprobarla** en el código de Blizzard para Forever: rama `forever` de `Gethe/wow-ui-source`, carpeta `Interface/AddOns/Blizzard_APIDocumentationGenerated/`. La comprobación se anota en la tabla §9.3.
3. **Toda llamada a la API del juego pasa por `Core/API.lua`.** Es la única capa que habla con el juego. Debe:
   - detectar si la función existe antes de llamarla;
   - devolver `nil` en vez de romper;
   - tratar los valores secretos (`issecretvalue`).
4. **La lógica pura (`Logic/`) no toca la API del juego.** Recibe datos y devuelve decisiones, y es lo que se testea fuera del juego con `tests/run.py` (`uv run --with lupa python tests/run.py`).
5. **Cero contaminación ("taint").** No se modifican marcos seguros de Blizzard, no se reemplazan sus funciones (solo `hooksecurefunc` y `TooltipDataProcessor`) y no se crean variables globales salvo las declaradas en el TOC.
6. **Cada cambio deja los tests en verde** (`uv run --with lupa python tests/run.py`) y actualiza `CHANGELOG.md`.
7. **Diagnóstico primero.** Cada capacidad que depende del juego tiene su prueba en `/safeloot test`, y el resultado se guarda en `SafeLootDB.diagnostics` para poder leerlo desde disco (`WTF/Account/<cuenta>/SavedVariables/SafeLoot.lua`).

---

## 1. Visión

**SafeLoot protege al jugador que entra en grupos con desconocidos.**
- **Antes de unirte**, te dice con quién tuviste problemas.
- **Durante la run**, hace sonar una alarma si cambian las reglas del botín y marca las tiradas de Necesidad imposibles.
- **Al final**, deja constancia de lo ocurrido.

No castiga, no bloquea y no publica a nadie: **avisa, recuerda y deja pruebas**. Funciona entero aunque seas el único del grupo que lo tiene.

Promesa al jugador, en una frase: *"Nunca más te enterarás tarde de que te han cambiado las reglas."*

### 1.1 Por qué existe (evidencia, nov. 2026)
- Quejas recientes y crecientes por ninjas, reservas fijas y cambios a botín maestro antes del último jefe. "Loot Etiquette" llegó a 111 mensajes el 23-11. Hay tres hilos del 23-11 que describen el cambio a botín maestro en el último momento. Un jugador dice que el "99% de los grupos de UBRS" llevan reserva.
- Ningún addon de Forever junta las piezas, y **ninguno avisa al miembro del grupo cuando cambia el método de botín**. Los existentes son Loot Pact (17 descargas), InstanceLootMethod (44), Lootoman (1,4K), Ninja loot (251), Grudge Ledger (54) y BlackList Premium (5,2K).
- Las raids del 9-12 (10/20/40 jugadores, botín maestro, reservas) van a multiplicar el problema.
- Detalle: `reports/Necesidades actuales nivel 60 Forever.md` en la carpeta superior.

---

## 2. Usuarios y escenarios

| Usuario | Situación | Lo que necesita |
|---|---|---|
| **Ana, jugadora de PUG** (principal) | Hace mazmorras de nivel 60 con desconocidos | Saber con quién se juega, enterarse a tiempo si cambian las reglas y que quede constancia |
| **Krag, líder honrado** | Monta grupos y quiere atraer gente | Publicar unas reglas claras de un clic y que le reconozcan como fiable |
| **Hermandad "Los Pacientes"** | Comparte experiencias entre sus miembros | Memoria común solo dentro de la hermandad, con caducidad |
| **Raider de PUG (desde el 9-12)** | Raids de 10/20 con botín maestro y reservas blandas | Saber quién reparte, qué se reservó y si algo cambia con la raid empezada |

---

## 3. Principios de producto (en orden de prioridad)

1. **Protege al miembro, no al líder.** Las herramientas para el líder ya existen (Gargul y otras). SafeLoot es el escudo de quien recibe.
2. **Funciona solo.** Todo lo esencial (alarma, detector, memoria) funciona sin que nadie más tenga el addon. Si otros lo tienen, mejora.
3. **Avisa, nunca acusa en tu nombre.** Ningún mensaje sale al chat sin un clic tuyo.
4. **La información llega en el momento de decidir**: al ver el anuncio, al recibir la invitación, antes del jefe. Ni antes ni después.
5. **Silencio por defecto.** Ningún aviso sin motivo. Un falso positivo vale menos que diez avisos útiles: ante la duda se marca "Dudoso", nunca "Imposible".
6. **Privado por diseño.**
   - La memoria es tuya.
   - Compartirla con la hermandad es opcional, se puede revocar y caduca a los 90 días.
   - **Nunca hay listas públicas entre desconocidos** (CurseForge lo prohíbe y se presta al acoso).
7. **Nativo.** Debe parecer parte de Forever, no un addon pegado encima (ver §6).
8. **Accesible.** Se puede usar sin depender del color, con texto grande, con voz y con teclado (ver §7).
9. **Ligero.** Funciona por eventos, sin `OnUpdate` permanentes. El coste en combate es prácticamente cero.
10. **Honesto.** Si algo no se puede saber, lo dice ("Sin datos"), no se lo inventa.

---

## 4. Funcionalidades (con criterios de aceptación)

### 4.1 El Vigilante — alarma de cambio de reglas ★ pieza estrella
**Qué hace.**
1. Al entrar en un grupo, al cambiar de líder o al entrar en una instancia, toma una **foto del reparto**:
   - método de botín (`C_PartyInfo.GetLootMethod`);
   - quién reparte con botín maestro;
   - umbral de calidad (`GetLootThreshold`, si existe);
   - líder.
2. Escucha `PARTY_LOOT_METHOD_CHANGED` y `PARTY_LEADER_CHANGED`. Compara contra el **contrato vigente**, que es la foto inicial si nadie pactó nada.
3. Si cambia algo relevante:
   - muestra el **aviso central nativo** (`RaidWarningUtil.AddMessage`, el mismo marco que las alertas de banda);
   - suena `SOUNDKIT.RAID_WARNING`;
   - aparece un **panel de acción** con «Preguntar en el grupo», «Guardar prueba» y «Entendido»;
   - opcionalmente, lo lee en voz alta (texto a voz).
   - Todo queda registrado en el diario de la run.

**Gravedad.**
- **Roja:** botín de grupo, Necesidad antes que Codicia o libre → **botín maestro**; o cambio de la persona que reparte.
- **Ámbar:** subida del umbral de calidad, o cambio de líder con el botín maestro activo.
- **Informativa:** cambios hacia un método más abierto, por ejemplo de botín maestro a botín de grupo.

**Criterios de aceptación.**
- [ ] El cambio a botín maestro con la run empezada dispara el aviso rojo en menos de 1 s, dentro y fuera de instancias. *(Requiere prueba en el juego: P1.)*
- [ ] Sin contrato pactado, la referencia es la foto inicial.
- [ ] Ningún aviso al formar el grupo ni cuando el cambio lo haces tú.
- [ ] El panel no se cierra solo y no tapa la interfaz de combate. Se puede mover y su posición se recuerda.
- [ ] En combate solo se muestra el aviso; el panel aparece al salir de combate, salvo que el jugador lo configure de otra forma.

### 4.2 El Detector — tiradas sospechosas
**Qué hace.**
1. Escucha `LOOT_HISTORY_UPDATE_DROP` y lee `C_LootHistory.GetSortedInfoForDrop`, que da por cada jugador nombre, clase, tipo de tirada y si ganó.
2. Para cada tirada de **Necesidad**, evalúa con `Logic/Judge.lua`:
   - **Imposible:** la clase no puede usar ese tipo de armadura o arma **nunca**. Tabla base vanilla en `Logic/Proficiency.lua`, marcada como "a verificar en Forever".
   - **Dudoso:**
     - choca con el contrato (Necesidad en un objeto reservado por otro, o en un BoE cuando se pactó Codicia);
     - o la estadística principal no encaja con la clase (por ejemplo, fuerza para un mago).
   - La tirada de **Transmog** nunca es falta.
3. Respaldo si no hay historial: `CHAT_MSG_LOOT`, protegido con `issecretvalue`, solo si el texto es legible.

**UI.** Una marca discreta junto al aviso de botín, más una entrada en el diario: *"⚠ Necesidad imposible: Zarn (mago) → [Coraza de malla]. Los magos no pueden llevar malla."* Botón «Avisar al grupo», que solo envía si lo pulsas.

**Criterios de aceptación.**
- [ ] Cero "Imposible" en casos dudosos. La tabla de competencias admite excepciones configurables.
- [ ] Los objetos que no se equipan (recetas, materiales, consumibles) nunca generan marcas de clase.
- [ ] Un solo aviso por drop, aunque el evento se repita.

### 4.3 La Memoria — recordar a la gente
**Qué guarda** por jugador:
- el nombre completo con apellido (Forever usa nombres de dos partes);
- la clase;
- eventos con fecha, lugar y tipo, que pueden ser automáticos o notas manuales;
- etiquetas negativas («ninja», «cambió reglas», «extorsión», «abandonó») y **positivas** («de confianza», «buen líder»).

**Dónde se muestra.**
- Tooltip del jugador (`TooltipDataProcessor.AddTooltipPostCall` con `Enum.TooltipDataType.Unit`).
- Fila del **buscador de grupos**: `hooksecurefunc("LFGBrowseSearchEntry_Update")`, que muestra un icono junto al nombre del líder (`searchResultInfo.leaderName`). También el tooltip de esa fila (`LFGBrowseSearchEntryTooltip_UpdateAndShow`).
- **Invitación recibida** (`PARTY_INVITE_REQUEST`): una tarjeta junto al diálogo de invitación.
- **Al entrar en un grupo** (`GROUP_ROSTER_UPDATE`): un aviso si alguien del grupo tiene historial.
- **Susurro de un desconocido**: una línea discreta, solo si el texto del evento no es secreto.

**Hermandad (fase 2).** Sincronización opcional por mensajes de addon `GUILD`:
- solo eventos automáticos por defecto; las notas manuales, si el usuario quiere;
- cada entrada indica quién la registró;
- caduca a los 90 días;
- se puede silenciar a un informante.

**Criterios de aceptación.**
- [ ] Ningún dato sale de tu PC sin activar la opción de hermandad.
- [ ] Caducidad automática a los 90 días, configurable entre 30 y 365, y botón «Olvidar a este jugador».
- [ ] La memoria es por cuenta (todos tus personajes) y por región/ruleset, con la clave `nombre-apellido`.

### 4.4 El Contrato — reglas antes de empezar
**Tres formas de fijarlo, de menos a más esfuerzo.**
1. **Automática:** la foto del reparto al entrar (ver 4.1).
2. **Copiada:** el addon lee el anuncio del buscador (`searchResultInfo.comment`) y el chat del grupo. Si detecta reglas (HR, SR, MS>OS, ML, FFA, «reserva», «todo codicia»…), propone *"¿Usar como reglas?"* con el texto interpretado. Lo confirmas o lo corriges.
3. **Propuesta:** rellenas la ficha con:
   - el método;
   - la regla de Necesidad (principal antes que secundaria, todo Codicia, solo si es mejora);
   - las reservas (fijas o blandas, quién y qué);
   - qué hacer con los BoE.

   «Publicar» escribe un **mensaje normal en el chat del grupo** (lo ven todos, tengan o no el addon), por ejemplo: *"[Reglas] Botín de grupo · MS>OS · Reserva: Krag → Mano de Dal'Rend. ¿De acuerdo? Responded «ok»"*. El addon apunta quién responde «ok», «sí», «+1» o «yes», con la hora. Quien tiene el addon ve además la ficha y pulsa «Acepto».

**Criterios de aceptación.**
- [ ] El mensaje de chat cabe en 255 caracteres y sale en el idioma del usuario, con las abreviaturas internacionales.
- [ ] Publicar solo ocurre con un clic. Nunca hay envíos automáticos al chat.
- [ ] Se recomienda pactar en la piedra de encuentro, antes de entrar. Dentro de instancias, el chat puede llegar como secreto (P3).

### 4.5 El Resumen — al terminar
Al salir de la instancia o del grupo se muestra una tarjeta compacta con:
- el contrato y si se cumplió o se rompió, y cuándo;
- cada objeto y quién lo ganó;
- las marcas del Detector y los cambios del Vigilante.

Botones:
- «Guardar en memoria»: rellena la memoria con un clic y te deja añadir una etiqueta positiva o negativa a cada jugador.
- «Copiar resumen»: genera un texto para Discord.
- «Cerrar».

### 4.6 Modo raid (fase 3)
Igual que en mazmorra, más:
- quién reparte con botín maestro;
- la lista de reservas blandas (importación pegada en texto);
- alarma si cambia quien reparte o si se añaden reservas con la raid empezada.

Es compatible con Gargul, RCLC y Raidify: no los sustituye.

---

## 5. Experiencia de usuario

### 5.1 Primer uso (onboarding de 30 segundos)
La primera vez se abre una tarjeta de bienvenida de 3 pasos, con imagen y una frase cada uno:
1. *"Te aviso si cambian el botín."*
2. *"Marco tiradas imposibles."*
3. *"Recuerdo a la gente, solo para ti."*

Un botón «Entendido» y un enlace «Ajustes». No vuelve a salir.

### 5.2 Flujo principal
| Momento | Qué ve el jugador |
|---|---|
| Buscador de grupos | Icono junto al líder: verde («De confianza»), rojo («Cuidado») o nada. El tooltip explica el motivo y la fecha |
| Invitación | Tarjeta junto a la invitación: «Krag · cambió a botín maestro (18-11, Scholomance)» |
| En el grupo | Indicador compacto anclado en una esquina, movible: «Reglas: Botín de grupo · 1 reserva». Al pasar el ratón, la ficha completa |
| Alarma | Aviso central nativo, sonido y panel de acción |
| Final | Tarjeta de resumen |

### 5.3 Microcopy (tono y estilo)
- **Inglés es el idioma base** (nombre, página pública, textos por defecto y respaldo). Idiomas incluidos: English, Español, Deutsch, Français y Português (Brasil). El ajuste «Idioma» ofrece Automático (sigue al juego) o uno fijo; cambiarlo pide recargar la interfaz.
- En cada idioma: frases cortas y verbos claros, y en español tuteo. Se usan los términos del cliente de ese idioma (Necesidad/Codicia, Bedarf/Gier, Besoin/Cupidité, Necessidade/Ganância). Nada de jerga sin explicar: la primera vez, «botín maestro (el líder reparte)».
- Nunca acusar. Se dice «Necesidad imposible: los magos no pueden llevar malla», no «¡Zarn es un ninja!».
- Los mensajes que salen al chat son educados y neutros: *"Hola, el método de botín ha cambiado a botín maestro. ¿Seguimos con lo acordado?"*
- Todo texto vive en `Locales/`: `enUS.lua` escribe la base en `SL.L`; los demás (`esES`, `deDE`, `frFR`, `ptBR`) son tablas en `SL.Locales[código]` que se aplican al cargar (`SL:ApplyLocale`). Un test exige que los cinco tengan exactamente las mismas claves.

### 5.4 Estados vacíos y errores
- Memoria vacía: *"Aún no has apuntado a nadie. Lo haré solo cuando pase algo."*
- Función no disponible en el juego: *"Esta función no está disponible en tu versión del juego"* y se registra en el diagnóstico. Nunca un error Lua visible para el usuario.

---

## 6. Diseño visual nativo — "heredar, no imitar"

**Regla de oro:** no se dibuja arte propio. Se usan **las mismas plantillas, atlas, fuentes y sonidos que el juego**, para que SafeLoot herede automáticamente el aspecto de Forever (que ya modifica sus marcos con `Camelot/NineSliceLayoutOverrides.lua`). Si Blizzard cambia el estilo, el addon cambia con él.

### 6.1 Plantillas verificadas en la rama `forever` (23-11-2026)
| Uso | Plantilla / API | Archivo fuente |
|---|---|---|
| Ventana principal | `PortraitFrameTemplate` (marco con retrato, como el de Personaje) | `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml` |
| Ventana sin retrato | `ButtonFrameTemplate` + layout `ButtonFrameTemplateNoPortrait` | idem + `NineSliceLayouts.lua` |
| Panel interior | `InsetFrameTemplate` | idem |
| Pestañas inferiores | `PanelTabButtonTemplate` | idem |
| Botones | `UIPanelButtonTemplate` | `Blizzard_SharedXML/Shared/Button/UIPanelButtonTemplates.xml` |
| Cerrar | `UIPanelCloseButton` | `SharedUIPanelTemplates.xml` |
| Casillas | `UICheckButtonTemplate` | `Shared/Button/CheckButtonTemplates.xml` |
| Campo de texto | `SharedEditBoxTemplate` | `SharedUIPanelTemplates.xml` |
| Listas | `WowScrollBoxList` + `MinimalScrollBar` + `ScrollUtil.InitScrollBoxListWithScrollBar` | `Shared/Scroll/ScrollTemplates.xml`, `MinimalScrollBar.xml` |
| Diálogos, paneles de aviso | `NineSliceUtil.ApplyLayoutByName(frame, "Dialog")` o `"TooltipDefaultLayout"` | `NineSliceLayouts.lua` |
| Fondo de tarjeta | `BackdropTemplate` | `Blizzard_SharedXML/Backdrop.xml` |
| Tooltips | `GameTooltip` + `TooltipDataProcessor.AddTooltipPostCall` | `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua` |
| Aviso central | `RaidWarningUtil.AddMessage(texto, colorInfo, duración)` (respaldo: `RaidWarningFrame:AddMessage`) | `Blizzard_RaidWarning/RaidWarning.lua` |
| Ajustes | `Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnSetting` + `Settings.CreateCheckbox/CreateSlider/CreateDropdown` + `Settings.RegisterAddOnCategory` | `Blizzard_Settings_Shared/Blizzard_Settings.lua` |
| Botón en el minimapa | Compartimento de addons (`## AddonCompartmentFunc` en el TOC) | `Blizzard_Minimap/Camelot/AddonCompartment.lua` |
| Voz (accesibilidad) | `C_VoiceChat.SpeakText(voiceID, texto, rate, volume, overlap)` | `VoiceChatDocumentation.lua` |

Toda plantilla se crea con `UI.Create(...)`. Este helper comprueba antes con `C_XMLUtil.GetTemplateInfo` y, si falta, usa un respaldo sin romper.

### 6.2 Tipografía
Solo objetos de fuente del juego:
- `GameFontNormalLarge`: títulos.
- `GameFontNormal`: cabeceras doradas.
- `GameFontHighlight`: texto principal blanco.
- `GameFontHighlightSmall` / `GameFontDisableSmall`: secundario.
- `GameFontRed` / `GameFontGreen`: estados, siempre acompañados de un icono.

Tamaño de texto configurable (Normal / Grande) eligiendo el objeto de fuente, nunca con tamaños inventados.

### 6.3 Color
Solo constantes del juego:
- `NORMAL_FONT_COLOR` (dorado);
- `HIGHLIGHT_FONT_COLOR`;
- `RED_FONT_COLOR`, `GREEN_FONT_COLOR`, `ORANGE_FONT_COLOR`;
- `GRAY_FONT_COLOR`;
- colores de calidad de objeto (`ITEM_QUALITY_COLORS`);
- colores de clase (`C_ClassColor.GetClassColor` o `RAID_CLASS_COLORS`).

### 6.4 Iconografía (texturas clásicas, reconocibles al instante)
- Estados ✔ / ✖ / ?: `Interface\RaidFrame\ReadyCheck-Ready`, `ReadyCheck-NotReady`, `ReadyCheck-Waiting`, los mismos de la comprobación de banda. **La forma comunica sin color.**
- Aviso: `Interface\DialogFrame\UI-Dialog-Icon-AlertNew`.
- Marcas: los iconos de objetivo de banda (`Interface\TargetingFrame\UI-RaidTargetingIcon_X`).
- Retrato del addon: un icono de objeto vanilla de bolsa o cofre.

Cualquier textura nueva se verifica antes en el juego (P5).

### 6.5 Movimiento y sonido
- Animaciones suaves de 0,15–0,25 s: aparición con alfa y un ligero desplazamiento, usando `AnimationGroup`. Opción «Reducir animaciones».
- Sonidos de `SOUNDKIT`:
  - `RAID_WARNING`: alarma roja.
  - `READY_CHECK`: contrato publicado o aceptado.
  - `IG_MAINMENU_OPEN` / `IG_MAINMENU_CLOSE`: abrir y cerrar.
  - `IG_CHARACTER_INFO_TAB`: pestañas.
  - `IG_MAINMENU_OPTION_CHECKBOX_ON/OFF`: casillas.
- Cada categoría de sonido se puede desactivar por separado.

### 6.6 Composición
- Rejilla de 8 px y márgenes internos de 16 px.
- Ventana principal de 560×460, que se puede mover y escalar entre 80 % y 130 %, y recuerda su posición.
- ESC la cierra (`UISpecialFrames`) y tiene atajo de teclado (`Bindings.xml`).
- Pestañas abajo, como en las ventanas clásicas: **Contrato · Diario · Jugadores**. Los ajustes van en Opciones > AddOns, y hay un botón de engranaje que lleva allí.

---

## 7. Accesibilidad (lista de comprobación obligatoria)
- [ ] **Nunca solo color:** todo estado lleva icono con forma distinta y texto.
- [ ] Contraste: texto blanco o dorado sobre los fondos oscuros nativos; nada de gris sobre gris en información importante.
- [ ] Tamaño de texto Normal/Grande y escala de ventana del 80 % al 130 %.
- [ ] Alarmas que no dependen de la vista: sonido y, opcionalmente, **voz** (texto a voz del juego).
- [ ] Alarmas que no dependen del oído: aviso central, panel persistente y destello opcional del icono.
- [ ] Sin límites de tiempo: el panel de alarma no se cierra solo.
- [ ] Teclado: atajo para abrir, ESC para cerrar, Intro para la acción principal en las tarjetas.
- [ ] Tooltips en todos los controles, explicando qué hacen y qué consecuencia tienen.
- [ ] Respeta el modo daltónico del juego (CVar `colorblindMode`): añade texto o símbolos extra.
- [ ] Sin parpadeos rápidos (más de 3 por segundo prohibido).
- [ ] Lenguaje llano y glosario en la pestaña de ayuda.

---

## 8. Arquitectura

```
SafeLoot/
  SafeLoot.toc         -- Interface 16001 (Forever)
  Bindings.xml            -- atajo para abrir la ventana
  Locales/                -- enUS.lua (base) + esES, deDE, frFR, ptBR (sobrescrituras)
  Core/
    Init.lua              -- espacio de nombres, bus de eventos, módulos, idioma, comandos /safeloot y /sl
    API.lua               -- ÚNICA capa con la API del juego (detección de funciones, issecretvalue, pcall)
    Store.lua             -- SavedVariables: valores por defecto, versión de esquema, migraciones, caducidad
  Logic/                  -- PURO (sin API del juego), testeable fuera del juego
    Proficiency.lua       -- competencias de armadura y armas por clase (base vanilla, a verificar)
    Rules.lua             -- modelo de contrato, comparación, interpretación de texto, formato de chat
    Judge.lua             -- evaluación de tiradas → Imposible / Dudoso / nada
    Memory.lua            -- registros de jugadores: alta, consulta, caducidad, etiquetas
  Modules/
    Diagnostics.lua       -- /safeloot test: comprueba capacidades y guarda el informe en disco
    Watcher.lua           -- el Vigilante
    LootWatch.lua         -- el Detector (historial de botín y respaldo por chat)
    MemoryHooks.lua       -- tooltip, buscador de grupos, invitaciones, entrada en grupo
    Contract.lua          -- publicar, leer respuestas, interpretar anuncios y chat
    Summary.lua           -- resumen de la run
  UI/
    Theme.lua             -- fuentes, colores, texturas y sonidos (todo nativo)
    Widgets.lua           -- UI.Create, botones, filas, tarjetas
    Alert.lua             -- aviso central y panel de acción
    MainFrame.lua         -- ventana con pestañas
    Settings.lua          -- integración en Opciones > AddOns
  tests/                  -- run.py (Lua 5.1 vía lupa) + specs + simulación de la API del juego
  docs/PROMPT_MAESTRO.md  -- este documento
```

- **Ciclo de vida:** `ADDON_LOADED` → `Store:Init` → `OnInitialize` de cada módulo → `PLAYER_LOGIN` → `OnEnable`.
- **Bus interno:** `SL:Fire("CONTRACT_CHANGED", contract)`, `SL:On(...)`. Los módulos no se llaman directamente entre sí.
- **SavedVariables:**
  - `SafeLootDB` (cuenta): `settings`, `players`, `runs` (últimas 50), `diagnostics`, `schema`.
  - `SafeLootCharDB` (personaje): posición de ventanas y estado de la run en curso.
- **Límites:** máximo 2.000 jugadores y 50 runs; se poda lo más antiguo. Las notas manuales tienen 200 caracteres como máximo.

---

## 9. Restricciones de Forever (Midnight) y cómo se respetan

### 9.1 Restricciones
- **Registro de combate cerrado:** no se usa `COMBAT_LOG_EVENT*`.
- **Valores secretos:** antes de comparar, concatenar u operar con cualquier dato de unidades o chat, se pasa `issecretvalue(v)`. Si es secreto, se ignora sin error.
- **Chat bloqueado en instancias o encuentros:** los eventos de chat pueden llegar como secretos y los mensajes de addon pueden fallar (`AddOnMessageLockdown`). Por eso el contrato se pacta fuera, antes de entrar.
- **Mensajes de addon:**
  - prefijo `SafeLoot` (11 caracteres de un máximo de 16);
  - 255 bytes como máximo;
  - ráfaga de 10 y 1 por segundo;
  - las cuentas de prueba y veteranas no pueden enviar.
  - Formato versionado: `1|TIPO|campos…`.
- **Chat del usuario:** solo `SendChatMessage` a `PARTY`/`RAID` tras un clic. Nada de `SAY`/`YELL`/`EMOTE`.
- **GUID ofuscados y APIs de reino vacías:** no se usan GUIDs como identidad duradera. La identidad es `nombre-apellido` según `UnitFullName` / `C_PlayerInfo`.
- **CurseForge:** prohibidas las listas globales de jugadores. Solo memoria personal y de hermandad.

### 9.2 Antitaint
- Solo `hooksecurefunc`, `HookScript` sobre marcos no protegidos y `TooltipDataProcessor`.
- No se tocan `StaticPopup` del juego; las tarjetas son propias.
- No hay `SetScript` sobre marcos de Blizzard.

### 9.3 Tabla de APIs (comprobadas en la documentación; ✅ juego = probado en el cliente)
| API / evento | Docs Forever | ✅ juego |
|---|---|---|
| `C_PartyInfo.GetLootMethod()` → método, masterLootPartyID, masterLooterRaidID | ✔ | ☐ P1 |
| `PARTY_LOOT_METHOD_CHANGED` | ✔ | ☐ P1 |
| `Enum.LootMethod` {Freeforall=0, Roundrobin=1, Masterlooter=2, Group=3, Needbeforegreed=4, Personal=5} | ✔ | ☐ |
| `C_LootHistory.GetSortedInfoForDrop(encounterID, lootListKey)` → rollInfos{playerName, playerClass, state, isWinner, roll} | ✔ | ☐ P2 |
| `LOOT_HISTORY_UPDATE_DROP(encounterID, lootListKey)` | ✔ | ☐ P2 |
| `Enum.EncounterLootDropRollState` {NeedMainSpec=0, NeedOffSpec=1, Transmog=2, Greed=3, NoRoll=4, Pass=5} | ✔ | ☐ |
| `C_ChatInfo.SendAddonMessage` / `RegisterAddonMessagePrefix` | ✔ | ☐ P3 |
| `C_LFGList.GetSearchResultInfo` → leaderName, comment | ✔ | ☐ P4 |
| `LFGBrowseSearchEntry_Update` / `LFGBrowseSearchEntryTooltip_UpdateAndShow` (para engancharse) | ✔ (código) | ☐ P4 |
| `TooltipDataProcessor.AddTooltipPostCall` | ✔ (código) | ☐ |
| `RaidWarningUtil.AddMessage` | ✔ (código) | ☐ P5 |
| `Settings.RegisterVerticalLayoutCategory` y relacionadas | ✔ (código) | ☐ |
| `C_VoiceChat.SpeakText(voiceID, text, rate, volume, overlap)` | ✔ | ☐ |
| `UnitIsPlayer`, `UnitLevel`, `UnitClass` (fuera de instancias) | ✔ | ☐ |

### 9.4 Pruebas en el juego (Fase 0, `/safeloot test`)
- **P1** Alarma: con dos personajes o un amigo, cambiar el método de botín dentro y fuera de una instancia. ¿Llega el evento? ¿`GetLootMethod` devuelve valores no secretos?
- **P2** Historial: tirar por un objeto en grupo. ¿Se leen nombre, clase y estado dentro de la instancia?
- **P3** Mensajes de addon: enviar `PARTY` fuera y dentro de una instancia y anotar el código de resultado.
- **P4** Buscador: abrir el buscador con anuncios. ¿Salta el gancho? ¿Hay `leaderName` y `comment`?
- **P5** Aviso central y texturas: ¿se ve el aviso y cargan los iconos?

Los resultados se guardan en `SafeLootDB.diagnostics` con fecha, versión del juego y lugar.

---

## 10. Datos de referencia

### 10.1 Competencias por clase (base vanilla, **a verificar en Forever**)
- **Armadura máxima:**
  - Guerrero y Paladín: placas (desde nivel 40; antes, malla).
  - Cazador y Chamán: malla (desde nivel 40; antes, cuero).
  - Pícaro y Druida: cuero.
  - Sacerdote, Mago y Brujo: tela.
- Escudos: Guerrero, Paladín y Chamán.
- Armas: tabla completa en `Logic/Proficiency.lua`.
- Ante la duda, **"desconocido" ≠ "imposible"**.

### 10.2 Vocabulario del intérprete de reglas
| Expresión | Significado |
|---|---|
| `HR`, `hard res`, `reserva fija`, `reservado` | Reserva fija |
| `SR`, `soft res`, `reserva blanda` | Reserva blanda |
| `MS>OS`, `MS > OS`, `main>off`, `principal antes que secundaria` | Especialización principal antes que secundaria |
| `ML`, `master loot`, `botín maestro`, `maestro despojador` | Botín maestro |
| `FFA`, `free roll`, `libre` | Libre |
| `todo codicia`, `all greed`, `greed all` | Todo Codicia |
| `BoE greed`, `BoE a codicia` | BoE a Codicia |
| Acuerdo: `ok`, `okay`, `sí`, `si`, `vale`, `+1`, `yes`, `y`, `👍`, `de acuerdo`, `sure` | Respuesta afirmativa |

---

## 11. Calidad

**Lecciones del cliente real (heredadas de BlazonGuild, mismo autor, probadas en Forever):**
- Los nombres son «Nombre Apellido». `UnitName` da solo el nombre; se usa `Core/Names.lua` (`UnitFullName` y la normalización de «Nombre-Apellido»).
- No existe `GetItemInfo` global: se usa siempre `C_Item`. Tampoco existen `EasyMenu` ni `InterfaceOptions_AddCategory`.
- En combate, Forever bloquea algunas lecturas (`ADDON_ACTION_BLOCKED`). Lo que no hace falta en plena pelea se aplaza con `SL:AfterCombat`.
- No se crean, mueven ni redimensionan marcos propios **dentro** de marcos protegidos en combate. Los marcos propios se construyen fuera de combate.
- Lua 5.1 estándar: `xpcall` no pasa argumentos (se usa un cierre) y `string.lower` puede romper el UTF-8 según la configuración regional (minúsculas solo de la A a la Z).

- **Tests:** `uv run --with lupa python tests/run.py` carga todos los `.lua` en Lua 5.1 (lupa) con una API del juego simulada.
  - Comprueba la **sintaxis** de todos los archivos.
  - Ejecuta los **specs de lógica**.
  - Hace una **prueba de carga** del addon completo con la API simulada.
  - Detecta **globales filtrados**.
- **Rendimiento:** no hay `OnUpdate` permanente; solo animaciones breves. En combate solo se procesan eventos de botín y de método.
- **Errores:** cada manejador de evento va envuelto en `xpcall` con informe a `/safeloot debug`. El usuario nunca ve un error Lua por culpa de SafeLoot.
- **Definición de terminado:** tests en verde, CHANGELOG actualizado, criterios de aceptación de la función marcados y prueba en el juego hecha o señalada como pendiente.

---

## 12. Fases

| Fase | Contenido | Sale cuando… |
|---|---|---|
| **0 — Diagnóstico** | `/safeloot test` (P1 a P5) y su informe en disco | Los resultados de P1 y P2 están leídos y anotados en §9.3 |
| **1 — Escudo personal** | Vigilante, Detector, Memoria personal, aviso central y panel, ventana con Diario y Jugadores, tooltip y buscador, ajustes | Una run real sin errores y con la alarma probada |
| **2 — Contrato y hermandad** | Ficha, publicar en el chat, leer respuestas, interpretar anuncios, sincronizar con la hermandad | Probado en 3 runs con desconocidos |
| **3 — Raids** | Modo raid, reservas blandas, compatibilidad con Gargul | Probado en una raid del 9-12 |
| **4 — Pulido y publicación** | Onboarding, accesibilidad completa, localización, página de CurseForge/Wago, packager | Lista de accesibilidad al 100 % |

---

## 13. Distribución
- TOC: `## Interface: 16001`, `## SavedVariables: SafeLootDB`, `## SavedVariablesPerCharacter: SafeLootCharDB`, `## IconTexture`, `## AddonCompartmentFunc`.
- Empaquetado con BigWigs packager (`.pkgmeta`, que excluye `tests/` y `docs/`) hacia CurseForge y Wago. WoWInterface no admite Forever.
- Versiones semánticas y `CHANGELOG.md` en español e inglés.
- Página pública honesta: qué hace, qué no hace y por qué no hay listas públicas. Autor visible, sin promoción agresiva (hay rechazo de la comunidad a los addons de baja calidad hechos con IA).

## 14. Riesgos
| Riesgo | Mitigación |
|---|---|
| El evento de método no llega o es secreto en instancias | Diagnóstico P1 desde el día 1; respaldo comprobando `GetLootMethod` al salir de combate y al despojar |
| Falsos positivos del Detector | "Imposible" solo con una tabla segura; excepciones configurables; botón «Esto es un error» |
| Blizzard añade botín personal o "Bind on Need" | El Vigilante y la Memoria siguen siendo útiles; replantear el Detector |
| Uso para acosar | Sin listas públicas, notas privadas por defecto, caducidad y mensajes neutros |
| Chat bloqueado en instancias | Pactar fuera; el contrato es local; los mensajes de addon solo son una mejora |

## 15. Glosario
| Término | Significado |
|---|---|
| **Necesidad / Codicia** | Botones de tirada (*Need* / *Greed*) |
| **Botín maestro** | El líder reparte a mano (*Master Loot*) |
| **Reserva fija / blanda** | Fija: el objeto es de alguien antes de empezar. Blanda: solo compiten quienes lo apuntaron |
| **MS>OS** | Primero quien lo use en su especialización principal |
| **BoE** | Se liga al equiparse; se puede vender |
| **PUG** | Grupo de desconocidos |
| **Run** | Una pasada completa por una mazmorra o raid |
