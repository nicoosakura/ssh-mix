<template>
  <div style="display: flex; min-height: 100vh;">
    <AppSidebar />
    <main class="main-content">
      <!-- Header bar -->
      <div class="header-bar">
        <div class="page-title">
          <h1>{{ currentRoute.title }}</h1>
          <p>{{ currentRoute.desc }}</p>
        </div>
        <div v-if="currentRoute.showSearch || currentRoute.showAdd" class="header-actions">
          <div v-if="currentRoute.showSearch" class="search-container">
            <span class="search-icon">🔍</span>
            <input type="text" class="search-input"
              :placeholder="currentRoute.searchPlaceholder"
              :value="searchQuery"
              @input="searchQuery = $event.target.value" />
          </div>
          <button v-if="currentRoute.showAdd" class="btn-action btn-p" @click="triggerAddUser">
            <span>+</span> 增加用户
          </button>
        </div>
      </div>

      <!-- Routed View -->
      <router-view :search-query="searchQuery" @add-user="onAddUser" />
    </main>
  </div>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import AppSidebar from '../components/layout/AppSidebar.vue'

const route = useRoute()
const searchQuery = ref('')

const addUserTrigger = ref(0)

const routeMeta = {
  'Console':       { title: '控制台主页',   desc: '全平台运行状态与核心数据概览',           showSearch: false, showAdd: false },
  'Users':         { title: '用户管理中心', desc: '查看并管理全平台的系统资源与权限',        showSearch: true, searchPlaceholder: '按用户名或 ID 搜索...', showAdd: true },
  'System':        { title: '系统状态监控', desc: '宿主机实时性能指标与后台运行状态',        showSearch: false, showAdd: false },
  'GlobalServers': { title: '全局资产概览', desc: '实时监控全平台所有用户的服务器资产状态',  showSearch: true, searchPlaceholder: '搜索服务器名或所属者...', showAdd: false },
  'GlobalScripts': { title: '全局脚本仓库', desc: '集中管理与查阅全平台所有用户的自动化脚本', showSearch: true, searchPlaceholder: '搜索脚本名或所属者...', showAdd: false },
}

const currentRoute = computed(() => routeMeta[route.name] || { title: '管理系统', desc: '', showSearch: false, showAdd: false })

// Reset search when navigating
watch(() => route.name, () => { searchQuery.value = '' })

function triggerAddUser() {
  addUserTrigger.value++
}
function onAddUser() {}
</script>

<style scoped>
.main-content { margin-left: var(--sidebar-width); padding: 40px; flex: 1; transition: var(--transition); }
.header-bar { display: flex; justify-content: space-between; align-items: flex-end; margin-bottom: 40px; }
.page-title h1 { font-size: 2rem; color: white; margin-bottom: 8px; }
.page-title p { color: var(--text-muted); }
.header-actions { display: flex; gap: 16px; align-items: center; }
</style>
