# codelabs-setup

Instalador único de máquina nueva para el portfolio de codelabs.studio. Mide
el hardware, deduce qué puede hacer la máquina, instala lo que le toca según
el **pack** de la persona (fundador, desarrollador, marketer, aprendiz o
máquina trabajadora) y da de alta la máquina en la flota de MemoryFirst.

Diseño: `codelabs-brain/docs/63-plan-maestro-operativo-flota-tareas-lanzamiento-2026-09-23.md`,
apartados 2.6 y 12.3.

## Por qué existe (y qué sustituye)

Hasta el 23-sep-2026 había **dos** instaladores que no se hablaban:
`codelabs-setup` (mayo, plugins + hooks + `~/.devproxy`) y `claude-bootstrap`
(febrero, plugins públicos/privados desde GitHub con overlays). `claude-bootstrap`
queda **retirado** (su README lo marca; el repo no se borra, por si hace
falta consultar su historial). Todo lo útil de los dos vive ahora aquí, en un
único CLI: `codelabs-setup v2`.

## Regla de diseño (no negociable)

**Ningún portátil guarda secretos de producción.** Este instalador:
- Nunca copia un `.env` real. Si un repo trae `.env.example` / `.sample` /
  `.template` / `.dist`, genera un `.env` de DESARROLLO a partir de esa
  plantilla; lo que no tenga un valor de desarrollo se marca como
  `CHANGEME_DEV_<CLAVE>` con un aviso, nunca se inventa un valor plausible.
- Nunca exporta un secreto en un dotfile (`.zshrc`, `.bashrc`, `.profile`).
- El token de la máquina (de `POST /v1/fleet/machines/enroll`) se guarda
  donde lo leen los hooks de MemoryFirst: Keychain en macOS (vía
  `security -i` por stdin, nunca por argv) o un fichero 0600 en Linux.
  Nunca se imprime.
- Tailscale se conecta con login interactivo; este script **no lleva ni
  acepta una auth key**.

## Uso

```bash
git clone http://100.126.7.116:3300/jose/codelabs-setup.git
cd codelabs-setup

# qué haría, sin tocar nada
./bin/codelabs-setup enroll --name "mi-mac" --person jose.diaz@codelabs.studio \
    --pack developer --repos codelabs-brain,tubexperto --dry-run

# de verdad
./bin/codelabs-setup enroll --name "mi-mac" --person jose.diaz@codelabs.studio \
    --pack developer --repos codelabs-brain,tubexperto

# qué falta / qué hay instalado (nunca muestra valores de credenciales)
./bin/codelabs-setup doctor

# reintentar el alta en la flota si el primer enroll dio 404
./bin/codelabs-setup register
```

### Packs

| Pack | Claude Code | Docker | Maestro | Repos | Notas |
|---|---|---|---|---|---|
| `founder` | sí, con `codelabs-cofounder` | si la máquina lo aguanta | sí (con Java) | núcleo por defecto, o `--repos` | perfil de Jose |
| `developer` | sí | si la máquina lo aguanta | sí (con Java) | solo con `--repos` explícito | colaborador o empleado |
| `marketer` | **no** (no lo necesita) | no | no | ninguno | solo accesos directos a hub/partners/AlmaOS |
| `learner` | **no, nunca** (términos de Anthropic: 18+, sin excepción) | no | no | solo si se indica `--repos` | aprendiz (p. ej. un menor); mismos accesos que marketer |
| `worker` | sí (corre `claude -p` sin pantalla) | **no** (va enjaulado, sin socket de Docker) | no | los que le asigne su dueño | máquina trabajadora sin pantalla |

La definición completa de cada pack está en `packs/<nombre>.pack.sh`
(qué instala, qué plugins, qué repos por defecto).

### Capacidades deducidas del hardware

`codelabs-setup enroll` y `codelabs-setup doctor` miden:
- **docker**: instalable si la máquina lo aguanta. En macOS, **no** si el SO
  es anterior a 13 (caso i7 2015 con macOS 12) o si hay menos de 8 GB de RAM.
- **ios_build**: solo macOS, con Xcode instalado en una versión igual o por
  encima de la mínima que compila las apps actuales del portfolio (hoy 15).
