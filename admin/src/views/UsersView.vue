<template>
  <div class="section-fade">
    <!-- Batch action bar -->
    <div v-if="selected.size > 0" class="glass-panel"
      style="padding:12px 20px; margin-bottom:16px; display:flex; justify-content:space-between; align-items:center; border-color:rgba(var(--primary-rgb),0.3);">
      <span style="color:var(--primary);">已选中 {{ selected.size }} 名用户</span>
      <button class="btn-action" style="background:rgba(248,81,73,0.15); color:var(--danger); border:1px solid rgba(248,81,73,0.3);"
        @click="showBatchConfirm = true">🗑️ 批量删除</button>
    </div>

    <!-- User Grid -->
    <div class="user-grid">
      <div v-if="!filteredUsers.length" style="grid-column:1/-1; text-align:center; padding:60px; color:var(--text-muted);">
        {{ searchQuery ? '未找到匹配用户' : '暂无用户数据' }}
      </div>
      <div v-for="user in filteredUsers" :key="user.ID"
        class="glass-panel user-card" @click="openUserServers(user)">
        <!-- Checkbox -->
        <div style="position:absolute; top:12px; left:12px;" @click.stop>
          <input type="checkbox" :checked="selected.has(user.ID)"
            @change="toggleSelect(user.ID)"
            style="width:16px; height:16px; accent-color:var(--primary); cursor:pointer;" />
        </div>
        <div class="user-card-header" style="padding-left:28px;">
          <div style="font-size:1.5rem;">👤</div>
          <span :class="['role-tag', user.role === 'admin' ? 'admin' : '']">{{ user.role }}</span>
        </div>
        <div style="margin-bottom: 16px;">
          <h3 style="color:white; font-size:1.1rem;">{{ user.username }}</h3>
          <p style="color:var(--text-muted); font-size:0.85rem; margin-top:4px;">UID: {{ user.ID }}</p>
        </div>
        <div style="display:flex; gap:8px;" @click.stop>
          <button class="btn-action" style="background:rgba(255,255,255,0.05); color:white; font-size:0.8rem; padding:6px 14px;"
            @click.stop="openEdit(user)">编辑</button>
          <button class="btn-action" style="background:rgba(88,200,255,0.1); color:#58c8ff; font-size:0.8rem; padding:6px 14px;"
            @click.stop="openResetPwd(user)">重置密码</button>
          <button class="btn-action" style="background:rgba(248,81,73,0.1); color:var(--danger); font-size:0.8rem; padding:6px 14px;"
            @click.stop="openDelete(user)">删除</button>
        </div>
      </div>
    </div>

    <!-- Add User Modal -->
    <Teleport to="body">
      <Transition name="modal">
        <div v-if="showAdd" class="modal-overlay" @click.self="showAdd = false">
          <div class="glass-panel modal-box" style="max-width:450px;" @click.stop>
            <div class="modal-head">
              <h2>创建新账户</h2>
              <button style="background:none; border:none; color:var(--text-muted); font-size:1.5rem; cursor:pointer;" @click="showAdd = false">&times;</button>
            </div>
            <div class="modal-body">
              <form @submit.prevent="submitAdd">
                <div style="margin-bottom:16px;"><label>用户名</label><input v-model="form.username" class="input-field" required /></div>
                <div style="margin-bottom:16px;"><label>初始密码</label><input v-model="form.password" type="password" class="input-field" required minlength="6" /></div>
                <div style="margin-bottom:24px;">
                  <label>职能角色</label>
                  <select v-model="form.role" class="input-field" style="appearance:none; color:white;">
                    <option value="user">普通用户 (Standard User)</option>
                    <option value="admin">超级管理员 (Super Admin)</option>
                  </select>
                </div>
                <button type="submit" class="btn-action btn-p" style="width:100%; justify-content:center;">确认创建并分配权限</button>
              </form>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>

    <!-- Edit Modal -->
    <Teleport to="body">
      <Transition name="modal">
        <div v-if="showEdit" class="modal-overlay" @click.self="showEdit = false">
          <div class="glass-panel modal-box" style="max-width:450px;" @click.stop>
            <div class="modal-head">
              <h2>编辑用户 - <span style="color:var(--primary);">@{{ editingUser?.username }}</span></h2>
              <button style="background:none; border:none; color:var(--text-muted); font-size:1.5rem; cursor:pointer;" @click="showEdit = false">&times;</button>
            </div>
            <div class="modal-body">
              <form @submit.prevent="submitEdit">
                <div style="margin-bottom:16px;">
                  <label>职能角色</label>
                  <select v-model="editForm.role" class="input-field" style="appearance:none; color:white;">
                    <option value="user">普通用户 (Standard User)</option>
                    <option value="admin">超级管理员 (Super Admin)</option>
                  </select>
                </div>
                <div style="margin-bottom:24px;"><label>重置密码 (留空表示不修改)</label><input v-model="editForm.password" type="password" class="input-field" placeholder="New password (optional)" /></div>
                <button type="submit" class="btn-action btn-p" style="width:100%; justify-content:center;">确认更新设置</button>
              </form>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>

    <!-- Reset Password Modal -->
    <Teleport to="body">
      <Transition name="modal">
        <div v-if="showResetPwd" class="modal-overlay" @click.self="showResetPwd = false">
          <div class="glass-panel modal-box" style="max-width:400px;" @click.stop>
            <div class="modal-head">
              <h2>强制重置密码 - <span style="color:var(--primary);">@{{ resetPwdUser?.username }}</span></h2>
              <button style="background:none; border:none; color:var(--text-muted); font-size:1.5rem; cursor:pointer;" @click="showResetPwd = false">&times;</button>
            </div>
            <div class="modal-body">
              <form @submit.prevent="submitResetPwd">
                <div style="margin-bottom:24px;">
                  <label>新密码 (至少 6 位)</label>
                  <input v-model="newPwd" type="password" class="input-field" required minlength="6" placeholder="输入新密码" />
                </div>
                <button type="submit" class="btn-action btn-p" style="width:100%; justify-content:center;">确认重置</button>
              </form>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>

    <!-- User Servers Modal -->
    <Teleport to="body">
      <Transition name="modal">
        <div v-if="showServers" class="modal-overlay" @click.self="showServers = false">
          <div class="glass-panel modal-box" @click.stop>
            <div class="modal-head">
              <h2>@{{ serversUser?.username }} 的服务器资产</h2>
              <button style="background:none; border:none; color:var(--text-muted); font-size:1.5rem; cursor:pointer;" @click="showServers = false">&times;</button>
            </div>
            <div class="modal-body">
              <div v-if="loadingServers" style="text-align:center; padding:20px; color:var(--text-muted);">资产加载中...</div>
              <div v-else-if="!userServers.length" style="color:var(--text-muted); text-align:center;">该用户暂无托管服务器</div>
              <div v-for="s in userServers" :key="s.ID" class="server-item">
                <div>
                  <div style="color:white; font-weight:600;">{{ s.name }}</div>
                  <div style="color:var(--text-muted); font-size:0.8rem;">{{ s.username }}@{{ s.host }}</div>
                </div>
                <div :class="['status-badge', s.status === 'online' ? 'online' : 'offline']">
                  <div class="dot"></div>{{ s.status === 'online' ? '在线' : '离线' }}
                </div>
              </div>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>

    <!-- Single Delete -->
    <ConfirmModal v-model="showConfirm" title="确认删除用户？"
      message="此操作将永久移除该用户的所有关联资产，该操作无法撤销。确定继续吗？"
      @confirm="confirmDelete" />

    <!-- Batch Delete -->
    <ConfirmModal v-model="showBatchConfirm" :title="`确认批量删除 ${selected.size} 名用户？`"
      message="此操作将永久移除所有选中用户及其关联资产，无法撤销。"
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

