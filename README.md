# GPU Monitor

**GPU Monitor** é um aplicativo nativo e leve para macOS (`x86_64`), em Swift e SwiftUI, feito para monitorar GPUs NVIDIA através do driver **NullMoth** (`IOAccelerator` / `NVAccel`).

Ele vive na barra de menus do macOS (como o Stats), sem janela principal automática nem ícone no Dock, lendo diretamente do `IORegistry` o dicionário `PerformanceStatistics` publicado pelo driver.

## O que o app exibe

### Barra de menus
- Ícone discreto (`cpu`) ao lado do percentual do núcleo, por exemplo: `GPU 18%`.
- Atualiza aproximadamente a cada 1 segundo, mesmo com o painel fechado.
- Quando o indicador do núcleo não está disponível ou ocorre falha de leitura, exibe `GPU —` (nunca `0%` por padrão).

### Painel compacto
- **Nome da GPU**: obtido de forma confiável a partir da propriedade `model` do `IOPCIDevice` pai (por exemplo, `NVIDIA GeForce RTX 3060 Laptop GPU`), ou `GPU detectada` caso não seja possível identificá-lo com segurança.
- **Seletor multi-GPU** (exibido apenas quando há mais de um `IOAccelerator`): seleciona automaticamente a GPU NVIDIA quando identificada de forma inequívoca (`vendor-id == 0x10de` / sinais não conflitantes) ou permite escolher o dispositivo manualmente sem somar GPUs nem rotular outra GPU como NVIDIA.
- **Indicadores percentuais** (individuais, nunca somados, com barra visual de `0` a `100%`):
  1. **Núcleo da GPU** — `GPU Core Utilization %`
  2. **Uso do dispositivo** — `Device Utilization %`
  3. **Utilização da memória** — `GPU Memory Utilization %`
  4. **Motor de vídeo** — `GPU Video Engine Utilization %`
  5. **Decodificação de vídeo** — `GPU Video Decode Utilization %`
- **Temperatura** — `Temperature(C)`, exibida separadamente em `°C` (sem barra percentual).
- **Tratamento de anomalias**:
  - Campo ausente, booleano ou não numérico → exibe `Indisponível`.
  - Valor numérico fora de `0–100%` → preserva o número bruto na leitura e exibe aviso de valor inesperado, limitando apenas a barra visual ao intervalo `0–100%`.
  - Falha de leitura → exibe estado claro de erro e preserva o horário da última leitura bem-sucedida.
- **Botão Sair** (`⌘Q`) para encerrar o aplicativo normalmente.
- Suporte nativo aos modos **claro** e **escuro** do macOS.

## Como funciona a coleta

- **Caminho principal (`IOKit`)**: enumera dispositivos `IOAccelerator` via `IOServiceGetMatchingServices` e consulta apenas as propriedades necessárias com `IORegistryEntryCreateCFProperty`, sem shell e sem exigir `sudo`, alterações de permissões, extensões ou acesso à EFI.
- **Fallback estruturado (`ioreg`)**: caso a leitura direta via `IOKit` falhe, executa `/usr/sbin/ioreg -r -c IOAccelerator -d 1 -a` em segundo plano e interpreta o plist XML independentemente da ordem das chaves.
- **Sem recursos extras**: 100% local e somente leitura, sem comunicação com a internet, telemetria, gráficos históricos, daemons ou inicialização automática com o macOS.

## Precisão e limitações

> Os indicadores são fornecidos pelo driver, podem ter atraso e não identificam o aplicativo ou codec responsável.

- O campo `GPU Video Engine Utilization %` é exibido como **Motor de vídeo** (não como `NVENC` ou `Encoder`).
- Um valor positivo não comprova sozinho que um aplicativo específico está usando aceleração de hardware.

## Requisitos e compilação

- macOS Intel (`x86_64`) — testado em macOS Tahoe 26.7.3 com driver NullMoth 3.0.
- Xcode (testado com Xcode 26.6, `MACOSX_DEPLOYMENT_TARGET = 14.0`).

### Pelo Xcode
1. Abra `GPUMonitor.xcodeproj`.
2. Selecione o esquema **GPUMonitor** (`My Mac`).
3. Pressione `⌘R` para executar ou `⌘U` para rodar os testes unitários.

### Pelo Terminal
```bash
# Rodar testes unitários (x86_64)
xcodebuild test -project GPUMonitor.xcodeproj -scheme GPUMonitor -destination 'platform=macOS,arch=x86_64'

# Compilar Release (x86_64)
xcodebuild build -project GPUMonitor.xcodeproj -scheme GPUMonitor -configuration Release -destination 'platform=macOS,arch=x86_64'
```

## Estrutura do repositório

```text
gpu-monitor/
├── AGENTS.md                         # Guia de contexto e regras para agentes de IA
├── README.md
├── GPUMonitor.xcodeproj/             # Projeto Xcode e esquema compartilhado
├── GPUMonitor/
│   ├── GPUMonitorApp.swift           # MenuBarExtra (.window) + AppDelegate (.accessory)
│   ├── Info.plist                    # LSUIElement = true
│   ├── Models/GPUMetrics.swift       # Tipos, parser IORegistry, seleção multi-GPU e formatação
│   ├── Services/
│   │   ├── GPUCollecting.swift       # Protocolo e CompositeGPUCollector
│   │   ├── IOKitGPUCollector.swift   # Leitura direta IOKit / IORegistry
│   │   └── IORegFallbackCollector.swift # Fallback estruturado via /usr/sbin/ioreg -a
│   ├── ViewModels/GPUMonitorViewModel.swift # Polling assíncrono (~1s) e estado da UI
│   └── Views/
│       ├── MenuBarPanelView.swift    # Painel compacto da barra de menus
│       └── MetricRowView.swift       # Linha de indicador com barra 0–100%
└── GPUMonitorTests/
    └── GPUMonitorTests.swift         # Testes unitários e de integração com host
```
