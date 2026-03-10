# Server Manager - Makefile
# 使用方法: make dev / make build / make start

.PHONY: dev build start stop install help

GREEN  = \033[0;32m
CYAN   = \033[0;36m
RESET  = \033[0m

help:
	@echo "$(CYAN)Server Manager 命令列表:$(RESET)"
	@echo "  $(GREEN)make install$(RESET) - 安装前端依赖"
	@echo "  $(GREEN)make build  $(RESET) - 构建 Vue 3 前端"
	@echo "  $(GREEN)make dev    $(RESET) - 启动开发模式 (后端 + 前端 dev server)"
	@echo "  $(GREEN)make start  $(RESET) - 生产模式启动 (build + 后端)"
	@echo "  $(GREEN)make stop   $(RESET) - 停止所有服务"

install:
	@echo "$(CYAN)安装前端依赖...$(RESET)"
	cd admin && npm install

build:
	@echo "$(CYAN)构建 Vue 3 前端...$(RESET)"
	cd admin && npm run build
	@echo "$(GREEN)✓ 构建完成$(RESET)"

dev:
	@echo "$(CYAN)启动开发服务器...$(RESET)"
	@echo "  - 后端: http://localhost:8080"
	@echo "  - 前端: http://localhost:5173/admin/"
	@(cd admin && npm run dev &) && cd server && go run .

start: build
	@echo "$(CYAN)启动生产服务器...$(RESET)"
	cd server && go run .

stop:
	@echo "$(CYAN)停止服务...$(RESET)"
	@lsof -ti:8080 | xargs kill -9 2>/dev/null || true
	@lsof -ti:5173 | xargs kill -9 2>/dev/null || true
	@echo "$(GREEN)✓ 服务已停止$(RESET)"
