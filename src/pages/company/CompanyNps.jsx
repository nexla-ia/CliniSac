import { useState } from 'react'
import { useAuth } from '../../context/AuthContext'
import { supabase } from '../../lib/supabase'
import { Star } from 'lucide-react'
import './Company.css'

const labelStyle = {
  display: 'block', fontSize: 11, fontWeight: 500,
  color: 'var(--text-muted)', marginBottom: 5,
  textTransform: 'uppercase', letterSpacing: '0.05em',
}

export default function CompanyNps() {
  const { session } = useAuth()
  const companyId = session?.company?.id

  const [googleReviewUrl,          setGoogleReviewUrl]          = useState(session?.company?.google_review_url || '')
  const [followupQuestionMessage,  setFollowupQuestionMessage]  = useState(session?.company?.followup_question_message || '')
  const [followupReviewMessage,    setFollowupReviewMessage]    = useState(session?.company?.followup_review_message || '')
  const [savingFollowup,   setSavingFollowup]   = useState(false)
  const [followupSaved,    setFollowupSaved]    = useState(false)
  const [followupErr,      setFollowupErr]      = useState('')

  async function saveFollowup() {
    if (!companyId) return
    setSavingFollowup(true); setFollowupErr(''); setFollowupSaved(false)
    const { error } = await supabase
      .from('companies')
      .update({
        google_review_url: googleReviewUrl.trim() || null,
        followup_question_message: followupQuestionMessage.trim() || null,
        followup_review_message: followupReviewMessage.trim() || null,
      })
      .eq('id', companyId)
    setSavingFollowup(false)
    if (error) {
      setFollowupErr('Erro ao salvar: ' + error.message)
    } else {
      setFollowupSaved(true)
      setTimeout(() => setFollowupSaved(false), 2500)
    }
  }

  return (
    <div className="alerts-root">
      <div className="alerts-header" style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: '1.5rem' }}>
        <div>
          <div style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '1.3rem', color: 'var(--text-primary)', marginBottom: 4 }}>
            NPS
          </div>
          <div style={{ fontSize: 13, color: 'var(--text-muted)' }}>
            Follow-up pós-consulta e avaliação Google
          </div>
        </div>
      </div>

      <div className="nx-card" style={{ padding: '1.25rem 1.5rem' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>

          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{ width: 36, height: 36, borderRadius: '50%', background: '#FEF9C3', border: '1px solid #FDE68A', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              <Star size={16} style={{ color: '#CA8A04' }} />
            </div>
            <div style={{ fontSize: 13, color: 'var(--text-secondary)', lineHeight: 1.5, maxWidth: 620 }}>
              1h depois que a consulta é marcada como <strong>concluída</strong>, o paciente recebe uma enquete
              perguntando como foi. Se responder <strong>Ótima/Boa</strong>, o link de avaliação do Google já
              é enviado na hora. Se responder <strong>Regular/Ruim</strong>, ninguém recebe o link — vira um
              alerta pra recepção ligar antes que a insatisfação vire uma nota pública. O resultado (quantos
              responderam, nota geral, quem avaliou mal) fica em <strong>Métricas → aba NPS</strong>.
            </div>
          </div>

          {/* Link do Google */}
          <div>
            <div style={labelStyle}>Link de avaliação do Google Meu Negócio</div>
            <input
              className="nx-input"
              placeholder="Ex: https://g.page/r/xxxxxxx/review"
              value={googleReviewUrl}
              onChange={e => setGoogleReviewUrl(e.target.value)}
              style={{ maxWidth: 480 }}
            />
            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 6 }}>
              Sem link cadastrado, o sistema ainda pergunta "como foi a consulta?", só não manda nada
              de avaliação — nem na hora, nem na pesquisa mensal de reforço.
            </div>
          </div>

          {/* Mensagem da pergunta */}
          <div>
            <div style={labelStyle}>Mensagem da pergunta (enquete pós-consulta)</div>
            <textarea
              className="nx-input"
              rows={2}
              placeholder="Olá {nome}! 👋 Como foi sua consulta?"
              value={followupQuestionMessage}
              onChange={e => setFollowupQuestionMessage(e.target.value)}
              style={{ maxWidth: 520, resize: 'vertical' }}
            />
            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 6 }}>
              Use <code style={{ fontSize: 11 }}>{'{nome}'}</code> pro nome do paciente. Vazio = usa o texto padrão.
            </div>
            <div style={{
              background: '#F0FDF4', border: '1px solid #BBF7D0', borderRadius: 12,
              padding: '12px 14px', fontSize: 13.5, lineHeight: 1.55, color: '#0F172A',
              maxWidth: 480, marginTop: 8,
            }}>
              {(followupQuestionMessage.trim() || 'Olá {nome}! 👋 Como foi sua consulta?')
                .replace(/\{nome\}/gi, 'Maria')}
            </div>
          </div>

          {/* Mensagem de avaliação (link) */}
          <div>
            <div style={labelStyle}>Mensagem que acompanha o link do Google</div>
            <textarea
              className="nx-input"
              rows={2}
              placeholder="Que ótimo, {nome}! 😄 Se puder, deixa sua avaliação — ajuda muito a gente: {link}"
              value={followupReviewMessage}
              onChange={e => setFollowupReviewMessage(e.target.value)}
              style={{ maxWidth: 520, resize: 'vertical' }}
            />
            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 6 }}>
              Use <code style={{ fontSize: 11 }}>{'{nome}'}</code> e <code style={{ fontSize: 11 }}>{'{link}'}</code>.
              Essa mesma mensagem vale pro envio na hora (resposta boa) e pro reforço mensal de quem não respondeu.
            </div>
            <div style={{
              background: '#F0FDF4', border: '1px solid #BBF7D0', borderRadius: 12,
              padding: '12px 14px', fontSize: 13.5, lineHeight: 1.55, color: '#0F172A',
              maxWidth: 480, marginTop: 8,
            }}>
              {(followupReviewMessage.trim() || 'Que ótimo, {nome}! 😄 Se puder, deixa sua avaliação — ajuda muito a gente: {link}')
                .replace(/\{nome\}/gi, 'Maria')
                .replace(/\{link\}/gi, googleReviewUrl.trim() || 'https://g.page/r/xxxxxxx/review')}
            </div>
          </div>

          {/* Save */}
          <div style={{ display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap', paddingTop: 4 }}>
            <button onClick={saveFollowup} disabled={savingFollowup} className="nx-btn-primary"
              style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 12, padding: '8px 16px' }}>
              {savingFollowup ? 'Salvando...' : 'Salvar configuração'}
            </button>
            {followupSaved && (
              <span style={{ fontSize: 12, color: '#16A34A', fontWeight: 600 }}>
                ✓ Salvo com sucesso
              </span>
            )}
            {followupErr && (
              <span style={{ fontSize: 12, color: '#DC2626', fontWeight: 600 }}>
                {followupErr}
              </span>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
