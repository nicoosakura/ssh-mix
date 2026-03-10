<template>
  <div class="section-fade">
    <!-- Stats Cards -->
    <div class="stats-grid">
      <div class="glass-panel stats-card">
        <div class="stats-label">注册用户总数</div>
        <div class="stats-value">{{ adminStore.totalUsers || '-' }}</div>
      </div>
      <div class="glass-panel stats-card alt">
        <div class="stats-label">全网服务器资产</div>
        <div class="stats-value">{{ adminStore.totalServers || '-' }}</div>
      </div>
      <div class="glass-panel stats-card">
        <div class="stats-label">系统运行状态</div>
        <div class="stats-value" style="color: var(--success); font-size: 1.5rem;">Stable ✓</div>
      </div>
    </div>

    <!-- Resource Monitor -->
    <div class="glass-panel" style="padding: 24px; margin-bottom: 24px;">
      <h3 style="color: white; margin-bottom: 24px; font-weight: 500;">后端核心资源实时状态</h3>
      <div v-if="sysInfo">
        <div class="monitor-box-mini">
          <div class="monitor-label-row">
            <span>当前内存分配 (MEM Alloc)</span>
            <span>{{ sysInfo.mem_alloc_mb?.toFixed(1) }} MB / {{ sysInfo.mem_total_mb?.toFixed(1) }} MB</span>
          </div>
          <div class="progress-track">
            <div class="progress-fill" :style="{ width: memPct + '%' }" :class="memPct > 80 ? 'danger' : memPct > 60 ? 'warning' : ''"></div>
          </div>
        </div>
        <div class="monitor-box-mini" style="margin-bottom: 0; margin-top: 20px;">
          <div class="monitor-label-row">
            <span>活跃协程负载 (Goroutines)</span>
            <span>{{ sysInfo.goroutines }} active goroutines</span>
          </div>
          <div class="progress-track">
            <div class="progress-fill" :style="{ width: goPct + '%', background: 'var(--secondary)', boxShadow: '0 0 10px rgba(2,136,209,0.2)' }"></div>
          </div>
        </div>
      </div>
    </div>

    <!-- 资源使用历史图表 -->
    <div class="glass-panel" style="padding: 24px; margin-bottom: 24px;" v-if="adminStore.cpuHistory.length >= 2">
      <h3 style="color: white; margin-bottom: 20px; font-weight: 500;">📈 资源使用趋势（实时）</h3>
      <Line :data="chartData" :options="chartOptions" style="max-height:200px;" />
    </div>

    <!-- Quick Actions -->
    <div style="margin-bottom: 24px;">
      <h3 style="color: white; margin-bottom: 16px; font-weight: 500;">快捷管理员操作</h3>
      <div class="quick-actions-grid">
        <div class="glass-panel quick-btn" @click="goToUsers"><span>➕</span><span>新建系统用户</span></div>
        <div class="glass-panel quick-btn" @click="router.push('/system')"><span>📡</span><span>查看运行环境</span></div>
        <div class="glass-panel quick-btn" @click="refreshAll"><span>🔄</span><span>刷新全局数据</span></div>
        <div class="glass-panel quick-btn" @click="router.push('/servers')"><span>🌐</span><span>全局资产概览</span></div>
      </div>
    </div>

    <!-- Audit Logs -->
    <div class="glass-panel">
      <div style="display:flex; justify-content:space-between; align-items:center; padding: 20px 24px; border-bottom: 1px solid var(--card-border);">
        <h3 style="color:white; font-weight:500;">最近系统审计日志</h3>
        <div style="display:flex; gap:12px; align-items:center;">
          <select v-model="auditFilter" class="input-field" style="width:120px; height:32px; font-size:0.8rem; background:rgba(255,255,255,0.05); margin:0; padding: 4px 8px;">
            <option value="">全部行为</option>
            <option value="LOGIN">登录</option>
            <option value="CREATE">创建</option>
            <option value="DELETE">删除</option>
            <option value="UPDATE">更新</option>
            <option value="RESET">重置密码</option>
          </select>
          <button class="btn-action" style="background:none; border:1px solid var(--card-border); font-size:0.8rem;" @click="loadLogs">刷新日志</button>
        </div>
      </div>
      <div style="padding: 0 8px;">
        <table class="activity-table">
          <thead>
            <tr><th>发生时间</th><th>操作员</th><th>行为</th><th>详细信息</th></tr>
          </thead>
          <tbody>
            <tr v-if="!filteredLogs.length">
              <td colspan="4" style="text-align:center; color:var(--text-muted); padding:40px;">暂无最近操作记录</td>
            </tr>
            <tr v-for="log in filteredLogs" :key="log.id">
              <td style="color:var(--text-muted); font-size:0.8rem;">{{ formatDate(log.created_at) }}</td>
              <td style="font-weight:600; color:var(--primary);">@{{ log.username }}</td>
              <td><span :class="['action-badge', log.action]">{{ log.action }}</span></td>
              <td style="color:var(--text-muted);">{{ log.detail }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, inject } from 'vue'
