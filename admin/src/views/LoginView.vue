<template>
  <div id="login-view">
    <div class="glass-panel login-box fade-up">
      <div class="sidebar-header" style="justify-content: center; padding-top: 0;">
        <div class="brand-logo">S</div>
        <div class="brand-name">Server Manager Admin</div>
      </div>
      <h2 style="text-align: center; margin-bottom: 30px; font-weight: 400;">欢迎回来</h2>
      <form @submit.prevent="handleLogin">
        <div style="margin-bottom: 20px;">
          <label class="field-label">管理员账户</label>
          <input v-model="username" type="text" class="input-field" placeholder="Username" required />
        </div>
        <div style="margin-bottom: 30px;">
          <label class="field-label">访问凭据</label>
          <input v-model="password" type="password" class="input-field" placeholder="Password" required />
        </div>
        <button type="submit" class="btn-action btn-p" style="width: 100%; justify-content: center;" :disabled="loading">
          {{ loading ? '授权中...' : '立即授权登录' }}
        </button>
        <p v-if="error" class="error-msg">{{ error }}</p>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref, inject } from 'vue'
import { useRouter } from 'vue-router'
import { useRSALogin } from '../composables/useAuth'
import { useAuthStore } from '../stores/auth'

const router = useRouter()
const auth = useAuthStore()
const { encryptedLogin } = useRSALogin()
const toast = inject('toast')

const username = ref('')
const password = ref('')
const loading = ref(false)
const error = ref('')

async function handleLogin() {
  loading.value = true
  error.value = ''
  try {
    const data = await encryptedLogin(username.value, password.value)
    auth.setAuth(data)
    toast.show('授权成功，进入安全管理环境')
    router.push('/')
  } catch (e) {
    error.value = e.message
    toast.show(e.message, true)
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
#login-view {
  display: flex; align-items: center; justify-content: center;
  height: 100vh; background: var(--bg-dark);
}
.login-box { width: 90%; max-width: 400px; padding: 40px; box-shadow: 0 20px 50px rgba(0,0,0,0.5); }
.sidebar-header { padding: 0 0 24px 0; display: flex; align-items: center; gap: 12px; }
.brand-logo {
  width: 40px; height: 40px;
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  border-radius: 12px; display: flex; align-items: center; justify-content: center;
  font-weight: 800; font-size: 1.2rem; color: white; box-shadow: 0 0 20px var(--primary-glow);
}
.brand-name { font-weight: 700; color: white; font-size: 1.1rem; }
.field-label { font-size: 0.8rem; color: var(--text-muted); }
.error-msg { color: var(--danger); font-size: 0.85rem; margin-top: 12px; text-align: center; }
button:disabled { opacity: 0.6; cursor: not-allowed; transform: none !important; }
</style>