// Selection
const selected = ref(new Set())
function toggleSelect(id) {
  const s = new Set(selected.value)
  if (s.has(id)) s.delete(id); else s.add(id)
  selected.value = s
}

const filteredUsers = computed(() => {
  const q = (props.searchQuery || '').toLowerCase()
  if (!q) return adminStore.users
  return adminStore.users.filter(u =>
    u.username.toLowerCase().includes(q) || String(u.ID).includes(q)
  )
})

// Add
const showAdd = ref(false)
const form = ref({ username: '', password: '', role: 'user' })
async function submitAdd() {
  try {
    await adminStore.createUser(form.value)
    toast.show('用户账户创建并授权成功')
    showAdd.value = false
    form.value = { username: '', password: '', role: 'user' }
  } catch (e) { toast.show(e.message, true) }
}

// Edit
const showEdit = ref(false)
const editingUser = ref(null)
const editForm = ref({ role: 'user', password: '' })
function openEdit(user) { editingUser.value = user; editForm.value = { role: user.role, password: '' }; showEdit.value = true }
async function submitEdit() {
  const payload = { role: editForm.value.role }
  if (editForm.value.password) payload.password = editForm.value.password
  try {
    await adminStore.updateUser(editingUser.value.ID, payload)
    toast.show('用户信息已成功同步')
    showEdit.value = false
  } catch (e) { toast.show(e.message, true) }
}

// Reset Password
const showResetPwd = ref(false)
const resetPwdUser = ref(null)
const newPwd = ref('')
function openResetPwd(user) { resetPwdUser.value = user; newPwd.value = ''; showResetPwd.value = true }
async function submitResetPwd() {
  try {
    await adminStore.resetUserPassword(resetPwdUser.value.ID, newPwd.value)
    toast.show(`@${resetPwdUser.value.username} 的密码已重置`)
    showResetPwd.value = false
  } catch (e) { toast.show(e.message, true) }
}

// Delete
const showConfirm = ref(false)
const deletingUser = ref(null)
function openDelete(user) { deletingUser.value = user; showConfirm.value = true }
async function confirmDelete() {
  try {
    await adminStore.deleteUser(deletingUser.value.ID)
    selected.value.delete(deletingUser.value.ID)
    toast.show('账户已安全移除')
    showConfirm.value = false
  } catch (e) { toast.show(e.message, true) }
}

// Batch delete
const showBatchConfirm = ref(false)
async function confirmBatchDelete() {
  try {
    await adminStore.batchDeleteUsers([...selected.value])
    toast.show(`已批量删除 ${selected.value.size} 名用户`)
    selected.value = new Set()
    showBatchConfirm.value = false
  } catch (e) { toast.show(e.message, true) }
}

// Servers modal
const showServers = ref(false)
const serversUser = ref(null)
const userServers = ref([])
const loadingServers = ref(false)
async function openUserServers(user) {
  serversUser.value = user; showServers.value = true; loadingServers.value = true
  try { userServers.value = await adminStore.fetchUserServers(user.ID) }
  catch { userServers.value = [] }
  finally { loadingServers.value = false }
}

defineExpose({ openAdd: () => { showAdd.value = true } })
usePolling(() => adminStore.fetchUsers(), 5000)
</script>

<style scoped>
.modal-enter-active { transition: opacity 0.3s ease; }
.modal-leave-active { transition: opacity 0.2s ease; }
.modal-enter-from, .modal-leave-to { opacity: 0; }
</style>