import { useRouter } from 'vue-router'
import { useAdminStore } from '../stores/admin'
import { usePolling } from '../composables/usePolling'
import { Line } from 'vue-chartjs'
import {
  Chart as ChartJS, CategoryScale, LinearScale, PointElement,
  LineElement, Tooltip, Filler
} from 'chart.js'

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Tooltip, Filler)

const router = useRouter()
const adminStore = useAdminStore()
const toast = inject('toast')
const auditFilter = ref('')
const sysInfo = ref(null)

const memPct = computed(() => {
  if (!sysInfo.value) return 0
  const { mem_alloc_mb, mem_total_mb } = sysInfo.value
  return mem_total_mb > 0 ? Math.min((mem_alloc_mb / mem_total_mb) * 100, 100) : 0
})
const goPct = computed(() => {
  if (!sysInfo.value) return 0
  return Math.min((sysInfo.value.goroutines / 500) * 100, 100)
})

// Chart data derived from cpuHistory
const chartData = computed(() => ({
  labels: adminStore.cpuHistory.map(h => h.time),
  datasets: [
    {
      label: '内存 (MB)',
      data: adminStore.cpuHistory.map(h => h.memMb),
      borderColor: '#58a6ff',
      backgroundColor: 'rgba(88,166,255,0.08)',
      fill: true,
      tension: 0.4,
      pointRadius: 3,
    },
    {
      label: '协程数',
      data: adminStore.cpuHistory.map(h => h.goroutines),
      borderColor: '#8957e5',
      backgroundColor: 'rgba(137,87,229,0.06)',
      fill: true,
      tension: 0.4,
      pointRadius: 3,
    }
  ]
}))

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: { legend: { display: true, labels: { color: '#8b949e', font: { size: 11 } } } },
  scales: {
    x: { ticks: { color: '#8b949e', maxRotation: 0, font: { size: 10 } }, grid: { color: 'rgba(255,255,255,0.04)' } },
    y: { ticks: { color: '#8b949e', font: { size: 10 } }, grid: { color: 'rgba(255,255,255,0.04)' } }
  }
}

const filteredLogs = computed(() => {
  if (!auditFilter.value) return adminStore.auditLogs
  return adminStore.auditLogs.filter(l => l.action.includes(auditFilter.value))
})

async function loadAll() {
  try {
    await Promise.all([
      adminStore.fetchUsers(),
      adminStore.fetchAllServers(),
      adminStore.fetchAuditLogs(),
    ])
    sysInfo.value = await adminStore.fetchSystemInfo()
  } catch { /* silent */ }
}

async function loadLogs() { await adminStore.fetchAuditLogs() }
function formatDate(d) { return new Date(d).toLocaleString('zh-CN') }
function goToUsers() { router.push('/users') }
async function refreshAll() { await loadAll(); toast.show('系统数据已强制刷新') }

usePolling(loadAll, 5000)
</script>

<style scoped>
.monitor-box-mini { margin-bottom: 20px; }
.monitor-label-row { display: flex; justify-content: space-between; margin-bottom: 8px; font-size: 0.85rem; color: var(--text-muted); }
</style>
