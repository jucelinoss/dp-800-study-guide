# Agentes locais

Esta pasta contém definições de agentes baseadas em prompt para tarefas especializadas do repositório.

## Agentes disponíveis

- [`documentation-maintainer.md`](documentation-maintainer.md): mantém a documentação alinhada ao Microsoft Learn, sincronizada entre todos os idiomas suportados e conectada aos laboratórios práticos.

## Convenção de idiomas

- `certification/` é a versão-base em inglês.
- Cada diretório de primeiro nível em `i18n/` representa um locale que deve ser descoberto e avaliado dinamicamente.
- O locale não deve ser hardcoded nas regras de um agente. Novos diretórios em `i18n/` entram automaticamente na matriz de sincronização depois de sua metadata/README ser verificada.
- Um arquivo é considerado sincronizado apenas quando a versão-base e todos os locales suportados possuem conteúdo equivalente ou uma lacuna explicitamente registrada.

## Convenção de laboratórios

- Os laboratórios executáveis ficam em `practice/labs/`.
- Quando houver documentação de laboratório, ela fica em `certification/resources/labs/` ou no espelho de locale correspondente.
- Conceitos novos devem ser conferidos contra o laboratório do mesmo domínio antes de a alteração ser considerada concluída.
