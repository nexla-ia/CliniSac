import React from 'react'
import { Link } from 'react-router-dom'
import './LandingPage.css'

// ⚠️ Troque pelo WhatsApp comercial do CliniSac (só dígitos, com DDI 55).
const WHATSAPP = '556999300101'
const waUrl = `https://wa.me/${WHATSAPP}?text=${encodeURIComponent(
  'Olá! Quero testar o CliniSac gratuitamente por 7 dias.'
)}`

const Check = ({ c = '#059669', s = 13 }) => (
  <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><path d="M20 6 9 17l-5-5" /></svg>
)
const Star = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="#F59E0B" stroke="#F59E0B" strokeWidth="1"><path d="M11.5 2.3a.53.53 0 0 1 .95 0l2.31 4.68a2.12 2.12 0 0 0 1.6 1.16l5.16.75a.53.53 0 0 1 .3.9l-3.74 3.64a2.12 2.12 0 0 0-.61 1.88l.88 5.14a.53.53 0 0 1-.77.56l-4.62-2.43a2.12 2.12 0 0 0-1.97 0L6.4 21.01a.53.53 0 0 1-.77-.56l.88-5.14a2.12 2.12 0 0 0-.61-1.88L2.16 9.79a.53.53 0 0 1 .3-.9l5.16-.76a2.12 2.12 0 0 0 1.6-1.16z" /></svg>
)

const solutions = [
  'WhatsApp e Instagram numa caixa só — não em abas soltas',
  'Agenda com lembrete e confirmação automática, sem disparador à parte',
  'Financeiro que nasce da consulta, sem planilha do lado',
  'CRM com funil e follow-up cobrado no dia certo',
]

const steps = [
  { n: '1', title: 'Conecte o WhatsApp da clínica', desc: 'A gente configura junto com você. O número continua o mesmo — a IA entra em cena no mesmo dia.' },
  { n: '2', title: 'A IA atende e organiza', desc: 'Paciente recebe resposta na hora, o lead entra no funil e a recepção assume pra marcar — com lembrete automático depois de agendado.' },
  { n: '3', title: 'Você acompanha tudo no painel', desc: 'Conversas, funil, agenda, financeiro e métricas num lugar só — com visão do que a IA fez.' },
]

const icps = [
  { tag: 'Odontologia', title: 'Orçamento que não esfria', desc: 'A IA responde na hora, o CRM cobra o follow-up e o lembrete mantém a cadeira cheia.' },
  { tag: 'Estética', title: 'Lead do Instagram que não some', desc: 'WhatsApp e Instagram na mesma caixa, funil de vendas e agenda — sem planilha do lado.' },
  { tag: 'Clínicas médicas', title: 'Várias agendas, uma recepção', desc: 'Prontuário, anamnese e financeiro fechando no mesmo painel do atendimento.' },
]

const faqs = [
  { q: 'Preciso trocar o número de WhatsApp da clínica?', a: 'Não. O seu número continua o mesmo — a IA entra por trás, sem o paciente perceber. A gente conecta junto com você no dia da configuração.' },
  { q: 'A IA marca a consulta sozinha?', a: 'Hoje a IA atende o primeiro contato, tira dúvidas e entende o que o paciente precisa — 24 horas por dia. Quem confirma o horário na agenda é a sua equipe. Já estamos evoluindo pra IA agendar de ponta a ponta; a confirmação de presença por WhatsApp já é o primeiro passo.' },
  { q: 'Consigo assumir a conversa quando eu quiser?', a: 'Sim, a qualquer momento. A IA segura o atendimento e avisa a equipe quando é caso de humano — e você assume com um clique, sem o paciente perder o fio.' },
  { q: 'E se eu não quiser usar a IA?', a: 'Sem problema. A IA é opcional e pode ficar desligada — aí sua equipe atende tudo manualmente e você segue com a caixa unificada, a agenda, o CRM, o prontuário e o financeiro do mesmo jeito. Se mudar de ideia, é só ligar a IA quando quiser.' },
  { q: 'Funciona com o Instagram também?', a: 'Funciona. WhatsApp e Instagram chegam na mesma caixa unificada, então a equipe responde tudo de um lugar só.' },
  { q: 'Os dados dos meus pacientes ficam seguros?', a: 'Sim. Cada clínica enxerga apenas os próprios dados, isolados das demais, com práticas de LGPD. Prontuário, conversa e financeiro ficam restritos à sua equipe.' },
  { q: 'Preciso instalar alguma coisa?', a: 'Não. O CliniSac roda no navegador, no computador ou no celular. A configuração é acompanhada pela nossa equipe — você não fica sozinho.' },
  { q: 'Como funciona o teste grátis?', a: '7 dias sem cartão de crédito e sem fidelidade. A gente configura junto, você usa com a clínica de verdade e decide depois.' },
]

