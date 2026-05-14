# Driver WDDM para AMD BC-250 (Cyan Skillfish / RDNA2)

**Versão:** 1.0.100.0  
**Data:** 09 de março de 2026  
**Plataforma:** Windows 10 (1607+) / Windows 11 — x64 apenas  
**Arquitetura de Driver:** WDDM 2.0 (Windows Display Driver Model)

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Especificações do Hardware](#2-especificações-do-hardware)
3. [Arquitetura do Driver](#3-arquitetura-do-driver)
4. [Estrutura de Arquivos](#4-estrutura-de-arquivos)
5. [Identificadores PCI](#5-identificadores-pci)
6. [Componentes do Driver](#6-componentes-do-driver)
7. [Sequência de Inicialização](#7-sequência-de-inicialização)
8. [Gerenciamento de Memória](#8-gerenciamento-de-memória)
9. [Submissão de Comandos](#9-submissão-de-comandos)
10. [Gerenciamento de Interrupções](#10-gerenciamento-de-interrupções)
11. [Motor de Display (DCN 2.01)](#11-motor-de-display-dcn-201)
12. [Gerenciamento de Energia](#12-gerenciamento-de-energia)
13. [Compilação e Build](#13-compilação-e-build)
14. [Instalação](#14-instalação)
15. [Limitações Conhecidas](#15-limitações-conhecidas)
16. [Referências Técnicas](#16-referências-técnicas)

---

## 1. Visão Geral

O **AMD BC-250** é um APU (Accelerated Processing Unit) baseado na arquitetura **Cyan Skillfish** (codinome interno da AMD), originalmente desenvolvido para placas de mineração de criptomoedas fabricadas pela ASRock. Trata-se de uma versão reduzida do SoC "Oberon" que equipa o PlayStation 5, com 6 núcleos Zen 2 e uma iGPU RDNA2 de 24 Compute Units (1536 Stream Processors).

Este projeto implementa um driver de display WDDM (Windows Display Driver Model) para o BC-250, permitindo que o Windows reconheça e utilize a GPU RDNA2 integrada para aceleração gráfica. O driver segue a especificação WDDM 2.0, compatível com Windows 10 (build 14393 ou posterior) e Windows 11.

> **Aviso Importante:** Este driver é um projeto de referência e pesquisa. A AMD não fornece suporte oficial para o BC-250 no Windows. O hardware foi projetado para Linux, onde recebe suporte completo via driver amdgpu e Mesa RADV. O uso deste driver em produção é de responsabilidade do usuário.

---

## 2. Especificações do Hardware

A tabela a seguir resume as especificações técnicas relevantes para o desenvolvimento do driver:

| Componente | Especificação |
|---|---|
| **APU Codinome** | Cyan Skillfish / Ariel (variante do PS5 Oberon) |
| **Arquitetura CPU** | AMD Zen 2, 6 núcleos / 12 threads, até 3,49 GHz |
| **Arquitetura GPU** | RDNA2 (GFX10.1 / Navi 1x) |
| **Compute Units** | 24 CUs (1536 Stream Processors) |
| **Shader Engines** | 1 SE com 2 Shader Arrays |
| **Tamanho do Wavefront** | 32 (modo Wave32 do RDNA2) |
| **Memória** | 16 GB GDDR6 compartilhada (UMA) |
| **Largura do Barramento** | 256 bits |
| **Clock Base da GPU** | 1000 MHz |
| **Clock Boost da GPU** | ~2000 MHz |
| **Clock da Memória** | 1750 MHz |
| **Saída de Vídeo** | 1x DisplayPort (DCN 2.01) |
| **TDP** | 220 W |
| **Interface** | PCIe (integrado ao APU) |
| **Fabricante da Placa** | ASRock (formato rack 4U) |

A GPU utiliza o motor de display **DCN 2.01** (Display Core Next), que suporta DisplayPort 1.4 com resolução máxima de 7680×4320 (8K) a 60 Hz, ou 4K a 120 Hz.

---

## 3. Arquitetura do Driver

O modelo WDDM divide o driver em dois componentes principais, conforme a arquitetura definida pela Microsoft:

```
┌─────────────────────────────────────────────────────────┐
│                    Aplicação D3D/Vulkan                  │
├─────────────────────────────────────────────────────────┤
│              Direct3D Runtime (d3d9/d3d11/d3d12)        │
├─────────────────────────────────────────────────────────┤
│         User-Mode Driver (UMD) — amdbc250umd64.dll      │  ← Espaço do Usuário
│    Constrói command buffers (DMA) com pacotes PM4        │
├─────────────────────────────────────────────────────────┤
│              gdi32.dll (thunks para kernel)              │
├─────────────────────────────────────────────────────────┤
│         DirectX Kernel Subsystem (dxgkrnl.sys)          │  ← Espaço do Kernel
│         Agendador (VidSch) + Gerenciador de Memória     │
├─────────────────────────────────────────────────────────┤
│    Kernel-Mode Driver (KMD) — amdbc250kmd.sys           │
│    Controla hardware: rings, IH, display, power         │
├─────────────────────────────────────────────────────────┤
│              Hardware AMD BC-250 (RDNA2 GPU)             │
└─────────────────────────────────────────────────────────┘
```

O **KMD** (Kernel-Mode Display Miniport Driver) é responsável por toda a comunicação direta com o hardware: mapeamento de registradores MMIO, inicialização dos ring buffers, tratamento de interrupções, gerenciamento de energia e controle do motor de display. O **UMD** (User-Mode Display Driver) é uma DLL carregada pelo runtime D3D que constrói os command buffers com pacotes PM4 (o protocolo de comandos da GPU AMD) e os submete ao KMD via chamadas de sistema.

---

## 4. Estrutura de Arquivos

```
amd-bc250-driver/
├── inc/
│   ├── amdbc250_hw.h          # Definições de hardware: IDs PCI, offsets MMIO,
│   │                          #   registradores, pacotes PM4, constantes
│   └── amdbc250_kmd.h         # Interface do KMD: estruturas WDDM, device
│                              #   extension, protótipos de callbacks DDI
├── src/
│   ├── kmd/
│   │   ├── amdbc250_kmd.c     # DriverEntry + todos os callbacks WDDM DDI
│   │   └── amdbc250_hw_init.c # Inicialização de hardware: rings, IH, display,
│   │                          #   memória, SMU, reset
│   └── umd/
│       ├── amdbc250_umd.c     # User-Mode Driver: OpenAdapter, CreateDevice,
│       │                      #   DrawPrimitive, Present, shaders
│       └── amdbc250umd.def    # Arquivo de exportação da DLL
├── inf/
│   └── amdbc250.inf           # Arquivo INF de instalação do driver Windows
├── build/
│   ├── amdbc250kmd.vcxproj    # Projeto MSBuild para o KMD (.sys)
│   └── amdbc250umd.vcxproj    # Projeto MSBuild para o UMD (.dll)
├── tools/
│   ├── Install-Driver.ps1     # Script PowerShell de instalação
│   └── Uninstall-Driver.ps1   # Script PowerShell de desinstalação
└── docs/
    └── README.md              # Esta documentação
```

---

## 5. Identificadores PCI

O Windows utiliza os identificadores PCI para associar o hardware ao driver correto. O arquivo INF declara os seguintes hardware IDs para o BC-250:

| Hardware ID | Descrição |
|---|---|
| `PCI\VEN_1002&DEV_13FE` | BC-250 variante principal (ASRock) |
| `PCI\VEN_1002&DEV_143F` | BC-250 variante alternativa |
| `PCI\VEN_1002&DEV_13DB` | Cyan Skillfish família estendida |
| `PCI\VEN_1002&DEV_13F9` | Cyan Skillfish família estendida |
| `PCI\VEN_1002&DEV_13FA` | Cyan Skillfish família estendida |
| `PCI\VEN_1002&DEV_13FB` | Cyan Skillfish família estendida |
| `PCI\VEN_1002&DEV_13FC` | Cyan Skillfish família estendida |

O Vendor ID `0x1002` pertence à Advanced Micro Devices, Inc. (AMD/ATI). Os Device IDs foram obtidos dos patches do driver Linux amdgpu submetidos por Alex Deucher (AMD) em junho de 2025.

---

## 6. Componentes do Driver

### 6.1 Kernel-Mode Driver (amdbc250kmd.sys)

O KMD implementa os seguintes callbacks WDDM DDI (Device Driver Interface):

| Callback | Função |
|---|---|
| `DxgkDdiAddDevice` | Aloca e inicializa a device extension |
| `DxgkDdiStartDevice` | Mapeia BARs PCI, inicializa hardware |
| `DxgkDdiStopDevice` | Para GPU, libera recursos |
| `DxgkDdiRemoveDevice` | Limpeza final |
| `DxgkDdiResetDevice` | Reset TDR (Timeout Detection & Recovery) |
| `DxgkDdiInterruptRoutine` | ISR: lê status de interrupção (DIRQL) |
| `DxgkDdiDpcRoutine` | DPC: processa entradas do IH ring |
| `DxgkDdiQueryAdapterInfo` | Reporta capacidades da GPU ao WDDM |
| `DxgkDdiCreateDevice` | Cria contexto por processo |
| `DxgkDdiCreateAllocation` | Aloca memória GPU |
| `DxgkDdiSubmitCommand` | Submete command buffer ao ring GFX |
| `DxgkDdiQueryCurrentFence` | Retorna valor atual do fence |
| `DxgkDdiBuildPagingBuffer` | Constrói comandos SDMA para paginação |
| `DxgkDdiQueryChildRelations` | Reporta saída DisplayPort |
| `DxgkDdiCommitVidPn` | Aplica configuração de display |
| `DxgkDdiSetPowerState` | Gerencia estados de energia D0-D3 |

### 6.2 User-Mode Driver (amdbc250umd64.dll)

O UMD exporta a função `OpenAdapter` como ponto de entrada, que preenche a tabela de funções D3D DDI:

| Função DDI | Descrição |
|---|---|
| `OpenAdapter` | Abre o adaptador, retorna tabela de funções |
| `CreateDevice` | Cria dispositivo D3D por aplicação |
| `CreateResource` | Aloca textura/buffer via D3DKMTCreateAllocation |
| `DrawPrimitive` | Emite pacote PM4 `DRAW_INDEX_AUTO` |
| `Present` | Flip/blit do back buffer para display |
| `Flush` | Submete command buffer via D3DKMTSubmitCommand |
| `Lock/Unlock` | Mapeamento CPU de recursos GPU |
| `CreateVertexShader/PixelShader` | Compilação e upload de shaders |
| `SetRenderState` | Configuração de estado de renderização |

---

## 7. Sequência de Inicialização

A inicialização do hardware segue esta ordem obrigatória para a arquitetura RDNA2:

**Passo 1 — SMU (System Management Unit):** O SMU controla clocks e tensões. O driver aguarda o SMU estar pronto (registrador `MP1_SMN_P2CMSG_33`) e envia a mensagem `EnableAllSmuFeatures`.

**Passo 2 — Controlador de Memória:** Configura o registrador `GB_ADDR_CONFIG` com a topologia de memória RDNA2: 4 pipes, interleave de 256 bytes, largura de 256 bits.

**Passo 3 — IH Ring (Interrupt Handler):** Aloca 64 KB de memória fisicamente contígua para o ring de interrupções. Programa os registradores `IH_RB_BASE`, `IH_RB_CNTL` e habilita interrupções via `IH_CNTL`.

**Passo 4 — GFX Ring:** Aloca 1 MB para o ring de comandos GFX. Programa `CP_RB0_BASE`, `CP_RB0_CNTL`, inicializa ponteiros RPTR/WPTR. Carrega microcode do CP (PFP + ME + MEC) e resume o processador de comandos.

**Passo 5 — SDMA Ring:** Aloca 256 KB para o ring SDMA (usado para transferências DMA entre VRAM e memória do sistema). Programa `SDMA0_GFX_RB_BASE` e `SDMA0_GFX_RB_CNTL`.

**Passo 6 — Display (DCN 2.01):** Habilita o CRTC0 e programa os registradores de timing para o modo padrão 1920×1080@60Hz.

---

## 8. Gerenciamento de Memória

O BC-250 usa uma arquitetura UMA (Unified Memory Architecture): os 16 GB de GDDR6 são compartilhados entre CPU e GPU. O driver expõe dois segmentos de memória ao WDDM:

| Segmento | Tipo | Tamanho | Uso |
|---|---|---|---|
| Segmento 0 | VRAM (aperture) | Configurável (padrão 512 MB) | Texturas, render targets, buffers GPU |
| Segmento 1 | Memória do sistema | 4 GB (aperture) | Eviction, recursos CPU-visíveis |

A alocação de VRAM é controlada pelo BIOS. A configuração recomendada é **512 MB dinâmico** (configurado via BIOS modificado P3.00). O driver lê o tamanho disponível e o reporta ao WDDM via `DxgkDdiQueryAdapterInfo` com o tipo `DXGKQAITYPE_QUERYSEGMENT`.

Para ring buffers e estruturas de controle, o driver usa `MmAllocateContiguousMemorySpecifyCache` com o tipo `MmWriteCombined`, que é o tipo de cache adequado para memória de escrita sequencial em hardware de GPU.

---

## 9. Submissão de Comandos

O fluxo de submissão de comandos segue o modelo WDDM padrão:

**No UMD:** A aplicação chama funções D3D (ex: `DrawIndexed`). O UMD constrói um **DMA buffer** (command buffer) preenchido com pacotes PM4. O pacote principal é o `INDIRECT_BUFFER` (opcode `0x3F`), que aponta para o buffer de comandos da aplicação.

**No KMD:** O `DxgkDdiSubmitCommand` recebe o DMA buffer e o insere no **GFX Ring** usando um pacote PM4 `INDIRECT_BUFFER`. O ponteiro de escrita (WPTR) é então atualizado no registrador `CP_RB0_WPTR` ou via **doorbell** (mecanismo de notificação de baixa latência).

**Sincronização:** O GPU escreve o valor do fence na memória de fence quando o comando é concluído (evento EOP — End of Pipe). O ISR detecta a entrada no IH ring com `ClientId = 0x0A` (GFX) e `SrcId = 0xE0` (EOP), e notifica o WDDM via `DxgkCbNotifyInterrupt` com `DXGK_INTERRUPT_DMA_COMPLETED`.

---

## 10. Gerenciamento de Interrupções

O BC-250 usa o mecanismo **IH (Interrupt Handler) ring** da AMD para todas as interrupções de hardware. O IH ring é um buffer circular de 64 KB onde o hardware escreve entradas de 16 bytes (4 DWORDs) para cada evento.

Cada entrada contém:
- **DW0[7:0]:** Source ID (tipo de evento)
- **DW0[15:8]:** Client ID (subsistema de origem)
- **DW1:** Dados do evento (ex: fence ID para EOP)
- **DW2-3:** Dados adicionais

O ISR (`DxgkDdiInterruptRoutine`) roda em DIRQL e apenas verifica se há novas entradas comparando o WPTR do hardware com o RPTR salvo. Se houver, agenda uma DPC. A DPC (`DxgkDdiDpcRoutine`) processa as entradas e notifica o WDDM:

| Client ID | Evento | Ação |
|---|---|---|
| `0x0A` (GFX) | EOP (SrcId=0xE0) | `DXGK_INTERRUPT_DMA_COMPLETED` |
| `0x08` (DCE) | VSYNC | `DXGK_INTERRUPT_CRTC_VSYNC` |
| `0x11` (VMC) | Falha de página | Tratamento de erro |

---

## 11. Motor de Display (DCN 2.01)

O BC-250 possui um único motor de display **DCN 2.01** (Display Core Next versão 2.01), que suporta uma saída DisplayPort. O driver implementa o gerenciamento de VidPN (Video Present Network) exigido pelo WDDM:

O callback `DxgkDdiQueryChildRelations` reporta um filho do tipo `TypeVideoOutput` com interface `D3DKMDT_VOT_DISPLAYPORT_EXTERNAL`. O callback `DxgkDdiQueryChildStatus` verifica o pino HPD (Hot Plug Detect) para detectar monitores conectados.

O timing de display padrão programado é **1920×1080 @ 60 Hz** (HDTV 1080p), com os seguintes parâmetros:

| Parâmetro | Valor |
|---|---|
| H Total | 2200 pixels |
| V Total | 1125 linhas |
| H Blank | 1920–2200 |
| V Blank | 1080–1125 |
| H Sync | 2008–2052 |
| V Sync | 1084–1089 |
| Pixel Clock | 148,5 MHz |

---

## 12. Gerenciamento de Energia

O driver implementa `DxgkDdiSetPowerState` para transições entre estados de energia:

| Estado | Descrição | Ação do Driver |
|---|---|---|
| D0 | Operação normal | Habilita clocks via SMU (MSG_66=1) |
| D1 | Espera leve | Reduz clocks (ULPS) |
| D2 | Espera profunda | Desliga clocks não essenciais |
| D3 | Desligamento | Para GPU, desabilita clocks (MSG_66=0) |

O driver também suporta **ULPS** (Ultra Low Power State) para o link DisplayPort quando nenhum monitor está conectado, reduzindo o consumo de energia em repouso.

---

## 13. Compilação e Build

### Pré-requisitos

Para compilar o driver, são necessários:

- **Windows Driver Kit (WDK)** versão 10.0.26100 ou posterior
- **Visual Studio 2022** com workload "Desenvolvimento para Desktop com C++"
- **Windows SDK** versão 10.0.26100 ou posterior

### Compilando o KMD

```powershell
# Abrir o Developer Command Prompt do WDK
cd amd-bc250-driver\build

# Compilar o driver kernel-mode
msbuild amdbc250kmd.vcxproj /p:Configuration=Release /p:Platform=x64

# Saída: Release\x64\amdbc250kmd.sys
```

### Compilando o UMD

```powershell
# Compilar o driver user-mode
msbuild amdbc250umd.vcxproj /p:Configuration=Release /p:Platform=x64

# Saída: Release\x64\amdbc250umd64.dll
```

### Assinatura do Driver

Drivers de kernel no Windows 10/11 x64 requerem assinatura digital. Para testes, habilite o modo de assinatura de teste:

```cmd
bcdedit /set testsigning on
```

Para produção, o driver deve ser assinado com um certificado EV (Extended Validation) e submetido ao WHQL (Windows Hardware Quality Labs) da Microsoft para obter assinatura oficial.

---

## 14. Instalação

### Instalação Automática (PowerShell)

```powershell
# Executar como Administrador
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Habilitar test signing e instalar
.\tools\Install-Driver.ps1 -EnableTestSigning -Force
```

### Instalação Manual

**Passo 1:** Habilitar test signing (requer reboot):
```cmd
bcdedit /set testsigning on
shutdown /r /t 0
```

**Passo 2:** Copiar arquivos do driver:
```cmd
copy amdbc250kmd.sys %SystemRoot%\System32\drivers\
copy amdbc250umd64.dll %SystemRoot%\System32\
copy amdbc250umd.dll %SystemRoot%\System32\
```

**Passo 3:** Instalar via PnPUtil:
```cmd
pnputil /add-driver amdbc250.inf /install
```

**Passo 4:** Verificar no Gerenciador de Dispositivos:
- Abrir `devmgmt.msc`
- Expandir "Adaptadores de Vídeo"
- Verificar se "AMD BC-250 APU (Cyan Skillfish) - RDNA2 GPU" aparece sem erros

### Desinstalação

```powershell
.\tools\Uninstall-Driver.ps1
```

---

## 15. Limitações Conhecidas

Este driver é uma implementação de referência com as seguintes limitações:

**Microcode do CP:** O driver não carrega o microcode do Command Processor (arquivos `navi10_pfp.bin`, `navi10_me.bin`, `navi10_mec.bin`). Ele depende do microcode já carregado pelo BIOS/UEFI. Uma implementação completa requereria o carregamento desses firmwares proprietários da AMD.

**Firmware VCN:** O motor de codificação/decodificação de vídeo (VCN) não é suportado. A Sony bloqueia o firmware VCN no BC-250 (mesmo problema no Linux).

**Vulkan/D3D12:** O UMD implementa apenas a interface D3D9 DDI. Suporte a D3D11, D3D12 e Vulkan requereria implementações adicionais das respectivas interfaces DDI.

**Shaders RDNA2:** A compilação de shaders RDNA2 (ISA GFX10.1) requer um compilador de shaders completo. Esta implementação aceita shaders mas não os compila para o hardware real.

**Modo de Assinatura:** O driver não possui assinatura WHQL e requer test signing habilitado.

**Suporte a Múltiplos Monitores:** O BC-250 possui apenas uma saída DisplayPort, portanto apenas um monitor é suportado.

---

## 16. Referências Técnicas

As seguintes fontes foram utilizadas no desenvolvimento deste driver:

| # | Referência |
|---|---|
| [1] | [AMD BC-250 Documentation (mothenjoyer69)](https://github.com/mothenjoyer69/bc250-documentation) |
| [2] | [AMD BC-250 Community Documentation](https://elektricm.github.io/amd-bc250-docs/) |
| [3] | [WDDM Architecture — Microsoft Docs](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/windows-vista-and-later-display-driver-model-architecture) |
| [4] | [Microsoft Graphics Driver Samples](https://github.com/microsoft/graphics-driver-samples) |
| [5] | [AMD Cyan Skillfish PCI IDs Patch (Alex Deucher, 2025)](https://lists.freedesktop.org/archives/amd-gfx/2025-June/126737.html) |
| [6] | [AMD amdgpu Linux Driver Source (kernel.org)](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/amd) |
| [7] | [AMD BC-250 Hashrate Specifications](https://www.hashrate.no/gpus/bc250/specs) |
| [8] | [WDDM 2.0 Overview — Microsoft Docs](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/windows-vista-display-driver-model-design-guide) |
| [9] | [D3DKMT Kernel-Mode Thunk Functions](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/_display/) |
| [10] | [AMD RDNA2 ISA Reference Guide (AMD GPUOpen)](https://gpuopen.com/rdna2-isa-documentation/) |

---

*Documentação — Projeto AMD BC-250 Windows Driver*

---

## Collaboration Stats (Current)

For shared debugging and reproducibility, current status snapshots are published under `stats/`.

- `stats/driver_status_2026-05-14.md`
- `stats/driver_status_2026-05-14.json`

Regenerate stats from the latest `TEST_MATRIX.md` and `PROGRESS.md`:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\generate-collab-stats.ps1
```

Before pushing new runs:

1. Update `TEST_MATRIX.md` with one-change-per-test results.
2. Update `PROGRESS.md` with timeline notes and blockers.
3. Regenerate `stats/*` using the script above.
4. Commit all three (`TEST_MATRIX.md`, `PROGRESS.md`, `stats/*`) together.
