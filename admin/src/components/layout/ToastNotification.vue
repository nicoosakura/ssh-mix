<template>
  <Teleport to="body">
    <div class="toast-container">
      <Transition name="toast">
        <div v-if="visible" class="glass-panel toast-item" :style="{ borderLeft: `4px solid ${isError ? 'var(--danger)' : 'var(--success)'}` }">
          {{ message }}
        </div>
      </Transition>
    </div>
  </Teleport>
</template>

<script setup>
import { ref } from 'vue'

const visible = ref(false)
const message = ref('')
const isError = ref(false)
let timeout = null

function show(msg, error = false) {
  message.value = msg
  isError.value = error
  visible.value = true
  clearTimeout(timeout)
  timeout = setTimeout(() => { visible.value = false }, 3000)
}

defineExpose({ show })
</script>

<style scoped>
.toast-item {
  padding: 16px 24px;
  font-weight: 500;
  min-width: 280px;
}
.toast-enter-active { transition: all 0.4s cubic-bezier(0.68, -0.55, 0.265, 1.55); }
.toast-leave-active { transition: all 0.3s ease; }
.toast-enter-from { transform: translateX(120%); opacity: 0; }
.toast-leave-to { transform: translateX(120%); opacity: 0; }
</style>
