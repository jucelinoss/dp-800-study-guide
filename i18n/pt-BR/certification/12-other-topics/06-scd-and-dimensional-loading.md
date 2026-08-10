---
title: Slowly Changing Dimensions e Cargas Dimensionais
type: study-material
tags:
  - dp-800
  - scd
  - slowly-changing-dimensions
  - etl
  - elt
  - data-warehouse
---

> [!info] Escopo
>
> Este tópico trata de como carregar dimensões e preservar alterações históricas
> em um modelo dimensional. Ele complementa [Modelagem Dimensional — Star Schema
> e Snowflake Schema](./05-dimensional-modeling.md).

# Slowly Changing Dimensions e Cargas Dimensionais

**Slowly Changing Dimension (SCD)**, ou dimensão de alteração lenta, é uma
estratégia para tratar mudanças nos atributos de uma dimensão. O termo “lenta”
não significa que a carga precise ser lenta; significa que os atributos mudam
com menos frequência do que os eventos registrados nas tabelas fato.

Exemplos de atributos que podem mudar:

- endereço ou segmento de um cliente;
- categoria ou marca de um produto;
- gerente ou região de uma loja;
- classificação de risco de uma conta.

A decisão principal é: **o relatório precisa enxergar o valor atual ou o valor que
era válido quando o evento aconteceu?**

## Natural key e surrogate key

Uma dimensão normalmente separa duas identidades:

- **Natural key/business key**: identificador da origem, como `CustomerId`.
- **Surrogate key**: identificador da versão da linha na dimensão, como
  `CustomerKey`.

No SCD tipo 2, o mesmo `CustomerId` pode aparecer em várias linhas, cada uma com
um `CustomerKey` diferente. A fato deve apontar para o `CustomerKey` correto
daquela versão, e não simplesmente para o identificador operacional.

```text
CustomerId = 42
    ├── CustomerKey = 1001 — endereço antigo — 2024-01-01 a 2025-03-31
    └── CustomerKey = 1048 — endereço atual — 2025-04-01 a 9999-12-31
```

## Tipos mais comuns de SCD

| Tipo | Estratégia | Mantém histórico? | Quando usar |
|---|---|---:|---|
| 0 | Ignorar a alteração | Não altera o valor | Atributo fixo, como data de nascimento ou chave original |
| 1 | Sobrescrever a linha | Não | Apenas o estado atual importa |
| 2 | Inserir nova versão e fechar a anterior | Sim, completo | Relatórios precisam respeitar o histórico |
| 3 | Manter valor atual e valor anterior em colunas | Limitado | Apenas uma mudança anterior é necessária |

Não existe um tipo universalmente melhor. A política pode variar por atributo na
mesma dimensão. Por exemplo, o e-mail pode ser tipo 1, enquanto o segmento de
cliente pode ser tipo 2.

## SCD tipo 0

No tipo 0, o valor original não é atualizado. A carga pode inserir uma nova
entidade, mas ignora alterações posteriores naquele atributo.

Use quando o atributo representa um fato imutável ou quando a regra de negócio
define que o primeiro valor deve ser preservado.

## SCD tipo 1

No tipo 1, a linha existente é atualizada com o novo valor. O modelo mantém apenas
o estado atual.

```sql
UPDATE d
SET d.EmailAddress = s.EmailAddress,
    d.UpdatedAt = SYSUTCDATETIME()
FROM dbo.DimCustomer AS d
JOIN stage.Customer AS s
  ON s.CustomerId = d.CustomerId;
```

Vantagens:

- implementação simples;
- não cria múltiplas versões do mesmo membro;
- adequado quando somente o estado atual é necessário.

Limitação principal: o relatório não consegue reconstruir o valor antigo sem uma
fonte histórica adicional.

## SCD tipo 2

No tipo 2, uma alteração rastreada fecha a versão atual e insere uma nova linha.
Um desenho comum usa:

- `CustomerKey` como chave substituta;
- `CustomerId` como chave natural;
- `EffectiveFrom`;
- `EffectiveTo`;
- `IsCurrent`.

Exemplo:

| CustomerKey | CustomerId | Segment | EffectiveFrom | EffectiveTo | IsCurrent |
|---:|---:|---|---|---|---:|
| 1001 | 42 | Standard | 2024-01-01 | 2025-03-31 | 0 |
| 1048 | 42 | Premium | 2025-04-01 | 9999-12-31 | 1 |

### Fluxo de carga tipo 2

1. Carregue a origem em uma área de staging.
2. Identifique a linha pela chave natural.
3. Compare somente os atributos marcados para histórico.
4. Se não houver alteração, não faça nada.
5. Se houver alteração, feche a versão atual.
6. Insira uma nova linha com nova chave substituta.
7. Carregue fatos apontando para a versão válida na data do evento.

Um padrão genérico, sem `MERGE`, é:

