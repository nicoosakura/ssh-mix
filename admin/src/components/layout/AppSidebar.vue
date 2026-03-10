<template>
  <aside class="sidebar">
    <div class="sidebar-header">
      <div class="brand-logo">S</div>
      <div class="brand-name">Admin Console</div>
    </div>
    <nav class="nav-menu">
      <router-link v-for="item in navItems" :key="item.to" :to="item.to"
        class="nav-item" active-class="active">
        <span>{{ item.icon }}</span> {{ item.label }}
      </router-link>
    </nav>
    <div class="sidebar-footer">
      <button class="logout-btn" @click="handleLogout">
        <span>退出安全会话</span>
      </button>
    </div>
  </aside>
</template>

<script setup>
import { useAuthStore } from '../../stores/auth'
import { useRouter } from 'vue-router'

const auth = useAuthStore()
const router = useRouter()

const navItems = [
  { to: '/', icon: '📊', label: '控制台主页' },
  { to: '/users', icon: '👥', label: '用户管理中心' },
  { to: '/system', icon: '🛡️', label: '系统状态监控' },
  { to: '/servers', icon: '🌐', label: '全局资产概览' },
  { to: '/scripts', icon: '📜', label: '全局脚本仓库' },
]

function handleLogout() {
  auth.logout()
  router.push('/login')
}
</script>

<style scoped>
.sidebar {
  width: var(--sidebar-width);
  height: 100vh;
  position: fixed;
  left: 0; top: 0;
  background: var(--bg-sidebar);
  border-right: 1px solid var(--card-border);
  display: flex;
  flex-direction: column;
  z-index: 100;
  transition: var(--transition);
}
.sidebar-header { padding: 30px 24px; display: flex; align-items: center; gap: 12px; }
.brand-logo {
  width: 40px; height: 40px;
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  border-radius: 12px;
  display: flex; align-items: center; justify-content: center;
  font-weight: 800; font-size: 1.2rem; color: white;
  box-shadow: 0 0 20px var(--primary-glow);
}
.brand-name { font-weight: 700; color: white; font-size: 1.1rem; }
.nav-menu { flex: 1; padding: 0 16px; display: flex; flex-direction: column; gap: 8px; }
.nav-item {
  padding: 12px 16px; border-radius: 12px; color: var(--text-muted);
  text-decoration: none; display: flex; align-items: center; gap: 12px;
  font-weight: 500; transition: var(--transition); cursor: pointer;
}
.nav-item:hover, .nav-item.active { background: rgba(255,255,255,0.05); color: white; }
.nav-item.active { color: var(--primary); }
.sidebar-footer { padding: 24px; border-top: 1px solid var(--card-border); }
.logout-btn {
  width: 100%; padding: 12px;
  background: rgba(248,81,73,0.1); color: var(--danger);
  border: 1px solid rgba(248,81,73,0.2); border-radius: 12px;
  cursor: pointer; font-weight: 600;
  display: flex; align-items: center; justify-content: center; gap: 8px;
  transition: var(--transition);
}
.logout-btn:hover { background: var(--danger); color: white; }
</style>
