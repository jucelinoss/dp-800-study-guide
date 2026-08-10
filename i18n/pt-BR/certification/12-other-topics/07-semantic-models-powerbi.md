---
title: Modelos Semânticos, Power BI e Segurança Analítica
type: study-material
tags:
  - dp-800
  - semantic-model
  - power-bi
  - dax
  - rls
  - fabric
---

> [!info] Escopo
>
> Este tópico mostra como um modelo dimensional é exposto para análise. Ele não
> substitui a documentação de Power BI, mas reúne as decisões que mais afetam a
> correção, a segurança e o desempenho de um modelo semântico.

# Modelos Semânticos, Power BI e Segurança Analítica

Um **modelo semântico** apresenta dados analíticos com nomes, relações, medidas e
regras que fazem sentido para os consumidores. Ele fica entre as tabelas físicas
e os relatórios:

```text
Fonte operacional / lakehouse / warehouse
                    ↓
          Modelo dimensional preparado
                    ↓
             Modelo semântico
                    ↓
          Relatórios, métricas e apps
```

O modelo semântico não deve ser tratado como uma simples cópia das tabelas de
origem. Ele deve esconder detalhes técnicos, expor métricas governadas e manter
um caminho de filtros previsível.

## Star schema no modelo semântico

Em um modelo estrela, as dimensões filtram e agrupam; as fatos armazenam os
eventos e as medidas. Uma relação típica é:

```text
DimDate (1) ─────── (*) FactSales
DimProduct (1) ──── (*) FactSales
DimCustomer (1) ─── (*) FactSales
```

A cardinalidade `1:*` informa que uma linha da dimensão pode estar relacionada a
várias linhas da fato. Em geral, o filtro deve fluir da dimensão para a fato.

Esse desenho ajuda a evitar:

- caminhos ambíguos de filtragem;
- duplicação de valores causada por joins incorretos;
- medidas diferentes para cada relatório;
- relacionamentos muitos-para-muitos acidentais.

## Relacionamentos e direção de filtro

Cada relacionamento possui propriedades que afetam o resultado:

| Propriedade | Pergunta que responde |
|---|---|
| Cardinalidade | É `1:1`, `1:*` ou `*:*`? |
| Direção do filtro | Para qual tabela o filtro se propaga? |
| Ativo | Esse caminho é o padrão para consultas? |
| Integridade | Existem chaves sem correspondência? |

Prefira relações `1:*` com filtro em uma direção, da dimensão para a fato. Use
filtro bidirecional somente quando houver uma necessidade clara e validada. Ele
pode criar caminhos ambíguos, reduzir desempenho e produzir resultados difíceis
de explicar.

```text
Preferível:
DimProduct ──(filtro)──> FactSales

Exige justificativa:
DimProduct <──(filtro bidirecional)──> FactSales
```

### Relação ativa e inativa

Quando uma fato possui mais de uma data, `DimDate` pode ter papéis diferentes:

- `OrderDateKey`;
- `ShipDateKey`;
- `DueDateKey`.

Normalmente apenas uma relação é ativa para evitar ambiguidade. Uma medida pode
ativar temporariamente outra relação:

```DAX
Sales Amount :=
SUM ( FactSales[SalesAmount] )

Sales Amount by Ship Date :=
CALCULATE (
    [Sales Amount],
    USERELATIONSHIP ( FactSales[ShipDateKey], DimDate[DateKey] )
)
```

Outra opção é carregar cópias com papéis explícitos, como `DimOrderDate` e
`DimShipDate`, quando isso tornar o modelo mais claro para os consumidores.

### Muitos-para-muitos

Não use `*:*` apenas para esconder uma chave mal definida. Quando uma relação
muitos-para-muitos representa um conceito real, considere uma tabela ponte:

```text
DimCustomer (1) ── (*) BridgeCustomerAccount (*) ── (1) DimAccount
```

A tabela ponte deve ter uma granularidade definida e ser testada para duplicidades.
Em muitos casos, uma dimensão ou uma fato sem fato explícita pode representar
melhor a associação.

## Medidas versus colunas calculadas

### Medidas

Medidas são calculadas no contexto da consulta. São apropriadas para somas,
razões, percentuais e métricas que precisam responder aos filtros do relatório.

```DAX
Total Sales :=
SUM ( FactSales[SalesAmount] )

Total Quantity :=
SUM ( FactSales[Quantity] )

Average Selling Price :=
DIVIDE ( [Total Sales], [Total Quantity] )
```

### Colunas calculadas

Colunas calculadas são materializadas no modelo durante o processamento. Use-as
quando o valor por linha for necessário para relacionamentos, agrupamentos ou
classificações que não dependem do filtro do visual.

