backup:
	tar -cjvf backup.tar.gz ~/dev/bossjones/oh-my-tmux/.tmux.conf ~/.tmux.conf.local
	ls -lta backup.tar.gz

place-configs: backup
	mkdir -p ~/dev/bossjones || true
	git clone git@github.com:bossjones/.tmux.git ~/dev/bossjones/oh-my-tmux || true
	ln -v -s -f ~/dev/bossjones/oh-my-tmux/.tmux.conf ~/.tmux.conf || true
	cp -av ~/dev/bossjones/oh-my-tmux/.tmux.conf.local ~/.tmux.conf.local || true

extra-tmux:
	bash -x extra.sh

reload:
	tmux source-file ~/.tmux.conf
