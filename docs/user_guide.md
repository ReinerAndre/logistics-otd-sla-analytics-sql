```markdown
# Guia do Usuário e Regras de Interpretação — Relatório de Canhotos e SLA (OTD)

## 1. Visão Geral
Este guia orienta analistas de logística, faturamento e gestores na leitura e utilização dos indicadores gerados pelo pipeline de monitoramento de entregas. Cada linha do relatório representa **uma única Nota Fiscal**.

---

## 2. Dicionário de Colunas e Indicadores

| Coluna | Descrição | Regra de Negócio Aplicada |
| :--- | :--- | :--- |
| **`serie_nf` / `numero_nf`** | Identificação da Nota Fiscal | Chave única do documento fiscal emitido. |
| **`data_emissao`** | Data de emissão da NF | Data base para início da contagem do *Transit Time*. |
| **`situacao_nf`** | Status fiscal da NF | Exibe `Normal` ou `Cancelada`. Notas canceladas não entram no cálculo de atraso. |
| **`transportadora`** | Código e nome da transportadora | Exibe `Não Informada` quando a nota não possui transportador vinculado (ex: retirada pelo cliente). |
| **`modalidade_frete`** | Tipo de responsabilidade do frete | Decodifica o padrão fiscal: `CIF` (Remetente), `FOB` (Destinatário), `PCIF`/`PFOB` (Próprio), `RTR` (Terceiros) ou `SEM`. |
| **`pedidos_vinculados`** | Pedidos de venda atendidos pela NF | Lista única e ordenada separada por vírgula. Exibe `Sem Pedido` para notas avulsas (remessas/amostras). |
| **`data_previsao_entrega`** | Data limite acordada para entrega | Prioriza a data negociada com o cliente; se ausente, usa a previsão padrão do pedido. Em notas com múltiplos pedidos, assume a **maior data**. |
| **`data_entrega_real`** | Data registrada no comprovante (canhoto) | Fica em branco (`NULL`) enquanto a entrega estiver em trânsito ou aguardando baixa administrativa. |
| **`dias_transit_time`** | Tempo total de transporte (dias corridos) | • **Com canhoto:** `Data Entrega Real - Data Emissão`<br>• **Sem canhoto:** `Data Atual - Data Emissão` (dias em aberto). |
| **`dias_desvio_prazo`** | Saldo de dias em relação ao prazo previsto | • **Negativo (`-X`):** Entregue X dias adiantado.<br>• **Zero (`0`):** Entregue no dia exato.<br>• **Positivo (`+X`):** Entregue (ou pendente) com X dias de atraso. |
| **`status_sla_otd`** | Classificação executiva da entrega | Status consolidado para filtros e gráficos de SLA (detalhado na seção 3). |

---

## 3. Matriz de Classificação (`status_sla_otd`)

Para facilitar a tomada de decisão operacional, o relatório divide as entregas em dois grandes grupos:

### A. Entregas Concluídas (Com Comprovante Baixado)
* **`Entregue no Prazo`:** Comprovante registrado exatamente na data prevista (`dias_desvio_prazo = 0`).
* **`Entregue Adiantada (Xd)`:** Comprovante registrado antes da data prevista.
* **`Entregue Atrasada (Xd)`:** Comprovante registrado após a data prevista.

### B. Entregas em Aberto (Sem Comprovante Baixado)
* **`Pendente (Dentro do Prazo)`:** A data atual ainda é menor ou igual à previsão de entrega.
* **`Pendente (Em Atraso - Xd)`:** A data prevista já venceu e o comprovante ainda não foi baixado no sistema (requer cobrança imediata à transportadora ou baixa administrativa).

### C. Exceções de Controle
* **`Nota Cancelada`:** Notas canceladas fiscalmente (devem ser desconsideradas nos indicadores de performance das transportadoras).
* **`Sem Previsão no Pedido`:** Notas sem pedido vinculado ou cujo pedido não possuía data de previsão preenchida.

---

## 4. Boas Práticas de Análise
1. **Apuração de OTD (On-Time Delivery):** Para calcular o percentual oficial de entregas no prazo de uma transportadora, filtre apenas notas com `situacao_nf = 'Normal'` e considere no numerador os status `Entregue no Prazo` + `Entregue Adiantada`.
2. **Auditoria de Pendências:** Utilize o filtro `Pendente (Em Atraso - Xd)` diariamente para identificar gargalos de baixa de canhoto ou extravios em trânsito.
```
