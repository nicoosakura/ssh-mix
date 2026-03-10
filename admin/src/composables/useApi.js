import { useAuthStore } from '../stores/auth'
import { useRouter } from 'vue-router'

const API_BASE = '/api'

export function useApi() {
  const auth = useAuthStore()

  async function request(path, options = {}) {
    const url = `${API_BASE}${path}${path.includes('?') ? '&' : '?'}_=${Date.now()}`
    const headers = { ...options.headers }

    if (auth.token) {
      headers['Authorization'] = `Bearer ${auth.token}`
    }

    if (options.body && typeof options.body === 'object' && !(options.body instanceof FormData)) {
      headers['Content-Type'] = 'application/json'
      options.body = JSON.stringify(options.body)
    }

    const res = await fetch(url, { ...options, headers })

    if (res.status === 401) {
      auth.logout()
      window.location.href = '/admin/'
      throw new Error('会话已过期，请重新登录')
    }

    const data = await res.json()
    if (!res.ok) throw new Error(data.error || '请求失败')
    return data
  }

  const get = (path) => request(path)
  const post = (path, body) => request(path, { method: 'POST', body })
  const put = (path, body) => request(path, { method: 'PUT', body })
  const del = (path) => request(path, { method: 'DELETE' })

  return { get, post, put, del, request }
}
