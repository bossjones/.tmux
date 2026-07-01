DOCKER_IMAGE ?= oh-my-tmux-test

docker-build:
	docker build -t $(DOCKER_IMAGE) .

docker-run: docker-build
	docker run -it $(DOCKER_IMAGE)

docker-smoke: docker-build
	docker run --name ohmytmux_smoke $(DOCKER_IMAGE) zsh -lc \
		'echo "SHELL=$$(getent passwd tmuxer | cut -d: -f7)"; tmux -V; \
		tmux -f /dev/null -L ci new-session -d \; source-file ~/.tmux.conf \; \
		show-options -g history-limit \; show-options -g mouse \; kill-server' ; \
	docker container rm ohmytmux_smoke

# Run the libtmux TDD contract test suite (requires uv and tmux >= 2.6 on PATH).
# Install dependencies first: uv sync --group dev
test:
	uv run pytest -q

.PHONY: docker-build docker-run docker-smoke test

backup:
	@files=""; \
	for f in "$$HOME/.tmux.conf" "$$HOME/.tmux.conf.local"; do \
		if [ -e "$$f" ]; then files="$$files $$f"; fi; \
	done; \
	if [ -n "$$files" ]; then \
		tar -cjvf backup.tar.gz $$files && ls -lta backup.tar.gz; \
	else \
		echo "no existing tmux configs to back up; skipping"; \
	fi

place-configs: backup
	mkdir -p ~/dev/bossjones
	if [ -d ~/dev/bossjones/oh-my-tmux/.git ]; then \
		git -C ~/dev/bossjones/oh-my-tmux pull --ff-only; \
	else \
		git clone git@github.com:bossjones/.tmux.git ~/dev/bossjones/oh-my-tmux; \
	fi
	ln -v -s -f ~/dev/bossjones/oh-my-tmux/.tmux.conf ~/.tmux.conf
	cp -av ~/dev/bossjones/oh-my-tmux/.tmux.conf.local ~/.tmux.conf.local
	@if tmux info >/dev/null 2>&1; then \
		tmux source-file ~/.tmux.conf && echo "reloaded running tmux"; \
	else \
		echo "configs placed; no tmux server running. Start tmux (or reload with <prefix> r) to load them."; \
	fi

extra-tmux:
	bash -x extra.sh

reload:
	@if tmux info >/dev/null 2>&1; then \
		tmux source-file ~/.tmux.conf && echo "reloaded running tmux"; \
	else \
		echo "no tmux server running; nothing to reload. Start tmux to load the config."; \
	fi
