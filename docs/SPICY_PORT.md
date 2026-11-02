# Port Android do Spicy Lyrics

Referência primária: [Spicy Lyrics desktop, 34ad8c6](https://github.com/Spikerko/spicy-lyrics/tree/34ad8c683204c522f227060475bf4f8aae36508e). Base Android: [Myspoti](https://github.com/kota-zo/myspoti). Referência secundária: [Spicy Lyrics Mobile, 4565dde](https://github.com/spicylyrics/mobile/tree/4565dde58003a7796c2be32f3022cef773dfa73b).

## Arquitetura e escopo

No desktop, PageView constrói a página e NowBar conecta seus controles ao Spotify. Fullscreen move a página, instala os listeners e governa as molas de opacidade, brilho e posição. Applyer monta as linhas, LyricsVirtualizer mede e recicla os elementos, LyricsSetter classifica os tempos e LyricsAnimator atualiza as letras. DynamicBG usa Kawarp 1.3.1 e CanvasImmersive usa o loop da faixa. O painel React configura esses módulos por stores.

No Celestify, SongPlayer, Graph e PlayerViewModel já têm a sessão de reprodução. LyricsViewModel, LyricsApi, SpicyCatalogue e SpicyImports resolvem as fontes. O parser TTML mantém grupos de sílabas, intervalos, duetos e vocais secundários. A alternativa puramente nativa já tem um renderer funcional em com/tx24/spicyplayer, mas não reproduzia a composição do Cinema do desktop. O port híbrido reutiliza os módulos web empacotados, mantém a resolução de dados e os transportes no Android e reserva o renderer nativo para as apresentações que precisam dele.

## Matriz de paridade

| Área e módulos de origem | Recursos auditados | Evidência e limites |
|---|---|---|
| PageView, NowBar, Fullscreen, CompactMode | modo normal, Cinema, fullscreen, compacto, troca de lado, metadata, coração, controles, timeline, volume, ocultação e bloqueio durante arraste | CSS e controlador originais no APK. Teste Chromium com ponte de teste em 1280×800, 800×1100 e 390×844. A ponte Android usa o player real. |
| Animator, Applyer, LyricsVirtualizer, ScrollToActiveLine | sílaba, palavra, caractere, linha, pausas instrumentais, fundo vocal, duetos, classes RTL, lista estática, auto-follow, rolagem livre, seek | Conversão TTML e renderer Android existentes têm testes JVM. A validação comparativa quadro a quadro em aparelho continua pendente. |
| DynamicBG e CanvasImmersive | Dynamic, Artist, Cover, Color, None, blur, Canvas e queda para a capa | Kawarp e CSS de Canvas empacotados. A disponibilidade do vídeo depende do catálogo e das preferências de dados/energia. |
| PlaybackSection | offset, compensação de seek, antecipação e distância, rolagem suave | Relógio da sessão local, ajuste de latência e seek pelo Android. Connect depende do estado fornecido pela sessão. |
| LyricsSection | simple, minimal, junção de sílabas, transliteração, hover, recuo de dueto, alinhamento dos créditos | Formatos ricos preservados. Mapeamento para fonte e idiomas depende do texto recebido. |
| BackgroundSection | estilo e blur das imagens, fundo do painel Now Playing | O painel lateral do Spotify Desktop não existe no Android. |
| InterfaceSection | posição dos controles, timeline externa, bloqueio da capa, aviso de letra ausente, volume, Now Playing e ocultação sem letra, PiP, esconder botão nativo do Spotify | PiP usa a activity flutuante. A injeção em botões e painéis do cliente desktop é específica do Spicetify. |
| AppearanceSection | fonte do sistema ou do tema, limite de FPS e valor do limite | O APK usa as fontes licenciadas e as fontes do Android. Taxas efetivas dependem do aparelho. |
| ExperimentsSection | newProgressBarStyling, lyricsSkeleton, canvasImmersive, npvCanvasBackground, popupDock, refinedBackground, refreshedSimpleLyrics, refinedCredits, scrubPreview, backgroundLinePop, keepOverlappingLines | Controles e efeitos do desktop não são automaticamente equivalentes a uma opção no Android. Regras remotas e experimentos do painel desktop não têm validação Android. |
| LyricsManager, serviços, AdvancedSection | importar, pré-visualizar, salvar, remover, buscar faixa, cache atual/global, estado da faixa, developer mode, catálogo e envio comunitário | Arquivos locais por gravação, cache nativo e catálogo autorizado. Upload de comunidade e administração de contas exigem um serviço com autorização própria. |
| Integrações específicas de plataforma | atalhos de teclado, Discord, extensão Marketplace, atualizações Spicetify, menu de contexto da janela, popup e painel NPV | A janela flutuante e as releases privadas têm implementações Android. APIs do shell Spotify Desktop não fazem parte da ponte. |

## Implementação e alcance

| Destino no repositório | Mudança |
|---|---|
| `third_party/spicy-renderer` | Applyer, Animator, LyricsSetter, virtualização, rolagem, segmentação de letras, molas e créditos. Dos 27 módulos TypeScript aqui, 26 correspondem ao checkout oficial. O outro é o agendador de quadros, adaptado para suspender em segundo plano ou após a estabilização da pausa. |
| `third_party/spicy-cinema` | Fullscreen, CanvasImmersive, Spring, Scheduler, Maid, ícones, transferência de elementos e skeleton mantêm o TypeScript original. O build troca as importações do host e gera módulos locais. |
| `base/app/src/main/assets/spicy-cinema` | Estrutura da página, controles por toque, ponte de mídia e estilos originais. Inclui o pacote publicado de Kawarp 1.3.1. O código de Canvas do desktop cria duas camadas de vídeo, mistura as transições, desenha a luz ambiental e anima a troca de lado. |
| `ui/immersive/lyrics/{CinemaSurface,SpicyCinema,DesktopLyrics,SpicyStage}.kt` | WebView local isolada, sessão reaproveitada entre painel e Cinema, transporte do Celestify, compensação de latência, TTML, ações de toque, fullscreen e PiP. Os caminhos Kotlin são relativos a `base/app/src/main/java/com/music/spotui`. |
| `ui/immersive/pages/ImmersiveSettingsScreen.kt`, `data/api/Api.kt`, recursos `values` e `values-pt` | Preferências persistentes por categoria, cache por faixa e global, diagnóstico da faixa, arte do artista e textos em português e inglês. |
| `tools/test-cinema.mjs`, `SpicyDocumentTest.kt` | Regressões do conteúdo embarcado e da conversão de TTML para o formato do Applyer. |

O botão de claquete no painel de letras abre o Cinema. O toque na capa revela os controles. A troca de lado fica disponível no layout dividido. Tablets que iniciam no compacto podem alternar pelo controle de layout. Quando o provedor devolve um videoclipe compatível, a engrenagem oferece a troca de áudio para vídeo. O Canvas é um loop mudo da faixa e pode aparecer automaticamente.

**Dados e serviços.** A importação TTML local, o preview, a persistência por gravação, a biblioteca e a restauração funcionam sem uma conta Spicy. O catálogo hospedado exige uma chave publicável válida. A ponte passa a mídia autorizada e o documento de letras para a WebView e mantém a conta do Spotify no player do Android. Letras estáticas usam o leitor branco sem animações. Preferências de movimento reduzido e documentos com sincronização incompleta usam o renderer Android. O diagnóstico e a limpeza de cache são locais. Não há envio de sincronizações para contas comunitárias.

**Diferenças visuais identificadas.** A fonte embarcada é Inter, com alternativa do sistema. A distribuição original referencia fontes externas. Na ausência da análise de áudio do Spotify Desktop, a velocidade de Kawarp acompanha reprodução e pausa. O estilo Cover Colors usa a média de 8 × 8 e os quatro fatores de escurecimento do fallback original. O Android não recebe o conjunto de contraste do GraphQL do Spotify Desktop. O Canvas depende das políticas de dados, energia e disponibilidade da mídia. A janela PiP também está sujeita aos controles de toque do próprio Android.

## Validação

- Os relatórios JUnit dos cinco módulos somam 739 testes. Foram 707 aprovações e 32 testes ignorados, sem falhas. Trinta exigem a infraestrutura de navegador CDP e dois são testes de rede opcionais.
- No Chromium com toque, a caixa da capa em 1280 × 800 ficou a menos de dois pixels CSS da página construída a partir do template e CSS da revisão oficial. O teste cobre dupla entrada e saída do Cinema, troca de lado, seeks para frente e para trás, classes de dueto, ênfase por caractere, janela flutuante e rotação de viewport. Uma letra de 260 versos alcançou o verso 219 sem montar todos os versos no DOM.
- A leitura de pixels na saída WebGL detectou quadros distintos gerados pelo Kawarp a partir de uma única capa. Os estilos de imagem e a troca para fundo vazio também foram exercitados. As capturas usam material controlado de teste. A referência utiliza o template do desktop isolado. Ela não substitui uma sessão do aplicativo Spotify Desktop.
- O teste de Canvas carregou um vídeo VP8 sintético por uma URL interceptada antes de sair do navegador. Verificou a ativação das duas camadas originais, avanço de tempo, pausa e troca de lado. O vídeo de teste acompanha o código-fonte. A suite também exercitou a mudança de retrato para paisagem em 844 × 390 e a reserva de espaço para o dock de PiP em 320 × 200.
- O build otimizado passou em `:app:assembleRelease -PoverDev` com análise de lint vital. O APK contém os bundles do renderer e de CanvasImmersive. O manifesto informa `app.myspoti.dev`, versão `2.3.1`, código `2003001`. O `apksigner` confirmou assinatura v2 e certificado SHA-256 `59ca6698986db2eaf412b803ecb40842e2c71da0b347d4ba7e0eb433f7258468`.
- Nenhum dispositivo ou emulador Android apareceu no ADB. Barras do sistema, retorno após pressão de memória, troca de fontes reais, áudio Bluetooth/Connect, Canvas e videoclipe de catálogo, autonomia e taxa sustentada de 60/90/120 Hz precisam de validação em hardware. A comparação quadro a quadro da experiência completa permanece em aberto.

## Reprodução do build

O Gradle empacota os assets versionados. Para regenerar os módulos web a partir da raiz, use Node 24 ou superior.

```sh
node third_party/spicy-cinema/build.mjs
cd third_party/spicy-renderer
npm ci
npm run build
```

Para reproduzir a comparação, defina `SPICY_UPSTREAM` para o checkout da revisão acima e `CINEMA_QA_DIR` para uma pasta de saída. Execute `node tools/test-cinema.mjs <playwright-core/index.mjs> <executável Chromium>`. O teste grava as vistas do celular, do tablet e do template original. O ADB e uma sessão real de reprodução são necessários para a etapa física. As licenças, avisos e código correspondente acompanham o APK na mesma distribuição.
