import { createRouter, createWebHashHistory } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const routes = [
    {
        path: '/login',
        name: 'Login',
        component: () => import('../views/LoginView.vue')
    },
    {
        path: '/',
        component: () => import('../views/DashboardLayout.vue'),
        meta: { requiresAuth: true },
        children: [
            { path: '', name: 'Console', component: () => import('../views/ConsoleView.vue') },
            { path: 'users', name: 'Users', component: () => import('../views/UsersView.vue') },
            { path: 'system', name: 'System', component: () => import('../views/SystemView.vue') },
            { path: 'servers', name: 'GlobalServers', component: () => import('../views/GlobalServersView.vue') },
            { path: 'scripts', name: 'GlobalScripts', component: () => import('../views/GlobalScriptsView.vue') },
        ]
    }
]

const router = createRouter({
    history: createWebHashHistory(),
    routes
})

router.beforeEach((to, from, next) => {
    const auth = useAuthStore()
    if (to.meta.requiresAuth && !auth.isAuthenticated) {
        next('/login')
    } else if (to.name === 'Login' && auth.isAuthenticated) {
        next('/')
    } else {
        next()
    }
})

export default router
