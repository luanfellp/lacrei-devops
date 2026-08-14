# Desafio DevOps - Lacrei Saúde

Solução desenvolvida para o desafio técnico de DevOps da Lacrei Saúde.

A aplicação é uma API Node.js containerizada com Docker e publicada em dois ambientes na AWS: Staging e Production. A infraestrutura foi criada com Terraform e o processo de build, teste e deploy é executado pelo GitHub Actions.

## Ambientes

| Ambiente | Endpoint |
|---|---|
| Staging | https://staging-api.luanmoura.com/status |
| Production | https://api.luanmoura.com/status |

A rota `/status` retorna informações básicas da aplicação, incluindo ambiente, versão em execução, uptime e timestamp.

Exemplo:

```json
{
  "status": "ok",
  "environment": "production",
  "version": "<commit-sha>",
  "uptimeSeconds": 120,
  "timestamp": "2026-08-13T20:00:00.000Z"
}
```

## Arquitetura

A infraestrutura utiliza:

- AWS EC2 para executar os containers
- Docker para empacotar a aplicação
- GitHub Container Registry (GHCR) para armazenar as imagens
- CloudFront na frente das EC2
- AWS Certificate Manager para TLS
- CloudWatch para métricas e alarmes
- Terraform para provisionamento
- GitHub Actions para CI/CD

O fluxo de acesso à aplicação é:

```text
Cliente
  |
  | HTTPS
  v
CloudFront
  |
  | HTTP
  v
EC2
  |
  v
Container Docker
  |
  v
Node.js :3000
```

O TLS termina no CloudFront. Entre o CloudFront e a EC2 o tráfego utiliza HTTP na porta 80.

A porta 80 das instâncias não fica aberta diretamente para toda a internet. O Security Group utiliza a prefix list gerenciada pela AWS para permitir conexões de origem do CloudFront.

Staging e Production utilizam instâncias EC2 diferentes.

## Por que usei meu próprio domínio

O desafio pedia HTTPS/TLS e também links públicos dos ambientes.

Como eu já tinha um domínio disponível, preferi criar subdomínios específicos para o projeto em vez de entregar os ambientes utilizando diretamente os IPs públicos das EC2.

Foram criados:

```text
staging-api.luanmoura.com
api.luanmoura.com
```

Com isso consegui configurar um certificado no AWS Certificate Manager e utilizar HTTPS nos dois ambientes através do CloudFront.

Além de atender ao requisito de TLS, essa escolha mantém o endereço utilizado para acessar a API separado do endereço da infraestrutura. Se uma instância ou distribuição precisar ser alterada, o endereço apresentado para quem consome a API pode continuar o mesmo.

Também deixou mais clara a separação entre Staging e Production sem adicionar um serviço mais complexo apenas para o desafio.

## Aplicação

A aplicação foi feita em Node.js com Express.

Para executar localmente:

```bash
npm ci
npm start
```

A API fica disponível em:

```text
http://localhost:3000
```

Para validar o projeto:

```bash
npm run lint
npm test
```

### Docker

Build da imagem:

```bash
docker build -t lacrei-api .
```

Execução:

```bash
docker run --rm \
  -p 3000:3000 \
  -e APP_ENV=local \
  -e APP_VERSION=dev \
  lacrei-api
```

Teste:

```bash
curl http://localhost:3000/status
```

O container possui `HEALTHCHECK` utilizando a própria rota `/status` e executa a aplicação com usuário não-root.

## CI/CD

O workflow é executado a cada push na branch `main`.

O fluxo atual é:

```text
Push na main
     |
     v
Lint + testes
     |
     v
Build da imagem Docker
     |
     v
Push para GHCR
     |
     v
Deploy em Staging
     |
     v
Smoke test HTTPS
     |
     v
Deploy em Production
     |
     v
Smoke test HTTPS
```

Se lint, testes, build ou validação de Staging falharem, o deploy de Production não acontece.

### Versionamento das imagens

Cada build publica duas tags no GHCR:

```text
latest
<commit-sha>
```

