-- ============================================================================
-- PROJETO: Monitoramento Logístico e Performance de Entregas (SLA / OTD)
-- DESCRIÇÃO: Consolidação 1:1 por Nota Fiscal com cálculo de Transit Time,
--            desvio de prazo contratado e status operacional de entrega.
-- ============================================================================

-- ETAPA 1: Deduplicação no nível de Nota Fiscal x Pedido de Venda
-- Evita a explosão de linhas causada por múltiplos itens do mesmo pedido na NF
-- e captura a maior data de previsão acordada por pedido.
with cte_notas_pedidos_dedup as (
  select nf.id_empresa,
         nf.serie_nf,
         nf.numero_nf,
         trunc(nf.data_emissao)                                              as data_emissao,
         decode(nf.status_nf, 'C', 'Cancelada', 'Normal')                    as situacao_nf,
         nf.status_nf                                                        as cod_situacao_nf,
         cli.id_parceiro || ' - ' || cli.razao_social                        as cliente,
         case 
           when nf.id_transportadora is not null 
           then nf.id_transportadora || ' - ' || transp.razao_social 
           else 'Não Informada' 
         end                                                                 as transportadora,
         decode(nf.modalidade_frete, 
                0, '(CIF) Frete por conta do Remetente',
                1, '(FOB) Frete por conta do Destinatário',
                3, '(PCIF) Transporte Próprio - Remetente',
                4, '(PFOB) Transporte Próprio - Destinatário',
                2, '(RTR) Frete por conta de Terceiros',
                9, '(SEM) Sem Ocorrência de Transporte',
                'Não Informado')                                             as modalidade_frete,
         trunc(nf.data_comprovante_entrega)                                  as data_entrega_real,
         ped.numero_pedido                                                   as numero_pedido,
         max(trunc(nvl(ped.data_prevista_cliente, ped.data_prevista_padrao))) as data_previsao_entrega
    from erp_schema.fato_nota_fiscal nf
   inner join erp_schema.dim_parceiros cli
      on nf.id_cliente = cli.id_parceiro
   inner join erp_schema.fato_nota_fiscal_item nfi
      on nf.id_empresa = nfi.id_empresa
     and nf.serie_nf   = nfi.serie_nf
     and nf.numero_nf  = nfi.numero_nf
    -- LEFT JOIN garante visibilidade de notas sem transportadora ou sem pedido (ex: remessas/balcão)
    left join erp_schema.dim_parceiros transp
      on nf.id_transportadora = transp.id_parceiro
    left join erp_schema.fato_nota_pedido_entrega npe
      on nfi.id_empresa     = npe.id_empresa
     and nfi.serie_nf       = npe.serie_nf
     and nfi.numero_nf      = npe.numero_nf
     and nfi.sequencia_item = npe.sequencia_item_nf
    left join erp_schema.fato_pedido_programacao ped
      on npe.id_empresa        = ped.id_empresa
     and npe.numero_pedido     = ped.numero_pedido
     and npe.sequencia_item    = ped.sequencia_item
     and npe.sequencia_entrega = ped.sequencia_entrega
   where nf.id_empresa = :param_empresa
     and nf.data_emissao between :param_data_inicio and :param_data_fim
   group by nf.id_empresa,
            nf.serie_nf,
            nf.numero_nf,
            trunc(nf.data_emissao),
            nf.status_nf,
            cli.id_parceiro,
            cli.razao_social,
            nf.id_transportadora,
            transp.razao_social,
            nf.modalidade_frete,
            trunc(nf.data_comprovante_entrega),
            ped.numero_pedido
),

-- ETAPA 2: Consolidação 1:1 no grão de Nota Fiscal
-- Concatena os pedidos distintos em string ordenada e define o prazo limite da NF.
cte_notas_consolidadas as (
  select np.id_empresa,
         np.serie_nf,
         np.numero_nf,
         np.data_emissao,
         np.situacao_nf,
         np.cod_situacao_nf,
         np.cliente,
         np.transportadora,
         np.modalidade_frete,
         np.data_entrega_real,
         listagg(np.numero_pedido, ', ') within group (order by np.numero_pedido) as pedidos_vinculados,
         max(np.data_previsao_entrega)                                           as data_previsao_entrega
    from cte_notas_pedidos_dedup np
   group by np.id_empresa,
            np.serie_nf,
            np.numero_nf,
            np.data_emissao,
            np.situacao_nf,
            np.cod_situacao_nf,
            np.cliente,
            np.transportadora,
            np.modalidade_frete,
            np.data_entrega_real
)

-- ETAPA 3: Camada Semântica e Cálculo de KPIs Logísticos (Transit Time & OTD)
select b.serie_nf,
       b.numero_nf,
       b.data_emissao,
       b.situacao_nf,
       b.cliente,
       b.transportadora,
       b.modalidade_frete,
       nvl(b.pedidos_vinculados, 'Sem Pedido')                               as pedidos_vinculados,
       b.data_previsao_entrega,
       b.data_entrega_real,

       -- KPI 1: Transit Time (Dias corridos da emissão até a entrega ou até hoje se em aberto)
       case 
         when b.data_entrega_real is null then trunc(sysdate) - b.data_emissao
         else b.data_entrega_real - b.data_emissao 
       end                                                                   as dias_transit_time,

       -- KPI 2: Desvio de Prazo (Negativo = Adiantado | 0 = No Prazo | Positivo = Atrasado)
       case 
         when b.data_previsao_entrega is null then null
         when b.data_entrega_real is null then trunc(sysdate) - b.data_previsao_entrega
         else b.data_entrega_real - b.data_previsao_entrega 
       end                                                                   as dias_desvio_prazo,

       -- KPI 3: Classificação de Performance (SLA / On-Time Delivery)
       case
         when b.cod_situacao_nf = 'C' then 'Nota Cancelada'
         when b.data_previsao_entrega is null then 'Sem Previsão no Pedido'
         when b.data_entrega_real is not null then
           case
             when b.data_entrega_real = b.data_previsao_entrega then 'Entregue no Prazo'
             when b.data_entrega_real < b.data_previsao_entrega then 'Entregue Adiantada (' || abs(b.data_entrega_real - b.data_previsao_entrega) || 'd)'
             else 'Entregue Atrasada (' || (b.data_entrega_real - b.data_previsao_entrega) || 'd)'
           end
         else
           case
             when trunc(sysdate) <= b.data_previsao_entrega then 'Pendente (Dentro do Prazo)'
             else 'Pendente (Em Atraso - ' || (trunc(sysdate) - b.data_previsao_entrega) || 'd)'
           end
       end                                                                   as status_sla_otd
  from cte_notas_consolidadas b
 order by b.serie_nf,
          b.numero_nf;