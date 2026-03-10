<template>
  <ToastNotification ref="toastRef" />
  <router-view />
</template>

<script setup>
import ToastNotification from './components/layout/ToastNotification.vue'
import { ref, provide } from 'vue'

const toastRef = ref(null)

provide('toast', {
  show(msg, isError = false) {
    toastRef.value?.show(msg, isError)
  }
})
</script>