O deploy não depende da tag `latest`. A pipeline utiliza o SHA do commit:

```text
ghcr.io/luanfellp/lacrei-devops/lacrei-api:<commit-sha>
```

Assim, Staging e Production recebem exatamente a mesma imagem produzida pelo pipeline.

O SHA também facilita identificar qual versão está em execução e permite voltar para uma imagem anterior em caso de problema.

## Deploy

O deploy atual é feito via SSH pelo GitHub Actions.

Os hosts, chave privada e passphrase utilizados pelo workflow são armazenados em GitHub Secrets e não fazem parte do repositório.

Na EC2, o processo é basicamente:

```text
docker pull
docker stop
docker rm
docker run
```

Depois de subir o container, o GitHub Actions acessa `/status` através do endereço HTTPS público.

Em Staging, esse teste funciona como validação antes da promoção para Production.

## Segurança

Algumas decisões tomadas para o desafio:

- chave privada SSH e passphrase ficam no GitHub Secrets
- arquivos de chave privada, estados Terraform e arquivos `.env` são ignorados pelo Git
- aplicação executa como usuário não-root dentro do container
- headers básicos de segurança são adicionados pelo Helmet
- HTTPS é obrigatório no acesso público
- HTTP no CloudFront é redirecionado para HTTPS
- TLS utiliza certificado do AWS Certificate Manager
- porta 80 das EC2 aceita tráfego somente das origens do CloudFront
- Staging e Production utilizam máquinas separadas

### SSH

A porta 22 continua disponível porque o modelo atual de deploy usa runners hospedados pelo GitHub Actions e conexão SSH com as EC2.

Essa é uma limitação conhecida da solução atual.

Uma evolução seria substituir esse acesso por AWS Systems Manager ou outro mecanismo de deploy que não dependa de uma porta SSH pública.

Preferi manter o deploy simples para o escopo do desafio em vez de adicionar mais componentes somente para eliminar essa dependência.

### CORS

Não configurei CORS porque a API entregue neste desafio não possui integração com um frontend executando em outra origem.

Caso esse cenário seja necessário, a configuração deve permitir apenas as origens conhecidas da aplicação em vez de liberar acesso globalmente.

## HTTPS

O acesso público passa pelo CloudFront.

As distribuições utilizam:

```text
HTTP -> redirect para HTTPS
HTTPS -> certificado ACM
CloudFront -> EC2 pela porta 80
```

O certificado é emitido pelo AWS Certificate Manager e os subdomínios apontam para suas respectivas distribuições do CloudFront.

O certificado ACM já existente é consultado pelo Terraform através de um `data source`, em vez de ser recriado a cada execução.

## Logs e monitoramento

Os logs de CI/CD ficam disponíveis diretamente nas execuções do GitHub Actions.

Na EC2, os logs da aplicação podem ser consultados com:

```bash
docker logs lacrei_api
```

A aplicação também escreve eventos básicos de inicialização e encerramento no stdout do container.

### CloudWatch

As métricas padrão das EC2 ficam disponíveis no CloudWatch.

Também foram criados alarmes de CPU para Staging e Production.

O alarme entra em estado de alerta quando a média de utilização de CPU permanece acima de 80% por dois períodos de cinco minutos.

Neste desafio o alarme não envia notificação.

Uma evolução simples seria conectar os alarmes a um tópico SNS e enviar notificações por e-mail ou para algum canal utilizado pela equipe.

## Rollback

As imagens são identificadas pelo SHA do commit, então uma versão anterior pode ser utilizada novamente sem precisar gerar uma nova imagem.

Primeiro é necessário localizar o SHA de uma execução anterior que estava funcionando.

Exemplo:

```text
<sha-anterior>
```

Depois de autenticar no GHCR, o rollback pode ser feito na EC2:

```bash
IMAGE=ghcr.io/luanfellp/lacrei-devops/lacrei-api
TAG=<sha-anterior>

docker pull $IMAGE:$TAG

docker stop lacrei_api || true
docker rm lacrei_api || true

docker run -d \
  -p 80:3000 \
  --name lacrei_api \
  --restart always \
  -e APP_ENV=production \
  -e APP_VERSION=$TAG \
  $IMAGE:$TAG
```

