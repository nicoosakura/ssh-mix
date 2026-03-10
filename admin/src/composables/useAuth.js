import JSEncrypt from 'jsencrypt'

const API_BASE = '/api'

export function useRSALogin() {
    async function getPublicKey() {
        const res = await fetch(`${API_BASE}/auth/public-key`)
        const data = await res.json()
        return data.public_key
    }

    async function encryptedLogin(username, password) {
        const pubKey = await getPublicKey()
        const encrypt = new JSEncrypt()
        encrypt.setPublicKey(pubKey)
        const encryptedPassword = encrypt.encrypt(password)

        const res = await fetch(`${API_BASE}/auth/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password: encryptedPassword })
        })

        const data = await res.json()
        if (!res.ok) throw new Error(data.error)

        if (data.role !== 'admin') {
            throw new Error('权限不足：仅限管理员登录管理系统')
        }

        return data
    }

    return { encryptedLogin }
}