const plans = [
  { name: 'Starter', sub: 'Pra clínica começando a organizar o atendimento', feat: false,
    items: ['IA no WhatsApp 24/7', 'Agenda + lembretes automáticos', 'Até 3 profissionais', '5 usuários na equipe'] },
  { name: 'Pro', sub: 'Pra clínica em crescimento, com equipe e funil', feat: true,
    items: ['Tudo do Starter', 'Instagram na caixa unificada', 'CRM com funil de vendas', 'Métricas de equipe e financeiro', 'Até 25 profissionais, agendas ilimitadas'] },
  { name: 'Business', sub: 'Pra redes e clínicas com várias unidades', feat: false,
    items: ['Tudo do Pro', 'Profissionais e usuários ilimitados', 'Vários números de WhatsApp', 'Comparativo entre filiais', 'API e integrações sob medida'] },
]

export default function LandingPage() {
  return (
    <div className="lp">

      {/* NAV */}
      <nav className="lp-nav">
        <div className="lp-wrap lp-nav-inner">
          <Link to="/"><img src="/clinisac-logo.svg" alt="CliniSac" /></Link>
          <div className="lp-nav-links">
            <a href="#recursos">A plataforma</a>
            <a href="#automacoes">Automações</a>
            <a href="#como-funciona">Como funciona</a>
            <a href="#pra-quem">Pra quem é</a>
            <a href="#planos">Planos</a>
            <a href="#faq">Dúvidas</a>
          </div>
          <div className="lp-nav-actions">
            <Link to="/login" className="lp-nav-enter">Entrar</Link>
            <a href={waUrl} target="_blank" rel="noreferrer" className="lp-btn lp-btn-primary lp-btn-sm">Agendar demonstração</a>
          </div>
        </div>
      </nav>

      {/* HERO */}
      <header className="lp-wrap lp-hero">
        <div className="lp-hero-copy">
          <h1>A clínica inteira — do primeiro contato ao <span className="serif hot">retorno do paciente</span>.</h1>
          <p className="lp-hero-sub">WhatsApp e Instagram, agenda com confirmação automática, CRM, prontuário, financeiro e métricas — integrados num painel só. A IA atende junto quando você quer; e desliga quando não quer.</p>
          <div className="lp-hero-ctas">
            <a href={waUrl} target="_blank" rel="noreferrer" className="lp-btn lp-btn-primary lp-btn-lg">Testar 7 dias grátis</a>
            <a href="#como-funciona" className="lp-btn lp-btn-ghost lp-btn-lg">Ver como funciona</a>
          </div>
          <span className="lp-trust"><Check c="#16A34A" s={14} /> Sem cartão de crédito · configuração acompanhada</span>
        </div>

        {/* mockup fiel ao painel de conversas */}
        <div className="lp-hero-panel">
          <div className="lp-mock">
            <div className="lp-mock-inner">
              <aside className="lp-m-side">
                <div className="lp-m-brand"><img src="/clinisac-logo.svg" alt="" /><span>Painel</span></div>
                <div className="lp-m-nav">
                  <span className="lp-m-sec">Atendimento</span>
                  <span className="lp-m-item on">Conversas <span className="lp-m-badge">4</span></span>
                  <span className="lp-m-item">Conversas IA</span>
                  <span className="lp-m-item">Alertas</span>
                  <span className="lp-m-sec">Gestão</span>
                  <span className="lp-m-item">Pacientes</span>
                  <span className="lp-m-item">Agenda</span>
                  <span className="lp-m-item">CRM</span>
                  <span className="lp-m-item">Financeiro</span>
                  <span className="lp-m-item">Métricas</span>
                </div>
              </aside>

              <div className="lp-m-list">
                <div className="lp-m-lh">Conversas</div>
                <div className="lp-m-conv on">
                  <div className="lp-m-conv-top"><b>Ana Beatriz</b><time>09:42</time></div>
                  <p>Pode ser 15h20</p>
                  <span className="lp-m-tag ia">IA atendendo</span>
                </div>
                <div className="lp-m-conv">
                  <div className="lp-m-conv-top"><b>Marcos Lima</b><span className="lp-m-unread">2</span></div>
                  <p>Quanto fica a limpeza?</p>
                  <span className="lp-m-tag wait">Aguardando</span>
                </div>
                <div className="lp-m-conv">
                  <div className="lp-m-conv-top"><b>Paula Andrade</b><time>09:10</time></div>
                  <p>Obrigada! Até amanhã</p>
                  <span className="lp-m-tag done">Finalizada</span>
                </div>
                <div className="lp-m-conv">
                  <div className="lp-m-conv-top"><b>Carlos Duarte</b><time>08:56</time></div>
                  <p>Consegue remarcar pra sexta?</p>
                  <span className="lp-m-tag ia">IA atendendo</span>
                </div>
              </div>

              <div className="lp-m-thread">
                <div className="lp-m-th">
                  <span className="lp-m-av">A</span>
                  <span><b>Ana Beatriz</b><small>(69) 98111-7022</small></span>
                  <span className="lp-m-live">IA ativa</span>
                </div>
                <div className="lp-m-body">
                  <span className="lp-m-day">Hoje</span>
                  <div className="lp-m-bubble lp-m-in">Oi! Queria saber se tem horário pra avaliação amanhã</div>
                  <div className="lp-m-bubble lp-m-out"><span className="lp-m-who">IA · CliniSac</span>Oi, Ana! Temos avaliação amanhã de manhã e à tarde 🙂 Já vou passar pra recepção confirmar o melhor horário pra você.</div>
                  <div className="lp-m-bubble lp-m-in">Perfeito, obrigada!</div>
                  <div className="lp-m-bubble lp-m-out"><span className="lp-m-who">IA · CliniSac</span>Combinado! Em instantes a recepção te chama pra fechar 🙌</div>
                  <span className="lp-m-sys"><span className="dot" />Lead registrado no funil · recepção notificada</span>
                </div>
              </div>
            </div>
          </div>
          <div className="lp-float">
            <span className="lp-float-ic"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#0F0E1B" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M20 6 9 17l-5-5" /></svg></span>
            <span><b>Sempre online</b><span>nenhum paciente sem resposta</span></span>
          </div>
        </div>
      </header>

      {/* FAIXA DE PROVA */}
      <div className="lp-strip">
        <div className="lp-wrap lp-strip-inner">
          <span><b>1 painel</b> pra clínica inteira</span>
          <span>WhatsApp <b>+ Instagram</b></span>
          <span>agenda · CRM · <b>financeiro</b></span>
          <span>IA <b>opcional</b>, com ou sem</span>
        </div>
      </div>

      {/* PROBLEMA / SOLUÇÃO */}
      <section className="lp-sec lp-sec-soft">
        <div className="lp-wrap lp-split">
          <div className="lp-head">
            <span className="lp-kicker">Seu problema, nossa solução</span>
            <h2>Uma clínica não deveria precisar de cinco sistemas abertos</h2>
            <p>WhatsApp Web num canto, o sistema de agenda em outro, o financeiro num terceiro, o disparador de mensagens num quarto — cada um cobrando à parte e nenhum conversando com o outro. O CliniSac junta tudo num painel só.</p>
          </div>
          <div className="lp-solutions">
            {solutions.map((s, i) => (
              <div className="lp-sol" key={i}><span className="lp-check"><Check /></span><span>{s}</span></div>
            ))}
          </div>
        </div>
      </section>

      {/* RECURSOS */}
      <section className="lp-sec" id="recursos">
        <div className="lp-wrap">
          <div className="lp-head center">
            <span className="lp-kicker">A plataforma</span>
            <h2>Uma clínica completa, não só um chatbot</h2>
            <p>Seis módulos que conversam entre si — a IA é só uma das camadas, e é opcional.</p>
          </div>
          <div className="lp-features">

            <article className="lp-feat">
              <div className="lp-feat-vis v-mint">
                <div className="lp-panel">
                  <div className="lp-mini-b lp-mini-in">Vocês atendem sábado?</div>
                  <div className="lp-mini-b lp-mini-out"><small>IA · 02:47</small>Atendemos sim! Sábado das 8h às 12h 🙂</div>
                  <div className="lp-mini-b lp-mini-in">Quero marcar avaliação</div>
                  <div className="lp-mini-b lp-mini-out">Perfeito! Já passo pra recepção confirmar seu horário.</div>
                </div>
              </div>
              <div className="lp-feat-body"><h3>Atendimento — com ou sem IA</h3><p>Caixa unificada de WhatsApp e Instagram pra equipe atender de um lugar só. Se quiser, a IA responde e qualifica na hora, 24/7; se não quiser, é só desligar.</p></div>
            </article>

            <article className="lp-feat">
              <div className="lp-feat-vis v-sky">
                <div className="lp-panel" style={{ gap: 4 }}>
                  <div style={{ display: 'grid', gridTemplateColumns: '30px repeat(3,1fr)', fontSize: 8, fontWeight: 700, color: '#475569', textAlign: 'center' }}>
                    <span /><span style={{ padding: '3px 0' }}>SEG</span><span style={{ padding: '3px 0', color: '#2563EB' }}>TER</span><span style={{ padding: '3px 0' }}>QUA</span>
                  </div>
                  {[['08:00', 'Ana · Aval.', '#ECFDF3', '#16A34A'], ['09:00', 'Paula · Limpeza', '#EFF6FF', '#2563EB'], ['10:00', 'Rafael · Canal', '#F5F3FF', '#7C3AED'], ['11:00', 'Júlia · Retorno', '#FEF9E7', '#B45309']].map(([h, t, bg, c], i) => (
                    <div key={i} style={{ display: 'grid', gridTemplateColumns: '30px repeat(3,1fr)', fontSize: 7, color: '#94A3B8', borderTop: '1px solid #F1EFF7' }}>
                      <span style={{ padding: '4px' }}>{h}</span><span />
                      <span style={{ padding: 2 }}><span style={{ display: 'block', background: bg, borderLeft: `2px solid ${c}`, borderRadius: 3, padding: '2px 4px', color: c, fontWeight: 600 }}>{t}</span></span><span />
                    </div>
                  ))}
                </div>
              </div>
              <div className="lp-feat-body"><h3>Agenda inteligente</h3><p>Agenda por profissional, bloqueios, recorrência, lembretes e confirmação por WhatsApp que reduzem faltas.</p></div>
            </article>

            <article className="lp-feat">
              <div className="lp-feat-vis v-violet">
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 7, height: '100%' }}>
                  {[['Novo lead', '#2563EB', ['Fernanda M.', 'Diego S.']], ['Orçamento', '#D97706', ['Ana Beatriz', 'Carlos D.']], ['Fechado', '#059669', ['Paula A.', 'Rafael T.']]].map(([col, c, names], i) => (
                    <div key={i} style={{ background: '#fff', border: '1px solid #EAE7F2', borderRadius: '8px 8px 0 0', padding: 7, display: 'flex', flexDirection: 'column', gap: 5 }}>
                      <span style={{ fontSize: 8, fontWeight: 700, color: '#475569', display: 'flex', alignItems: 'center', gap: 4 }}><span style={{ width: 6, height: 6, borderRadius: 2, background: c }} />{col}</span>
                      {names.map((n, j) => (
                        <span key={j} style={{ background: '#F8FAFC', border: '1px solid #EAE7F2', borderRadius: 6, padding: '5px 7px', fontSize: 8.5, fontWeight: 600, color: '#0F0E1B' }}>{n}</span>
                      ))}
                    </div>
                  ))}
                </div>
              </div>
              <div className="lp-feat-body"><h3>CRM com funil de vendas</h3><p>Kanban de leads e orçamentos: nada esquecido, temperatura do lead à vista, follow-up cobrado.</p></div>
            </article>

            <article className="lp-feat">
              <div className="lp-feat-vis v-amber">
                <div className="lp-panel">
                  <div style={{ display: 'flex', alignItems: 'center', gap: 7, borderBottom: '1px solid #F1EFF7', paddingBottom: 6 }}>
                    <span className="lp-m-av" style={{ width: 22, height: 22, fontSize: 10 }}>A</span>
                    <span style={{ lineHeight: 1.3 }}><b style={{ fontSize: 9.5 }}>Ana Beatriz Souza</b><br /><span style={{ fontSize: 7.5, color: '#94A3B8' }}>34 anos · desde mar/2026</span></span>
                    <span style={{ marginLeft: 'auto', fontSize: 7, fontWeight: 700, padding: '1px 6px', borderRadius: 20, color: '#059669', background: '#ECFDF5' }}>Em tratamento</span>
                  </div>
                  <div style={{ display: 'flex', gap: 4, fontSize: 7.5, fontWeight: 600 }}>
                    <span style={{ padding: '2px 7px', borderRadius: 6, background: '#EFF6FF', color: '#2563EB' }}>Prontuário</span>
                    <span style={{ padding: '2px 7px', borderRadius: 6, color: '#64748B', border: '1px solid #EAE7F2' }}>Anamnese</span>
                    <span style={{ padding: '2px 7px', borderRadius: 6, color: '#64748B', border: '1px solid #EAE7F2' }}>Plano</span>
                  </div>
                  {[['12/08', 'Avaliação inicial — anexo raio-x.pdf'], ['19/08', 'Limpeza + orientações'], ['02/09', 'Retorno · lembrete ativo']].map(([d, t], i) => (
                    <span key={i} style={{ background: '#F8FAFC', border: '1px solid #EAE7F2', borderRadius: 6, padding: '4px 7px', fontSize: 8, color: '#334155' }}><b>{d}</b> · {t}</span>
                  ))}
                </div>
              </div>
              <div className="lp-feat-body"><h3>Prontuário e anamnese</h3><p>Ficha do paciente, anexos, plano de tratamento e histórico da conversa no mesmo lugar.</p></div>
            </article>

            <article className="lp-feat">
              <div className="lp-feat-vis v-mint">
                <div className="lp-panel">
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6 }}>
                    <span style={{ background: '#F8FAFC', border: '1px solid #EAE7F2', borderRadius: 6, padding: '6px 8px' }}><span style={{ fontSize: 7, color: '#94A3B8', fontWeight: 700, textTransform: 'uppercase' }}>Recebido no mês</span><br /><b style={{ fontSize: 12, color: '#059669' }}>R$ 48.320</b></span>
                    <span style={{ background: '#F8FAFC', border: '1px solid #EAE7F2', borderRadius: 6, padding: '6px 8px' }}><span style={{ fontSize: 7, color: '#94A3B8', fontWeight: 700, textTransform: 'uppercase' }}>A receber</span><br /><b style={{ fontSize: 12, color: '#0F0E1B' }}>R$ 12.900</b></span>
                  </div>
                  {[['Limpeza · Paula A. · Pix', '+ R$ 280', '#059669'], ['Ortodontia · Rafael T. · 3x', '+ R$ 1.066', '#059669'], ['Aluguel · boleto', '− R$ 3.500', '#DC2626']].map(([t, v, c], i) => (
                    <span key={i} style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid #F1EFF7', padding: '3px 2px', fontSize: 8, color: '#334155' }}>{t}<b style={{ color: c }}>{v}</b></span>
                  ))}
                </div>
              </div>
              <div className="lp-feat-body"><h3>Financeiro integrado</h3><p>Consulta feita vira lançamento. Contas, transferências e fechamento do mês sem planilha.</p></div>
            </article>

            <article className="lp-feat">
              <div className="lp-feat-vis v-violet">
                <div className="lp-panel">
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 6 }}>
                    {[['Atend.', '1.284', '#0F0E1B'], ['IA', '68%', '#7C3AED'], ['Agend.', '312', '#059669']].map(([k, v, c], i) => (
                      <span key={i} style={{ background: '#F8FAFC', border: '1px solid #EAE7F2', borderRadius: 6, padding: '5px 7px' }}><span style={{ fontSize: 6.5, color: '#94A3B8', fontWeight: 700, textTransform: 'uppercase' }}>{k}</span><br /><b style={{ fontSize: 11, color: c }}>{v}</b></span>
                    ))}
                  </div>
                  <div style={{ flex: 1, display: 'flex', alignItems: 'flex-end', gap: 5, padding: '8px 4px 0' }}>
                    {[34, 48, 42, 62, 55, 78, 92].map((h, i) => (
                      <span key={i} style={{ flex: 1, height: `${h}%`, background: i === 6 ? '#22D3EE' : i >= 4 ? '#4ADE80' : '#BBF7D0', borderRadius: '3px 3px 0 0' }} />
                    ))}
                  </div>
                </div>
              </div>
              <div className="lp-feat-body"><h3>Métricas em tempo real</h3><p>Atendimentos, agendamentos, equipe e faturamento em dashboards sempre atualizados.</p></div>
            </article>

          </div>
        </div>
      </section>

      {/* AUTOMAÇÕES */}
      <section className="lp-sec lp-sec-soft" id="automacoes">
        <div className="lp-wrap">
          <div className="lp-head center">
            <span className="lp-kicker">Automações</span>
            <h2>O sistema trabalha mesmo quando ninguém está olhando</h2>
            <p>Rotinas que rodam sozinhas — antes e depois da consulta — pra clínica não depender de alguém lembrar.</p>
          </div>
          <div className="lp-autos">
            <article className="lp-auto">
              <span className="lp-auto-ic"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#0F0E1B" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 11l3 3L22 4" /><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" /></svg></span>
              <h3>Confirmação de presença</h3>
              <p>O sistema chama o paciente no WhatsApp pra confirmar a consulta e atualiza a agenda com a resposta — menos faltas, sem a recepção ligar.</p>
            </article>
            <article className="lp-auto">
              <span className="lp-auto-ic"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#0F0E1B" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 12a9 9 0 1 0 9-9 9 9 0 0 0-6.4 2.6L3 8" /><path d="M3 3v5h5" /></svg></span>
              <h3>Follow-up pós-consulta</h3>
              <p>Marcou a consulta como concluída? O sistema entra em contato pra saber como foi — cuidado que o paciente sente e que traz ele de volta.</p>
            </article>
            <article className="lp-auto">
              <span className="lp-auto-ic"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#0F0E1B" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M11.5 3.3a.5.5 0 0 1 .9 0l2.3 4.6 5.1.7a.5.5 0 0 1 .3.9l-3.7 3.6.9 5.1a.5.5 0 0 1-.8.5L12 16.9l-4.6 2.4a.5.5 0 0 1-.8-.5l.9-5.1L3.8 9.5a.5.5 0 0 1 .3-.9l5.1-.7z" /></svg></span>
              <h3>Pesquisa de satisfação</h3>
              <p>Envio automático da pesquisa de satisfação com o link do seu Google Meu Negócio — transforma paciente feliz em avaliação 5 estrelas.</p>
            </article>
            <article className="lp-auto">
              <span className="lp-auto-ic"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#0F0E1B" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 3v18h18" /><path d="m7 14 4-4 3 3 5-6" /></svg></span>
              <h3>Rastreamento de campanhas</h3>
              <p>Cada lead entra marcado com a origem, pra você medir quais campanhas realmente trazem paciente — e parar de gastar no que não converte.</p>
            </article>
          </div>
        </div>
      </section>

      {/* COMO FUNCIONA */}
      <section className="lp-sec" id="como-funciona">
        <div className="lp-wrap">
          <div className="lp-head">
            <span className="lp-kicker">Como funciona</span>
            <h2>Em produção na sua clínica em 3 passos</h2>
          </div>
          <div className="lp-steps">
            {steps.map((s) => (
              <div className="lp-step" key={s.n}><span className="lp-step-n">{s.n}</span><h3>{s.title}</h3><p>{s.desc}</p></div>
            ))}
          </div>
        </div>
      </section>

      {/* PRA QUEM É */}
      <section className="lp-sec" id="pra-quem">
        <div className="lp-wrap">
          <div className="lp-head">
            <span className="lp-kicker">Pra quem é</span>
            <h2>Feito pra clínica que atende pelo WhatsApp</h2>
          </div>
          <div className="lp-icps">
            {icps.map((i, k) => (
              <div className="lp-icp" key={k}><span className="lp-icp-tag">{i.tag}</span><h3>{i.title}</h3><p>{i.desc}</p></div>
            ))}
          </div>
        </div>
      </section>

      {/* DEPOIMENTO */}
      <section className="lp-sec lp-sec-soft">
        <div className="lp-wrap lp-quote">
          <div className="lp-stars">{[0, 1, 2, 3, 4].map((i) => <Star key={i} />)}</div>
          <blockquote>“Antes a recepção passava o dia no WhatsApp e mesmo assim paciente ficava sem resposta. Hoje a IA segura a madrugada e o fim de semana — a agenda nunca esteve tão cheia.”</blockquote>
          <cite><b>Dra. Camila R.</b><span>Clínica odontológica · Porto Velho/RO</span></cite>
        </div>
      </section>

      {/* PLANOS */}
      <section className="lp-sec" id="planos">
        <div className="lp-wrap">
          <div className="lp-head center">
            <span className="lp-kicker">Planos</span>
            <h2>Um plano pro tamanho da sua clínica</h2>
            <p>Fale com a gente e receba a proposta certa — sem surpresa, sem taxa escondida.</p>
          </div>
          <div className="lp-plans">
            {plans.map((p, k) => (
              <div className={`lp-plan${p.feat ? ' feat' : ''}`} key={k}>
                {p.feat && <span className="lp-plan-badge">Mais escolhido</span>}
                <div><h3>{p.name}</h3><p className="lp-plan-sub">{p.sub}</p></div>
                <div className="lp-plan-items">
                  {p.items.map((it, j) => (
                    <span className="lp-plan-it" key={j}><Check c={p.feat ? '#4ADE80' : '#059669'} />{it}</span>
                  ))}
                </div>
                <a href={waUrl} target="_blank" rel="noreferrer" className={`lp-btn lp-btn-lg ${p.feat ? 'lp-btn-primary' : 'lp-btn-ghost'}`} style={{ justifyContent: 'center' }}>Falar com a gente</a>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="lp-sec lp-sec-soft" id="faq">
        <div className="lp-wrap">
          <div className="lp-head center">
            <span className="lp-kicker">Dúvidas frequentes</span>
            <h2>O que as clínicas perguntam antes de começar</h2>
          </div>
          <div className="lp-faq">
            {faqs.map((f, i) => (
              <details className="lp-q" key={i}>
                <summary>
                  {f.q}
                  <span className="lp-q-ic"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#16A34A" strokeWidth="2.6" strokeLinecap="round"><path d="M12 5v14M5 12h14" /></svg></span>
                </summary>
                <p className="lp-q-a">{f.a}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* CTA FINAL */}
      <div className="lp-wrap lp-cta-wrap">
        <div className="lp-cta">
          <h2>Sua clínica com atendimento de alto nível, a partir de hoje</h2>
          <p>Teste 7 dias grátis, sem cartão e sem fidelidade. A gente configura junto com você.</p>
          <a href={waUrl} target="_blank" rel="noreferrer" className="lp-btn lp-btn-primary lp-btn-lg" style={{ marginTop: 6 }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="#0F0E1B"><path d="M17.47 14.38c-.3-.15-1.76-.87-2.03-.97-.27-.1-.47-.15-.67.15-.2.3-.77.97-.94 1.16-.17.2-.35.22-.64.08-.3-.15-1.26-.46-2.4-1.48-.88-.79-1.48-1.76-1.65-2.06-.17-.3-.02-.46.13-.6.13-.14.3-.35.45-.52.15-.17.2-.3.3-.5.1-.2.05-.37-.02-.52-.08-.15-.67-1.61-.92-2.2-.24-.58-.49-.5-.67-.51h-.57c-.2 0-.52.07-.8.37-.27.3-1.04 1.02-1.04 2.48s1.07 2.88 1.22 3.07c.15.2 2.1 3.2 5.08 4.49.7.3 1.26.49 1.7.63.7.22 1.36.19 1.87.12.57-.09 1.76-.72 2-1.41.25-.7.25-1.29.18-1.42-.08-.12-.27-.2-.57-.35" /><path d="M12.05 21.78h-.01a9.87 9.87 0 0 1-5.03-1.38l-.36-.21-3.74.98 1-3.65-.24-.37a9.86 9.86 0 0 1-1.51-5.26c0-5.45 4.44-9.88 9.89-9.88 2.64 0 5.12 1.03 6.99 2.9a9.83 9.83 0 0 1 2.89 6.99c0 5.45-4.44 9.88-9.89 9.88M20.46 3.49A11.82 11.82 0 0 0 12.05 0C5.5 0 .16 5.34.16 11.9c0 2.1.55 4.14 1.59 5.95L.06 24l6.3-1.65a11.88 11.88 0 0 0 5.69 1.45h.01c6.55 0 11.89-5.34 11.89-11.9 0-3.18-1.24-6.17-3.49-8.42" /></svg>
            Agendar demonstração
          </a>
        </div>
      </div>

      {/* FOOTER */}
      <footer className="lp-footer">
        <div className="lp-wrap lp-footer-inner">
          <div className="lp-footer-brand">
            <img src="/clinisac-logo.svg" alt="CliniSac" />
            <span>O SAC inteligente da sua clínica</span>
          </div>
          <small>CliniSac © 2026 · Feito no Brasil pra clínicas brasileiras</small>
        </div>
      </footer>

    </div>
  )
}
