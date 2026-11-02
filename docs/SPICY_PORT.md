# Celestify 2.4.0 · player, letras e Cinema nativos

## Auditoria da versão substituída

A versão 2.3.1 criava uma segunda WebView, carregava HTML e JavaScript locais e enviava posição e comandos pela interface Cinema. O DOM calculava retângulos normalizados para posicionar partes nativas sobre o conteúdo web. Durante transições, o toque dependia de duas superfícies com ciclos de layout diferentes. No player, a máscara da folha arredondava a superfície de fundo durante o gesto de fechar. O fundo dentro do painel de letras ainda tinha limites próprios. O [relatório histórico de 2.3.1](https://github.com/hinokame07/Celestify/blob/v2.3.1/docs/SPICY_PORT.md) documenta a implementação anterior.

## Arquitetura entregue

| Componente | Responsabilidade na versão nativa |
|---|---|
| `ImmersivePlayer.kt`, `ImmersivePlayerOverlay.kt`, `ImmersiveMiniPlayer.kt`, `PlayerControls.kt`, `ThinSlider.kt` | A capa e os metadados formam o cabeçalho em retrato. Em paisagem, o player divide o espaço entre arte/letras e transporte. O mini-player abre a folha existente. A máscara durante o arraste foi removida. A barra nativa recebe toque, arraste e ação de acessibilidade e lê o callback da faixa atual. Álbum, artista, favorito, fila, repetição, shuffle, dispositivos e extensões seguem ligados ao player existente. |
| `PlayerScreen.kt` e `LyricsScreen.kt` | As rotas Classic também usam o fundo nativo. A tela de letras posiciona conteúdo e insets acima de um fundo que cobre a janela. |
| `ImmersiveLyricsPanel.kt`, `SpicyStage.kt`, `SpicyDocument.kt`, `LyricsView.kt` | A rota Spicy entrega diretamente o documento Kotlin ao Canvas do Spicy Lyrics Mobile. A lista branca para texto sem sincronização continua disponível. O modo alternativo Celestify conserva a sua lista e as notas Genius. |
| `SpotifyMore.kt`, `Media.kt`, `LyricsApi.kt` | O adaptador HTTP carrega os dados e preserva o fim real da sílaba quando disponível. Para palavras com apenas início, o conversor pode usar o próximo início conhecido da mesma linha. O fim da última palavra não é prolongado até o fim da música. TTML com tempos e papéis vocais entra diretamente como documento rico. |
| `SpicyCinema.kt` | Dialog Compose em tela cheia. As áreas de arte, transporte e letra têm limites distintos. A letra e a capa trocam de posição sem desmontar o Canvas na vista dividida. A claquete abre o Cinema, a seta fecha, o olho mostra ou esconde controles. O menu permite romanização, volume, favorito, repetição, shuffle e videoclipe conforme disponibilidade. O Canvas silencioso e o videoclipe usam as superfícies de mídia nativas existentes. |
| `SpicyBackdrop.kt`, `Kawase.kt`, `WarpTexture.kt`, `res/raw/spicy_warp.glsl` | Glide decodifica a capa e o cache guarda texturas preparadas. Oito passagens Kawase sobre 128 × 128, deformação simplex de duas escalas, transição entre texturas, vinheta, saturação e dithering vêm de Kawarp 1.3.1. A textura GLES2 ocupa a janela, não recebe eventos de toque e usa o viewport real do EGL. Os insets e cantos da capa ficam exclusivamente na camada de conteúdo. Os modos Artista, Capa, Cores e Nenhum têm caminhos próprios. |

Os arquivos Kotlin do app estão sob `base/app/src/main/java`. O shader está em `base/app/src/main/res/raw`. O adaptador Spotify e seus modelos compartilhados estão em `base/api-spotify` e `base/api`. Foram retirados do aplicativo `CinemaSurface.kt`, `DesktopLyrics.kt`, a ponte JavaScript, a página e os bundles do desktop. O antigo teste de Chromium foi substituído por testes de entrada Compose.

## Reprodução e letras

O relógio do renderer consulta a posição da sessão por quadro com compensação de saída e ajuste manual. Pausa, buffering e busca usam o estado do SongPlayer. Os controles despacham comandos para a mesma sessão. A interface e a busca de letras funcionam sem um navegador de letras. As chamadas de catálogo e Spotify usam HTTP nativo e os arquivos TTML são processados no Android.

A sessão Spotify herdada do Myspoti continua usando o Web Player interno para autenticação e reprodução do catálogo quando essa é a fonte ativa. Downloads e fontes nativas usam o transporte já existente. Esta mudança não migra o motor de áudio do Spotify para um SDK Android. Os serviços hospedados mantêm suas exigências de autenticação. Nenhuma credencial é enviada para um renderer visual.

## Validação e limites

- `NativeCinemaTest` usa Android API 33 com Robolectric, gráficos nativos e eventos de ponteiro Compose. Exercita play/pause, anterior/próxima, arraste da barra, rolagem manual e seek no Canvas de letras, controles ocultos, troca de lado, mudança entre 390 × 820 e 840 × 390 dp e fechamento. Também exercita o transporte e o botão de fechar do player completo em ambos os formatos. Os dados e o relógio de teste são controlados.
- `KawaseTest` verifica conservação das cores inclusive nas bordas e mistura sem contaminação de canais. `SpicyDocumentTest` cobre texto estático, sincronização e duração. As suites existentes cobrem TTML, vocais secundários, animação e rolagem.
- O shader de produção compilou e vinculou em OpenGL ES usando EGL/SwiftShader do Android SDK. A leitura de pixels de dois quadros com a mesma textura verificou cobertura integral (alfa 255) e deslocamento temporal em 96 × 192 e 192 × 96. Essa medição isolada não representa a taxa de quadros do player.
- O AVD x86_64 chegou a ser criado e iniciado, mas não entrou online no ADB nesta máquina sem driver de aceleração do Android Emulator. Não houve sessão audiovisual em aparelho físico. Recorte de câmera específico, Bluetooth/Connect, vídeo de catálogo, desempenho sustentado e comparação visual quadro a quadro com o Spicy original permanecem sem confirmação em hardware.
- O renderer usa a tipografia disponível no Android. O movimento reage ao estado da reprodução sem análise de batidas da faixa. Por economia, o maior lado da superfície do shader é limitado a 960 pixels antes da composição. Movimento reduzido conserva a composição em repouso. Se o driver não oferecer o contexto necessário, há uma imagem nativa de recuperação.

## Reprodução dos testes

O comando de verificação usado a partir de `base` é `gradlew :app:testDebugUnitTest :host-android:testDebugUnitTest :api-spotify:test :extensions:test :host-cdp:test :app:assembleDebugAndroidTest :app:assembleRelease -PoverDev`. As cinco suítes registraram 744 testes, com 712 aprovações, 32 ignorados e zero falhas. O teste da claquete abriu e fechou o diálogo duas vezes pelo toque e verificou que o mesmo nó de tela permaneceu montado ao trocar a gravação.

O teste instrumental `WarpSurfaceDeviceTest` está em `base/app/src/androidTest`. Com um dispositivo conectado, `gradlew :app:connectedDebugAndroidTest` exercita a superfície Android real e verifica seus cantos após redimensionar. Ele não está incluído nas 712 aprovações.

## Licenças e referências

[Myspoti, GPL-3.0](https://github.com/kota-zo/myspoti) · [Spicy Lyrics Desktop, revisão 34ad8c6](https://github.com/spikerko/spicy-lyrics/tree/34ad8c683204c522f227060475bf4f8aae36508e) · [Spicy Lyrics Mobile, revisão 4565dde](https://github.com/spicylyrics/mobile/tree/4565dde58003a7796c2be32f3022cef773dfa73b). Os componentes Spicy mantêm AGPL-3.0. Os avisos de Kawarp e das demais dependências acompanham o fonte e o APK em `base/licenses` e `THIRD_PARTY_NOTICES.md`.