- **max_parallel_agents**: el más restrictivo entre "1 agente cada 4 GB de
  RAM" y "1 agente cada 2 núcleos".

Estas reglas están en `lib/capabilities.sh`, documentadas junto al código.

## Estructura

```
codelabs-setup/
├── bin/
│   └── codelabs-setup          # CLI: enroll | doctor | register
├── lib/
│   ├── common.sh                # log/run/would/confirm, DRY_RUN
│   ├── hardware.sh               # detect_hardware (macOS y Linux)
│   ├── capabilities.sh           # docker / ios_build / max_parallel_agents
│   ├── packs.sh                  # carga packs/<nombre>.pack.sh
│   ├── steps.sh                  # un paso idempotente por herramienta
│   ├── fleet.sh                  # alta en MemoryFirst + token de máquina
│   └── doctor.sh                 # `codelabs-setup doctor`
├── packs/
│   ├── founder.pack.sh
│   ├── developer.pack.sh
│   ├── marketer.pack.sh
│   ├── learner.pack.sh
│   └── worker.pack.sh
├── install/                      # heredado de v1: caddy/mkcert/gh/jq/tmux + ~/.devproxy
│   ├── macos.sh
│   ├── linux.sh
│   └── dev-proxy.sh
├── templates/
│   ├── CLAUDE.md.team / .personal
│   └── hooks/{anti-sycophancy.py,sync-skills-cache.sh}
├── tests/
│   ├── test_hardware.sh          # detección de hardware y capacidades
│   └── test_pack_dry_run.sh      # mapeo pack → pasos, vía --dry-run
└── README.md
```

## Qué instala cada paso (`lib/steps.sh`)

- **Base** (si el pack instala Claude Code o clona código): Tailscale
  (login interactivo, nunca auth key), git, Node LTS, pnpm (vía corepack),
  Python 3.
- **Herramientas de desarrollo local** (solo `founder`/`developer`): caddy,
  mkcert, gh, jq, tmux, y `~/.devproxy/` para el plugin `codelabs-dev-servers`
  (heredado de codelabs-setup v1).
- **Docker**: solo si el pack lo pide y `CAP_DOCKER` es cierto.
- **Maestro**: solo si el pack lo pide y hay Java.
- **Claude Code + plugins del pack**, `CLAUDE.md` (plantilla personal o
  team), y una fusión segura (vía `jq`, igual que el instalador de hooks de
  MemoryFirst) de `hooks`/`enabledPlugins` en `settings.json` que nunca toca
  `permissions`, `mcpServers` ni nada que no sea suyo.
- **Hooks de MemoryFirst** desde `memoryfirst/packages/claude-hooks`
  (busca el repo en `~/Dev/code/memoryfirst`; si no está clonado en esta
  máquina, avisa y sigue).
- **Clonado de repos** (solo los del pack o los pasados con `--repos`,
  nunca "todos por si acaso") y generación de `.env` de desarrollo desde
  plantilla.
- **Accesos directos** (`marketer`/`learner`): `.webloc` en macOS o
  `.desktop` en Linux, en `~/Codelabs Links/`.
- **Alta en la flota**: `POST /v1/fleet/machines/enroll`
  (`https://api.memoryfirst.ai`). Es una ruta solo para el owner; el token
  que devuelve se muestra una sola vez y un nuevo enroll de la misma máquina
  revoca el anterior. Si la API responde 404 (por ejemplo, mientras se
  despliega), el perfil se guarda en `~/.config/codelabs/machine.json` y
  queda `codelabs-setup register` para reintentar sin repetir todo el enroll.

## Tests

```bash
bash tests/test_hardware.sh      # detección de hardware y capacidades
bash tests/test_pack_dry_run.sh  # los cinco packs, vía --dry-run, en un HOME temporal
```

`--dry-run` no instala ni escribe nada; el test de packs lo comprueba
literalmente (compara el contenido de un `$HOME` temporal antes y después).

## Idempotencia

Cada paso comprueba antes de actuar (`command -v`, `test -f`, `test -d`).
Volver a ejecutar `enroll` con el mismo pack no reinstala lo que ya está, no
duplica hooks ni plugins en `settings.json`, y no re-clona un repo que ya
existe.

## Licencia

MIT.
