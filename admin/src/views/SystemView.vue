<template>
  <div class="section-fade">
    <div class="monitor-grid">
      <div class="glass-panel monitor-card" v-if="info">
        <h3 style="margin-bottom:20px; color:var(--primary);">后端运行环境</h3>
        <div class="monitor-item"><span class="monitor-label">内核版本</span><span class="monitor-val">{{ info.os }}</span></div>
        <div class="monitor-item"><span class="monitor-label">处理器架构</span><span class="monitor-val">{{ info.arch }}</span></div>
        <div class="monitor-item"><span class="monitor-label">Go 版本</span><span class="monitor-val">{{ info.go_version }}</span></div>
        <div class="monitor-item"><span class="monitor-label">逻辑 CPU</span><span class="monitor-val">{{ info.cpu_count }} 核</span></div>
      </div>
      <div class="glass-panel monitor-card" v-if="info">
        <h3 style="margin-bottom:20px; color:var(--secondary);">实时资源消耗</h3>
        <div class="monitor-item"><span class="monitor-label">当前内存分配</span><span class="monitor-val">{{ info.mem_alloc_mb?.toFixed(1) }} MB</span></div>
        <div class="monitor-item"><span class="monitor-label">系统内存预留</span><span class="monitor-val">{{ info.mem_total_mb?.toFixed(1) }} MB</span></div>
        <div class="monitor-item"><span class="monitor-label">活跃协程数</span><span class="monitor-val">{{ info.goroutines }}</span></div>
        <div class="monitor-item"><span class="monitor-label">服务运行时间</span><span class="monitor-val">{{ info.uptime }}</span></div>
      </div>
      <div v-if="!info" style="grid-column:1/-1; text-align:center; padding:60px; color:var(--text-muted);">加载中...</div>
      
      <!-- 数据库备份管理面板 -->
      <div class="glass-panel monitor-card" style="grid-column: 1 / -1;" v-if="info">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
          <h3 style="color:var(--warning); margin: 0;">数据库备份管理</h3>
          <button class="btn btn-primary" @click="handleCreateBackup" :disabled="isCreatingBackup">
            <span class="icon">{{ isCreatingBackup ? '⏳' : '💾' }}</span> {{ isCreatingBackup ? '备份中...' : '立即备份' }}
          </button>
        </div>
        
        <div v-if="adminStore.backups.length === 0" style="text-align:center; padding: 20px; color:var(--text-muted);">
          暂无备份记录
        </div>
        <div v-else class="backup-list">
          <div v-for="backup in adminStore.backups" :key="backup.filename" class="backup-item">
            <div class="backup-info">
              <span class="backup-name">{{ backup.filename }}</span>
              <span class="backup-meta">{{ formatBytes(backup.size) }} • {{ formatDate(backup.time) }}</span>
            </div>
            <button class="btn btn-danger btn-sm" @click="handleRestore(backup.filename)">
              恢复
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useAdminStore } from '../stores/admin'
import { usePolling } from '../composables/usePolling'

const adminStore = useAdminStore()
const info = ref(null)
const isCreatingBackup = ref(false)

// 格式化函数
const formatBytes = (bytes) => {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

const formatDate = (dateStr) => {
  const d = new Date(dateStr)
  return d.toLocaleString('zh-CN', {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit'
  })
}

// 备份操作
const handleCreateBackup = async () => {
  if (!confirm('确定要立即创建数据库冷备吗？')) return
  try {
    isCreatingBackup.value = true
    await adminStore.createBackup()
    alert('备份成功！')
  } catch (e) {
    alert('备份失败: ' + e.message)
  } finally {
    isCreatingBackup.value = false
  }
}

const handleRestore = async (filename) => {
  const msg = `⚠️ 警告 ⚠️\n\n确定要将数据库回滚到【${filename}】吗？\n当前的所有未备份数据将会丢失！\n建议先执行一次“立即备份”。`
  if (!confirm(msg)) return
  
  // 二次确认，防止手滑
  const confirmText = prompt(`请输入 "RESTORE" 来确认回滚操作:`)
  if (confirmText !== 'RESTORE') {
    alert('已取消回滚操作。')
    return
  }

  try {
    await adminStore.restoreBackup(filename)
    alert('恢复成功，建议重启后端服务以确保所有连接重置。')
    await adminStore.fetchBackups()
  } catch (e) {
    alert('恢复失败: ' + e.message)
  }
}

onMounted(() => {
  adminStore.fetchBackups()
})

usePolling(async () => {
  info.value = await adminStore.fetchSystemInfo()
}, 5000)
</script>

<style scoped>
.backup-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.backup-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px 16px;
  background: var(--bg-darker);
  border: 1px solid var(--border-color);
  border-radius: 8px;
  transition: all 0.2s ease;
}
.backup-item:hover {
  border-color: var(--primary);
  transform: translateX(4px);
}
.backup-info {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.backup-name {
  font-family: 'JetBrains Mono', monospace;
  font-size: 0.95rem;
  color: var(--text-primary);
}
.backup-meta {
  font-size: 0.85rem;
  color: var(--text-muted);
}
.btn-sm {
  padding: 6px 12px;
  font-size: 0.85rem;
}
