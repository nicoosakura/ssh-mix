<template>
  <Teleport to="body">
    <Transition name="modal">
      <div v-if="modelValue" class="modal-overlay" @click.self="$emit('update:modelValue', false)">
        <div class="glass-panel modal-box confirm-dialog">
          <div class="modal-body">
            <div class="confirm-icon">⚠️</div>
            <h2 style="color:white; margin-bottom: 12px;">{{ title }}</h2>
            <p style="color:var(--text-muted); margin-bottom: 30px;">{{ message }}</p>
            <div style="display:flex; gap:16px; justify-content: center;">
              <button class="btn-action" style="background:rgba(255,255,255,0.05); color:white;"
                @click="$emit('update:modelValue', false)">取消</button>
              <button class="btn-action" style="background:var(--danger); color:white;"
                @click="$emit('confirm')">确认删除</button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
defineProps({
  modelValue: Boolean,
  title: { type: String, default: '确认删除？' },
  message: { type: String, default: '此操作无法撤销。确定继续吗？' }
})
defineEmits(['update:modelValue', 'confirm'])
</script>

<style scoped>
.modal-enter-active { transition: opacity 0.3s ease; }
.modal-leave-active { transition: opacity 0.2s ease; }
.modal-enter-from, .modal-leave-to { opacity: 0; }
</style>
