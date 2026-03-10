<template>
  <div class="section-fade">
    <div class="user-grid">
      <div v-if="!filtered.length" style="grid-column:1/-1; text-align:center; padding:60px; color:var(--text-muted);">
        {{ searchQuery ? '未找到匹配脚本' : '暂无脚本数据' }}
      </div>
      <div v-for="s in filtered" :key="s.ID" class="glass-panel user-card" style="cursor:default; padding:20px;">
        <div style="display:flex; justify-content:space-between; align-items:flex-start; margin-bottom:12px;">
          <div style="font-size:1.5rem;">📜</div>
          <div style="display:flex; gap:8px; align-items:center;">
            <div class="role-tag" style="background:rgba(var(--primary-rgb),0.1); color:var(--primary);">@{{ s.owner_name }}</div>
            <button @click.stop="openDelete(s)" style="background:none; border:none; color:var(--danger); cursor:pointer; font-size:1.1rem;" title="全局清理脚本">🗑️</button>
          </div>
        </div>
        <h3 style="color:white; margin-bottom:8px;">{{ s.name }}</h3>
        <p style="color:var(--text-muted); font-size:0.85rem; line-height:1.4; height:3.4em; overflow:hidden;">{{ s.description || '无脚本描述信息' }}</p>
        <div style="margin-top:15px; background:rgba(0,0,0,0.2); padding:8px; border-radius:4px; font-family:monospace; font-size:0.75rem; color:#a5d6ff; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">
          {{ (s.content || '').substring(0, 60) }}...
        </div>
      </div>
    </div>

    <ConfirmModal v-model="showConfirm"
      title="确认清理此脚本？"
      message="此操作将从全局脚本库永久删除该脚本，无法撤销。"
      @confirm="confirmDelete" />
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

const filtered = computed(() => {
  const q = (props.searchQuery || '').toLowerCase()
  const scripts = adminStore.allScripts
  if (!q) return scripts
  return scripts.filter(s =>
    s.name.toLowerCase().includes(q) ||
    (s.owner_name && s.owner_name.toLowerCase().includes(q))
  )
})

const showConfirm = ref(false)
const deletingScript = ref(null)

function openDelete(s) { deletingScript.value = s; showConfirm.value = true }
async function confirmDelete() {
  try {
    await adminStore.deleteScript(deletingScript.value.ID)
    toast.show('脚本已全局清理')
    showConfirm.value = false
  } catch (e) { toast.show(e.message, true) }
}

usePolling(() => adminStore.fetchAllScripts(), 5000)
</script>
