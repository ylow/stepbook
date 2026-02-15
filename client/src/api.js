const API = '/api'

export async function fetchSequences() {
  const res = await fetch(`${API}/sequences`)
  return res.json()
}

export async function fetchSequence(id) {
  const res = await fetch(`${API}/sequences/${id}`)
  return res.json()
}

export async function createSequence(title, description = '') {
  const res = await fetch(`${API}/sequences`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, description })
  })
  return res.json()
}

export async function updateSequence(id, data) {
  const res = await fetch(`${API}/sequences/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  })
  return res.json()
}

export async function deleteSequence(id) {
  await fetch(`${API}/sequences/${id}`, { method: 'DELETE' })
}

export async function addStep(sequenceId, imageFile) {
  const form = new FormData()
  form.append('image', imageFile)
  const res = await fetch(`${API}/sequences/${sequenceId}/steps`, {
    method: 'POST',
    body: form
  })
  return res.json()
}

export async function updateStep(stepId, data) {
  const res = await fetch(`${API}/steps/${stepId}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  })
  return res.json()
}

export async function deleteStep(stepId) {
  await fetch(`${API}/steps/${stepId}`, { method: 'DELETE' })
}

export async function reorderSteps(sequenceId, stepIds) {
  const res = await fetch(`${API}/sequences/${sequenceId}/reorder`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ stepIds })
  })
  return res.json()
}

export async function exportSequence(id) {
  const res = await fetch(`${API}/sequences/${id}/export`)
  if (!res.ok) throw new Error('Export failed')
  const blob = await res.blob()
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = res.headers.get('Content-Disposition')?.match(/filename="(.+)"/)?.[1] || 'sequence.zip'
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

export async function importSequence(file) {
  const form = new FormData()
  form.append('file', file)
  const res = await fetch(`${API}/sequences/import`, {
    method: 'POST',
    body: form
  })
  if (!res.ok) {
    let msg = 'Import failed'
    try { const err = await res.json(); msg = err.error || msg } catch {}
    throw new Error(msg)
  }
  return res.json()
}
