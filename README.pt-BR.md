# Sirena

[English](README.md) · **Português**

Um app de barra de menus para macOS 15 ou mais novo que junta, num lugar só, as ferramentas do dia a dia: organizar janelas, ⌘ Tab com prévias, histórico da área de transferência, captura de texto, Pomodoro, seletor de cores, desenho na tela e mais.

## Recursos

**Atalhos** (menu ⚡ e Início)
- **Área de Transferência** — histórico pesquisável do que você copiou.
- **Fixar Janela** — mantém uma janela por cima de todas.
- **Capturar Texto** — copia o texto de qualquer parte da tela (OCR), QR codes e códigos de barras.
- **Captura de Tela** — atalho para a Captura de Tela da Apple: área, tela inteira ou gravação, já no modo escolhido. Por padrão, a captura é copiada e salva, na Mesa ou em Imagens › Screenshots.
- **Pomodoro** — timer de foco com pausas e contador na barra de menus.
- **Seletor de Cores** — captura cores da tela, histórico, paletas e vários formatos.
- **Desenho Livre** — desenhe, destaque e aponte por cima da tela; print de uma área selecionada (ou da tela inteira) com o desenho.
- **Espelho** — uma olhada rápida na câmera antes de uma chamada.

**Controles** — Não desligar tela, Desligar monitor (apaga a tela após uma contagem que dá para cancelar) e mixer de som (volume por app, saída e microfone).

**Recursos em segundo plano** — Janela e Dock (atalhos de janela, prévias no Dock, ⌘ Tab), Ícones Ocultos, Prateleira (arraste e solte) e Ilha Dinâmica.

## Compatibilidade

Funciona do **macOS 15 (Sequoia)** em diante. No macOS 26+ o visual usa Liquid Glass; nas versões anteriores o Sirena detecta a versão e usa os materiais translúcidos e botões clássicos do sistema, e os Ícones Ocultos usam a técnica do separador do Hidden Bar no lugar do recurso nativo do macOS 27.

## Instalação

Escolha um:

1. **Terminal, uma linha (recomendado).** Cole isto no Terminal:
   ```sh
   curl -fsSL https://witchmymac.com/install.sh | bash -s sirena
   ```
   Ele baixa a versão mais nova do GitHub, confere o SHA-256, instala o Sirena em Aplicativos e abre. Não aparece aviso do macOS, porque arquivos baixados pelo `curl` não ganham a marca de "baixado da internet". Rode a mesma linha de novo para atualizar. O script é aberto: [install.sh](https://witchmymac.com/install.sh).
2. **Baixe o DMG** em [Releases](https://github.com/matthfaria96/Sirena/releases) ou em [witchmymac.com](https://witchmymac.com), arraste o Sirena para Aplicativos (alguns recursos só funcionam a partir dessa pasta) e libere uma vez com:
   ```sh
   xattr -dr com.apple.quarantine "/Applications/Sirena.app"
   ```
   Ele só tira daquele app a marca de "baixado da internet".
3. **Baixe o DMG** e libere pelos Ajustes do Sistema: abra o app, clique em OK no aviso e vá em Ajustes do Sistema › Privacidade e Segurança › Abrir Mesmo Assim.

Depois, siga o onboarding para permitir **Acessibilidade** e **Gravação de Tela**.

## Compilar

Requer Xcode 27. O app gerado roda no macOS 15 ou mais novo.

```sh
xcodebuild -scheme Sirena -configuration Release -derivedDataPath build/DerivedData \
  -skipMacroValidation -skipPackagePluginValidation build
```

Esse build assina com o certificado local "Sirena Local Dev", que só é confiável no Mac onde foi criado. Para gerar os arquivos que vão para o Releases, use `scripts/package-release.sh`: ele assina ad hoc, sem Hardened Runtime, para que o app abra em qualquer Mac sem conta paga de desenvolvedor.

## Créditos e licença

O Sirena é distribuído sob a **GPL-3.0** (veja [LICENSE](LICENSE)), porque inclui código GPL-3.0. Partes vêm de projetos de código aberto, cada um com sua licença:

| Recurso | Baseado em | Licença |
|---|---|---|
| Janelas | [Rectangle](https://github.com/rxhanson/Rectangle) | MIT |
| Dock e prévias | [DockDoor](https://github.com/ejbills/DockDoor) | GPL-3.0 |
| ⌘ Tab, Ilha Dinâmica, mixer | [Vorssaint](https://github.com/vorssaint/vorssaint-utils) | GPL-3.0 |
| Área de Transferência | [Maccy](https://github.com/p0deje/Maccy) | MIT |
| Ícones Ocultos | [Hidden Bar](https://github.com/dwarvesf/hidden) | MIT |
| Não desligar tela | [Caffeine](https://github.com/domzilla/Caffeine) | MIT |
| Espelho | [Iris](https://github.com/ahmetb/Iris) | MIT |
| Som | [Fader](https://github.com/pantafive/fader) | MIT |

Fixar Janela, Capturar Texto, Melhorias, Prateleira, Pomodoro, Seletor de Cores e Desenho Livre foram escritos do zero, inspirados na lista de recursos de Floaty, TextSniper, Supercharge, Yoink, Flow, Pastel e ScreenBrush. Nenhum código desses apps comerciais foi usado.
