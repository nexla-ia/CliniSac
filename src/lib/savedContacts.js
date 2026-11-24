import { supabase } from './supabase'

// Pacientes (saved_contacts) têm UNIQUE (numero, instancia). Estes helpers deixam
// o salvar à prova dos dois casos que davam "Erro ao salvar":
//  - telefone vazio: grava NULL (vários pacientes sem telefone convivem). Se a
//    migration 20261124 ainda não rodou (numero NOT NULL), cai no '' antigo;
//  - número que já é de outro paciente: devolve quem é, pra tela avisar.

export const NOT_NULL = '23502'
export const DUPLICATE = '23505'

// Outro paciente da clínica com esse número (ignora o próprio, na edição).
export async function findOwnerOfNumero(instancia, numero, exceptId = null) {
  if (!numero) return null
  let q = supabase.from('saved_contacts').select('id, nome').eq('instancia', instancia).eq('numero', numero).limit(1)
  if (exceptId) q = q.neq('id', exceptId)
  const { data } = await q
  return data?.[0] || null
}

export function duplicateMessage(owner) {
  return owner?.nome
    ? `Esse número já está cadastrado para ${owner.nome}.`
    : 'Esse número já está cadastrado para outro paciente.'
}

// Roda a gravação com numero (NULL quando vazio) e, se o banco ainda exigir
// número (migration não rodou), tenta de novo com ''.
export async function saveWithOptionalNumero(numero, run) {
  const res = await run(numero || null)
  if (res.error?.code === NOT_NULL && !numero) return run('')
  return res
}