Depois do rollback:

```bash
curl https://api.luanmoura.com/status
```

O campo `version` permite conferir o SHA que está rodando.

Atualmente o rollback é manual. Um próximo passo seria criar um workflow com `workflow_dispatch` que recebesse o SHA desejado e executasse esse procedimento automaticamente.

## Terraform

A infraestrutura principal está definida no `main.tf`.

Antes de qualquer alteração:

```bash
terraform fmt
terraform validate
terraform plan
```

Depois de revisar o plano:

```bash
terraform apply
```

O `plan` é importante principalmente para evitar substituições não intencionais de EC2, Security Groups ou distribuições CloudFront.

Alguns recursos externos, como o certificado ACM e a configuração DNS do domínio, precisam existir para que toda a configuração funcione.

## Decisões tomadas durante o desenvolvimento

### EC2 em vez de uma plataforma mais complexa

Usei EC2 porque atende ao tamanho do desafio e permite mostrar de forma direta Docker, rede, deploy e separação entre ambientes.

ECS ou Kubernetes também poderiam executar a aplicação, mas adicionariam componentes que não eram necessários para este cenário.

### GHCR

Escolhi o GitHub Container Registry porque o código e o pipeline já estão no GitHub.

Assim foi possível utilizar o próprio `GITHUB_TOKEN` do workflow para publicar as imagens sem criar outro registry e outro conjunto de credenciais.

### CloudFront

O CloudFront foi adicionado principalmente para disponibilizar HTTPS nos endpoints e manter as EC2 como origem da aplicação.

A porta HTTP das instâncias ficou restrita à prefix list de origens do CloudFront.

### Imagem identificada pelo commit

No início seria possível trabalhar apenas com `latest`, mas isso dificultaria saber exatamente o que estava rodando e faria o rollback depender de reconstruir uma versão anterior.

Por isso o pipeline publica e utiliza também o SHA do commit.

## Problemas encontrados durante a implementação

### Permissão para publicar imagens no GHCR

Nas primeiras execuções do pipeline, o build da imagem funcionava, mas o push para o GitHub Container Registry falhava com erro de permissão (`permission_denied: write_package`).

O problema estava nas permissões do pacote no GHCR. Ajustei o acesso do GitHub Actions ao package e mantive o uso do `GITHUB_TOKEN` para publicação das imagens.

### Chave SSH com passphrase no deploy

O deploy via SSH também falhou inicialmente porque a chave privada utilizada possui passphrase.

A chave já estava armazenada no GitHub Secrets, mas o workflow precisava receber a passphrase separadamente. Adicionei esse valor como outro secret e configurei a action de SSH para utilizá-lo durante a conexão.

### Alterações de infraestrutura com Terraform

Durante alguns ajustes no Security Group, o `terraform plan` mostrou que uma alteração poderia causar a substituição de recursos que já estavam funcionando.

Em vez de aplicar diretamente, revisei o plano e mantive a configuração existente quando a mudança era apenas cosmética.

Reforçou a importância de revisar o `terraform plan` antes de executar um `apply`, principalmente em recursos que podem gerar substituições desnecessárias.

## Limitações e próximos passos

Para uma evolução desta solução, eu consideraria:

- substituir o deploy via SSH por AWS Systems Manager ou outro mecanismo sem acesso SSH público
- automatizar o rollback pelo GitHub Actions
- enviar os logs dos containers para CloudWatch Logs
- adicionar SNS aos alarmes do CloudWatch
- separar o Terraform em arquivos ou módulos caso a infraestrutura cresça

Para o escopo atual, preferi manter poucos componentes e conseguir explicar e testar cada parte da solução.

> **Status dos ambientes:** a infraestrutura pública de Staging e Production
> foi desativada após a conclusão da avaliação para evitar custos desnecessários.
> O código, a infraestrutura como código e o histórico do CI/CD permanecem
> disponíveis neste repositório.