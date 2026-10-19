# Sirena

Um app de barra de menus para macOS 26+ que junta, num lugar só, as ferramentas do dia a dia: organizar janelas, ⌘ Tab com prévias, histórico da área de transferência, captura de texto, Pomodoro, seletor de cores, desenho na tela e mais.

*A macOS menu bar app (macOS 26+) that brings window management, a ⌘ Tab switcher with previews, clipboard history, text capture, a Pomodoro timer, a color picker, screen drawing and more into one place. UI in Brazilian Portuguese.*

## Recursos

**Atalhos** (menu ⚡ e Início)
- **Área de Transferência** — histórico pesquisável do que você copiou.
- **Fixar Janela** — mantém uma janela por cima de todas.
- **Capturar Texto** — copia o texto de qualquer parte da tela (OCR), QR codes e códigos de barras.
- **Captura de Tela** — atalho para a Captura de Tela da Apple: área, tela inteira ou gravação, já no modo escolhido.
- **Pomodoro** — timer de foco com pausas e contador na barra de menus.
- **Seletor de Cores** — captura cores da tela, histórico, paletas e vários formatos.
- **Desenho Livre** — desenhe, destaque e aponte por cima da tela; print com o desenho.
- **Espelho** — uma olhada rápida na câmera antes de uma chamada.

**Controles** — Não desligar tela e mixer de som (volume por app, saída e microfone).

**Recursos em segundo plano** — Janela e Dock (atalhos de janela, prévias no Dock, ⌘ Tab), Ícones Ocultos, Prateleira (arraste e solte) e Ilha Dinâmica.

## Instalação

1. Baixe `Sirena.zip` na página de [Releases](../../releases) e mova `Sirena.app` para **/Applications** (alguns recursos só funcionam a partir dessa pasta).
2. O app não é notarizado pela Apple. Na primeira vez, clique com o botão direito em `Sirena.app` › **Abrir**, ou rode `xattr -dr com.apple.quarantine /Applications/Sirena.app`.
3. Siga o onboarding para permitir **Acessibilidade** e **Gravação de Tela**.

## Compilar

Requer Xcode 27 e macOS 26+.

```sh
xcodebuild -scheme Sirena -configuration Release -derivedDataPath build/DerivedData \
  -skipMacroValidation -skipPackagePluginValidation build
```

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
| Ajustes do reconhecimento em Capturar Texto | [TRex](https://github.com/amebalabs/TRex) | MIT |

Fixar Janela, Capturar Texto, Melhorias, Prateleira, Pomodoro, Seletor de Cores e Desenho Livre foram escritos do zero, inspirados na lista de recursos de Floaty, TextSniper, Supercharge, Yoink, Flow, Pastel e ScreenBrush. Nenhum código desses apps comerciais foi usado.
