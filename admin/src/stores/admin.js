import { defineStore } from 'pinia'
import { ref } from 'vue'
import { useApi } from '../composables/useApi'

export const useAdminStore = defineStore('admin', () => {
    const users = ref([])
    const auditLogs = ref([])
    const systemInfo = ref(null)
    const allServers = ref([])
    const allScripts = ref([])
    const backups = ref([])
    const totalUsers = ref(0)
    const totalServers = ref(0)
    // CPU usage history (最近 10 个采样点)
    const cpuHistory = ref([])

    const api = useApi()

    async function fetchUsers() {
        const data = await api.get('/admin/users')
        users.value = data
        totalUsers.value = data.length
        return data
    }

    async function createUser(payload) {
        await api.post('/admin/users', payload)
        await fetchUsers()
    }

    async function updateUser(uid, payload) {
        await api.put(`/admin/users/${uid}`, payload)
        await fetchUsers()
    }

    async function deleteUser(uid) {
        await api.del(`/admin/users/${uid}`)
        await fetchUsers()
    }

    async function batchDeleteUsers(ids) {
        await api.request('/admin/users/batch', {
            method: 'DELETE',
            body: JSON.stringify({ ids })
        })
        await fetchUsers()
    }

    async function resetUserPassword(uid, password) {
        await api.post(`/admin/users/${uid}/reset-password`, { password })
    }

    async function fetchUserServers(uid) {
        return await api.get(`/admin/users/${uid}/servers`)
    }

    async function fetchAuditLogs() {
        auditLogs.value = await api.get('/admin/audit-logs')
        return auditLogs.value
    }

    async function fetchSystemInfo() {
        const info = await api.get('/admin/system/info')
        systemInfo.value = info
        // Track CPU-equivalent metric (goroutines as load proxy)
        if (info) {
            cpuHistory.value.push({
                time: new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit', second: '2-digit' }),
                goroutines: info.goroutines || 0,
                memMb: info.mem_alloc_mb || 0
            })
            if (cpuHistory.value.length > 15) cpuHistory.value.shift()
        }
        return info
    }

    async function fetchAllServers() {
        allServers.value = await api.get('/admin/all-servers')
        totalServers.value = allServers.value.length
        return allServers.value
    }

    async function deleteServer(id) {
        await api.del(`/admin/all-servers/${id}`)
        await fetchAllServers()
    }

    async function batchDeleteServers(ids) {
        await api.request('/admin/all-servers/batch', {
            method: 'DELETE',
            body: JSON.stringify({ ids })
        })
        await fetchAllServers()
    }

    async function fetchAllScripts() {
        allScripts.value = await api.get('/admin/all-scripts')
        return allScripts.value
    }

    async function deleteScript(id) {
        await api.del(`/admin/all-scripts/${id}`)
        await fetchAllScripts()
    }

    async function exportServers(format = 'csv') {
        const auth = (await import('./auth')).useAuthStore()
        const url = `/api/admin/export?format=${format}&_=${Date.now()}`
        const res = await fetch(url, { headers: { Authorization: `Bearer ${auth().token}` } })
        if (!res.ok) throw new Error('导出失败')
        if (format === 'csv') {
            const blob = await res.blob()
            const a = document.createElement('a')
            a.href = URL.createObjectURL(blob)
            a.download = 'servers_export.csv'
            a.click()
            URL.revokeObjectURL(a.href)
        } else {
            return await res.json()
        }
    }

    async function fetchBackups() {
        backups.value = await api.get('/admin/backups')
        return backups.value
    }

    async function createBackup() {
        await api.post('/admin/backups/create')
        await fetchBackups()
    }

    async function restoreBackup(filename) {
        await api.post(`/admin/backups/restore/${filename}`)
    }

    return {
        users, auditLogs, systemInfo, allServers, allScripts,
        totalUsers, totalServers, cpuHistory,
        fetchUsers, createUser, updateUser, deleteUser, batchDeleteUsers,
        resetUserPassword, fetchUserServers,
        fetchAuditLogs, fetchSystemInfo,
        fetchAllServers, deleteServer, batchDeleteServers,
        fetchAllScripts, deleteScript, exportServers,
        backups, fetchBackups, createBackup, restoreBackup
    }
})
