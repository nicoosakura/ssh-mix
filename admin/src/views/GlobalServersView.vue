<template>
  <div class="section-fade">
    <!-- Insights Bar + Actions -->
    <div style="display:flex; justify-content:space-between; align-items:flex-start; margin-bottom:24px; flex-wrap:wrap; gap:12px;">
      <div class="stats-grid" style="margin-bottom:0; flex:1; min-width:500px;">
        <div class="glass-panel stats-card" style="padding:15px; border-left:4px solid var(--primary);">
          <div class="stats-label">全平台在线率</div>
          <div class="stats-value" style="font-size:1.5rem; color:var(--success);">{{ onlineRate }}%</div>
        </div>
        <div class="glass-panel stats-card" style="padding:15px; border-left:4px solid var(--success);">
          <div class="stats-label">在线资产</div>
          <div class="stats-value" style="font-size:1.5rem; color:var(--success);">{{ onlineCount }}</div>
        </div>
        <div class="glass-panel stats-card alt" style="padding:15px; border-left:4px solid var(--danger);">
          <div class="stats-label">故障节点数</div>
          <div class="stats-value" style="font-size:1.5rem; color:var(--danger);">{{ offlineCount }}</div>
        </div>
        <div class="glass-panel stats-card" style="padding:15px; border-left:4px solid var(--secondary);">
          <div class="stats-label">受控资源总量</div>
          <div class="stats-value" style="font-size:1.5rem;">{{ filtered.length }}</div>
        </div>
      </div>
      <!-- Export + Batch Actions -->
      <div style="display:flex; gap:8px; align-items:center; flex-shrink:0;">
        <button v-if="selected.size > 0" class="btn-action" style="background:rgba(248,81,73,0.15); color:var(--danger); border:1px solid rgba(248,81,73,0.3);"
          @click="openBatchDelete">🗑️ 批量删除 ({{ selected.size }})</button>
        <button class="btn-action" style="background:rgba(255,255,255,0.05); border:1px solid var(--card-border);"
          @click="exportCsv">⬇️ 导出 CSV</button>
      </div>
    </div>

    <!-- Server Grid -->
    <div class="user-grid">
      <div v-if="!filtered.length" style="grid-column:1/-1; text-align:center; padding:60px; color:var(--text-muted);">
        {{ searchQuery ? '未找到匹配资产' : '暂无资产数据' }}
      </div>
      <div v-for="s in filtered" :key="s.ID" class="glass-panel user-card" style="cursor:default;">
        <!-- Checkbox -->
        <div style="position:absolute; top:12px; left:12px;" @click.stop>
          <input type="checkbox" :checked="selected.has(s.ID)"
            @change="toggleSelect(s.ID)"
            style="width:16px; height:16px; accent-color:var(--primary); cursor:pointer;" />
        </div>
        <div class="user-card-header" style="padding-left:28px;">
          <div :class="['status-badge', s.status === 'online' ? 'online' : 'offline']" style="margin:0;">
            <div class="dot"></div>{{ s.status === 'online' ? '在线' : '离线' }}
          </div>
          <div class="role-tag" style="background:rgba(var(--primary-rgb),0.1); color:var(--primary);">@{{ s.owner_name }}</div>
        </div>
        <div style="margin-bottom:12px; padding-left:4px;">
          <h3 style="color:white;">{{ s.name }}</h3>
          <p style="color:var(--text-muted); font-size:0.85rem; margin-top:4px;">HOST: {{ s.host }}:{{ s.port }}</p>
          <p style="color:var(--text-muted); font-size:0.8rem; margin-top:2px;">{{ s.description || '无描述' }}</p>
        </div>
        <div style="position:absolute; top:15px; right:15px;">
          <button @click.stop="openDelete(s)" style="background:none; border:none; color:var(--danger); cursor:pointer; font-size:1.1rem;" title="全局移除资产">🗑️</button>
        </div>
      </div>
    </div>

    <!-- Single Delete -->
    <ConfirmModal v-model="showConfirm" title="确认移除此资产？"
      message="此操作将从全局视图永久删除该服务器资产，无法撤销。"
      @confirm="confirmDelete" />

    <!-- Batch Delete -->
    <ConfirmModal v-model="showBatchConfirm" title="确认批量删除？"
      :message="`即将删除选中的 ${selected.size} 台服务器，此操作无法撤销。`"
      @confirm="confirmBatchDelete" />
  </div>
</template>

<script setup>
import { ref, computed, inject } from 'vue'
import { useAdminStore } from '../stores/admin'
import { usePolling } from '../composables/usePolling'
import ConfirmModal from '../components/common/ConfirmModal.vue'

const props = defineProps({ searchQuery: String })
const adminStore = useAdminStore()
const toast = inject('toast')

const selected = ref(new Set())

function toggleSelect(id) {
  const s = new Set(selected.value)
  if (s.has(id)) s.delete(id); else s.add(id)
  selected.value = s
}

const filtered = computed(() => {
  const q = (props.searchQuery || '').toLowerCase()
  const servers = adminStore.allServers
  if (!q) return servers
  return servers.filter(s =>
    s.name.toLowerCase().includes(q) ||
    (s.owner_name && s.owner_name.toLowerCase().includes(q)) ||
    s.host.toLowerCase().includes(q)
  )
})

const onlineCount = computed(() => filtered.value.filter(s => s.status === 'online').length)
const offlineCount = computed(() => filtered.value.filter(s => s.status !== 'online').length)
const onlineRate = computed(() => {
  const total = filtered.value.length
  return total > 0 ? Math.round((onlineCount.value / total) * 100) : 0
})

// Single delete
const showConfirm = ref(false)
const deletingServer = ref(null)
function openDelete(s) { deletingServer.value = s; showConfirm.value = true }
async function confirmDelete() {
  try {
    await adminStore.deleteServer(deletingServer.value.ID)
    selected.value.delete(deletingServer.value.ID)
    toast.show('资产已全局移除')
    showConfirm.value = false
  } catch (e) { toast.show(e.message, true) }
}

// Batch delete
const showBatchConfirm = ref(false)
function openBatchDelete() { showBatchConfirm.value = true }
async function confirmBatchDelete() {
  try {
    await adminStore.batchDeleteServers([...selected.value])
    toast.show(`已批量删除 ${selected.value.size} 台服务器`)
    selected.value = new Set()
    showBatchConfirm.value = false
  } catch (e) { toast.show(e.message, true) }
}

// Export
async function exportCsv() {
  try {
    await adminStore.exportServers('csv')
    toast.show('CSV 导出成功')
  } catch (e) { toast.show(e.message, true) }
}

usePolling(() => adminStore.fetchAllServers(), 5000)
</script>
