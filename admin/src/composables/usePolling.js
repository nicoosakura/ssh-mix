import { onMounted, onUnmounted } from 'vue'

export function usePolling(callback, interval = 5000) {
    let timer = null

    function start() {
        stop()
        timer = setInterval(callback, interval)
    }

    function stop() {
        if (timer) {
            clearInterval(timer)
            timer = null
        }
    }

    onMounted(() => {
        callback()
        start()
    })

    onUnmounted(() => stop())

    return { start, stop }
}
