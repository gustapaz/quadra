# Direção visual — Quadra

Um jogo apresentado como um pôster geométrico: azul intenso em toda a superfície, papel claro para o tabuleiro, laranja para gestos e detalhes, verde suave para estados de conquista. A tipografia Roboto Condensed é compacta e direta; Roboto acompanha as instruções.

## Diferenças no portfólio

Acervo trabalha com papel marfim, imagens reais e uma parede assimétrica. Pulso é um instrumento escuro com pistas horizontais. Quadra é um ambiente lúdico em Flutter/Dart, com tabuleiro quadrado, peças de identidade visual e navegação de jogo. A implementação não reutiliza o shell ou CSS de nenhum dos dois; o visual é desenhado por widgets Flutter.

O tabuleiro é a função principal da primeira tela. No desktop, a composição é um tríptico: mensagem em escala de pôster, área jogável central e uma margem com legenda de pistas e progresso. No celular, as margens se transformam em um cabeçalho curto, e o tabuleiro ocupa a largura disponível. A coleção de desenhos é uma estante separada do jogo, com desenhos ainda não resolvidos ocultos.

## Interação e movimento

A cor de uma célula muda em resposta à jogada; o contorno laranja indica foco de teclado. As pistas ficam verdes quando os blocos daquela linha ou coluna correspondem ao que foi pintado. Isso é feedback local e não uma promessa de que a solução esteja correta. Não há movimento de fundo, scroll capturado ou efeito de entrada genérico. A transição das células respeita a preferência de movimento reduzido.

## Acessibilidade e plataforma

Semântica do Flutter ativada no início, rótulos de linha/coluna/estado, controles com nomes acessíveis, navegação por Tab, setas e atalhos. O conteúdo é uma aplicação CanvasKit; a página de entrada tem título, descrição, canonical, imagem social, estado de carregamento e fallback sem JavaScript. O jogo não é apresentado como conteúdo HTML indexável completo.

## Recursos

Desenhos, marca e composição criados em código. Fontes locais sob Apache 2.0 e licença do pacote Roboto Condensed fornecido com o SDK. Não há imagens remotas, geração paga, dados pessoais, APIs de aplicação ou serviço de ranking.