Como regra prática, prefira preparar atributos no warehouse quando isso reduzir
o custo, duplicação ou complexidade no modelo semântico. Não substitua uma medida
por uma coluna calculada apenas porque a coluna é mais fácil de escrever.

## Tabelas desconectadas

Uma tabela desconectada não propaga filtros por uma relação. Ela pode receber uma
seleção do usuário e ser consultada por uma medida, por exemplo para escolher uma
moeda, um cenário ou uma meta.

```DAX
Selected Currency :=
SELECTEDVALUE ( DimCurrencySelector[Currency], "BRL" )
```

Ela deve ser intencional. Uma tabela sem relação por erro de modelagem não é uma
tabela desconectada bem projetada.

## Segurança por linha (RLS)

**Row-level security (RLS)** restringe as linhas que um usuário pode consultar no
modelo semântico. Um padrão de segurança dinâmica usa uma tabela de acesso:

```text
UserPrincipalName | RegionKey
ana@contoso.com   | 10
ana@contoso.com   | 20
```

Uma regra DAX conceitual na tabela de acesso pode ser:

```DAX
UserPrincipalName = USERPRINCIPALNAME()
```

Depois, os relacionamentos propagam o conjunto de regiões permitido para a
dimensão e para as fatos. O desenho da propagação precisa ser validado; ativar
filtros bidirecionais de segurança pode afetar desempenho e criar ambiguidades.

Fluxo de implantação:

1. Defina as funções e regras no modelo.
2. Publique o modelo e o relatório.
3. Atribua usuários ou grupos às funções no serviço.
4. Use **Test as role** para validar casos permitidos e negados.
5. Teste usuários com múltiplas regiões, sem região e com acesso administrativo.

> [!warning] RLS não substitui segurança do workspace
>
> RLS restringe consumidores que consultam o modelo por meio das funções. Ele não
> deve ser tratado como barreira para administradores, membros ou contribuidores
> do workspace. Controle também permissões do workspace, item e fonte.

Quando o dado é acessado por outros caminhos — SQL, lakehouse, exportação ou API —
avalie segurança na camada correspondente. Um relatório protegido por RLS não
transforma automaticamente a tabela física em uma tabela protegida para todos os
outros consumidores.

## Escolha do modo de armazenamento

| Modo | Onde os dados são avaliados | Vantagem principal | Atenção |
|---|---|---|---|
| Import | Cache do modelo | Interação rápida e previsível | Refresh, memória e latência dos dados |
| DirectQuery | Fonte durante a consulta | Dados mais próximos da origem e menor cache | Desempenho depende da fonte e das consultas geradas |
| Direct Lake | Dados no OneLake, com comportamento próprio do Fabric | Acesso analítico a grandes volumes sem importar todo o modelo | Recursos sem suporte podem causar fallback para DirectQuery |

Não escolha o modo apenas pela atualização mais recente. Meça latência, volume,
concorrência, custo de refresh, capacidade da fonte e requisitos de segurança.
Em Direct Lake, monitore possíveis fallbacks para DirectQuery porque o comportamento
de desempenho pode mudar.

## Boas práticas de apresentação

- oculte chaves substitutas e colunas técnicas que não devem ser usadas no relatório;
- exponha nomes de negócio consistentes;
- organize medidas em tabelas ou pastas de medidas;
- defina formatos, unidades e casas decimais das métricas;
- marque e use corretamente a dimensão de data quando o modelo exigir calendário;
- documente a granularidade das fatos e o significado das medidas;
- evite relações ambíguas e filtro bidirecional sem justificativa;
- valide totais do modelo contra consultas de reconciliação no warehouse.

## Checklist de segurança e qualidade

- Um usuário sem acesso a uma região realmente não vê suas linhas?
- Um usuário com várias regiões vê todas e somente as permitidas?
- O teste foi feito com `Test as role` e com uma conta de serviço?
- Admins e membros do workspace foram considerados no modelo de ameaça?
- A segurança da fonte também foi avaliada?
- As dimensões filtram as fatos na direção esperada?
- Há uma única relação ativa para cada caminho de análise?
- As medidas funcionam em diferentes combinações de filtros?
- O modo de armazenamento atende latência, volume, atualização e custo?
- Fallbacks, refreshes e falhas de fonte são monitorados?

## Documentação oficial

- [Relacionamentos no Power BI Desktop](https://learn.microsoft.com/pt-br/power-bi/transform-model/desktop-relationships-understand)
- [Star schema e sua importância para o Power BI](https://learn.microsoft.com/pt-br/power-bi/guidance/star-schema)
- [Segurança por linha (RLS) no Power BI](https://learn.microsoft.com/en-us/fabric/security/service-admin-row-level-security)

---

**[← SCD e Cargas Dimensionais](./06-scd-and-dimensional-loading.md) | [↑ Voltar para Outros Tópicos](./other-topics.md)**