```sql
BEGIN TRANSACTION;

-- Fechar somente versões atuais que realmente mudaram.
UPDATE d
SET d.EffectiveTo = DATEADD(NANOSECOND, -100, s.ChangeEffectiveAt),
    d.IsCurrent = 0
FROM dbo.DimCustomer AS d
JOIN stage.Customer AS s
  ON s.CustomerId = d.CustomerId
WHERE d.IsCurrent = 1
  AND HASHBYTES('SHA2_256', CONCAT(d.Segment, N'|', d.Region))
      <> HASHBYTES('SHA2_256', CONCAT(s.Segment, N'|', s.Region));

-- Inserir a versão atual para novos membros e membros que mudaram.
INSERT dbo.DimCustomer
    (CustomerId, Segment, Region, EffectiveFrom, EffectiveTo, IsCurrent)
SELECT s.CustomerId,
       s.Segment,
       s.Region,
       s.ChangeEffectiveAt,
       CONVERT(datetime2(7), '9999-12-31 23:59:59.9999999'),
       1
FROM stage.Customer AS s
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.DimCustomer AS d
    WHERE d.CustomerId = s.CustomerId
      AND d.IsCurrent = 1
      AND d.Segment = s.Segment
      AND d.Region = s.Region
);

COMMIT TRANSACTION;
```

O código é um padrão didático. Em produção, trate concorrência, valores nulos,
precisão de datas, múltiplas alterações do mesmo membro no lote e reprocessamento.
Também prefira uma comparação de hash bem definida ou comparação coluna a coluna
que trate `NULL` de maneira explícita.

### Consultar a versão válida para uma fato

Para uma fato de vendas, a dimensão deve ser resolvida pela chave natural e pela
data do evento:

```sql
SELECT f.OrderId,
       d.CustomerKey,
       f.OrderDate,
       f.SalesAmount
FROM stage.Sales AS f
JOIN dbo.DimCustomer AS d
  ON d.CustomerId = f.CustomerId
 AND f.OrderDate >= d.EffectiveFrom
 AND f.OrderDate < d.EffectiveTo;
```

Usar `IsCurrent = 1` nessa consulta histórica pode associar uma venda antiga ao
segmento atual e produzir um relatório incorreto.

## SCD tipo 3

O tipo 3 mantém o valor atual e um valor anterior na mesma linha, por exemplo:

```text
CurrentSegment = Premium
PreviousSegment = Standard
```

É simples para perguntas que exigem apenas “atual versus anterior”, mas não
preserva uma sequência completa de alterações. Para histórico ilimitado ou
análise temporal, o tipo 2 é mais apropriado.

## Cargas incrementais de dimensões

Uma carga dimensional incremental deve identificar o que mudou sem reler a fonte
inteira desnecessariamente. As opções incluem:

- watermark baseado em data/hora ou versão;
- CDC, quando o detalhe das operações é necessário;
- Change Tracking, quando basta saber quais chaves precisam ser reconsultadas;
- arquivos incrementais ou partições de origem;
- comparação por hash após carregar um lote de staging.

O mecanismo de mudança não substitui a regra SCD. CDC ou CT informa que algo
mudou; a política SCD decide se deve ignorar, sobrescrever ou criar uma nova versão.

## Idempotência e reprocessamento

Uma carga idempotente produz o mesmo estado final quando o mesmo lote é executado
mais de uma vez. Para isso:

- use uma identificação do lote ou watermark persistido;
- não insira uma nova versão tipo 2 se os atributos não mudaram;
- garanta no máximo uma versão atual por chave natural;
- registre início, fim, contagens e erro do lote;
- faça commit das alterações de forma transacional quando possível;
- trate atrasos e eventos fora de ordem explicitamente.

Uma regra útil para validar uma dimensão tipo 2 é:

```sql
SELECT CustomerId
FROM dbo.DimCustomer
WHERE IsCurrent = 1
GROUP BY CustomerId
HAVING COUNT(*) <> 1;
```

O resultado esperado é vazio. Também valide intervalos sobrepostos, dimensões sem
membro desconhecido e fatos sem correspondência dimensional.

## Data warehouse versus atualização direta no Power BI

Uma atualização direta do modelo semântico pode ser suficiente quando apenas o
estado atual é necessário. Quando o requisito inclui histórico, múltiplas fontes,
grandes volumes ou cargas reproduzíveis, é preferível tratar o histórico no
warehouse e conectar o modelo semântico à dimensão preparada.

## Checklist de decisão

- O atributo precisa ser analisado como era no momento do evento?
- O histórico é completo ou apenas o valor anterior é suficiente?
- Qual é a chave natural e qual é a chave substituta?
- A data de vigência vem da origem ou do momento da carga?
- Como serão tratados `NULL`, exclusões e eventos fora de ordem?
- A carga pode ser reexecutada sem criar versões duplicadas?
- Há uma linha de membro desconhecido?
- Os fatos resolvem a dimensão pela data do evento?
- CDC, CT ou watermark atende ao nível de detalhe necessário?
- Existem reconciliações de contagem, totais e integridade referencial?

## Documentação oficial

- [Implementar SCD tipo 1 no Microsoft Fabric](https://learn.microsoft.com/pt-br/fabric/data-factory/slowly-changing-dimension-type-one)
- [Slowly changing dimensions no Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/iq/plan/powertable-concept-slowly-changing-dimensions)
- [Configurar Slowly Changing Dimensions](https://learn.microsoft.com/en-us/fabric/iq/plan/powertable-how-to-create-slowly-changing-dimension)

---

**[← Modelagem Dimensional](./05-dimensional-modeling.md) | [↑ Voltar para Outros Tópicos](./other-topics.md)**
